# Use official OpenWRT SDK image for x86-64 (faster native builds on Intel Mac)
FROM openwrt/sdk:x86-64-24.10.0

# Switch to root to set up directories
USER root

# Create directories and set ownership to buildbot user
RUN mkdir -p /builder/package/mini-mwan /builder/feeds /builder/dl /builder/bin && \
    chown -R buildbot:buildbot /builder/feeds /builder/dl /builder/bin

# Switch back to buildbot user
USER buildbot

# Set working directory to the SDK location
WORKDIR /builder

# The package files will be mounted at build time to /builder/package/mini-mwan/
# Feeds will be in Docker volumes for performance (owned by buildbot)
# Output will be in /builder/bin (mounted)

CMD ["/bin/bash"]
