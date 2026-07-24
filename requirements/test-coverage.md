# Requirements Test Coverage Matrix

This document maps functional requirements to their corresponding test files.

## Status Legend
- ✅ **Implemented & Tested**: Requirement implemented, tests passing
- 🔶 **Implemented, Tests Pending**: Code exists, tests need mini-mwan.lua refactoring
- ⏳ **Planned**: Requirement documented, not yet implemented
- ❌ **Not Covered**: No tests for this requirement
- 📝 **System-level only**: Requires real OpenWrt environment, not unit-testable

---

## FR-1: Interface Monitoring

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-1.1 | Connectivity Detection | Critical | `spec/unit/latency_spec.lua` + `spec/integration/failover_spec.lua` | ✅ |
| FR-1.2 | Interface State Detection | Critical | `spec/unit/interface_state_spec.lua` + `spec/integration/failover_spec.lua` | ✅ |
| FR-1.3 | Gateway Discovery | Critical | `spec/unit/gateway_spec.lua` + `spec/unit/status_update_spec.lua` | ✅ |
| FR-1.4 | Latency Measurement | Medium | `spec/unit/latency_spec.lua` | ✅ |
| FR-1.5 | Status Classification | Critical | `spec/unit/degradation_spec.lua` + `spec/integration/failover_spec.lua` | ✅ |
| FR-1.6 | Degradation Detection | High | `spec/unit/degradation_spec.lua` + `spec/unit/status_update_spec.lua` | ✅ |

### Test Coverage Details

#### FR-1.1: Connectivity Detection
**Test Cases** in `spec/integration/failover_spec.lua`:
- ✓ Primary interface pingable
- ✓ Primary interface not pingable (failure detection)
- ✓ Interface recovers after failure

#### FR-1.2: Interface State Detection
**Unit Tests** in `spec/unit/interface_state_spec.lua`:
- ✓ Detect interface UP state (UP + LOWER_UP flags)
- ✓ Detect interface DOWN state (no UP flag)
- ✓ Detect non-existent interface ("does not exist" message)
- ✓ Handle interface with only UP flag (no LOWER_UP)
- ✓ Handle interface with LOWER_UP only (matches "UP" substring)
- ✓ Handle empty output (no device match)
- ✓ Parse real OpenWrt ip addr output format
- ✓ Handle VLAN interfaces (eth0.100 naming)

**Integration Tests** in `spec/integration/failover_spec.lua`:
- ✓ Interface physically UP
- ✓ Interface physically DOWN
- ✓ Interface recovery

#### FR-1.3: Gateway Discovery
**Test Cases** in `spec/unit/gateway_spec.lua`:
- ✓ Extract gateway from libubus network.interface dump
- ✓ Handle P2P interface (no gateway)
- ✓ Handle empty response
- ✓ Extract default route from multiple routes
- ✓ Handle multiple interfaces

#### FR-1.4: Latency Measurement
**Test Cases** in `spec/unit/latency_spec.lua`:
- ✓ Extract average latency from successful ping (real OpenWrt format)
- ✓ High precision latency values (23.457 ms)
- ✓ Low single-digit latency (0.923 ms)
- ✓ High triple-digit latency (251.456 ms)
- ✓ Integer latency values (no decimal)
- ✓ Failed pings return latency 0
- ✓ No output / empty output handling
- ✓ Partial packet loss handling
- ✓ Malformed output handling
- ✓ Correct ping command parameters
- ✓ Default parameter usage
- ✓ Deadline parameter calculation

#### FR-1.5: Status Classification
**Test Cases** in `spec/integration/failover_spec.lua`:
- ✓ Interface marked "up" (UP + ping success)
- ✓ Interface marked "down" (UP + ping fail)
- ✓ Interface marked "interface_down" (physically DOWN)
- ⏳ Interface marked "disabled" (needs test)

