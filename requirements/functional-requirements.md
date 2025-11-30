# Functional Requirements

## FR-1: Interface Monitoring

### FR-1.1 Connectivity Detection
**ID**: FR-1.1
**Priority**: Critical
**Description**: The system SHALL monitor connectivity of each configured WAN interface using ICMP ping tests.

**Acceptance Criteria**:
- Ping tests MUST be sent through the specific interface being tested (using `-I` flag)
- Number of ping packets SHALL be configurable (default: 3)
- Ping timeout SHALL be configurable (default: 2 seconds)
- Ping target SHALL be configurable per interface
- At least one successful ping response indicates connectivity

### FR-1.2 Interface State Detection
**ID**: FR-1.2
**Priority**: Critical
**Description**: The system SHALL detect the physical state of network interfaces.

**Acceptance Criteria**:
- System MUST distinguish between interface UP and DOWN states
- System MUST detect non-existent interfaces
- Detection SHALL use `ip addr show` command

### FR-1.3 Gateway Discovery
**ID**: FR-1.3
**Priority**: Critical
**Description**: The system SHALL automatically discover gateway addresses for managed interfaces.

**Acceptance Criteria**:
- Gateway MUST be obtained using ubus network.interface.dump call
- System SHALL look for default route (target "0.0.0.0", mask 0) in route table for each interface
- Gateway discovery SHALL match interfaces by device name, not interface name
- Missing gateway SHALL be handled gracefully for P2P interfaces
- Gateway discovery SHALL occur on each configuration reload

### FR-1.4 Latency Measurement
**ID**: FR-1.4
**Priority**: Medium
**Description**: The system SHALL measure average round-trip latency for each interface.

**Acceptance Criteria**:
- Latency MUST be extracted from ping command output (avg field)
- Latency SHALL be reported in milliseconds
- Failed pings SHALL result in latency value of 0

### FR-1.5 Status Classification
**ID**: FR-1.5
**Priority**: Critical
**Description**: The system SHALL classify each interface into one of the following states:

| Status | Description | Condition |
|--------|-------------|-----------|
| `up` | Fully operational | Interface UP AND ping successful |
| `down` | Connectivity lost | Interface UP BUT ping failed |
| `interface_down` | Physically down | Interface DOWN or non-existent |
| `disabled` | Not monitored | Interface disabled in config OR missing required parameters |

**Acceptance Criteria**:
- Status transitions MUST be logged with timestamps
- Status MUST be persisted across config reloads
- Status changes MUST include previous and new status in logs

### FR-1.6 Degradation Detection
**ID**: FR-1.6
**Priority**: High
**Description**: The system SHALL detect configuration issues that prevent normal interface operation.

**Acceptance Criteria**:
- Regular (non-P2P) interfaces without gateways SHALL be marked degraded
- Degradation reason "no_gateway" indicates incomplete DHCP configuration
- Degradation reason "ipv6_detected" indicates IPv6 address on interface (not supported)
- Degraded regular interfaces SHALL NOT have routes configured
- Degraded interfaces SHALL continue monitoring for auto-recovery
- P2P interfaces without gateways SHALL NOT be marked degraded

---

## FR-2: Routing Management

### FR-2.1 Failover Mode
**ID**: FR-2.1
**Priority**: Critical
**Description**: The system SHALL provide failover mode where interfaces are prioritized by metric, with automatic failover to backup interfaces.

**Acceptance Criteria**:
- Primary interface MUST be the lowest-metric interface with status "up"
- Primary interface SHALL have default route at its configured metric
- Backup interfaces SHALL have default routes at their configured metrics
- DOWN interfaces SHALL have routes at metric 900 (to allow ping tests)
- When primary fails, next-priority backup MUST automatically become primary
- Failover SHALL occur within one check interval

### FR-2.2 Multiuplink Mode
**ID**: FR-2.2
**Priority**: High
**Description**: The system SHALL provide multiuplink mode where traffic is load-balanced across all operational interfaces.

**Acceptance Criteria**:
- System MUST create multipath route with all "up" interfaces
- Each interface SHALL be weighted according to its configured weight
- DOWN interfaces SHALL have routes at metric 900 (to allow ping tests)
- Load balancing SHALL use Linux kernel's multipath routing
- Traffic distribution MUST be approximately proportional to weights

