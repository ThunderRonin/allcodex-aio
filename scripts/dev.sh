#!/usr/bin/env bash

# dev.sh - Launch AllCodex Dev Environment using mprocs

# Check if mprocs is installed
if ! command -v mprocs &> /dev/null; then
    echo -e "\033[0;31mmprocs is not installed.\033[0m"
    echo "This dev script uses mprocs to create a beautifully tabbed terminal interface."
    echo ""
    echo "To install mprocs:"
    echo "  macOS/Linux: curl -sL https://raw.githubusercontent.com/pvolok/mprocs/master/install.sh | sh"
    echo "  or via cargo: cargo install mprocs"
    echo ""
    echo "Once installed, re-run this script!"
    exit 1
fi

echo "Spinning up the AllCodex dev ecosystem with mprocs..."
mprocs
