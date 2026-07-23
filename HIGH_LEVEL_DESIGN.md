# Mini-MWAN High-Level Design Document

## Overview

This document describes the internal architecture and operational flow of Mini-MWAN, a lightweight multi-WAN failover and load balancing daemon for OpenWrt.

---

## Architecture Overview

### Design Philosophy

Mini-MWAN follows a **state-based routing control** approach:

1. **Immutable Configuration** - Loaded once per cycle from UCI, never modified
2. **Mutable State** - Discovered fresh each cycle via kernel probes (ip, ubus, ping)
3. **Routing Table Management** - Direct manipulation of kernel routing table via `ip route` commands

### Component Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Mini-MWAN Daemon                            │
├─────────────────────────────────────────────────────────────────┤
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐  │
│  │   Config Loader │  │   State Probe   │  │   Route Manager │  │
│  │   (UCI)         │  │   (ip/ubus/ping)│  │   (ip route)    │  │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘  │
│                           │                                      │
│  ┌────────────────────────▼─────────────────────────────────┐   │
│  │                  Work Cycle (main loop)                   │   │
│  │  1. Load config from UCI                                  │   │
│  │  2. Probe state: interface UP/DOWN, gateway, ping         │   │
│  │  3. Classify: usable/probe_only/degraded                  │   │
│  │  4. Configure routes based on mode (failover/multiuplink) │   │
│  └───────────────────────────────────────────────────────────┘   │
└───────────────────────────────────────────────────────────────────┘
```

---

## Operational Cycle

Mini-MWAN operates as an **event-driven timer loop** using uloop (OpenWrt's event loop). The daemon runs indefinitely with configurable check intervals (default: 30 seconds).

### Cycle Flow Diagram

```
┌────────────────────────────────────────────────────────────────────────────┐
│                         WORK CYCLE                                         │
├────────────────────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ STEP 1: LOAD CONFIGURATION                                           │  │
│  │   Source: /etc/config/mini-mwan                                      │  │
│  │   Actions:                                                           │  │
│  │     - Read global settings (enabled, mode, check_interval)          │  │
│  │     - Load all interface configurations (device, metric, weight,    │  │
│  │       ping_target, ping_count, ping_timeout)                        │  │
│  │     - Validate configuration (≥2 interfaces, valid IPs, etc.)       │  │
│  │                                                                       │  │
│  │   Output: config table (immutable)                                  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                              │                                              │
│                              ▼                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ STEP 2: PROBE INTERFACE STATE                                        │  │
│  │   For each configured interface:                                     │  │
│  │                                                                       │  │
│  │   a) Check if interface exists:  `ip addr show dev <device>`         │  │
│  │      → absent (doesn't exist)                                        │  │
│  │      → exists (proceed to next check)                                │  │
│  │                                                                       │  │
│  │   b) Check if interface is UP:   `<[^>]*UP[^>]*>` in ip addr output │  │
│  │      → down (kernel flag not set)                                    │  │
│  │      → up (proceed to next check)                                    │  │
│  │                                                                       │  │
│  │   c) Discover gateway via ubus:  `network.interface.dump`           │  │
│  │      - Look for default route (0.0.0.0/0 or ::/0)                    │  │
│  │      - Extract nexthop (gateway IP)                                  │  │
│  │      - Note: nexthop="0.0.0.0" means P2P (no gateway)                │  │
│  │                                                                       │  │
│  │   d) Check connectivity:         `ping -I <device> -c <count> ...`   │  │
│  │      - Ping configured target                                        │  │
│  │      - Extract: packets received, average latency                    │  │
│  │                                                                       │  │
│  │   e) Compute routing class:                                          │  │
│  │      ┌────────────────────────────────────────────────────────────┐  │  │
│  │      │ Class          │ Conditions                                │  │  │
│  │      ├────────────────┼───────────────────────────────────────────┤  │  │
│  │      │ absent         │ ip addr reports device doesn't exist      │  │  │
│  │      │ down           │ kernel UP flag not set                    │  │  │
│  │      │ unconfigured   │ Kernel UP + routing info unavailable      │  │  │
│  │      │ probe_only     │ Kernel UP + routing info present + ping   │  │  │
│  │      │                │   failed                                  │  │  │
│  │      │ usable         │ Kernel UP + routing info present + ping   │  │  │
│  │      │                │   successful                              │  │  │
│  │      └────────────────┴───────────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │   f) Log state transitions (info level)                             │  │
│  │                                                                       │  │
│  │   Output: state table with routing_class per interface              │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                              │                                              │
│                              ▼                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ STEP 3: CLEANUP UNMANAGED ROUTES                                     │  │
│  │                                                                       │  │
│  │   a) Query existing default routes: `ip route show default`         │  │
│  │                                                                       │  │
│  │   b) For each existing route:                                       │  │
│  │      - If device is NOT in managed_devices list → DELETE            │  │
│  │                                                                       │  │
│  │   c) Query existing IPv6 default routes: `ip -6 route show default` │  │
│  │                                                                       │  │
│  │   d) For each existing IPv6 route:                                  │  │
│  │      - If device is NOT in managed_devices list → DELETE            │  │
│  │                                                                       │  │
│  │   Purpose: Remove routes created by other tools (e.g., VPN clients) │  │
│  │   that conflict with mini-mwan management                           │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                              │                                              │
│                              ▼                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ STEP 4: CLASSIFY AND CONFIGURE ROUTES                              │  │
│  │                                                                       │  │
│  │   a) Classify interfaces by routing class:                          │  │
│  │      - usable:    ping successful, routing info present             │  │
│  │      - probe_only: kernel UP, routing info present, ping failed     │  │
│  │                                                                       │  │
│  │   b) Configure probe_only interfaces (metric 900):                  │  │
│  │      - Allows ping tests to detect recovery                         │  │
│  │      - Does not handle normal traffic (high metric)                 │  │
│  │                                                                       │  │
│  │   c) Configure usable interfaces based on mode:                     │  │
│  │                                                                       │  │
│  │      ┌────────────────────────────────────────────────────────────┐  │  │
│  │      │ Mode: failover                                             │  │  │
│  │      ├────────────────────────────────────────────────────────────┤  │  │
│  │      │ - All usable interfaces get routes at their configured     │  │  │
│  │      │   metrics (kernel handles priority)                        │  │  │
│  │      │ - Primary = lowest-metric usable interface                 │  │  │
│  │      │ - Backup interfaces get routes at their metrics            │  │  │
│  │      │ - If primary fails, backup with next-lowest metric becomes │  │  │
│  │      │   primary (kernel routing does this automatically)         │  │  │
│  │      └────────────────────────────────────────────────────────────┘  │  │
│  │                                                                       │  │
│  │      ┌────────────────────────────────────────────────────────────┐  │  │
│  │      │ Mode: multiuplink                                          │  │  │
│  │      ├────────────────────────────────────────────────────────────┤  │  │
│  │      │ - Create multipath route: `ip route replace default ...    │  │  │
│  │      │   nexthop via <gw1> dev <dev1> weight <w1>                 │  │  │
│  │      │   nexthop via <gw2> dev <dev2> weight <w2> ...`            │  │  │
│  │      │ - Traffic distributed proportionally to weights            │  │  │
│  │      │ - IPv6 multipath created if interfaces have IPv6 gateways  │  │  │
│  │      └────────────────────────────────────────────────────────────┘  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                              │                                              │
│                              ▼                                              │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │ STEP 5: PUBLISH STATUS                                               │  │
│  │                                                                       │  │
│  │   - Update global status object (mode, timestamp, check_interval)   │  │
│  │   - Build interfaces array with:                                    │  │
│  │     - device, ping_target, routing_class, status_since             │  │  │
│  │     - last_check, latency, gateway, ipv6_gateway                   │  │  │
│  │     - rx_bytes, tx_bytes (from /sys/class/net/...)                 │  │  │
│  │   - Expose via ubus: mini-mwan.status()                            │  │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────────┘
```

---

## Key Data Structures

### Configuration (Immutable - from UCI)

```lua
config = {
  enabled = true,              -- boolean from UCI
  mode = "failover",           -- "failover" or "multiuplink"
  check_interval = 30,         -- seconds between cycles
  log_level = "emerg",         -- log level for audit
  interfaces = {
    {
      device = "eth0",         -- physical device name
      metric = 10,             -- route priority (lower = higher)
      weight = 3,              -- load balance weight (multiuplink only)
      ping_target = "1.1.1.1", -- IP to ping for connectivity
      ping_count = 3,          -- packets per ping
      ping_timeout = 2         -- timeout per packet (seconds)
    },
    -- ... more interfaces
  }
}
```

### State (Mutable - discovered each cycle)

```lua
interface_state = {
  eth0 = {
    does_exist = true,         -- interface exists in kernel
    routing_class = "usable",  -- absent|down|unconfigured|probe_only|usable
    alive = true,              -- true only when routing_class == "usable"
    status_since = 1234567890, -- Unix epoch of last routing_class change
    latency = "12.5",          -- avg ping latency in ms (string)
    ipv6_gateway = "2001:db8::1", -- IPv6 gateway if available
    last_check = 1234567890    -- Unix epoch of last health check
  },
  -- ... more interfaces
}
```

---

## Routing Class Computation

The routing class determines how an interface is treated in the routing table.

### Algorithm Overview

The routing class is computed fresh each cycle based on three orthogonal facts:
1. **Interface existence** - Does the kernel know about this device?
2. **Interface state** - Is the interface administratively UP?
3. **Routing information availability** - Is there a gateway, or is it a P2P interface?

```
┌───────────────────────────────────────────────────────────────────────────────────┐
│                    ROUTING CLASS COMPUTATION ALGORITHM                            │
├───────────────────────────────────────────────────────────────────────────────────┤
│                                                                                   │
│  INPUT:  interface_config (device, metric, ping_target, etc.)                    │
│          interface_state (from previous cycle, may be empty)                     │
│  OUTPUT: routing_class ("absent" | "down" | "unconfigured" | "probe_only" |      │
│                         "usable")                                                 │
│                                                                                   │
│  STEP 1: CHECK IF INTERFACE EXISTS                                               │
│          └─> Run: ip addr show dev <device>                                      │
│          └─> If output contains "does not exist":                                │
│                routing_class = "absent"                                          │
│                does_exist = false                                                │
│                alive = false                                                     │
│                return                                                            │
│                                                                                   │
│  STEP 2: CHECK IF INTERFACE IS UP                                                │
│          └─> Check ip addr output for "<...UP...>" flag                          │
│          └─> If UP flag not found:                                               │
│                routing_class = "down"                                            │
│                does_exist = true                                                 │
│                alive = false                                                     │
│                return                                                            │
│                                                                                   │
│  STEP 3: CHECK FOR ROUTING INFORMATION                                           │
│          └─> For P2P interfaces (POINTOPOINT flag):                              │
│                routing info IS available (no gateway needed)                     │
│          └─> For regular interfaces (ethernet/WiFi):                             │
│                routing info available ONLY if gateway exists                     │
│                (gateway discovered via ubus network.interface.dump)              │
│          └─> If routing info NOT available:                                      │
│                routing_class = "unconfigured"                                    │
│                does_exist = true                                                 │
│                alive = false                                                     │
│                return                                                            │
│                                                                                   │
│  STEP 4: CHECK CONNECTIVITY (PING)                                               │
│          └─> Run: ping -I <device> -c <count> -W <timeout> <target>              │
│          └─> If at least 1 packet received:                                      │
│                routing_class = "usable"                                          │
│                does_exist = true                                                 │
│                alive = true                                                      │
│                latency = extracted from ping output (avg)                        │
│                return                                                            │
│          └─> If 0 packets received:                                              │
│                routing_class = "probe_only"                                      │
│                does_exist = true                                                 │
│                alive = false                                                     │
│                latency = "?"                                                     │
│                return                                                            │
│                                                                                   │
└───────────────────────────────────────────────────────────────────────────────────┘
```

### Routing Class Decision Table

| Exists | Up | Has Gateway/P2P | Ping Success | Routing Class | Why |
|--------|----|-----------------|--------------|---------------|-----|
| No | - | - | - | **absent** | Interface doesn't exist in kernel |
| Yes | No | - | - | **down** | Kernel DOWN flag set |
| Yes | Yes | No (regular) | - | **unconfigured** | No gateway, not P2P |
| Yes | Yes | Yes (P2P or gateway) | No | **probe_only** | Can probe for recovery |
| Yes | Yes | Yes | Yes | **usable** | Fully operational |

### P2P Interface Exception

Point-to-point interfaces (VPN tunnels, PPP) are treated differently:

- **Regular interfaces**: Must have a gateway to pass "routing info available" check
- **P2P interfaces**: No gateway required - the interface itself handles routing

Detection: Check for `POINTOPOINT` flag in `ip link show dev <device>` output.

### State Transitions

When routing_class changes between cycles, a transition is logged:

| From → To | Log Message |
|-----------|-------------|
| `absent` → `down` | Interface appeared but is down |
| `absent` → `unconfigured` | Interface appeared without gateway |
| `down` → `absent` | Interface disappeared |
| `down` → `unconfigured` | Interface came up without gateway |
| `down` → `probe_only` | Interface came up, gateway present, ping failed |
| `down` → `usable` | Interface came up with connectivity |
| `unconfigured` → `absent` | Interface disappeared |
| `unconfigured` → `down` | Interface went down |
| `unconfigured` → `probe_only` | Gateway appeared, ping failed |
| `unconfigured` → `usable` | Gateway appeared, ping succeeded |
| `probe_only` → `absent` | Interface disappeared |
| `probe_only` → `down` | Interface went down |
| `probe_only` → `unconfigured` | Gateway was lost |
| `probe_only` → `usable` | Ping recovered (connectivity restored) |
| `usable` → `absent` | Interface disappeared |
| `usable` → `down` | Interface went down |
| `usable` → `unconfigured` | Gateway was lost |
| `usable` → `probe_only` | Ping failed (connectivity lost) |


---

## Route Configuration Logic

### Failover Mode

In failover mode, all usable interfaces get routes at their configured metrics:

```
Given interfaces:
  eth0: metric=10, usable
  eth1: metric=20, usable
  eth2: metric=30, usable