### FR-2.3 Point-to-Point Interface Support
**ID**: FR-2.3
**Priority**: High
**Description**: The system SHALL support point-to-point interfaces (VPN tunnels, PPP) that have no traditional gateway.

**Acceptance Criteria**:
- Interfaces marked as `point_to_point=1` SHALL create routes without "via" clause
- P2P interfaces without gateways SHALL NOT be marked degraded
- Route format: `ip route replace default dev <device> metric <metric>`

### FR-2.4 Route Cleanup
**ID**: FR-2.4
**Priority**: Medium
**Description**: The system SHALL manage the routing table to prevent conflicts and clean up duplicate routes.

**Acceptance Criteria**:
- When setting a route, duplicate default routes for the same device SHALL be cleaned up
- Cleanup MUST happen AFTER the new route is set (to prevent routing downtime)
- System SHALL query existing routes using `ip route show default dev <device>`
- System SHALL preserve the lowest-metric route (our route) and delete all others
- In multiuplink mode, all existing default routes (except metric 900) SHALL be removed before setting multipath route
- Degraded non-P2P interfaces SHALL NOT have routes configured
- Route changes SHALL use `replace` operation to handle both creation and update
- Duplicate routes created by external tools SHALL be removed automatically

### FR-2.5 Metric Management
**ID**: FR-2.5
**Priority**: High
**Description**: The system SHALL use route metrics to control traffic flow.

**Acceptance Criteria**:
- Each interface SHALL have a configurable metric (default: 10)
- Lower metric values MUST have higher priority
- DOWN interfaces SHALL use metric 900
- Metric 900 MUST allow ping tests while not handling normal traffic

---

## FR-3: Configuration Management

### FR-3.1 UCI Configuration
**ID**: FR-3.1
**Priority**: Critical
**Description**: The system SHALL use UCI for all configuration.

**Acceptance Criteria**:
- Configuration file MUST be `/etc/config/mini-mwan`
- Configuration SHALL be reloaded on each check interval
- Invalid configuration SHALL be logged but not crash the daemon

### FR-3.2 Global Settings
**ID**: FR-3.2
**Priority**: Critical
**Description**: The system SHALL support global settings section.

**Configuration Parameters**:
| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `enabled` | boolean | 0 | Enable/disable daemon |
| `mode` | string | "failover" | Operation mode: "failover" or "multiuplink" |
| `check_interval` | integer | 30 | Seconds between health checks |
| `audit` | string | "none" | Command audit logging level supported values: emerg, alert, crit, err, warning, notice, info, debug |

### FR-3.3 Interface Configuration
**ID**: FR-3.3
**Priority**: Critical
**Description**: The system SHALL support per-interface configuration.

**Configuration Parameters**:
| Parameter | Type | Default | Required | Description |
|-----------|------|---------|----------|-------------|
| `enabled` | boolean | 1 | No | Enable/disable interface |
| `device` | string | - | Yes | Physical interface name (eth0, wg0, etc.) |
| `metric` | integer | 10 | No | Route priority (lower = higher priority) |
| `weight` | integer | 3 | No | Load balancing weight for multiuplink |
| `ping_target` | string | - | Yes | IP address for connectivity checks |
| `ping_count` | integer | 3 | No | Number of ping packets |
| `ping_timeout` | integer | 2 | No | Ping timeout in seconds |

### FR-3.4 Dynamic Interface Support
**ID**: FR-3.4
**Priority**: Medium
**Description**: The system SHALL support arbitrary number of interfaces.

**Acceptance Criteria**:
- System MUST dynamically load all `interface` sections from config
- No hardcoded interface limits
- Each interface section MUST have unique name (wan1, wan2, etc.)

### FR-3.5 Validation Requirements
**ID**: FR-3.5
**Priority**: High
**Description**: The system SHALL validate configuration at runtime.

**Acceptance Criteria**:
- At least 2 interfaces with valid device names MUST be configured for operation
- Missing required parameters SHALL cause interface to be marked "disabled"
- Configuration errors SHALL be logged

---

## FR-4: State Persistence

