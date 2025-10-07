#!/usr/bin/env python3
"""Simple Jinja2 template renderer to replace j2cli."""

import sys
import json
from jinja2 import Environment, FileSystemLoader
from pathlib import Path

def main():
    if len(sys.argv) < 3:
        print("Usage: render_template.py <template_file> <json_context_file> [output_file]", file=sys.stderr)
        sys.exit(1)

    template_file = sys.argv[1]
    json_file = sys.argv[2]
    output_file = sys.argv[3] if len(sys.argv) > 3 else None

    # Load JSON context
    with open(json_file, 'r') as f:
        context = json.load(f)

    # Setup Jinja2 environment
    template_path = Path(template_file)
    env = Environment(
        loader=FileSystemLoader(template_path.parent),
        trim_blocks=True,
        lstrip_blocks=True
    )

    # Render template
    template = env.get_template(template_path.name)
    rendered = template.render(**context)

    # Output
    if output_file:
        with open(output_file, 'w') as f:
            f.write(rendered)
    else:
        print(rendered)

if __name__ == '__main__':
    main()
