#!/bin/bash
# Build script for mini-mwan package using Docker

set -e

echo "Building mini-mwan package for ramips/mt7621..."

# Build or start the Docker container
docker-compose up -d

# Run the build inside the container
docker-compose exec -T openwrt-sdk bash -c "
    # Update feeds (first time only, but safe to run again)
    ./scripts/feeds update -a
    ./scripts/feeds install -a

    # Build the package
    make package/mini-mwan/compile V=s

    # Copy built packages to output directory
    mkdir -p /builder/bin_output
    find bin/packages -name 'mini-mwan*.ipk' -exec cp -v {} /builder/bin_output/ \;
"

echo ""
echo "Build complete! Packages are in ./bin directory:"
ls -lh ./bin/*.ipk 2>/dev/null || echo "No packages found in ./bin"

# Stop the container
docker-compose down

echo ""
echo "To install on your device:"
echo "  scp bin/*.ipk root@<router-ip>:/tmp/"
echo "  ssh root@<router-ip>"
echo "  opkg install /tmp/mini-mwan*.ipk"
