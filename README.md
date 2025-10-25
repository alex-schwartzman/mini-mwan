# Mini-MWAN - Lightweight Multi-WAN for OpenWrt

A lightweight multi-WAN management daemon for OpenWrt with failover and load balancing capabilities. Designed as a simple alternative to mwan3 for OpenWrt 24.10+.

## What is Mini-MWAN?

Mini-MWAN monitors multiple WAN interfaces and manages routing based on connectivity status. It supports:

- **Failover mode**: Primary/backup WAN with automatic failback
- **Multi-uplink mode**: Load balancing across multiple WAN connections
- **Interface monitoring**: Ping-based connectivity checks through specific interfaces
- **Traffic statistics**: Real-time RX/TX byte counters with automatic formatting
- **Web interface**: LuCI integration for easy configuration and monitoring
- **Automatic recovery**: Interfaces automatically return to service when connectivity is restored

## Why Mini-MWAN?

With mwan3 unavailable in OpenWrt 24.10, Mini-MWAN provides a simpler, more maintainable solution for basic multi-WAN needs. It's written in pure Lua with minimal dependencies, making it easy to understand, modify, and troubleshoot.

## Requirements

- **OpenWrt**: 24.10 or later
- **Architecture**: Platform-independent (Lua-based)
- **Dependencies**:
  - `lua`
  - `libuci-lua`
  - `luci-lib-nixio`
  - `lua-cjson`
  - `luci-base` (for web interface)

## Installation

### Pre-built Packages