#### FR-1.6: Degradation Detection
**Test Cases** in `spec/unit/degradation_spec.lua`:
- ✓ Regular interface without gateway → unconfigured
- ✓ P2P interface without gateway → not unconfigured (uses IPv4 ping for routing class)
- ✓ Regular interface with gateway → usable (IPv4 ping determines routing class)
- ✓ Auto-recovery when gateway appears
- ✓ Degraded (unconfigured) interface skipped in routing

**Note**: IPv6 is now supported as a secondary protocol on interfaces that have IPv4 connectivity.
Interfaces are classified based on IPv4 connectivity; IPv6 routes are added only when:
1. Interface routing class is `usable` (IPv4 ping succeeds)
2. Both IPv4 and IPv6 gateways are present

IPv6 routing is **NOT** added when IPv4 connectivity is lost (`probe_only` state) to prevent
routing leaks - the interface falls back to fail-closed behavior.

---

## FR-2: Routing Management

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-2.1 | Failover Mode | Critical | `spec/integration/failover_spec.lua` | ✅ |
| FR-2.2 | Multiuplink Mode | High | `spec/integration/multiuplink_spec.lua` | ✅ |
| FR-2.3 | Point-to-Point Interface Support | High | `spec/unit/gateway_spec.lua` + `spec/integration/failover_spec.lua` | ✅ |
| FR-2.4 | Route Cleanup | Medium | `spec/integration/route_cleanup_spec.lua` | ✅ |
| FR-2.5 | Metric Management | High | `spec/integration/failover_spec.lua` | ✅ |

### Test Coverage Details

#### FR-2.1: Failover Mode
**Test Cases** in `spec/integration/failover_spec.lua`:
- ✓ Use primary (lowest metric) when available
- ✓ Failover to backup when primary fails
- ✓ Restore primary when recovered
- ✓ Handle both interfaces failed (warning, no crash)
- ✓ Degraded interfaces skipped

#### FR-2.2: Multiuplink Mode
**Test Cases** in `spec/integration/multiuplink_spec.lua`:
- ✓ Multipath route creation with all UP interfaces (2 and 3 interfaces)
- ✓ Weight distribution across interfaces
- ✓ Failed interface removal from multipath
- ✓ Degraded interface handling in multiuplink mode
- ✓ All interfaces down scenario
- ✓ P2P interface support in multipath routes
- ✓ Interface recovery in multiuplink mode

#### FR-2.3: Point-to-Point Interface Support
**Test Cases** in `spec/integration/failover_spec.lua`:
- ✓ VPN tunnel with ISP failover
- ✓ P2P route without gateway
- ✓ P2P interface not marked degraded

#### FR-2.4: Route Cleanup
**Test Cases** in `spec/integration/route_cleanup_spec.lua`:
- ✓ Flush duplicate routes for same device
- ✓ Flush routes without explicit metric
- ✓ Flush multiple routes for same gateway at different metrics
- ✓ No intervention when route is already correct
- ✓ Flush and re-add for P2P interfaces with duplicates
- ✓ Remove unmanaged default routes
- ✓ Preserve managed routes

#### FR-2.5: Metric Management
**Test Cases** in `spec/integration/failover_spec.lua`:
- ✓ Primary interface uses configured metric
- ✓ Backup interfaces use their metrics
- ✓ DOWN interfaces use metric 900

---

## FR-3: Configuration Management

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-3.1 | UCI Configuration | Critical | `spec/unit/config_spec.lua` | ✅ |
| FR-3.2 | Global Settings | Critical | `spec/unit/config_spec.lua` | ✅ |
| FR-3.3 | Interface Configuration | Critical | `spec/unit/config_spec.lua` | ✅ |
| FR-3.4 | Dynamic Interface Support | Medium | `spec/unit/config_spec.lua` | ✅ |
| FR-3.5 | Validation Requirements | High | `spec/unit/config_spec.lua` | ✅ |

### Test Coverage Details

#### FR-3.1: UCI Configuration
**Test Cases** in `spec/unit/config_spec.lua`:
- ✓ Load configuration from UCI
- ✓ Convert string values to appropriate types (boolean, number)