Kernel routing table after configuration:
  default via 192.168.1.1 dev eth0 metric 10  ← Primary (lowest metric)
  default via 192.168.2.1 dev eth1 metric 20  ← Backup
  default via 192.168.3.1 dev eth2 metric 30  ← Secondary backup

Traffic routing:
  - Primary path: eth0 (metric 10)
  - If eth0 fails: eth1 (metric 20) becomes primary
  - If eth1 fails: eth2 (metric 30) becomes primary
  - Kernel automatically handles failover based on metrics
```

### Multiuplink Mode

In multiuplink mode, a single multipath route distributes traffic across all usable interfaces:

```
Given interfaces:
  eth0: metric=10, weight=3, usable, gateway=192.168.1.1
  eth1: metric=20, weight=5, usable, gateway=192.168.2.1

Command executed:
  ip route replace default \
    nexthop via 192.168.1.1 dev eth0 weight 3 \
    nexthop via 192.168.2.1 dev eth1 weight 5

Traffic distribution:
  - Traffic distributed proportionally to weights
  - eth0 receives ~3/8 (37.5%) of traffic
  - eth1 receives ~5/8 (62.5%) of traffic
  - If one interface fails, all traffic shifts to remaining interfaces
```

### P2P Interface Support

Point-to-point interfaces (VPN tunnels) have routes configured without "via" clause:

```
Given interface:
  wg0: point_to_point=true, metric=20, usable

