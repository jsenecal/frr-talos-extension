#!/usr/bin/env python3
"""
Configuration loader for FRR-Cilium BGP integration
Supports multiple configuration sources with precedence
"""

import os
import sys
import yaml
import json
from pathlib import Path
from typing import Dict, Any, Optional

class ConfigLoader:
    """Load configuration from YAML/JSON files only"""

    def __init__(self):
        self.config = {}

    def load_file(self, filepath: str) -> Dict[str, Any]:
        """Load configuration from YAML or JSON file"""
        path = Path(filepath)
        if not path.exists():
            return {}

        with open(path, 'r') as f:
            if path.suffix in ['.yaml', '.yml']:
                return yaml.safe_load(f) or {}
            elif path.suffix == '.json':
                return json.load(f)
        return {}



    def _set_nested(self, d: Dict, path: str, value: Any):
        """Set a value in nested dictionary using dot notation"""
        keys = path.split('.')
        for key in keys[:-1]:
            d = d.setdefault(key, {})
        d[keys[-1]] = value

    def _merge_deep(self, base: Dict, override: Dict) -> Dict:
        """Deep merge two dictionaries"""
        result = base.copy()
        for key, value in override.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = self._merge_deep(result[key], value)
            else:
                result[key] = value
        return result

    def load(self) -> Dict[str, Any]:
        """Load configuration from files only"""
        config = {}

        # Load from config files (in order of precedence)
        config_files = [
            '/etc/frr/config.default.yaml',
            '/etc/frr/config.yaml',
            '/etc/frr/config.local.yaml',
            os.environ.get('FRR_CONFIG_FILE', '/etc/frr/config.yaml')
        ]

        for config_file in config_files:
            if config_file and Path(config_file).exists():
                file_config = self.load_file(config_file)
                config = self._merge_deep(config, file_config)

        return config


    def generate_j2_context(self, config: Dict[str, Any]) -> str:
        """Generate JSON context for j2cli"""
        return json.dumps(config, indent=2)

def main():
    """Main entry point"""
    import argparse

    parser = argparse.ArgumentParser(description='Load FRR configuration from files')
    parser.add_argument('--json', action='store_true',
                      help='Output as JSON for j2cli')
    parser.add_argument('--validate', action='store_true',
                      help='Validate configuration')
    parser.add_argument('--config', default='/etc/frr/config.yaml',
                      help='Config file path')

    args = parser.parse_args()

    # Override config file if specified
    if args.config:
        os.environ['FRR_CONFIG_FILE'] = args.config

    loader = ConfigLoader()
    config = loader.load()

    if args.validate:
        # Basic validation
        required = [
            'bgp.upstream.local_asn',
            'bgp.upstream.router_id',
            'bgp.cilium.local_asn',
            'bgp.cilium.remote_asn'
        ]
        missing = []
        for path in required:
            keys = path.split('.')
            value = config
            for key in keys:
                value = value.get(key)
                if value is None:
                    missing.append(path)
                    break

        if missing:
            print(f"Missing required configuration: {', '.join(missing)}", file=sys.stderr)
            sys.exit(1)
        print("Configuration valid")

    elif args.json:
        print(loader.generate_j2_context(config))

    else:
        # Pretty print config
        import pprint
        pprint.pprint(config)

if __name__ == '__main__':
    main()