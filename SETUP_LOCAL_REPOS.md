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

3. **Checkout the correct branches/commits (optional but recommended):**
   ```bash
   cd ~/openwrt-repos/openwrt
   git checkout openwrt-24.10

   cd ~/openwrt-repos/packages
   git checkout 201fd099b80a2931b7326ce20b0cbb824296c99f

   cd ~/openwrt-repos/luci
   git checkout 7b0663a5557118499dc3b3d44550efc1b6fa3feb

   cd ~/openwrt-repos/routing
   git checkout e87b55c6a642947ad7e24cd5054a637df63d5dbe

   cd ~/openwrt-repos/telephony
   git checkout fd605af7143165a2490681ec1752f259873b9147
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