#### FR-3.2: Global Settings
**Test Cases** in `spec/unit/config_spec.lua`:
- ✓ Load enabled flag (string "1" → boolean true)
- ✓ Detect disabled state (string "0" → boolean false)
- ✓ Load mode setting (failover/multiuplink)
- ✓ Default mode to "failover" if missing
- ✓ Load check_interval as number
- ✓ Default check_interval to 30 if missing
- ✓ Load audit log level
- ✓ Default log_level to "emerg" if missing

#### FR-3.3: Interface Configuration
**Test Cases** in `spec/unit/config_spec.lua`:
- ✓ Load interface with all fields
- ✓ Apply default metric (10) if missing
- ✓ Apply default weight (3) if missing
- ✓ Apply default ping_count (3) if missing
- ✓ Apply default ping_timeout (2) if missing
- ✓ Handle VLAN interface names (eth0.100)
- ✓ Convert string numbers to integers

#### FR-3.4: Dynamic Interface Support
**Test Cases** in `spec/unit/config_spec.lua`:
- ✓ Load multiple interfaces (2, 3, N)
- ✓ Minimal valid configuration (only required fields)
- ✓ All devices loaded correctly (metrics determine priority, not config order)

#### FR-3.5: Validation Requirements
**Test Cases** in `spec/unit/config_spec.lua`:
- ✓ Valid IPv4 address detection
- ✓ Invalid IPv4 address detection (out of range, malformed)
- ✓ Valid interface name detection
- ✓ Invalid interface name detection (spaces, special chars, too long)
- ✓ Config validation passes for valid config
- ✓ Config validation fails for missing ping_target
- ✓ Config validation fails for invalid ping_target
- ✓ Config validation fails for invalid device name
- ✓ Config validation fails for less than 2 interfaces
- ✓ Config validation fails for check_interval out of range
- ✓ Disabled config bypasses validation

---

## FR-4: State Persistence

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-4.1 | Runtime State Preservation | High | `spec/unit/config_spec.lua` (state model) | ✅ |
| FR-4.2 | Status via ubus | High | `spec/unit/status_update_spec.lua` | ✅ |

### Test Coverage Details

#### FR-4.1: Runtime State Preservation
**Test Cases** in `spec/unit/config_spec.lua` and `spec/unit/interface_state_spec.lua`:
- ✓ `status_since` preserved when routing_class is stable (state unchanged)
- ✓ Clock advancement does not affect preserved `status_since` value
- ✓ `routing_class` transitions logged correctly across reloads

**Note**: Mini-MWAN distinguishes between:
- **Config**: Immutable data from UCI (device, metric, ping_target, etc.)
- **State**: Runtime data discovered each cycle (gateway, latency, routing_class)
- **Persistent State**: Only `routing_class`, `does_exist`, `status_since` survive config reloads
- Other fields (`latency`, `alive`, `gateway`) are recalculated fresh each cycle

#### FR-4.2: Status via ubus
**Test Cases** in `spec/unit/status_update_spec.lua`:
- ✓ Status object published via ubus
- ✓ All interface fields correctly included
- ✓ Network statistics (rx_bytes, tx_bytes) included
- ✓ IPv6 gateway included when available

---

## FR-5: Logging and Audit

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-5.1 | Event Logging | High | `spec/integration/logging_spec.lua` | ✅ |
| FR-5.2 | Audit Logging | Medium | `spec/integration/logging_spec.lua` | ✅ |
| FR-5.3 | Network Statistics | Low | `spec/unit/status_update_spec.lua` | ✅ |

### Test Coverage Details

#### FR-5.1: Event Logging
**Test Cases** in `spec/integration/logging_spec.lua`:
- ✓ Interface UP transitions logged at info level with latency
- ✓ Interface DOWN transitions logged at info level
- ✓ Route interventions logged at notice level
- ✓ Route cleanup logged at notice level
- ✓ Degradation warnings logged at warning level
- ✓ Ping results logged at debug level
- ✓ System probes logged at debug level

