#!/bin/bash
set -e

# Template validation script
# This validates the FRR template before building the container

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${1:-examples/config-bfd.yaml}"

echo "=== FRR Template Validator ==="
echo "Template: frr.conf.j2"
echo "Config: $CONFIG_FILE"
echo ""

# Check dependencies
if ! command -v python3 &> /dev/null; then
    echo "ERROR: python3 is required"
    exit 1
fi

# Convert YAML to JSON
echo "Step 1: Loading and converting config..."
python3 "$SCRIPT_DIR/config_loader.py" --json --config "$CONFIG_FILE" > /tmp/frr-test-config.json

if [ $? -ne 0 ]; then
    echo "ERROR: Config loading failed"
    exit 1
fi

# Render the template
echo "Step 2: Rendering template..."
python3 "$SCRIPT_DIR/render_template.py" \
    "$SCRIPT_DIR/frr.conf.j2" \
    /tmp/frr-test-config.json \
    /tmp/frr-test.conf

if [ $? -ne 0 ]; then
    echo "ERROR: Template rendering failed"
    exit 1
fi

echo "✓ Template rendered successfully"
echo ""

# Check for common errors
echo "Step 3: Checking for common configuration errors..."

# Check for undefined route-maps
ERRORS=0
while IFS= read -r line; do
    if echo "$line" | grep -q "route-map.*out\|route-map.*in"; then
        MAP_NAME=$(echo "$line" | grep -o "route-map [^ ]*" | awk '{print $2}')
        if ! grep -q "^route-map $MAP_NAME " /tmp/frr-test.conf; then
            echo "ERROR: Route-map '$MAP_NAME' is referenced but not defined"
            ERRORS=$((ERRORS + 1))
        fi
    fi
done < <(grep -E "neighbor.*route-map" /tmp/frr-test.conf || true)

# Check for undefined prefix-lists
while IFS= read -r line; do
    if echo "$line" | grep -q "prefix-list.*in\|prefix-list.*out\|match.*prefix-list"; then
        LIST_NAME=$(echo "$line" | grep -o "prefix-list [^ ]*" | awk '{print $2}')
        if ! grep -q "prefix-list $LIST_NAME seq" /tmp/frr-test.conf; then
            echo "ERROR: Prefix-list '$LIST_NAME' is referenced but not defined"
            ERRORS=$((ERRORS + 1))
        fi
    fi
done < <(grep -E "neighbor.*prefix-list|match.*prefix-list" /tmp/frr-test.conf || true)

# Check for configuration ordering (prefix-lists and route-maps before BGP config)
FIRST_BGP_LINE=$(grep -n "^router bgp" /tmp/frr-test.conf | head -1 | cut -d: -f1)
LAST_ROUTEMAP_LINE=$(grep -n "^route-map.*permit\|^route-map.*deny" /tmp/frr-test.conf | tail -1 | cut -d: -f1)

if [ -n "$FIRST_BGP_LINE" ] && [ -n "$LAST_ROUTEMAP_LINE" ]; then
    if [ "$LAST_ROUTEMAP_LINE" -gt "$FIRST_BGP_LINE" ]; then
        echo "ERROR: Route-maps are defined after BGP configuration (ordering issue)"
        echo "  First BGP config at line: $FIRST_BGP_LINE"
        echo "  Last route-map at line: $LAST_ROUTEMAP_LINE"
        ERRORS=$((ERRORS + 1))
    fi
fi

if [ $ERRORS -eq 0 ]; then
    echo "✓ No configuration errors found"
else
    echo ""
    echo "Found $ERRORS error(s) in configuration"
    exit 1
fi

echo ""

# Show generated config summary
echo "Step 4: Configuration summary..."
echo "  BGP routers: $(grep -c "^router bgp" /tmp/frr-test.conf || echo 0)"
echo "  BGP neighbors: $(grep -c "^ neighbor.*remote-as" /tmp/frr-test.conf || echo 0)"
echo "  Prefix-lists: $(grep -c "^ip prefix-list\|^ipv6 prefix-list" /tmp/frr-test.conf || echo 0)"
echo "  Route-maps: $(grep -c "^route-map.*permit\|^route-map.*deny" /tmp/frr-test.conf || echo 0)"
echo "  BFD profiles: $(grep -c "^ profile" /tmp/frr-test.conf || echo 0)"

echo ""
echo "Generated config saved to: /tmp/frr-test.conf"
echo ""
echo "✓ Template validation PASSED"