Download the latest `.ipk` files from [GitHub Releases](https://github.com/alex-schwartzman/mini-mwan/releases).

**Via SSH:**
```bash
# Copy packages to your router
scp mini-mwan_*.ipk luci-app-mini-mwan_*.ipk root@192.168.1.1:/tmp/

# SSH into your router
ssh root@192.168.1.1

# Install the packages
opkg install /tmp/mini-mwan_*.ipk
opkg install /tmp/luci-app-mini-mwan_*.ipk
```

**Via LuCI Web Interface:**
1. Navigate to: System → Software
2. Click "Upload Package..."
3. Upload and install `mini-mwan_*.ipk`
4. Repeat for `luci-app-mini-mwan_*.ipk`

### Building from Source

See [Building the Package](#building-the-package) section below.

## Configuration

### Via LuCI Web Interface

1. Navigate to: **Network → Mini-MWAN**
2. Configure your WAN interfaces:
   - Enable/disable each interface
   - Set ping target (e.g., 1.1.1.1, 8.8.8.8)
   - Set metric (lower = higher priority in failover mode)
   - Set weight (for load balancing in multi-uplink mode)
3. Configure global settings:
   - **Mode**: `failover` or `multi-uplink`
   - **Check interval**: How often to ping (in seconds)
4. Click **Save & Apply**

### Via UCI Command Line

#### Basic Configuration Example

```bash
# Global settings
uci set mini-mwan.global=global
uci set mini-mwan.global.enabled='1'
uci set mini-mwan.global.mode='failover'
uci set mini-mwan.global.check_interval='30'

# Configure WAN1 (primary)
uci set mini-mwan.wan1=interface
uci set mini-mwan.wan1.enabled='1'
uci set mini-mwan.wan1.name='wan'
uci set mini-mwan.wan1.ping_target='1.1.1.1'
uci set mini-mwan.wan1.ping_count='3'
uci set mini-mwan.wan1.ping_timeout='2'
uci set mini-mwan.wan1.metric='100'
uci set mini-mwan.wan1.weight='1'

# Configure WAN2 (backup)
uci set mini-mwan.wan2=interface
uci set mini-mwan.wan2.enabled='1'
uci set mini-mwan.wan2.name='wan2'
uci set mini-mwan.wan2.ping_target='8.8.8.8'
uci set mini-mwan.wan2.ping_count='3'
uci set mini-mwan.wan2.ping_timeout='2'
uci set mini-mwan.wan2.metric='200'
uci set mini-mwan.wan2.weight='1'

# Commit and restart
uci commit mini-mwan
/etc/init.d/mini-mwan restart
```

#### Configuration Parameters

**Global Settings:**
- `enabled`: Enable/disable the service (0/1)
- `mode`: Operation mode (`failover` or `multi-uplink`)
- `check_interval`: Ping check interval in seconds (5-3600)

**Interface Settings:**
- `enabled`: Enable/disable this interface (0/1)
- `name`: OpenWrt interface name (e.g., `wan`, `wan2`)
- `ping_target`: IP address to ping for connectivity check
- `ping_count`: Number of ping attempts (default: 3)
- `ping_timeout`: Ping timeout in seconds (default: 2)
- `metric`: Routing metric - lower value = higher priority (default: 100)
- `weight`: Load balancing weight in multi-uplink mode (default: 1)

### Service Control

```bash
# Start service
/etc/init.d/mini-mwan start

# Stop service
/etc/init.d/mini-mwan stop

# Restart service
/etc/init.d/mini-mwan restart

# Check status
/etc/init.d/mini-mwan status

# Enable on boot
/etc/init.d/mini-mwan enable

# Disable on boot
/etc/init.d/mini-mwan disable
```

## Monitoring

### Via LuCI Web Interface

Navigate to **Network → Mini-MWAN → Status** to see:
- Current operation mode
- Interface status (UP/DOWN/Disabled)
- Ping latency
- Traffic statistics (RX/TX bytes)
- Gateway information
- Last check timestamp

Status updates automatically every 5 seconds.

### Via Command Line

```bash
# View status file
cat /var/run/mini-mwan.status

# View logs
cat /var/log/mini-mwan.log

# Or via logread
logread | grep mini-mwan
```

## Comparison with mwan3

| Feature | Mini-MWAN | mwan3 |
|---------|-----------|-------|
| **Complexity** | ~500 lines of Lua | ~10,000+ lines |
| **Dependencies** | 4 packages | Many (including iptables, ipset, etc.) |
| **Configuration** | Simple UCI config | Complex rules and policies |
| **Failover** | ✅ Yes | ✅ Yes |
| **Load Balancing** | ✅ Basic (weight-based) | ✅ Advanced (ratio, balance) |
| **Traffic Statistics** | ✅ Yes (RX/TX) | ❌ No |
| **Custom Rules** | ❌ No | ✅ Yes (iptables-based) |
| **Sticky Sessions** | ❌ No | ✅ Yes |
| **Per-protocol Routing** | ❌ No | ✅ Yes |
| **OpenWrt 24.10** | ✅ Supported | ❌ Not available |

**Use Mini-MWAN if you need:**
- Simple failover between 2-3 WAN connections
- Basic load balancing
- Easy setup and maintenance
- OpenWrt 24.10 compatibility

**Use mwan3 if you need:**
- Complex routing policies
- Per-application or per-protocol routing
- Sticky sessions for specific services
- OpenWrt 23.05 or earlier

## Building the Package

### Prerequisites

- Docker Desktop (macOS, Windows, or Linux)
- Git

### Quick Build

```bash
# Clone the repository
git clone https://github.com/alex-schwartzman/mini-mwan.git
cd mini-mwan

# Build using Docker
make -f Makefile.dev rebuild-hard
```

Built packages will be in `./bin/packages/x86_64/base/`:
- `mini-mwan_1.0.0-r1_all.ipk`
- `luci-app-mini-mwan_1.0.0-r1_all.ipk`

### Development Environment

This project includes a Docker-based development environment and VS Code devcontainer support.

**Available make targets:**
```bash
make -f Makefile.dev build          # Build both packages
make -f Makefile.dev rebuild-hard   # Full rebuild from scratch
make -f Makefile.dev clean-soft     # Clean build artifacts
make -f Makefile.dev shell          # Open shell in container
make -f Makefile.dev help           # Show all targets
```

**VS Code users:**
1. Install "Dev Containers" extension
2. Open project in VS Code
3. Click "Reopen in Container"
4. Use integrated terminal for building

## Troubleshooting

### Service won't start
```bash
# Check logs
logread | grep mini-mwan

# Check UCI configuration
uci show mini-mwan

# Verify dependencies
opkg list-installed | grep -E 'lua|uci|nixio|cjson'
```

### Interface not monitored
- Verify interface name matches OpenWrt interface (not device)
- Check that ping target is reachable
- Ensure interface is enabled in both OpenWrt and Mini-MWAN config
- Check `/var/run/mini-mwan.status` for error messages

### No status displayed in LuCI
- Verify `luci-app-mini-mwan` is installed
- Restart uhttpd: `/etc/init.d/uhttpd restart`
- Clear browser cache

## Contributing

Contributions are welcome! Please:
1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Submit a pull request

## License

GPL-2.0 - See [LICENSE](LICENSE) file for details.

## Author

Alex Schwartzman <openwrt@schwartzman.uk>

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and changes.