Command executed:
  ip route add default dev wg0 metric 20

Note: No "via <gateway>" clause - the interface itself handles routing
```

### Probe-Only Routes (Metric 900)

When interfaces are `probe_only`, they receive routes at metric 900 to allow ping tests while not handling normal traffic:

```
Given interface:
  eth0: probe_only, gateway=192.168.1.1, metric=10 (configured)

Command executed:
  ip route add default via 192.168.1.1 dev eth0 metric 900

Purpose:
  - Allows ping tests to detect recovery
  - Does not handle normal traffic (metric 900 is too high)
  - When ping recovers, routing_class becomes "usable" and normal routes are set
```

---

## Route Management Implementation

### Route Enforce Logic (`enforce_route_state()`)

The `enforce_route_state()` function manages routes for interfaces configured in mini-mwan. It follows a **no-downtime** approach:

```
Algorithm:
  1. Query existing routes: ip route show default dev <device>
  2. If multiple routes exist:
     - Delete duplicate routes (routes 2-N)
     - Keep at least one route at all times
  3. If the remaining route doesn't match desired state:
     - Replace it with the correct route

Rationale:
  - `ip route replace` operates on route key (destination, gateway, device, metric)
    not on "position" in a list
  - Deleting duplicates first, then replacing ensures at least one route exists
  - This prevents routing downtime during state changes
