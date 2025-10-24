# Use official OpenWRT SDK image for x86-64 (faster native builds on Intel Mac)
FROM openwrt/sdk:x86-64-24.10.0

# Build argument for enabling VS Code server pre-caching (devcontainer only)
ARG INSTALL_VSCODE_SERVER=false
ARG VSCODE_COMMIT=7d842fb85a0275a4a8e4d7e040d2625abbf7f084

# Switch to root to set up directories
USER root

# Create directories and set ownership to buildbot user
RUN mkdir -p /builder/package/mini-mwan /builder/feeds /builder/dl /builder/bin && \
    chown -R buildbot:buildbot /builder/feeds /builder/dl /builder/bin

# Install VS Code server (only when INSTALL_VSCODE_SERVER=true)
RUN if [ "$INSTALL_VSCODE_SERVER" = "true" ]; then \
        # Create vscode user if it doesn't exist
        if ! id -u vscode >/dev/null 2>&1; then \
            useradd -m -s /bin/bash vscode; \
        fi && \
        # Pre-cache VS Code server
        mkdir -p /home/vscode/.vscode-server/bin/${VSCODE_COMMIT} && \
        curl -fsSL "https://update.code.visualstudio.com/commit:${VSCODE_COMMIT}/server-linux-x64/stable" \
            -o /tmp/vscode-server.tar.gz && \
        tar -xzf /tmp/vscode-server.tar.gz -C /home/vscode/.vscode-server/bin/${VSCODE_COMMIT} --strip-components=1 && \
        rm /tmp/vscode-server.tar.gz && \
        chown -R vscode:vscode /home/vscode/.vscode-server; \
    fi

# Switch back to buildbot user
USER buildbot

# Set working directory to the SDK location
WORKDIR /builder

# The package files will be mounted at build time to /builder/package/mini-mwan/
# Feeds will be in Docker volumes for performance (owned by buildbot)
# Output will be in /builder/bin (mounted)

CMD ["/bin/bash"]