### FR-4.1 Runtime State Preservation
**ID**: FR-4.1
**Priority**: High
**Description**: The system SHALL preserve interface state across configuration reloads.

**Persistent State Fields**:
- `status` - Current interface status
- `status_since` - Timestamp of last status change
- `latency` - Last measured latency
- `last_check` - Timestamp of last health check
- `degraded` - Degradation flag
- `degraded_reason` - Degradation reason string

**Acceptance Criteria**:
- State MUST persist in memory across config reloads
- State SHALL NOT persist across daemon restarts
- Timestamp fields MUST use Unix epoch time

### FR-4.2 Status via ubus
**ID**: FR-4.2
**Priority**: High
**Description**: The system SHALL expose current status via ubus for external consumption.

**Acceptance Criteria**:
- Status MUST be accessible via ubus object `mini-mwan` method `status`
- Format SHALL be JSON
- Response MUST include global fields: mode, timestamp, check_interval
- Response MUST include interfaces array with all status fields per interface
- Status SHALL be updated after each monitoring cycle
- Status MUST include network statistics (rx_bytes, tx_bytes)

---

## FR-5: Logging and Audit

### FR-5.1 Dual Logging
**ID**: FR-5.1
**Priority**: High
**Description**: The system SHALL log to both file and syslog.

**Acceptance Criteria**:
- Application log MUST be at `/var/log/mini-mwan.log`
- Same messages MUST be sent to syslog with tag "mini-mwan"
- Log messages MUST include ISO 8601 timestamps
- Log format: `[YYYY-MM-DD HH:MM:SS] message`

### FR-5.2 Event Logging
**ID**: FR-5.2
**Priority**: High
**Description**: The system SHALL log significant events.

**Logged Events**:
- Daemon startup
- Status changes (with old and new status)
- Interface degradation detection
- Primary interface selection (failover mode)
- Multipath route creation (multiuplink mode)
- Configuration errors
- No WAN connections available

### FR-5.3 Audit Logging
**ID**: FR-5.3
**Priority**: Medium
**Description**: The system SHALL optionally log all executed commands at configurable verbosity levels.

**Acceptance Criteria**:
- Audit logging MUST be disabled by default (`audit="none"`)
- When set to "info" level, important shell commands MUST be logged before execution
- When set to "debug" level, all shell commands MUST be logged before execution
- Audit logs SHALL use format: "Executing: <command>"
- Audit logs MUST NOT log sensitive information
- Log level names ("none", "info", "debug") SHALL be used instead of numeric values

### FR-5.4 Network Statistics
**ID**: FR-5.4
**Priority**: Low
**Description**: The system SHALL collect network traffic statistics.

**Acceptance Criteria**:
- RX bytes SHALL be read from `/sys/class/net/<device>/statistics/rx_bytes`
- TX bytes SHALL be read from `/sys/class/net/<device>/statistics/tx_bytes`
- Statistics SHALL be included in status file
- Missing statistics SHALL default to "0"

---

## FR-6: Operational Requirements

### FR-6.1 Daemon Lifecycle
**ID**: FR-6.1
**Priority**: Critical
**Description**: The system SHALL run as a continuous daemon process.

**Acceptance Criteria**:
- Daemon MUST run in infinite loop with sleep intervals
- Sleep duration SHALL be configurable via `check_interval`
- Daemon MUST be managed by procd (OpenWrt process manager)
- Signal handling SHALL be delegated to procd

### FR-6.2 Service Control
**ID**: FR-6.2
**Priority**: Critical
**Description**: The system SHALL integrate with OpenWrt's init system.

**Acceptance Criteria**:
- Init script MUST be at `/etc/init.d/mini-mwan`
- Service MUST support: start, stop, restart, status
- Service MUST clean up status file on stop
- Service MUST support enable/disable for boot startup

### FR-6.3 Graceful Degradation
**ID**: FR-6.3
**Priority**: High
**Description**: The system SHALL continue operating with degraded functionality when possible.

**Acceptance Criteria**:
- Service disabled state SHALL only log and sleep
- Single active WAN SHALL still be managed
- Configuration errors SHALL not crash daemon
- Missing dependencies SHALL be logged but not fatal