```

### Route Cleanup Logic (`cleanup_unmanaged_routes()`)

The `cleanup_unmanaged_routes()` function removes routes for interfaces NOT managed by mini-mwan:

```
Algorithm:
  1. Build list of managed devices from current config
  2. Query all default routes: ip route show default
  3. For each route:
     - If device is NOT in managed_devices → DELETE
  4. Repeat for IPv6 routes

Purpose:
  - Removes routes created by external tools (e.g., VPN clients)
  - Cleans up stale routes from previous configurations
  - Does not affect routes for managed interfaces
```

### Multiuplink Mode Route Management

In multiuplink mode, a single multipath route replaces all existing default routes:

```
Command:
  ip route replace default \
    nexthop via 192.168.1.1 dev eth0 weight 3 \
    nexthop via 192.168.2.1 dev eth1 weight 5

Behavior:
  - `ip route replace` atomically replaces the existing default route
  - All previous routes (including metric 900) are replaced
  - Traffic distributed proportionally to weights
```

### Key Design Principles

| Principle | Rationale |
|-----------|-----------|
| Keep at least one route during changes | Prevent routing downtime |
| Delete duplicates first, then replace | Ensures no gap in routing |
| Use `ip route replace` for specific keys | Creates or updates as needed |
| Separate cleanup from enforcement | Single responsibility: cleanup unmanaged vs enforce managed |

---

## IPv4-Only Routing (IPv6 Safety)

Mini-MWAN implements **IPv4-first routing** to prevent DNS leak scenarios:

### Design Principle

> **IPv4 connectivity determines routing class. IPv6 routes are only added when IPv4 routing is also active.**

### Implementation

```lua
-- In enforce_route_state():
if ipv6_gw and desired_gw and target_metric < 900 then
    -- Only set IPv6 route when:
    -- 1. IPv6 gateway exists
    -- 2. IPv4 gateway exists (desired_gw)
    -- 3. Interface is usable (target_metric < 900)
    set_ipv6_route()
