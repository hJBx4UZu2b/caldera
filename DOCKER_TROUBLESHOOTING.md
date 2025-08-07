# Docker Build Troubleshooting Guide

## Issue: "not our ref" / "did not contain" Git Submodule Error

### Root Cause
This error occurs when the local git repository references a submodule commit that doesn't exist in the remote repository. This commonly happens when:
1. Local submodule has uncommitted changes that were never pushed
2. The submodule reference points to a commit from a different branch/fork
3. Repository was cloned from a modified version with custom commits

**Error message example:**
```
fatal: remote error: upload-pack: not our ref 838e1aae66090acf1bacc3296a8536ca0ad0dc75
fatal: Fetched in submodule path 'plugins/magma', but it did not contain 838e1aae66090acf1bacc3296a8536ca0ad0dc75. Direct fetching of that commit failed.
```

### Quick Fix

**Option 1: Use the enhanced build helper script (Recommended)**
```bash
./build-caldera-enhanced.sh
```

**Option 2: Manual fix for specific submodule**
```bash
# Fix magma submodule specifically
git submodule deinit -f plugins/magma
rm -rf plugins/magma
git submodule add https://github.com/mitre/magma.git plugins/magma

# Then build
docker-compose build
```

**Option 3: Reset all submodules to remote state**
```bash
# Remove all submodules
git submodule deinit -f --all
rm -rf plugins/*

# Re-initialize from scratch  
git submodule update --init --recursive

# Build
docker-compose build
```

### Step-by-Step Manual Fix

1. **Identify problematic submodule:**
```bash
git submodule update --recursive
# Look for "not our ref" errors
```

2. **Check current submodule commit:**
```bash
git submodule status | grep magma
# Shows: 838e1aae66090acf1bacc3296a8536ca0ad0dc75 plugins/magma (heads/master-1-g838e1aa)
```

3. **Check what commits exist in remote:**
```bash
curl -s "https://api.github.com/repos/mitre/magma/commits?per_page=10" | grep '"sha"'
```

4. **Reset submodule to valid commit:**
```bash
git submodule deinit -f plugins/magma
rm -rf plugins/magma
git clone https://github.com/mitre/magma.git plugins/magma
cd plugins/magma && git checkout master  # or the latest valid commit
cd .. && git add plugins/magma
```

### Advanced Troubleshooting

**1. Switch to HTTPS if SSH fails:**
```bash
sed -i 's|git@github.com:|https://github.com/|' .gitmodules
git submodule sync
git submodule update --init --recursive
```

**2. Force update to latest remote state:**
```bash
git submodule foreach --recursive 'git fetch origin && git checkout $(git rev-parse origin/HEAD)'
```

**3. Check network and authentication:**
```bash
# Test GitHub access
ssh -T git@github.com

# Or test HTTPS
curl -I https://github.com/mitre/magma.git
```

### Prevention

1. **Always clone with --recursive:**
```bash
git clone --recursive https://github.com/mitre/caldera.git
```

2. **Keep submodules in sync:**
```bash
git submodule update --remote --merge
```

3. **Use official repository:**
Make sure you're cloning from the official MITRE repository, not a fork with custom commits.

### Docker Build Improvements

The enhanced build script (`build-caldera-enhanced.sh`) automatically:
- Detects commit reference issues
- Fixes problematic submodules automatically
- Provides detailed error messages
- Handles network/authentication issues

### Verification

After fixing, verify everything works:
```bash
# Check submodule status
git submodule status

# Verify critical files exist
ls -la plugins/magma/package.json

# Test Docker build
docker-compose build --no-cache

# Start services
docker-compose up -d
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888
# Should return 200
```

---

## Issue: "plugins/magma seems to be empty" during Docker build

### Root Cause
This error occurs when git submodules are not properly initialized during the repository clone process. The `plugins/magma` directory exists but is empty because the submodule content wasn't downloaded.

### Quick Fix

**Option 1: Use the build helper script**
```bash
./build-caldera.sh
```

**Option 2: Manual fix**
```bash
# Initialize missing submodules
git submodule update --init --recursive

# Build Docker images
docker-compose build
```

**Option 3: Re-clone with submodules**
```bash
# Delete existing directory and re-clone properly
rm -rf caldera
git clone --recursive https://github.com/mitre/caldera.git
cd caldera
docker-compose build
```

### Prevention

**Always clone with --recursive flag:**
```bash
git clone --recursive https://github.com/mitre/caldera.git
```

**Or initialize submodules after cloning:**
```bash
git clone https://github.com/mitre/caldera.git
cd caldera
git submodule update --init --recursive
```

### Advanced Troubleshooting

**1. Check submodule status:**
```bash
git submodule status
```
Expected output should show commit hashes, not empty lines or minus signs.

**2. Check specific submodule:**
```bash
ls -la plugins/magma/
# Should show files like package.json, src/, etc.
```

