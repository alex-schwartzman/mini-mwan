# Mini-MWAN Requirements Documentation

This directory contains the complete software requirements specification for the Mini-MWAN project.

## Document Structure

The requirements are organized into the following documents:

### 1. [Overview](./overview.md)
High-level system overview including:
- Purpose and scope
- Target environment and dependencies
- System context diagram
- Design goals
- Out-of-scope items

**Read this first** to understand what Mini-MWAN is and what it aims to achieve.

### 2. [Functional Requirements](./functional-requirements.md)
Detailed functional requirements organized by subsystem:
- **FR-1**: Interface Monitoring (connectivity detection, state detection, latency measurement)
- **FR-2**: Routing Management (failover mode, multiuplink mode, P2P support)
- **FR-3**: Configuration Management (UCI integration, parameters, validation)
- **FR-4**: State Persistence (runtime state, status file output)
- **FR-5**: Logging and Audit (dual logging, event tracking, network statistics)
- **FR-6**: Operational Requirements (daemon lifecycle, service control)

**Use this** to understand what the system does and how it behaves.

### 3. [Non-Functional Requirements](./non-functional-requirements.md)
Quality attributes and constraints:
- **NFR-1**: Performance (resource footprint, response time, scalability)
- **NFR-2**: Reliability (availability, fault tolerance, recovery)
- **NFR-3**: Maintainability (code quality, modularity, debuggability)
- **NFR-4**: Compatibility (OpenWrt integration, interface types, Lua version)
- **NFR-5**: Security (privileges, input validation, audit trail)
- **NFR-6**: Usability (operational simplicity, observability, error messages)
- **NFR-7**: Portability (architecture independence, OpenWrt versions)
- **NFR-8**: Testability (unit testing, integration testing, field testing)

**Use this** to understand performance, reliability, and quality requirements.

### 4. [Data Requirements](./data-requirements.md)
Data structures, formats, and interfaces:
- **DR-1**: Configuration File Format (UCI structure and fields)
- **DR-2**: Status File Format (INI-style output format)
- **DR-3**: Log File Format (application logs and syslog)
- **DR-4**: Runtime Data Structures (internal Lua tables)
  - **DR-4.1**: State model (Config vs State vs Status)
  - **DR-4.2**: Interface state object (ephemeral, rebuilt each cycle)
  - **DR-4.3**: Persistent state table (survives config reloads)
  - **DR-4.4**: State persistence rules
- **DR-5**: External Interface Dependencies (netifd, ip commands, ping)
- **DR-6**: File System Requirements (locations, permissions)
- **DR-7**: Data Validation Requirements (input sanitization, type coercion)

**Use this** to understand data formats, APIs, and validation rules.

**Note**: Mini-MWAN distinguishes between:
- **Config**: Immutable data from UCI (device, metric, ping_target, etc.)
- **State**: Runtime data discovered each cycle (gateway, latency, routing_class)
- **Status**: Presentation layer for ubus/LuCI display
- **Persistent State**: Only `routing_class`, `does_exist`, `status_since` survive config reloads

### 5. [Constraints and Dependencies](./constraints-and-dependencies.md)
Platform limitations and dependencies:
- **CD-1**: Platform Constraints (hardware, network, filesystem)
- **CD-2**: Software Dependencies (OS, Lua, system tools, services)
- **CD-3**: Design Constraints (language, architecture, integration)
- **CD-4**: Operational Constraints (privileges, timing, boot sequence)
- **CD-5**: External Interface Constraints (UCI, netifd, kernel routing)
- **CD-6**: Compatibility Constraints (backward/forward compatibility)
- **CD-7**: Development Constraints (environment, testing, documentation)

**Use this** to understand the limitations and dependencies of the system.

---

## Requirement ID Format

Requirements use the following ID format:
- **FR-X.Y**: Functional Requirement, subsystem X, requirement Y
- **NFR-X.Y**: Non-Functional Requirement, category X, requirement Y
- **DR-X.Y**: Data Requirement, subsystem X, requirement Y
- **CD-X.Y**: Constraint/Dependency, category X, item Y

### Priority Levels
- **Critical**: Must-have for basic operation
- **High**: Important for production use
- **Medium**: Desirable for complete solution
- **Low**: Nice-to-have or future enhancement

---

## Requirements Traceability

### Core Features

| Feature | Requirements |
|---------|--------------|
| Failover routing | FR-2.1, FR-1.1, FR-1.5, FR-2.4, NFR-2.2 |
| Multiuplink (load balancing) | FR-2.2, FR-1.1, FR-1.5, FR-2.4, NFR-2.2 |
| Interface monitoring | FR-1.1 through FR-1.6, NFR-1.2 |
| Route management | FR-2.4, FR-2.5 |
| Configuration management | FR-3.1 through FR-3.5, DR-1.1, CD-5.1 |
| State persistence | FR-4.1, FR-4.2, DR-4.1, DR-4.2 |
| Degradation detection | FR-1.6, DR-2.1, DR-4.1 |
| P2P interface support | FR-2.3, FR-1.6, DR-1.1 |
| Logging and audit | FR-5.1 through FR-5.4, DR-3.1, DR-3.2 |