end
```

### Why This Matters

**Leak Scenario Prevented:**
1. WAN1 (eth0) has IPv4 connectivity (ping target reachable)
2. WAN2 (wg0 VPN tunnel) has IPv6 connectivity
3. Without IPv4-first logic, DNS AAAA queries might use IPv6 (WAN2) while traffic routes via IPv4 (WAN1)
4. This would leak your real public IP because the response routing doesn't match the query path

**How Mini-MWAN Prevents This:**
- Routing class is determined by IPv4 ping results only
- IPv6 routes are added ONLY on interfaces that also have IPv4 routing
- If IPv4 connectivity fails, no traffic is routed (fail-closed) rather than falling back to IPv6

---

## State Persistence

### Purpose

The `interface_state` table persists across UCI config reloads to prevent status flapping during configuration updates.

### What Persists

| Field | Purpose |
|-------|---------|
| `routing_class` | Last known routing class |
| `alive` | Last known connectivity status |
| `does_exist` | Last known interface existence |
| `status_since` | Timestamp of last routing_class change |
| `latency` | Last measured latency |
| `ipv6_gateway` | Last known IPv6 gateway |
| `last_check` | Timestamp of last health check |

### What Does NOT Persist

- State is **not** persisted across daemon restarts (each start gets fresh state)
- State is **not** persisted across system reboots (tmpfs `/var`)

### Implementation

```lua
local interface_state = {}  -- Global table, persists across config reloads