**3. Manual submodule fix:**
```bash
git submodule deinit -f plugins/magma
git submodule update --init plugins/magma
```

**4. Network/authentication issues:**
```bash
# Test GitHub SSH access
ssh -T git@github.com

# Or switch to HTTPS URLs in .gitmodules
sed -i 's/git@github.com:/https:\/\/github.com\//' .gitmodules
git submodule sync
git submodule update --init --recursive
```

### Similar Issues with Other Plugins

The same solution applies to other plugins that might have similar issues:
- `plugins/training` (has package.json)
- `plugins/stockpile` (critical for abilities)
- `plugins/sandcat` (agents)

### Docker Build Improvements

The updated Dockerfile now includes automatic submodule initialization:
- Installs git in the build stage
- Checks for missing submodules
- Automatically initializes them
- Provides clear error messages

### Verification

After fixing, verify the build works:
```bash
docker-compose build --no-cache
docker-compose up -d
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888
# Should return 200
```

---

## Issue: "plugins/magma/dist/assets/ does not exist" Runtime Error

### Root Cause
This error occurs when the Vue.js frontend build fails or the dist directory is not properly created/copied during the Docker build process. The Caldera web interface requires the compiled frontend assets to serve static files.

**Error message example:**
```
ValueError: 'plugins/magma/dist/assets/' does not exist
FileNotFoundError: [Errno 2] No such file or directory: 'plugins/magma/dist'
```

### Quick Fix

**Option 1: Use the enhanced build helper script**
```bash
./build-caldera-enhanced.sh
```

**Option 2: Ensure submodules are initialized before building**
```bash
# Initialize submodules first
git submodule update --init --recursive

# Verify magma submodule has the required files
ls -la plugins/magma/package.json

# Build Docker images
docker-compose build --no-cache
```

### Advanced Troubleshooting

**1. Check if magma submodule is properly initialized:**
```bash
ls -la plugins/magma/
# Should show package.json, src/, and other Vue.js project files
```

**2. Test Vue build locally (optional):**
```bash
cd plugins/magma
npm install
npm run build
ls -la dist/
# Should show index.html, assets/, etc.
```

**3. Check Docker build logs for frontend build stage:**
```bash
docker-compose build 2>&1 | grep -A10 -B5 "Building Magma frontend"
```

**4. Verify Docker multi-stage build:**
```bash
# Build only the UI stage
docker build --target ui-build -t caldera-ui .

# Check if dist was created
docker run --rm caldera-ui ls -la /usr/src/app/plugins/magma/dist/
```

### Prevention

1. **Always initialize submodules before Docker build:**
```bash
git clone --recursive https://github.com/mitre/caldera.git
```

2. **Use the build helper scripts provided:**
```bash
./build-caldera-enhanced.sh  # Handles submodules and builds automatically
```

3. **Check frontend build in the Docker logs:**
The enhanced Dockerfile now provides detailed error messages if the frontend build fails.

### Verification

After fixing, verify the web interface works:
```bash
docker-compose up -d
curl -s -o /dev/null -w "%{http_code}" http://localhost:8888
# Should return 200

# Check logs for any asset serving errors
docker-compose logs caldera | grep -i "assets\|dist\|static"
```

---

## Issue: "bash checker is not working well" / Missing Submodule Files

### Root Cause
The Docker build process cannot initialize git submodules because the `.dockerignore` file excludes `.git` directories for security and performance reasons. This means submodules must be initialized on the host system before building Docker images.

**Error indicators:**
- "some of the plugins is still empty"
- "cannot open ./update-agents.sh: No such file"
- "sandcat submodule is still empty"

### Solution

The new Dockerfile approach provides clear error messages and instructions instead of trying to fix submodules inside Docker:

**When you see the submodule initialization error, run ONE of these solutions:**

**Solution 1 (Recommended): Use the build helper script**
```bash
./build-caldera-enhanced.sh
```

**Solution 2: Initialize submodules manually**
```bash
git submodule update --init --recursive
docker-compose build
```

**Solution 3: Re-clone with submodules**
```bash
rm -rf <current-directory>
git clone --recursive https://github.com/mitre/caldera.git
cd caldera && docker-compose build
```

### Why the Change

The previous "bash checker" approach tried to run `git submodule update` inside Docker, but this fails because:
1. `.dockerignore` excludes `.git` directories
2. No git history is available in the container
3. Authentication tokens may not be available

The new approach:
1. Detects missing submodules clearly
2. Provides explicit instructions
3. Fails fast with helpful error messages
4. Ensures reproducible builds

### Verification

Check that all required submodules are present:
```bash
# Verify critical submodules exist and have content
ls -la plugins/magma/package.json         # Vue.js frontend
ls -la plugins/sandcat/update-agents.sh   # Agent management
ls -la plugins/stockpile/                 # Core abilities
```