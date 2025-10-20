# Use official OpenWRT SDK image for ramips/mt7621
FROM openwrt/sdk:ramips-mt7621-24.10.0

# Set working directory
WORKDIR /home/build/openwrt

# The package will be mounted at build time
CMD ["/bin/bash"]
