# Constraints and Dependencies

## CD-1: Platform Constraints

### CD-1.1 Hardware Constraints
**ID**: CD-1.1
**Priority**: Critical
**Description**: Target hardware limitations.

**Memory Constraints**:
- Total system RAM: Typically 32MB - 512MB on OpenWrt routers
- Available RAM for applications: Often < 50MB after OS
- Flash storage: 4MB - 128MB (read-only squashfs)
- Writable overlay: Often < 10MB

**CPU Constraints**:
- Architecture: MIPS, ARM, or x86
- Clock speed: Typically 200MHz - 1GHz
- Cores: Often single-core
- No FPU on some platforms

**Implications**:
- Code MUST be memory-efficient (no large data structures)
- Minimize string allocations and concatenations
- Avoid floating-point where possible
- Use efficient algorithms (avoid O(n²) or worse)

### CD-1.2 Network Constraints
**ID**: CD-1.2
**Priority**: High
**Description**: Network environment limitations.

**Constraints**:
- Multiple WAN interfaces with varying speeds (1Mbps - 1Gbps)
- High latency on some connections (satellite, cellular)
- Asymmetric speeds (different upload/download)
- Dynamic IP addresses (DHCP)
- Interface state changes (physical disconnection)

**Implications**:
- Ping timeouts MUST be configurable
- Don't assume symmetric routing
- Handle DHCP lease renewals gracefully
- Expect interface flapping

### CD-1.3 Filesystem Constraints
**ID**: CD-1.3
**Priority**: High
**Description**: OpenWrt filesystem structure.

**Constraints**:
- Root filesystem is read-only squashfs
- `/etc` is overlay (copy-on-write)
- `/var` is tmpfs (lost on reboot)
- `/tmp` is tmpfs (lost on reboot)
- Limited write cycles on flash

**Implications**:
- Logs in /var are ephemeral
- Status files don't survive reboot
- Minimize writes to /etc
- No persistent state on disk

---

## CD-2: Software Dependencies

### CD-2.1 Operating System
**ID**: CD-2.1
**Priority**: Critical
**Description**: Required OS and version.

| Dependency | Version | Purpose |
|------------|---------|---------|
| OpenWrt | 21.02+ | Operating system |
| Linux Kernel | 5.4+ | Routing, networking |
| BusyBox | Any OpenWrt version | Core utilities |

### CD-2.2 Lua Runtime
**ID**: CD-2.2
**Priority**: Critical
**Description**: Lua interpreter and libraries.

| Dependency | Package Name | Version | Purpose |
|------------|--------------|---------|---------|
| Lua | `lua` | 5.1+ | Script execution |
| LuCI UCI | `libuci-lua` | Any | Configuration access |
| nixio | `luci-lib-nixio` | Any | Sleep, file operations |
| cJSON | `lua-cjson` | Any | JSON parsing |

**Package Installation**:
```bash
# ---- For OpenWrt 25+ ----
apk update
apk add lua libuci-lua luci-lib-nixio lua-cjson

# ---- For OpenWrt 24 and earlier ----
# opkg update
# opkg install lua libuci-lua luci-lib-nixio lua-cjson
```

### CD-2.3 System Tools
**ID**: CD-2.3
**Priority**: Critical
**Description**: Required command-line utilities.

| Tool | Package | Purpose |
|------|---------|---------|
| `ip` | `ip-full` or `ip-tiny` | Route management |
| `ping` | `busybox` | Connectivity testing |
| `ubus` | `netifd` | Gateway discovery |
| `logger` | `busybox` | Syslog integration |
| `grep` | `busybox` | Text filtering |

**Notes**:
- `ip-full` required for multipath routing
- `ip-tiny` may lack some features
- BusyBox versions of tools may have limited options

### CD-2.4 System Services
**ID**: CD-2.4
**Priority**: Critical
**Description**: Required system daemons.

| Service | Purpose | Interaction |
|---------|---------|-------------|
| netifd | Network management | Provides interface status via libubus API |
| procd | Process management | Manages daemon lifecycle |
| uci | Configuration system | Provides config access |
| logd | Log management | Receives syslog messages |

