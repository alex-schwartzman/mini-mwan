# Mini-MWAN OpenWRT Application

A skeleton OpenWRT application with LuCI web interface for Multi-WAN management.

## Project Structure

```
mini-mwan/
├── Makefile                          # Main package Makefile
├── Dockerfile                        # OpenWRT SDK Docker image
├── docker-compose.yml                # Docker Compose configuration
├── build.sh                          # Automated build script
├── .devcontainer/
│   └── devcontainer.json             # VS Code devcontainer config
├── .vscode/
│   ├── tasks.json                    # VS Code build tasks
│   └── extensions.json               # Recommended extensions
├── .editorconfig                     # Editor configuration
├── files/
│   ├── mini-mwan.sh                  # Main application script
│   ├── mini-mwan.config              # UCI configuration template
│   └── mini-mwan.init                # Init script
├── luasrc/
│   ├── controller/
│   │   └── mini-mwan.lua             # LuCI controller
│   └── model/
│       └── cbi/
│           └── mini-mwan.lua         # LuCI CBI model
└── luci-app-mini-mwan/
    └── Makefile                      # LuCI application Makefile
```

## Configuration Parameters

The application includes two configuration parameters accessible via LuCI:

1. **Enable/Disable** (`enabled`)
   - Type: Boolean (0/1)
   - Default: 0 (disabled)
   - Description: Enable or disable the mini-mwan service

2. **Check Interval** (`check_interval`)
   - Type: Integer (range: 5-3600)
   - Default: 30 seconds
   - Description: Interval in seconds to check WAN connections

## Building the Package

### Prerequisites

- Docker Desktop installed on macOS
- Your OpenWRT device info (for this example: ASUS RT-AX53U with ramips/mt7621 architecture)

### Quick Build with Docker

The easiest way to build the package is using the provided Docker setup:

```bash
# Simply run the build script
./build.sh
```

This will:
1. Build/start a Docker container with the OpenWRT SDK for ramips/mt7621
2. Compile the mini-mwan package
3. Output the .ipk files to the `./bin` directory

The built packages will be:
- `mini-mwan_1.0.0-1_all.ipk` - Main package
- `luci-app-mini-mwan_*.ipk` - LuCI web interface (if included)

### Manual Docker Build

If you prefer to build manually:

```bash
# Build the Docker image
docker-compose build

# Start the container
docker-compose up -d

# Enter the container
docker-compose exec openwrt-sdk bash

# Inside the container:
./scripts/feeds update -a
./scripts/feeds install -a
make package/mini-mwan/compile V=s

# Copy packages to output
mkdir -p /home/build/bin
find bin/packages -name 'mini-mwan*.ipk' -exec cp {} /home/build/bin/ \;

# Exit container
exit

# Stop container
docker-compose down
```

### Building for Different Architecture

If your device has a different architecture, edit the `Dockerfile` and change:
```dockerfile
FROM openwrt/sdk:ramips-mt7621-24.10.0
```

Common architectures:
- `x86-64-24.10.0` - x86 64-bit devices
- `ramips-mt7621-24.10.0` - MediaTek MT7621 (ASUS RT-AX53U, etc.)
- `ath79-generic-24.10.0` - Atheros AR71xx/AR9xxx
- `bcm27xx-bcm2711-24.10.0` - Raspberry Pi 4

Find your architecture at: https://downloads.openwrt.org/releases/24.10.0/targets/

## Development with VS Code

This project includes a VS Code devcontainer configuration for seamless development.

### Setup

1. Install the "Dev Containers" extension in VS Code:
   - Extension ID: `ms-vscode-remote.remote-containers`

2. Open this project in VS Code

3. When prompted, click "Reopen in Container" (or press `F1` and search for "Dev Containers: Reopen in Container")

VS Code will:
- Build the Docker container using the same `Dockerfile`
- Install recommended extensions (Lua, ShellCheck, etc.)
- Set up the OpenWRT SDK environment
- Mount your workspace for live editing

### Building from VS Code

Once inside the container, you can build using:

**Option 1: VS Code Tasks (Recommended)**
- Press `Cmd+Shift+B` (macOS) or `Ctrl+Shift+B` (Linux/Windows)
- Select "Build and copy packages"

**Option 2: Integrated Terminal**
```bash
# Open a terminal in VS Code (Ctrl+`)
cd /home/build/openwrt
make package/mini-mwan/compile V=s

# Copy to output directory
mkdir -p /home/build/bin
find bin/packages -name 'mini-mwan*.ipk' -exec cp {} /home/build/bin/ \;
```

Built packages will appear in your local `./bin` directory.

### Why This Approach?

**Single Source of Truth**: Both the standalone build script and VS Code devcontainer use the **same Dockerfile**. This means:
- No configuration drift between environments
- Same build environment whether you use `./build.sh` or VS Code
- Changes to the Dockerfile automatically apply to both

**Workflow Flexibility**:
- Use `./build.sh` for quick CI/CD builds
- Use VS Code devcontainer for development with full IDE features
- Both produce identical results

## Installing on OpenWRT Device

### Option 1: Via SCP and SSH

```bash
# Copy packages to your router
scp bin/*.ipk root@192.168.1.1:/tmp/

# SSH into your router
ssh root@192.168.1.1

# Install the packages
opkg install /tmp/mini-mwan_*.ipk
opkg install /tmp/luci-app-mini-mwan_*.ipk
```

### Option 2: Via LuCI Web Interface

1. Open your router's web interface (e.g., http://192.168.1.1)
2. Navigate to: System → Software
3. Click "Upload Package..."
4. Upload `mini-mwan_*.ipk` and click "Install"
5. Repeat for `luci-app-mini-mwan_*.ipk`

## Usage

### Via LuCI Web Interface

1. Navigate to: Network → Mini-MWAN
2. Configure the settings:
   - Enable the service
   - Set the check interval (in seconds)
3. Click "Save & Apply"

### Via UCI Command Line

```bash
# Enable the service
uci set mini-mwan.global.enabled='1'

# Set check interval to 60 seconds
uci set mini-mwan.global.check_interval='60'

# Commit changes
uci commit mini-mwan

# Restart service
/etc/init.d/mini-mwan restart
```

### Service Control

```bash
# Start service
/etc/init.d/mini-mwan start

# Stop service
/etc/init.d/mini-mwan stop

# Restart service
/etc/init.d/mini-mwan restart

# Enable on boot
/etc/init.d/mini-mwan enable

# Disable on boot
/etc/init.d/mini-mwan disable
```

## Development

### Adding More Configuration Parameters

1. Edit `files/mini-mwan.config` to add new UCI options
2. Update `luasrc/model/cbi/mini-mwan.lua` to add LuCI form fields
3. Modify `files/mini-mwan.sh` to use the new parameters

### Customizing Application Logic

Edit `files/mini-mwan.sh` to implement your custom Multi-WAN logic in the `start_service()` and `stop_service()` functions.

## License

GPL-2.0

## Author

Your Name <your.email@example.com>
