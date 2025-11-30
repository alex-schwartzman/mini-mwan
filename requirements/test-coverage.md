# Requirements Test Coverage Matrix

This document maps functional requirements to their corresponding test files.

## Status Legend
- ✅ **Implemented & Tested**: Requirement implemented, tests passing
- 🔶 **Implemented, Tests Pending**: Code exists, tests need mini-mwan.lua refactoring
- ⏳ **Planned**: Requirement documented, not yet implemented
- ❌ **Not Covered**: No tests for this requirement

---

## FR-1: Interface Monitoring

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-1.1 | Connectivity Detection | Critical | `spec/integration/failover_spec.lua` | 🔶 |
| FR-1.2 | Interface State Detection | Critical | `spec/integration/failover_spec.lua` | 🔶 |
| FR-1.3 | Gateway Discovery | Critical | `spec/unit/gateway_spec.lua` | 🔶 |
| FR-1.4 | Latency Measurement | Medium | `spec/unit/latency_spec.lua` | ✅ |
| FR-1.5 | Status Classification | Critical | `spec/integration/failover_spec.lua` | 🔶 |
| FR-1.6 | Degradation Detection | High | `spec/unit/degradation_spec.lua` | 🔶 |

### Test Coverage Details

#### FR-1.1: Connectivity Detection
**Test Cases** in `spec/integration/failover_spec.lua`:
- ✓ Primary interface pingable
- ✓ Primary interface not pingable (failure detection)
- ✓ Interface recovers after failure

#### FR-1.2: Interface State Detection
**Test Cases** in `spec/integration/failover_spec.lua`:
- ✓ Interface physically UP
- ✓ Interface physically DOWN
- ✓ Interface recovery

#### FR-1.3: Gateway Discovery
**Test Cases** in `spec/unit/gateway_spec.lua`:
- ✓ Extract gateway from ubus dump JSON
- ✓ Handle P2P interface (no gateway)
- ✓ Handle invalid JSON response
- ✓ Handle empty response
- ✓ Extract default route from multiple routes

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
- ✓ Regular interface without gateway → degraded
- ✓ P2P interface without gateway → not degraded
- ✓ Interface with IPv6 → degraded
- ✓ Regular interface with gateway → healthy
- ✓ Auto-recovery when gateway appears
- ✓ Degraded interface skipped in routing

---

## FR-2: Routing Management

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-2.1 | Failover Mode | Critical | `spec/integration/failover_spec.lua` | ✅ |
| FR-2.2 | Multiuplink Mode | High | `spec/integration/multiuplink_spec.lua` | ✅ |
| FR-2.3 | Point-to-Point Interface Support | High | `spec/integration/failover_spec.lua` | ✅ |
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
**Coverage**: ⏳ Feature discussed, not implemented
**Test Cases Needed**:
- Remove unmanaged default routes
- Preserve managed routes
- Handle duplicate routes

#### FR-2.5: Metric Management
**Test Cases** in `spec/integration/failover_spec.lua`:
- ✓ Primary interface uses configured metric
- ✓ Backup interfaces use their metrics
- ✓ DOWN interfaces use metric 900

---

## FR-3: Configuration Management

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-3.1 | UCI Configuration | Critical | (needs test) | ⏳ |
| FR-3.2 | Global Settings | Critical | (needs test) | ⏳ |
| FR-3.3 | Interface Configuration | Critical | (needs test) | ⏳ |
| FR-3.4 | Dynamic Interface Support | Medium | (needs test) | ⏳ |
| FR-3.5 | Validation Requirements | High | (needs test) | ⏳ |

### Coverage Gap
Configuration management tests are needed. Suggested file: `spec/unit/config_spec.lua`

**Test Cases Needed**:
- Load configuration from UCI
- Parse global settings
- Parse interface sections
- Handle missing required fields
- Handle invalid values (use defaults)
- Support arbitrary number of interfaces

---

## FR-4: State Persistence

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-4.1 | Runtime State Preservation | High | (needs test) | ⏳ |
| FR-4.2 | Status File Output | High | (needs test) | ⏳ |