**Service Dependencies**:
- netifd MUST be running before mini-mwan starts
- UCI MUST be accessible for configuration
- procd MUST be available for daemon management

---

## CD-3: Design Constraints

### CD-3.1 Language Constraints
**ID**: CD-3.1
**Priority**: Critical
**Description**: Implementation language restrictions.

**Constraints**:
- MUST use Lua (OpenWrt standard)
- MUST NOT use compiled languages (no compiler on device)
- MUST use only standard Lua libraries available on OpenWrt
- MUST NOT require external Lua modules not in OpenWrt repos

**Rationale**:
- Lua is standard on OpenWrt
- Cross-compilation complexity
- Package size constraints
- Ease of modification in field

### CD-3.2 Architecture Constraints
**ID**: CD-3.2
**Priority**: High
**Description**: Software architecture limitations.

**Constraints**:
- Single-process daemon (no multi-process architecture)
- Polling-based (no event-driven architecture)
- No database (file-based state only)
- No external service dependencies
- No network protocols (pure local operations)

**Rationale**:
- Simplicity and reliability
- Limited resources
- Minimal dependencies
- Easy troubleshooting

### CD-3.3 Integration Constraints
**ID**: CD-3.3
**Priority**: High
**Description**: System integration requirements.

**Constraints**:
- MUST use UCI for configuration (OpenWrt standard)
- MUST use procd init system (no systemd)
- MUST NOT modify kernel routing policy
- MUST NOT interfere with firewall rules
- MUST NOT manage NAT or masquerading

**Rationale**:
- OpenWrt ecosystem consistency
- Separation of concerns
- Avoid conflicts with other services

### CD-3.4 Protocol Constraints
**ID**: CD-3.4
**Priority**: Medium
**Description**: Network protocol limitations.

**Constraints**:
- IPv4 ONLY (IPv6 not supported)
- ICMP ping for monitoring (no TCP/UDP probes)
- No BGP, OSPF, or other routing protocols
- No SNMP or other management protocols

**Current Limitations**:
- IPv6 detection causes degraded state
- Cannot monitor HTTPS endpoints
- Cannot use DNS for monitoring

**Future Considerations**:
- IPv6 support would require major refactoring
- Alternative probes (HTTP, DNS) could be added
- SNMP integration for monitoring could be beneficial

---

## CD-4: Operational Constraints

### CD-4.1 Privilege Requirements
**ID**: CD-4.1
**Priority**: Critical
**Description**: Required system privileges.

**Requirements**:
- Daemon MUST run as root
- Capability to modify routing table (CAP_NET_ADMIN)
- Read access to /sys/class/net
- Write access to /var and /tmp

**Rationale**:
- Routing table modification requires root
- OpenWrt doesn't support capability-based security
- System statistics require sysfs access

### CD-4.2 Timing Constraints
**ID**: CD-4.2
**Priority**: High
**Description**: Time-sensitive operations.

**Constraints**:
- Check interval minimum: 10 seconds (prevent thrashing)
- Check interval maximum: 300 seconds (5 minutes max delay)
- Ping deadline: (count × timeout) + 2 seconds
- Route update: Must complete within 1 second
- Config reload: Must complete within 5 seconds

**Rationale**:
- Too-frequent checks waste resources
- Too-infrequent checks delay failover
- Prevent zombie ping processes
- Fast failover requirement

### CD-4.3 Boot Sequence Constraints
**ID**: CD-4.3
**Priority**: High
**Description**: System startup requirements.

**Boot Dependencies**:
1. Kernel networking initialized
2. netifd started
3. UCI configuration available
4. Network interfaces configured
5. Then mini-mwan can start

**Init Script Priority**:
- START priority: 99 (start late, after network)
- STOP priority: 10 (stop early, before network)

### CD-4.4 Resource Limits
**ID**: CD-4.4
**Priority**: Medium
**Description**: Imposed resource limitations.

