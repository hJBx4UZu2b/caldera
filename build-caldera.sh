#!/bin/bash

# Caldera Docker Build Helper
# This script ensures all submodules are properly initialized before building

set -e

echo "=== Caldera Docker Build Helper ==="
echo "Checking submodule status..."

# Check if this is a git repository
if [ ! -d ".git" ]; then
    echo "Error: This doesn't appear to be a git repository."
    echo "Please run: git clone --recursive https://github.com/mitre/caldera.git"
    exit 1
fi

# Check critical submodules
CRITICAL_SUBMODULES="plugins/magma plugins/stockpile plugins/sandcat"
MISSING_SUBMODULES=""

for submodule in $CRITICAL_SUBMODULES; do
    if [ ! -f "$submodule/.git" ] && [ ! -d "$submodule/.git" ]; then
        echo "Missing submodule: $submodule"
        MISSING_SUBMODULES="$MISSING_SUBMODULES $submodule"
    fi
done

# Initialize missing submodules
if [ ! -z "$MISSING_SUBMODULES" ]; then
    echo "Initializing missing submodules..."
    git submodule update --init --recursive $MISSING_SUBMODULES
    echo "Submodules initialized successfully!"
fi

# Verify critical files exist
if [ ! -f "plugins/magma/package.json" ]; then
    echo "Error: plugins/magma/package.json not found after submodule initialization."
    echo "This may indicate a network issue or repository access problem."
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check your internet connection"
    echo "2. Verify GitHub access: ssh -T git@github.com"
    echo "3. Try manual initialization: git submodule update --init --recursive"
    echo "4. If using HTTPS, try switching to SSH URLs in .gitmodules"
    exit 1
fi

echo "✅ All submodules properly initialized!"
echo "Building Docker images..."

# Build with proper error handling
if ! docker-compose build; then
    echo "❌ Docker build failed!"
    echo ""
    echo "Common solutions:"
    echo "1. Check Docker daemon is running"
    echo "2. Free up disk space"
    echo "3. Try: docker system prune -f"
    echo "4. Check network connectivity"
    exit 1
fi

echo "✅ Docker build completed successfully!"
echo ""
echo "To start Caldera, run:"
echo "  docker-compose up -d"
echo ""
echo "Web interface will be available at: http://localhost:8888"