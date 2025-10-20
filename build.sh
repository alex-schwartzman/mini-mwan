#!/bin/bash
# Build script for mini-mwan package using Docker
# Follows official OpenWRT SDK pattern

set -e

echo "Building mini-mwan package for ramips/mt7621..."

# Build or start the Docker container
docker-compose up -d

# Run the build inside the container
docker-compose exec -T openwrt-sdk bash -c "
    # Update feeds (cached in Docker volume for performance)
    echo 'Updating feeds...'
    ./scripts/feeds update -a

    echo 'Installing feeds...'
    ./scripts/feeds install -a

    # Build the package
    echo 'Building mini-mwan package...'
    make package/mini-mwan/compile V=s
"

echo ""
echo "Build complete! Packages are in ./bin directory:"
ls -lh ./bin/packages/*/base/mini-mwan*.ipk 2>/dev/null || echo "No packages found"

# Stop the container
docker-compose down

echo ""
echo "To install on your device:"
echo "  scp ./bin/packages/*/base/mini-mwan*.ipk root@<router-ip>:/tmp/"
echo "  ssh root@<router-ip>"
echo "  opkg install /tmp/mini-mwan*.ipk"