function save_interface_state(device, iface_state)
  iface_state.last_check = deps.time()
  interface_state[device] = {
    does_exist    = iface_state.does_exist,
    routing_class = iface_state.routing_class,
    alive         = iface_state.alive,
    status_since  = iface_state.status_since,
    latency       = iface_state.latency,
    ipv6_gateway  = iface_state.ipv6_gateway,
    last_check    = iface_state.last_check,
  }
  return iface_state
end
```

---

## Event Logging

### Log Levels

| Level | Purpose | Example |
|-------|---------|---------|
| **debug** | Probes and detailed diagnostic | `Probe: /bin/ping -I eth0 -c 3 ...` |
| **info** | State transitions and important events | `eth0: Interface UP (latency: 12.50 ms)` |
| **notice** | Route interventions | `Intervention: /sbin/ip route add default ...` |
| **warning** | Interface disappearance | `eth0: Interface DISAPPEARED (USB dongle removed?)` |
| **err** | Configuration errors and failures | `ERROR: At least 2 interfaces must be configured` |

### Audit Logging

When `audit` mode is enabled, all system commands are logged:

```
Debug: Probe: ubus call network.interface dump
Debug: Probe: /sbin/ip addr show dev eth0
Debug: Probe: /bin/ping -I eth0 -c 3 -W 2 1.1.1.1
Notice: Intervention: /sbin/ip route add default via 192.168.1.1 dev eth0 metric 10
Notice: Intervention: /sbin/ip route flush default dev eth0
```

---

## Error Handling

### Graceful Degradation

Mini-MWAN is designed to fail gracefully:

1. **Invalid Configuration**: Daemon logs errors and continues sleeping (no crash)
2. **Missing Dependencies**: Logs error and continues operation
3. **Command Failures**: Errors logged but daemon continues
4. **Single Interface**: Still manages routing (with warning)

### Error Cases Handled

| Scenario | Behavior |
|----------|----------|
| UCI parse error | Logged, use defaults |
| Ping command fails | Interface marked probe_only |
| Ubus connection fails | Gateway not discovered (interface may become unconfigured) |
| Route command fails | Logged (interface may not be routable) |
| No interfaces configured | Daemon logs error and continues |

---

## Integration with OpenWrt

### UCI Configuration

**File**: `/etc/config/mini-mwan`

```bash
config settings 'settings'
    option enabled '1'
    option mode 'failover'
    option check_interval '30'
    option audit 'error'

config interface 'wan1'
    option device 'eth0'
    option metric '10'
    option weight '3'
    option ping_target '1.1.1.1'
    option ping_count '3'
    option ping_timeout '2'

