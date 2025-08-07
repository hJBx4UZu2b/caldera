# This file uses a staged build, using a different stage to build the UI (magma)
# Build the UI
FROM node:23 AS ui-build

# Install git for submodule operations
RUN apt-get update && apt-get install -y git && rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

ADD . .

# Check for missing submodules and provide clear error message
RUN echo "Checking for missing submodules..." && \
    MISSING_SUBMODULES="" && \
    for submodule in plugins/magma plugins/sandcat plugins/stockpile; do \
        if [ ! -d "$submodule" ] || [ -z "$(ls -A $submodule 2>/dev/null)" ]; then \
            echo "ERROR: Missing or empty submodule: $submodule"; \
            MISSING_SUBMODULES="$MISSING_SUBMODULES $submodule"; \
        fi; \
    done && \
    if [ ! -z "$MISSING_SUBMODULES" ]; then \
        echo ""; \
        echo "=== SUBMODULE INITIALIZATION REQUIRED ==="; \
        echo "The following submodules are missing:$MISSING_SUBMODULES"; \
        echo ""; \
        echo "Please run ONE of these solutions BEFORE building Docker:"; \
        echo ""; \
        echo "Solution 1 (Recommended): Use the build helper script"; \
        echo "  ./build-caldera-enhanced.sh"; \
        echo ""; \
        echo "Solution 2: Initialize submodules manually"; \
        echo "  git submodule update --init --recursive"; \
        echo "  docker-compose build"; \
        echo ""; \
        echo "Solution 3: Re-clone with submodules"; \
        echo "  rm -rf <current-directory>"; \
        echo "  git clone --recursive https://github.com/mitre/caldera.git"; \
        echo "  cd caldera && docker-compose build"; \
        echo ""; \
        echo "Note: Git operations cannot be performed inside Docker due to .dockerignore"; \
        echo "excluding .git directories for security and performance reasons."; \
        echo ""; \
        exit 1; \
    else \
        echo "✅ All critical submodules are present"; \
    fi

# Build VueJS front-end
RUN if [ -f "plugins/magma/package.json" ]; then \
        echo "Building Magma frontend..."; \
        cd plugins/magma; \
        echo "Installing npm dependencies..."; \
        npm install; \
        echo "Building Vue.js frontend..."; \
        npm run build; \
        echo "Frontend build completed"; \
        if [ ! -d "dist" ]; then \
            echo "ERROR: Frontend build failed - dist directory not created"; \
            echo "This can happen due to:"; \
            echo "1. Node.js/npm installation issues"; \
            echo "2. Network connectivity problems during npm install"; \
            echo "3. Build script failures"; \
            echo "Contents of plugins/magma:"; \
            ls -la .; \
            exit 1; \
        fi; \
        echo "✅ Frontend build successful - dist directory created"; \
        ls -la dist/; \
    else \
        echo "Error: Magma submodule still not available after initialization"; \
        echo "Please run: git clone --recursive <repo-url> or git submodule update --init --recursive"; \
        ls -la plugins/magma; \
        exit 1; \
    fi

# This is the runtime stage
# It containes all dependencies required by caldera
FROM debian:bookworm-slim AS runtime

# There are two variants - slim and full
# The slim variant excludes some dependencies of *emu* and *atomic* that can be downloaded on-demand if needed
# They are very large
ARG VARIANT=full
ENV VARIANT=${VARIANT}

# Display an error if variant is set incorrectly, otherwise just print information regarding which variant is in use
RUN if [ "$VARIANT" = "full" ]; then \
        echo "Building \"full\" container suitable for offline use!"; \
    elif [ "$VARIANT" = "slim" ]; then \
        echo "Building slim container - some plugins (emu, atomic) may not be available without an internet connection!"; \
    else \
        echo "Invalid Docker build-arg for VARIANT! Please provide either \"full\" or \"slim\"."; \
        exit 1; \
fi

WORKDIR /usr/src/app

# Copy in source code and compiled UI
# IMPORTANT NOTE: the .dockerignore file is very important in preventing weird issues.
# Especially if caldera was ever compiled outside of Docker - we don't want those files to interfere with this build process,
# which should be repeatable.
ADD . .
COPY --from=ui-build /usr/src/app/plugins/magma/dist /usr/src/app/plugins/magma/dist
RUN echo "Verifying frontend assets copied correctly..." && \
    if [ ! -d "/usr/src/app/plugins/magma/dist" ]; then \
        echo "ERROR: Frontend dist directory not found after copy"; \
        echo "Contents of plugins/magma:"; \
        ls -la /usr/src/app/plugins/magma/ || echo "magma directory does not exist"; \
        exit 1; \
    fi && \
    if [ ! -d "/usr/src/app/plugins/magma/dist/assets" ]; then \
        echo "ERROR: Frontend assets directory not found"; \
        echo "Contents of dist directory:"; \
        ls -la /usr/src/app/plugins/magma/dist/ || echo "dist directory empty"; \
        exit 1; \
    fi && \
    echo "✅ Frontend assets verified successfully" && \
    ls -la /usr/src/app/plugins/magma/dist/

