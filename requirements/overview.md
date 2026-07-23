# Mini-MWAN - Software Requirements Specification

## 1. Overview

### 1.1 Purpose
Mini-MWAN is a lightweight multi-WAN management daemon for OpenWrt that provides automatic failover and load balancing across multiple internet connections.

### 1.2 Scope
This document specifies the requirements for mini-mwan, including:
- Interface monitoring and health detection
- Automatic routing management for failover and load balancing
- Configuration management via UCI
- Status reporting and logging
- Integration with OpenWrt network infrastructure (netifd)

### 1.3 Target Environment
- **Platform**: OpenWrt-based routers
- **Language**: Lua 5.1+
- **Dependencies**:
  - UCI (Unified Configuration Interface)
  - netifd (OpenWrt network daemon)
  - iproute2 (ip command)
  - nixio (Lua networking library)
  - cjson (JSON parsing)

### 1.4 Definitions and Acronyms

| Term | Definition |
|------|------------|
| WAN | Wide Area Network - Internet-facing network interface |
| UCI | Unified Configuration Interface - OpenWrt's configuration system |
| netifd | OpenWrt's network interface daemon |
| P2P | Point-to-Point - Network interfaces without traditional gateways (e.g., VPN tunnels) |
| Failover | Automatic switching to backup connection when primary fails |
| Multiuplink | Load balancing traffic across multiple connections |
| Metric | Route priority value (lower = higher priority) |
| Degraded | Interface state indicating configuration issues preventing normal operation |
| Cleanup | Removal of routes created by external tools or stale routes from previous configurations |
| Enforcement | Ensuring the correct route exists for a managed interface at the configured metric |

### 1.5 System Context

```
┌─────────────────────────────────────────────┐
│           OpenWrt Router                     │
│                                              │
│  ┌────────────┐         ┌──────────────┐   │
│  │   netifd   │◄────────┤  mini-mwan   │   │
│  │ (network   │ ubus    │  daemon      │   │
│  │  daemon)   │         │              │   │
│  └─────┬──────┘         └──────┬───────┘   │
│        │                       │            │
│        │                       │ ip route   │
│        ▼                       ▼            │
│  ┌─────────────────────────────────────┐   │
│  │      Linux Kernel Routing Table     │   │
│  └──┬────────┬────────┬────────┬───────┘   │
│     │        │        │        │            │
└─────┼────────┼────────┼────────┼────────────┘
      │        │        │        │
   ┌──▼──┐  ┌──▼──┐  ┌──▼──┐  ┌──▼──┐
   │WAN1 │  │WAN2 │  │WAN3 │  │ ... │
   │eth0 │  │wg0  │  │ppp0 │  │     │
   └──┬──┘  └──┬──┘  └──┬──┘  └─────┘
      │        │        │
   ┌──▼────────▼────────▼──────────────┐
   │        Internet (ISPs)             │
   └────────────────────────────────────┘
```

### 1.6 Design Goals

1. **Simplicity**: Lightweight daemon with minimal resource footprint
2. **Reliability**: Continuous monitoring with automatic recovery
3. **Flexibility**: Support various interface types (Ethernet, VPN, PPP, etc.)
4. **Transparency**: Clear logging and status reporting for troubleshooting
5. **Integration**: Seamless integration with OpenWrt ecosystem
6. **Resilience**: Handle degraded states gracefully without cascading failures

### 1.7 Out of Scope

The following are explicitly **NOT** part of mini-mwan's scope:
- Per-application routing policies (policy-based routing)
- Deep packet inspection or traffic shaping
- VPN tunnel establishment (only manages routing for existing tunnels)
- DHCP client functionality (relies on netifd)
- DNS management
- IPv6-only routing (IPv6 routing is only added as secondary on interfaces with IPv4 connectivity)
- GUI/Web interface (handled separately by luci-app-mini-mwan)
