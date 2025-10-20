# Mini-MWAN OpenWRT Application

A skeleton OpenWRT application with LuCI web interface for Multi-WAN management.

## Project Structure

```
mini-mwan/
├── Makefile                          # Main package Makefile
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

## Installation

### Building for OpenWRT

1. Copy this directory to your OpenWRT buildroot:
   ```bash
   cp -r mini-mwan/ <openwrt-buildroot>/package/network/services/
   ```

2. Copy the LuCI app to the feeds:
   ```bash
   cp -r luci-app-mini-mwan/ <openwrt-buildroot>/feeds/luci/applications/
   ```

3. Update and install feeds:
   ```bash
   cd <openwrt-buildroot>
   ./scripts/feeds update -a
   ./scripts/feeds install -a
   ```

4. Configure and build:
   ```bash
   make menuconfig
   # Select: Network -> mini-mwan
   # Select: LuCI -> Applications -> luci-app-mini-mwan
   make package/mini-mwan/compile V=s
   make package/luci-app-mini-mwan/compile V=s
   ```

### Installing on OpenWRT Device

1. Copy the built packages to your device
2. Install using opkg:
   ```bash
   opkg install mini-mwan_*.ipk
   opkg install luci-app-mini-mwan_*.ipk
   ```

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