config interface 'wan2'
    option device 'wg0'
    option metric '20'
    option weight '5'
    option ping_target '8.8.8.8'
```

### Service Control

```bash
# Start/stop/restart
/etc/init.d/mini-mwan start
/etc/init.d/mini-mwan stop
/etc/init.d/mini-mwan restart

# Enable/disable on boot
/etc/init.d/mini-mwan enable
/etc/init.d/mini-mwan disable

# Check status
/etc/init.d/mini-mwan status

# View logs
logread | grep mini-mwan
cat /var/log/mini-mwan.log
```

### Status via ubus

```bash
ubus call mini-mwan status
```

Returns JSON with:
- Global: mode, timestamp, check_interval
- Per-interface: device, routing_class, latency, gateway, traffic stats

---

## Testing Strategy

### Unit Tests

Test individual functions in isolation:
- `config_spec.lua` - Configuration loading
- `gateway_spec.lua` - Gateway discovery via ubus
- `interface_state_spec.lua` - Interface UP/DOWN detection
- `latency_spec.lua` - Ping latency parsing
- `degradation_spec.lua` - Routing class computation
- `status_update_spec.lua` - Status via ubus

### Integration Tests

End-to-end scenarios:
- `failover_spec.lua` - Primary/backup failover
- `multiuplink_spec.lua` - Load balancing
- `route_cleanup_spec.lua` - Duplicate route handling
- `interface_lifecycle_spec.lua` - Interface disappearance/reappearance
- `logging_spec.lua` - Audit logging

### Test Coverage

Tests verify:
- State transitions between all routing classes
- Route configuration in both modes
- IPv4 and IPv6 routing
- P2P interface handling
- Error handling and recovery
- Logging at all levels

---

## Performance Characteristics

### Resource Usage

- **Memory**: ~100KB for interface state + configuration
- **CPU**: < 1% during normal operation (mostly idle in uloop)
- **Network**: 3 pings per interface per check_interval

### Timing Constraints

| Operation | Maximum Time |
|-----------|--------------|
| Config reload | 5 seconds |
| Ping check | (count × timeout) + 2 seconds |
| Route update | 1 second |
| Check interval | Configurable (10-300 seconds) |

---

## Troubleshooting

### Common Issues

1. **No routes being set**:
   - Check `logread | grep mini-mwan` for configuration errors
   - Verify at least 2 interfaces are configured
   - Check that interfaces have IPv4 gateways

2. **Interface stuck in unconfigured**:
   - Interface has UP flag but no gateway
   - Check DHCP lease status
   - Verify gateway is reachable

3. **Interface stuck in probe_only**:
   - Interface has gateway but ping fails
   - Verify ping_target is reachable from interface
   - Check firewall rules (may block ICMP)

4. **Unexpected route changes**:
   - Check for duplicate routes from other tools
   - Review logs for routing class transitions
   - Verify check_interval is not too short

### Debug Commands

```bash
# View mini-mwan logs
logread | grep mini-mwan
tail -f /var/log/mini-mwan.log

# Check routing table
ip route show table main
ip route show default

# Check interface status
ip addr show dev eth0
ip link show dev eth0

# Test ping from specific interface
ping -I eth0 -c 3 1.1.1.1

# Query ubus status
ubus call mini-mwan status
```

---

## Future Enhancements

Potential improvements (not currently implemented):

1. **Alternative health probes**: HTTP(S), DNS queries
2. **Latency-based routing**: Prefer interfaces with lower latency
3. **Packet loss-based routing**: Prefer interfaces with lower packet loss
4. **Per-application routing**: Policy-based routing
5. **Sticky sessions**: Maintain connection to same interface
6. **Full IPv6 support**: Independent IPv6 routing decisions

---

## Author

Alex Schwartzman <openwrt@schwartzman.uk>

## Version

1.0.0

## Date

2026-07-22
