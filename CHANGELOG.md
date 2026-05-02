# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- **Interface classification refactored to explicit 5-state FSA** (`routing_class` replaces `degraded`/`degraded_reason`/`is_up`/`does_exist`)
  - States: `absent` | `down` | `unconfigured` | `probe_only` | `usable`
  - `probe_only` (kernel-UP, no ping) now receives metric-900 routes for recovery probing — previously these interfaces were silently ignored
  - `unconfigured` (no gateway or IPv6 detected) receives no route — prevents routing blackholes during DHCP renegotiation
  - All routing decisions (failover, multiuplink, probe routes) now keyed on `routing_class` string
  - LuCI status page updated to display `routing_class` with per-state badge and row colouring
  - ubus `mini-mwan.status` response updated: removed `does_exist`, `is_up`, `degraded`, `degraded_reason`; added `routing_class`
- **P2P gateway fix**: `probe_all_gateways` now ignores nexthop `"0.0.0.0"` (netifd encoding for P2P routes) — previously WireGuard interfaces were assigned `gateway = "0.0.0.0"` causing `via 0.0.0.0` to be re-set every cycle
- **Gateway Discovery**: Refactored to use libubus library directly instead of shell execution
  - Changed from `exec("ubus call network.interface dump")` with JSON parsing to native `conn:call()` API
  - Eliminates shell command overhead and JSON serialization/deserialization
  - Fixes test state pollution by moving `conn` from module-level to `deps.ubus_conn`
  - Removes impossible "invalid JSON" error scenario (libubus guarantees valid Lua tables)
- **BREAKING**: Replaced file-based status communication with ubus
  - Status now exposed via `ubus call mini-mwan status` instead of `/var/run/mini-mwan.status`
  - Status format changed from INI to JSON
  - LuCI frontend updated to use ubus RPC instead of file reads
  - Daemon now uses uloop event loop instead of blocking sleep loop
  - rpcd ACL updated to grant access to `mini-mwan.status` ubus method

### Removed
- `/var/run/mini-mwan.status` file no longer created
- File-based status polling removed from LuCI

## [1.0.0] - 2025-10-23

### Added
- Network traffic statistics (RX/TX bytes) displayed in status page with automatic formatting (B/KB/MB/GB/TB)
- Interface-specific routing with metric and weight configuration support
- LuCI web interface for status monitoring and configuration
- Real-time status updates every 5 seconds
- Support for both failover and multi-uplink (load balancing) modes
- Ping-based connectivity monitoring through specific interfaces
- Automatic interface state tracking with timestamp logging
- Status file generation at `/var/run/mini-mwan.status`
- Configuration via UCI (`/etc/config/mini-mwan`)
- Init script for automatic startup
- Docker-based development environment with OpenWrt SDK
- Offline build support with local feeds
- Interface-specific ping checks to prevent false positives

## [Unreleased]

### Planned
- Community feedback integration
- CI/CD on GitHub actions