### Quality Attributes

| Attribute | Requirements |
|-----------|--------------|
| Low resource usage | NFR-1.1, CD-1.1 |
| Fast failover | NFR-1.2, CD-4.2 |
| High availability | NFR-2.1, NFR-2.2, NFR-2.4 |
| Easy troubleshooting | NFR-3.3, NFR-6.2, FR-5.1, FR-5.3 |
| OpenWrt integration | NFR-4.1, CD-2.1, CD-3.3 |
| Security | NFR-5.1 through NFR-5.4, CD-4.1 |

---

## Implementation Status

### Implemented Features
- ✅ Failover mode (FR-2.1)
- ✅ Multiuplink mode (FR-2.2)
- ✅ ICMP monitoring (FR-1.1)
- ✅ Interface state detection (FR-1.2)
- ✅ Gateway discovery via netifd (FR-1.3)
- ✅ Latency measurement (FR-1.4)
- ✅ Status classification (FR-1.5)
- ✅ Degradation detection (FR-1.6) - **Recently added**
- ✅ P2P interface support (FR-2.3) - **Recently added**
- ✅ UCI configuration (FR-3.1, FR-3.2, FR-3.3)
- ✅ State persistence (FR-4.1, FR-4.2)
- ✅ Dual logging (FR-5.1, FR-5.2)
- ✅ Audit mode (FR-5.3)
- ✅ Network statistics (FR-5.4)

### Planned Enhancements
- ⏳ Alternative health probes (HTTP, DNS instead of just ping)
- ⏳ Policy-based routing (out of scope for now)

### Known Limitations
- ⚠️ IPv4-first routing (IPv6 available as secondary on interfaces with IPv4 connectivity)
- ⚠️ ICMP only for monitoring (no TCP/UDP probes - CD-3.4)
- ⚠️ Polling-based (no event-driven architecture - CD-3.2)
- ⚠️ No unit tests (limited testing infrastructure - NFR-8.1, CD-7.2)

---

## Use Cases

### UC-1: Basic Failover Setup
**User Story**: As a home user, I want my router to automatically switch to a backup internet connection when the primary fails.

**Relevant Requirements**:
- FR-2.1 (Failover mode)
- FR-1.1, FR-1.5 (Connectivity detection and status)
- NFR-1.2 (Fast failover)
- FR-3.2, FR-3.3 (Configuration)

### UC-2: Dual-ISP Load Balancing
**User Story**: As a business, I want to load-balance traffic across two ISP connections to maximize throughput.

**Relevant Requirements**:
- FR-2.2 (Multiuplink mode)
- FR-3.3 (Weight configuration)
- NFR-1.3 (Scalability)

### UC-3: VPN Tunnel with ISP Failover
**User Story**: As a remote office, I want to maintain VPN connectivity through either of two ISP connections.

**Relevant Requirements**:
- FR-2.3 (P2P interface support)
- FR-2.1 (Failover mode)
- FR-1.6 (Degradation detection)

### UC-4: Cellular Backup for Cable
**User Story**: As a small business, I want to fall back to LTE when my cable internet fails.

**Relevant Requirements**:
- FR-2.1 (Failover mode)
- FR-3.3 (Metric configuration for priority)
- FR-1.6 (DHCP degradation handling)

### UC-5: Troubleshooting Connection Issues
**User Story**: As an administrator, I need to understand why failover isn't working.

**Relevant Requirements**:
- FR-5.1, FR-5.2 (Logging)
- FR-5.3 (Audit mode)
- FR-4.2 (Status file)
- NFR-3.3, NFR-6.2 (Debuggability and observability)

---

## Change History

| Date | Version | Changes | Requirements Affected |
|------|---------|---------|----------------------|
| 2024-10 | 1.0 | Initial requirements documentation | All |
| 2024-10 | 1.1 | Added degradation detection feature | FR-1.6, DR-2.1, DR-4.1 |
| 2024-10 | 1.1 | Added P2P interface support | FR-2.3, DR-1.1 |

---

## Contributing

When proposing new features or changes:
1. **Identify affected requirements** in this documentation
2. **Propose requirement changes** or additions
3. **Verify no conflicts** with existing requirements
4. **Update this documentation** when features are implemented

---

## References

### External Standards
- [OpenWrt Documentation](https://openwrt.org/docs/start)
- [UCI Configuration System](https://openwrt.org/docs/guide-user/base-system/uci)
- [Lua 5.1 Reference Manual](https://www.lua.org/manual/5.1/)
- [Linux Advanced Routing & Traffic Control](https://lartc.org/)

### Related Projects
- [mwan3](https://github.com/openwrt/packages/tree/master/net/mwan3) - Full-featured multi-WAN package
- [luci-app-mini-mwan](../luci-app-mini-mwan/) - Web UI for mini-mwan

### Internal Documentation
- [../README.md](../README.md) - Project README
- [../mini-mwan/files/mini-mwan.lua](../mini-mwan/files/mini-mwan.lua) - Main daemon implementation
- [../mini-mwan/files/mini-mwan.config](../mini-mwan/files/mini-mwan.config) - Example configuration
