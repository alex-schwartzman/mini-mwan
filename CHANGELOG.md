# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