| Resource | Limit | Rationale |
|----------|-------|-----------|
| Max interfaces | 8 | Routing table size, complexity |
| Max log size | N/A | Handled by logd rotation |
| Max status file | ~10KB | Reasonable for 8 interfaces |
| Memory usage | 5MB | Embedded constraints |
| CPU usage | 5% average | Leave resources for routing |

---

## CD-5: External Interface Constraints

### CD-5.1 UCI Configuration Interface
**ID**: CD-5.1
**Priority**: Critical
**Description**: UCI system limitations.

**Constraints**:
- Configuration is text-based (no binary format)
- No schema validation by UCI
- Reloads require re-reading entire config
- No transactional updates
- No config change notifications

**Implications**:
- Daemon must poll for config changes (check each interval)
- Validation must be done by application
- Partial config updates not possible

### CD-5.2 netifd Interface Constraints
**ID**: CD-5.2
**Priority**: High
**Description**: Limitations of netifd integration.

**Constraints**:
- libubus provides synchronous call interface only (no async callbacks)
- No API for route notifications
- No callbacks for interface state changes
- Gateway information may lag actual state
- Interface names are aliases, not physical devices

**Implications**:
- Polling required for state changes
- JSON parser dependency
- Potential race conditions
- Name resolution may be needed

### CD-5.3 Kernel Routing Constraints
**ID**: CD-5.3
**Priority**: High
**Description**: Linux kernel routing limitations.

**Constraints**:
- Multipath routing support varies by kernel version
- Route replacement is not atomic
- No route change callbacks
- Metric range: 0-4294967295 (use 1-999)
- Duplicate routes can exist temporarily

**Implications**:
- Delete before replace in some cases
- Race conditions possible
- Cleanup logic needed

---

## CD-6: Compatibility Constraints

### CD-6.1 Backward Compatibility
**ID**: CD-6.1
**Priority**: Medium
**Description**: Configuration compatibility requirements.

**Requirements**:
- New configuration options MUST have sensible defaults
- Existing configurations MUST continue working
- New features MUST be opt-in when possible
- Status file format changes MUST be backward-compatible

**Versioning**:
- No formal version in config file
- Features detected by presence of options
- Default behavior preserved

### CD-6.2 Forward Compatibility
**ID**: CD-6.2
**Priority**: Low
**Description**: Future-proofing considerations.

**Considerations**:
- Configuration parser SHOULD ignore unknown options
- Status file SHOULD be extensible (new fields OK)
- Log format SHOULD remain parseable
- API contracts (commands, files) SHOULD be stable

### CD-6.3 Third-Party Integration
**ID**: CD-6.3
**Priority**: Medium
**Description**: Integration with other software.

**Integrations**:
- LuCI web interface (luci-app-mini-mwan)
- Monitoring systems (reading status file)
- Automation scripts (UCI manipulation)
- Log aggregation (syslog consumers)

**Constraints**:
- Status file format stability
- Syslog format consistency
- UCI schema stability
- Predictable behavior

---

## CD-7: Development Constraints

### CD-7.1 Development Environment
**ID**: CD-7.1
**Priority**: Low
**Description**: Development tooling limitations.

**Constraints**:
- Testing requires OpenWrt device or VM
- No local development on macOS/Windows
- Limited debugging tools on device
- No IDE support for OpenWrt

**Tools Available**:
- SSH access to device
- `luacheck` for static analysis
- `logread` for runtime logs
- `uci` for config manipulation

### CD-7.2 Testing Constraints
**ID**: CD-7.2
**Priority**: Medium
**Description**: Testing environment limitations.

**Constraints**:
- Unit testing difficult (no test framework)
- Integration testing requires physical interfaces
- Mock objects not easily available
- Network testing requires real connections

**Approaches**:
- Manual testing on device
- Audit mode for observing behavior
- Status file for validation
- Log analysis for verification

### CD-7.3 Documentation Constraints
**ID**: CD-7.3
**Priority**: Low
**Description**: Documentation requirements.

**Requirements**:
- Documentation MUST be in Markdown
- Code comments MUST be in English
- Configuration examples MUST be provided
- No external documentation hosting

**Locations**:
- README.md in repository
- Comments in Lua code
- Example config in package
- Requirements docs (this directory)
