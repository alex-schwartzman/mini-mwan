# Parametrized Dockerfile for OpenWRT SDK builds
# Use build arg to specify architecture (e.g., x86-64, ramips-mt76x8)
ARG ARCH=x86-64
FROM openwrt/sdk:${ARCH}-25.12.0-rc1

# Switch to root to set up directories
USER root

# Create directories and set ownership to buildbot user
RUN mkdir -p /builder/package /builder/feeds /builder/dl /builder/bin && \
    chown -R buildbot:buildbot /builder/feeds /builder/dl /builder/bin

# Switch back to buildbot user
USER buildbot

# Set working directory to the SDK location
WORKDIR /builder

# The mini-mwan files will be mounted at build time to /openwrt-repos/packages/net/mini-mwan/
# Feeds will be installed into Docker volumes for performance (owned by buildbot)
# Source of feeds will be local copies of repos.
# Output will be in /builder/bin (mounted)

CMD ["/bin/bash"]
