#!/bin/bash

# Caldera Docker Build Helper - Enhanced with submodule commit fix
# This script ensures all submodules are properly initialized before building
#
# Usage:
#   ./build-caldera-enhanced.sh          # Build full variant (default)
#   ./build-caldera-enhanced.sh --slim   # Build slim variant (faster, no offline EMU data)
#   ./build-caldera-enhanced.sh slim     # Same as --slim
#   ./build-caldera-enhanced.sh --prebuild  # Pre-build frontend assets locally first
#   ./build-caldera-enhanced.sh --force-clean  # Clean all build artifacts and rebuild

set -e

echo "=== Caldera Docker Build Helper (Enhanced) ==="

# Parse command line arguments
FORCE_PREBUILD=false
FORCE_CLEAN=false
BUILD_VARIANT="full"

for arg in "$@"; do
    case $arg in
        --slim|slim)
            BUILD_VARIANT="slim"
            ;;
        --prebuild)
            FORCE_PREBUILD=true
            ;;
        --force-clean)
            FORCE_CLEAN=true
            ;;
        --help|-h)
            echo "Caldera Docker Build Helper (Enhanced)"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "OPTIONS:"
            echo "  --slim, slim       Build slim variant (faster, no offline EMU data)"
            echo "  --prebuild        Force pre-build of frontend assets locally"
            echo "  --force-clean     Clean all build artifacts and rebuild from scratch"
            echo "  --help, -h        Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0                # Build full variant with auto-detection"
            echo "  $0 --slim         # Build slim variant for faster builds"
            echo "  $0 --prebuild     # Pre-build frontend assets locally first"
            echo "  $0 --force-clean  # Clean everything and rebuild"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Build configuration: variant=$BUILD_VARIANT, prebuild=$FORCE_PREBUILD, clean=$FORCE_CLEAN"
echo "Checking submodule status..."

# Check if this is a git repository
if [ ! -d ".git" ]; then
    echo "Error: This doesn't appear to be a git repository."
    echo "Please run: git clone --recursive https://github.com/mitre/caldera.git"
    exit 1
fi

# Function to fix submodule commit reference issues
fix_submodule_commit_issue() {
    local submodule_path=$1
    local repo_url=$2
    
    echo "Fixing commit reference issue for $submodule_path..."
    
    # Remove problematic submodule
    git submodule deinit -f $submodule_path 2>/dev/null || true
    rm -rf $submodule_path
    
    # Re-add submodule with fresh clone
    git submodule add $repo_url $submodule_path 2>/dev/null || {
        # If submodule already exists in .gitmodules, just clone it
        echo "Re-initializing existing submodule..."
        git clone $repo_url $submodule_path
        cd $submodule_path
        # Checkout to master/main branch
        git checkout $(git remote show origin | grep 'HEAD branch' | cut -d' ' -f5) 2>/dev/null || git checkout master 2>/dev/null || git checkout main 2>/dev/null
        cd ..
    }
    
    echo "Fixed $submodule_path"
}

# Check critical submodules
CRITICAL_SUBMODULES="plugins/magma plugins/stockpile plugins/sandcat"
MISSING_SUBMODULES=""

for submodule in $CRITICAL_SUBMODULES; do
    if [ ! -f "$submodule/.git" ] && [ ! -d "$submodule/.git" ]; then
        echo "Missing submodule: $submodule"
        MISSING_SUBMODULES="$MISSING_SUBMODULES $submodule"
    fi
done

# Try to initialize missing submodules
if [ ! -z "$MISSING_SUBMODULES" ]; then
    echo "Initializing missing submodules..."
    
    # First try normal submodule update
    if ! git submodule update --init --recursive $MISSING_SUBMODULES 2>/dev/null; then
        echo "Normal submodule initialization failed, trying commit reference fix..."
        
        # Handle specific known problematic submodules
        for submodule in $MISSING_SUBMODULES; do
            case $submodule in
                "plugins/magma")
                    fix_submodule_commit_issue "plugins/magma" "https://github.com/mitre/magma.git"
                    ;;
                "plugins/stockpile")
                    fix_submodule_commit_issue "plugins/stockpile" "https://github.com/mitre/stockpile.git"
                    ;;
                "plugins/sandcat")
                    fix_submodule_commit_issue "plugins/sandcat" "https://github.com/mitre/sandcat.git"
                    ;;
                *)
                    echo "Attempting generic fix for $submodule"
                    REPO_URL=$(git config -f .gitmodules submodule.$submodule.url)
                    if [ ! -z "$REPO_URL" ]; then
                        fix_submodule_commit_issue "$submodule" "$REPO_URL"
                    fi
                    ;;
            esac
        done
    fi
    
    echo "Submodules initialization completed!"