# From https://docs.docker.com/build/building/best-practices/
# Install caldera dependencies
RUN echo "deb http://mirrors.ustc.edu.cn/debian bookworm main contrib non-free" > /etc/apt/sources.list && \
echo "deb http://mirrors.ustc.edu.cn/debian bookworm-updates main contrib non-free" >> /etc/apt/sources.list && \
echo "deb http://mirrors.ustc.edu.cn/debian-security bookworm-security main contrib non-free" >> /etc/apt/sources.list && \
echo "Acquire::http::Proxy \"http://mirrors.ustc.edu.cn:80\";" > /etc/apt/apt.conf.d/99proxy && \
apt-get update && \
apt-get --no-install-recommends -y install git curl unzip python3-dev python3-pip golang-go mingw-w64 zlib1g gcc && \
rm -rf /var/lib/apt/lists/*

# Fix line ending error that can be caused by cloning the project in a Windows environment
RUN if [ -f "/usr/src/app/plugins/sandcat/update-agents.sh" ]; then \
        echo "Fixing line endings and permissions for sandcat update-agents.sh"; \
        cd /usr/src/app/plugins/sandcat && \
        tr -d '\15\32' < ./update-agents.sh > ./update-agents.sh.tmp && \
        mv ./update-agents.sh.tmp ./update-agents.sh && \
        chmod +x ./update-agents.sh; \
    else \
        echo "ERROR: sandcat submodule is not properly initialized - update-agents.sh not found"; \
        echo "Available files in plugins/sandcat:"; \
        ls -la /usr/src/app/plugins/sandcat/ || echo "Directory does not exist"; \
        echo "This indicates the submodule initialization failed in the previous step"; \
        exit 1; \
    fi

# Set timezone (default to UTC)
ARG TZ="UTC"
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && \
    echo $TZ > /etc/timezone

# Install pip requirements
RUN pip3 install --break-system-packages --no-cache-dir -r requirements.txt 

# For offline atomic (disable it by default in slim image)
# Disable atomic if this is not downloaded
RUN if [ ! -d "/usr/src/app/plugins/atomic/data/atomic-red-team" ] && [ "$VARIANT" = "full" ]; then   \
        git clone --depth 1 https://github.com/redcanaryco/atomic-red-team.git \
            /usr/src/app/plugins/atomic/data/atomic-red-team;                  \
    else \
        sed -i '/\- atomic/d' conf/default.yml; \
fi

# For offline emu
# (Emu is disabled by default, no need to disable it if slim variant is being built)
RUN if [ ! -d "/usr/src/app/plugins/emu/data/adversary-emulation-plans" ] && [ "$VARIANT" = "full" ]; then   \
        git clone --depth 1 https://github.com/center-for-threat-informed-defense/adversary_emulation_library \
            /usr/src/app/plugins/emu/data/adversary-emulation-plans;                  \
fi

# Download emu payloads
# emu doesn't seem capable of running this itself - always download
RUN cd /usr/src/app/plugins/emu; ./download_payloads.sh

# The commands above (git clone) will generate *huge* .git folders - remove them
RUN (find . -type d -name ".git") | xargs rm -rf

# Install Go dependencies
RUN if [ -d "/usr/src/app/plugins/sandcat/gocat" ] && [ -f "/usr/src/app/plugins/sandcat/gocat/go.mod" ]; then \
        echo "Installing Go dependencies for sandcat"; \
        cd /usr/src/app/plugins/sandcat/gocat && go mod tidy && go mod download; \
    else \
        echo "ERROR: sandcat gocat directory or go.mod not found"; \
        echo "Contents of plugins/sandcat:"; \
        ls -la /usr/src/app/plugins/sandcat/ || echo "Directory does not exist"; \
        exit 1; \
    fi

# Update sandcat agents
RUN if [ -f "/usr/src/app/plugins/sandcat/update-agents.sh" ]; then \
        echo "Updating sandcat agents"; \
        cd /usr/src/app/plugins/sandcat && ./update-agents.sh; \
    else \
        echo "ERROR: update-agents.sh not found in sandcat plugin"; \
        exit 1; \
    fi

# Make sure emu can always be used in container (even if not enabled right now)
RUN cd /usr/src/app/plugins/emu; \
    pip3 install --break-system-packages -r requirements.txt

# Install builder plugin requirements
RUN cd /usr/src/app/plugins/builder; \
    pip3 install --break-system-packages -r requirements.txt

STOPSIGNAL SIGINT

# Default HTTP port for web interface and agent beacons over HTTP
EXPOSE 8888

# Default HTTPS port for web interface and agent beacons over HTTPS (requires SSL plugin to be enabled)
EXPOSE 8443

# TCP and UDP contact ports
EXPOSE 7010
EXPOSE 7011/udp

# Websocket contact port
EXPOSE 7012

# Default port to listen for DNS requests for DNS tunneling C2 channel
EXPOSE 8853

# Default port to listen for SSH tunneling requests
EXPOSE 8022

# Default FTP port for FTP C2 channel
EXPOSE 2222

ENTRYPOINT ["python3", "server.py"]