**Test Cases** in `spec/integration/interface_lifecycle_spec.lua`:
- ✓ Interface disappearance logged at warning level (USB dongle, tunnel down)
- ✓ Interface reappearance logged at info level (device reconnected)
- ✓ VPN tunnel lifecycle (down → up)
- ✓ No duplicate logs when state unchanged

#### FR-5.2: Audit Logging
**Test Cases** in `spec/integration/logging_spec.lua`:
- ✓ System probes (ubus, ip addr, ping) logged at debug level
- ✓ System interventions (ip route) logged at notice level
- ✓ Normal operations (nothing changed) - debug logging only
- ✓ State-changing operations - notice logging for interventions

---

## FR-6: Operational Requirements

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-6.1 | Daemon Lifecycle | Critical | `mini-mwan/files/mini-mwan.lua` (main() + work_cycle()) | 📝 |
| FR-6.2 | Service Control | Critical | `mini-mwan/files/mini-mwan.init` | 📝 |
| FR-6.3 | Graceful Degradation | High | `spec/integration/failover_spec.lua` + `spec/unit/config_spec.lua` | ✅ |

### Notes
- **FR-6.1 and FR-6.2**: System-level testing with procd/init script requires a real OpenWrt environment.
  - Not suitable for unit tests
  - Implementation verified via code review
  - Manual testing on device required

---

## Summary Statistics

### Overall Coverage

| Category | Total | Tested | System-only | Pending | Coverage % |
|----------|-------|--------|-------------|---------|------------|
| FR-1: Monitoring | 6 | 6 | 0 | 0 | 100% |
| FR-2: Routing | 5 | 5 | 0 | 0 | 100% |
| FR-3: Configuration | 5 | 5 | 0 | 0 | 100% |
| FR-4: State | 2 | 2 | 0 | 0 | 100% |
| FR-5: Logging | 3 | 3 | 0 | 0 | 100% |
| FR-6: Operational | 3 | 1 | 2 | 0 | 33% |
| **TOTAL** | **24** | **22** | **2** | **0** | **92%** |

**Code Coverage:** 75% (75.33% overall, 92.95% for main daemon file)

### Notes on Coverage

- **FR-4.1 (State Persistence)**: Fully tested - `status_since` persistence verified. The state model is clearly defined: only `routing_class`, `does_exist`, and `status_since` persist across config reloads; all other state is recalculated fresh each cycle.
- **FR-6.1 (Daemon Lifecycle)**: System-level testing only. Requires real OpenWrt with procd.
- **FR-6.2 (Service Control)**: System-level testing only. Requires real OpenWrt with init system.

### Priority Coverage

| Priority | Total | Tested | System-only | Pending | Coverage % |
|----------|-------|--------|-------------|---------|------------|
| Critical | 10 | 6 | 2 | 0 | 80% |
| High | 8 | 5 | 0 | 0 | 100% |
| Medium | 5 | 1 | 0 | 4 | 20% |
| Low | 2 | 0 | 0 | 2 | 0% |

---

## Manual Testing Required

Some requirements cannot be fully unit tested and require manual verification on a real OpenWrt device:

| Requirement | Manual Test Procedure |
|-------------|----------------------|
| FR-6.1 | Start/stop daemon via procd, verify lifecycle |
| FR-6.2 | Test init script: start, stop, restart, enable, disable |
| NFR-1.1 | Monitor resource usage on actual OpenWrt device |
| NFR-1.2 | Measure failover time with real network interruption |
| NFR-4.1 | Deploy to router, test with real ISPs and interfaces |

---

## Continuous Improvement

### Adding Tests for New Features

When adding new features:
1. Write tests **before** implementing feature (TDD)
2. Update this coverage matrix
3. Link test file to requirement ID in comments
4. Ensure all acceptance criteria have tests

### Reviewing Coverage

Monthly review:
1. Run `busted --coverage && luacov`
2. Identify uncovered code paths
3. Add tests for gaps
4. Update this document

### Reporting Issues

If tests reveal bugs:
1. Create failing test demonstrating bug
2. Fix bug
3. Verify test passes
4. Document in CHANGELOG.md