fi

# Verify critical files exist
if [ ! -f "plugins/magma/package.json" ]; then
    echo "Error: plugins/magma/package.json not found after submodule initialization."
    echo "This may indicate a network issue or repository access problem."
    echo ""
    echo "Troubleshooting steps:"
    echo "1. Check your internet connection"
    echo "2. Verify GitHub access: ssh -T git@github.com"
    echo "3. Try switching to HTTPS URLs:"
    echo "   sed -i 's|git@github.com:|https://github.com/|' .gitmodules"
    echo "   git submodule sync && git submodule update --init --recursive"
    exit 1
fi

echo "✅ All submodules properly initialized!"

# Handle force clean option
if [ "$FORCE_CLEAN" = true ]; then
    echo "🧹 Force clean requested - removing build artifacts..."
    
    # Clean magma build artifacts
    if [ -d "plugins/magma/dist" ]; then
        echo "Removing plugins/magma/dist/"
        rm -rf plugins/magma/dist/
    fi
    
    if [ -d "plugins/magma/node_modules" ]; then
        echo "Removing plugins/magma/node_modules/"
        rm -rf plugins/magma/node_modules/
    fi
    
    # Clean training build artifacts
    if [ -d "plugins/training/node_modules" ]; then
        echo "Removing plugins/training/node_modules/"
        rm -rf plugins/training/node_modules/
    fi
    
    # Clean Docker images
    echo "Cleaning Docker images..."
    docker image rm caldera:latest 2>/dev/null || echo "No existing caldera:latest image to remove"
    
    echo "✅ Clean completed"
fi

# Fix permissions for sandcat script (common issue)
if [ -f "plugins/sandcat/update-agents.sh" ] && [ ! -x "plugins/sandcat/update-agents.sh" ]; then
    echo "Fixing execute permissions for sandcat update-agents.sh..."
    chmod +x plugins/sandcat/update-agents.sh
    echo "✅ Fixed sandcat script permissions"
fi

# Check for commit reference issues in existing submodules
echo "Checking for commit reference issues in existing submodules..."
if git submodule update 2>&1 | grep -q "not our ref\|did not contain"; then
    echo "⚠️  Found commit reference issues, attempting automatic fix..."
    
    # Get list of problematic submodules
    PROBLEMATIC_SUBMODULES=$(git submodule status | grep "^-\|^+" | awk '{print $2}')
    
    for submodule in $PROBLEMATIC_SUBMODULES; do
        if [ -f "$submodule/.git" ] || [ -d "$submodule/.git" ]; then
            REPO_URL=$(git config -f .gitmodules submodule.$submodule.url)
            echo "Fixing commit reference for $submodule..."
            fix_submodule_commit_issue "$submodule" "$REPO_URL"
        fi
    done
fi

echo "🔍 Checking for missing build artifacts..."

# Function to check and build frontend assets
check_and_build_frontend() {
    echo "Checking frontend build artifacts..."
    
    # Check magma frontend
    if [ -d "plugins/magma" ] && [ -f "plugins/magma/package.json" ]; then
        local needs_build=false
        
        if [ "$FORCE_PREBUILD" = true ]; then
            echo "🔧 Force prebuild requested for frontend"
            needs_build=true
        elif [ ! -d "plugins/magma/dist" ] || [ -z "$(ls -A plugins/magma/dist 2>/dev/null)" ]; then
            echo "⚠️  Magma frontend dist/ directory missing or empty"
            echo "This is critical - the web interface won't work without it"
            needs_build=true
        fi
        
        if [ "$needs_build" = true ]; then
            # Check if we can build it locally
            if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
                echo "📦 Node.js detected, attempting to pre-build frontend..."
                cd plugins/magma
                
                echo "Installing dependencies..."
                if npm install; then
                    echo "Building frontend assets..."
                    if npm run build; then
                        echo "✅ Frontend build successful!"
                        local file_count=$(find dist -type f 2>/dev/null | wc -l)
                        echo "📁 Created $file_count frontend files"
                        
                        # Verify critical files exist
                        if [ -f "dist/index.html" ] && [ -d "dist/assets" ]; then
                            echo "✅ Critical frontend files verified"
                        else
                            echo "⚠️  Some critical files may be missing"
                        fi
                    else
                        echo "❌ Frontend build failed, Docker will rebuild it"
                    fi
                else
                    echo "❌ npm install failed, Docker will handle the build"
                fi
                cd ../..
            else
                echo "⚠️  Node.js not found locally - Docker will build frontend"
                echo "   This may increase build time and require internet connectivity"
                echo "   To speed up builds: install Node.js locally and run:"
                echo "   cd plugins/magma && npm install && npm run build"
                echo "   Or use: $0 --prebuild (after installing Node.js)"
            fi
        else
            local file_count=$(find plugins/magma/dist -type f 2>/dev/null | wc -l)
            echo "✅ Magma frontend dist/ directory exists with $file_count files"
        fi
    fi
    
    # Check training plugin
    if [ -d "plugins/training" ] && [ -f "plugins/training/package.json" ]; then
        if [ ! -d "plugins/training/node_modules" ]; then
            echo "ℹ️  Training plugin node_modules missing (non-critical)"
        else
            echo "✅ Training plugin dependencies found"
        fi
    fi
}