### Coverage Gap
State persistence tests needed. Suggested file: `spec/unit/state_spec.lua`

**Test Cases Needed**:
- State persists across config reload
- State resets on daemon restart
- Status file format correct
- Status file includes all fields
- Degradation info in status file

---

## FR-5: Logging and Audit

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-5.1 | Dual Logging | High | (needs test) | ⏳ |
| FR-5.2 | Event Logging | High | (needs test) | ⏳ |
| FR-5.3 | Audit Logging | Medium | (needs test) | ⏳ |
| FR-5.4 | Network Statistics | Low | (needs test) | ⏳ |

### Coverage Gap
Logging tests needed. Suggested file: `spec/unit/logging_spec.lua`

**Test Cases Needed**:
- Log to file
- Log to syslog
- Log format correct
- Status changes logged
- Audit mode logs commands
- Network stats collected

---

## FR-6: Operational Requirements

| ID | Requirement | Priority | Test File | Status |
|----|-------------|----------|-----------|--------|
| FR-6.1 | Daemon Lifecycle | Critical | (manual test) | ⏳ |
| FR-6.2 | Service Control | Critical | (manual test) | ⏳ |
| FR-6.3 | Graceful Degradation | High | `spec/integration/failover_spec.lua` | 🔶 |

### Notes
FR-6.1 and FR-6.2 require system-level testing (init scripts, procd integration). Not suitable for unit tests.

---

## Summary Statistics

### Overall Coverage

| Category | Total | Tested | Pending | Planned | Coverage % |
|----------|-------|--------|---------|---------|------------|
| FR-1: Monitoring | 6 | 6 | 0 | 0 | 100% |
| FR-2: Routing | 5 | 5 | 0 | 0 | 100% |
| FR-3: Configuration | 5 | 0 | 0 | 5 | 0% |
| FR-4: State | 2 | 1 | 0 | 1 | 50% |
| FR-5: Logging | 4 | 0 | 0 | 4 | 0% |
| FR-6: Operational | 3 | 1 | 0 | 2 | 33% |
| **TOTAL** | **25** | **13** | **0** | **12** | **52%** |

### Priority Coverage

| Priority | Total | Tested | Pending | Coverage % |
|----------|-------|--------|---------|------------|
| Critical | 10 | 6 | 4 | 60% |
| High | 8 | 5 | 3 | 63% |
| Medium | 5 | 1 | 4 | 20% |
| Low | 2 | 0 | 2 | 0% |

---

## Next Steps to Improve Coverage

### Phase 2: Fill Critical Gaps (Priority: High)
5. **Create config_spec.lua** - Test UCI configuration loading (FR-3)
6. **Create state_spec.lua** - Test state persistence (FR-4)
7. **Create monitoring_spec.lua** - Test latency measurement (FR-1.4)

**Estimated Effort**: 4-6 hours
**Impact**: +30% coverage (to 66%)

### Phase 3: Complete Coverage (Priority: Medium)
8. **Create multiuplink_spec.lua** - Test load balancing mode (FR-2.2)
9. **Create logging_spec.lua** - Test logging subsystem (FR-5)
10. **Add edge case tests** - Error conditions, race conditions

**Estimated Effort**: 6-8 hours
**Impact**: +34% coverage (to 100%)

### Phase 4: Integration & CI (Priority: Medium)
11. **Setup CI pipeline** - Run tests automatically
12. **Coverage reporting** - Track coverage trends
13. **Performance benchmarks** - Ensure tests run quickly

**Estimated Effort**: 2-4 hours

---

## Coverage Goals

| Milestone | Target Coverage | Target Date | Status |
|-----------|----------------|-------------|--------|
| M1: Basic Tests Working | 36% | TBD | 🔶 Pending refactor |
| M2: Critical Requirements | 66% | TBD | ⏳ Planned |
| M3: Full Coverage | 100% | TBD | ⏳ Planned |

---

## Manual Testing Required

Some requirements cannot be fully unit tested and require manual verification:

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
