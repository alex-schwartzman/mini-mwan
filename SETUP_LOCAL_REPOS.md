# Setting Up Local OpenWRT Repositories

This guide explains how to set up local OpenWRT repository clones for offline development and to avoid network traffic during builds.

## Initial Setup (One-Time, Requires Internet)

1. **Create the repository directory:**
   ```bash
   mkdir -p ~/openwrt-repos
   cd ~/openwrt-repos
   ```

2. **Clone the OpenWRT repositories:**
   ```bash
   # Main OpenWRT repository
   git clone https://git.openwrt.org/openwrt/openwrt.git

   # Feed repositories
   git clone https://git.openwrt.org/feed/packages.git
   git clone https://git.openwrt.org/project/luci.git
   git clone https://git.openwrt.org/feed/routing.git
   git clone https://git.openwrt.org/feed/telephony.git
   ```

3. **Checkout the correct branches/commits:**
   ```bash

   Recommended: Use v24.10.4 (latest stable release)

  cd ~/openwrt-repos/openwrt && git checkout openwrt-24.10 && git pull
  cd ~/openwrt-repos/packages && git checkout openwrt-24.10 && git pull
  cd ~/openwrt-repos/luci && git checkout openwrt-24.10 && git pull
  cd ~/openwrt-repos/routing && git checkout openwrt-24.10 && git pull
  cd ~/openwrt-repos/telephony && git checkout openwrt-24.10 && git pull

   ```

## Building with Local Repositories

1. **Start the container:**
   ```bash
   docker-compose run --rm openwrt-sdk bash
   ```

2. **Update feeds (uses local repos, no network required):**
   ```bash
   scripts/feeds update -i -a
   ```

   The `-i` flag tells the script to only recreate the index without fetching from network.

3. **Install feeds:**
   ```bash
   scripts/feeds install -a
   ```

4. **Build your package as usual:**
   ```bash
   make package/mini-mwan/compile V=s
   ```

## Updating Repositories (When Online)

When you want to get the latest updates from upstream:

```bash
cd ~/openwrt-repos/openwrt
git pull

cd ~/openwrt-repos/packages
git pull

cd ~/openwrt-repos/luci
git pull

cd ~/openwrt-repos/routing
git pull

cd ~/openwrt-repos/telephony
git pull
```

Then rebuild the feeds index in the container:
```bash
docker-compose run --rm openwrt-sdk scripts/feeds update -i -a
```

## Benefits

- **Offline development:** Work without internet connectivity
- **Faster builds:** No network fetches during `scripts/feeds update`
- **Version control:** Pin to specific commits by checking out branches/tags in your local repos
- **Network efficiency:** Update all repos once, use them for multiple experiments

## File Structure

```
~/openwrt-repos/          # Local git repositories (on host)
├── openwrt/
├── packages/
├── luci/
├── routing/
└── telephony/

mini-mwan/
├── feeds.conf            # Custom feeds config pointing to local repos
└── docker-compose.yml    # Mounts ~/openwrt-repos into container
```

## Troubleshooting

**If feeds update fails:**
- Ensure all repositories are cloned to `~/openwrt-repos/`
- Check that the repository names match exactly (case-sensitive)
- Verify the container can see the mounted repos: `docker-compose run --rm openwrt-sdk ls /openwrt-repos`

**To switch back to network-based feeds:**
- Remove or rename `feeds.conf`
- The SDK will fall back to `feeds.conf.default` which uses remote URLs