# Function to check build tools availability
check_build_dependencies() {
    echo "Checking build dependencies..."
    
    local missing_tools=()
    
    # Check Node.js for frontend builds
    if ! command -v node >/dev/null 2>&1; then
        missing_tools+=("Node.js (for frontend builds)")
    fi
    
    # Check Python for Caldera
    if ! command -v python3 >/dev/null 2>&1; then
        missing_tools+=("Python3 (for Caldera)")
    fi
    
    # Check Docker
    if ! command -v docker >/dev/null 2>&1; then
        missing_tools+=("Docker (required)")
    fi
    
    # Check Docker Compose
    if ! command -v docker-compose >/dev/null 2>&1; then
        missing_tools+=("docker-compose (required)")
    fi
    
    if [ ${#missing_tools[@]} -gt 0 ]; then
        echo "⚠️  Missing build tools:"
        for tool in "${missing_tools[@]}"; do
            echo "   - $tool"
        done
        echo ""
        echo "🔧 Installation suggestions:"
        echo "   Node.js: https://nodejs.org/ or 'brew install node' (macOS)"
        echo "   Docker: https://docs.docker.com/get-docker/"
        echo ""
    else
        echo "✅ All essential build tools found"
    fi
}

# Function to estimate build complexity
estimate_build_time() {
    local build_estimate="Fast (~2-3 minutes)"
    local factors=()
    
    if [ ! -d "plugins/magma/dist" ]; then
        build_estimate="Medium (~5-8 minutes)"
        factors+=("Frontend build required")
    fi
    
    if [ "$VARIANT" = "full" ]; then
        build_estimate="Slow (~10-15 minutes)"
        factors+=("Full EMU data download")
    fi
    
    if [ ${#factors[@]} -gt 0 ]; then
        echo "⏱️  Estimated build time: $build_estimate"
        echo "   Factors:"
        for factor in "${factors[@]}"; do
            echo "   - $factor"
        done
    else
        echo "⏱️  Estimated build time: $build_estimate"
    fi
    echo ""
}

# Run the checks
check_build_dependencies
check_and_build_frontend
estimate_build_time

echo "Building Docker images..."

# Set the variant for docker-compose
export VARIANT=$BUILD_VARIANT

# Provide build information
echo "📦 Build configuration:"
echo "   Variant: $BUILD_VARIANT"
if [ "$BUILD_VARIANT" = "slim" ]; then
    echo "   • Faster build (no offline EMU data)"
    echo "   • Some plugins may require internet connectivity"
else
    echo "   • Full offline capability"
    echo "   • Includes EMU adversary emulation data"
fi

# Build with proper error handling
if ! docker-compose build; then
    echo "❌ Docker build failed!"
    echo ""
    echo "Common solutions:"
    echo "1. Check Docker daemon is running"
    echo "2. Free up disk space"
    echo "3. Try: docker system prune -f"
    echo "4. Check network connectivity"
    echo "5. Try building without cache: docker-compose build --no-cache"
    exit 1
fi

echo "✅ Docker build completed successfully!"
echo ""
echo "🚀 Caldera is ready!"
echo ""
echo "To start Caldera:"
echo "  docker-compose up -d"
echo ""
echo "Web interface will be available at:"
echo "  http://localhost:8888"
echo ""
echo "Default credentials:"
echo "  Username: red or blue or admin"
echo "  Password: admin"