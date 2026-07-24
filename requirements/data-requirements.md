# Data and Interface Requirements

## DR-1: Configuration File Format

### DR-1.1 UCI Configuration Structure
**ID**: DR-1.1
**Priority**: Critical
**Description**: Configuration SHALL use UCI format at `/etc/config/mini-mwan`.

**File Structure**:
```ini
config settings 'settings'
	option enabled '0|1'
	option mode 'failover|multiuplink'
	option check_interval '<seconds>'
	option audit 'emerg|alert|crit|err|warning|notice|info|debug'

config interface '<name>'
	option enabled '0|1'
	option device '<interface_name>'
	option metric '<priority_value>'
	option weight '<load_balance_weight>'
	option ping_target '<ip_address>'
	option ping_count '<number>'
	option ping_timeout '<seconds>'
```

**Field Specifications**:

#### Settings Section
| Field | Type | Range/Values | Default | Required |
|-------|------|--------------|---------|----------|
| enabled | boolean | 0, 1 | 0 | Yes |
| mode | string | "failover", "multiuplink" | "failover" | No |
| check_interval | integer | 10-300 | 30 | No |
| audit | boolean | 0, 1 | 0 | No |

#### Interface Section
| Field | Type | Range/Values | Default | Required |
|-------|------|--------------|---------|----------|
| enabled | boolean | 0, 1 | 1 | No |
| device | string | Valid interface name | - | Yes |
| metric | integer | 1-899 | 10 | No |
| weight | integer | 1-100 | 3 | No |
| ping_target | string | Valid IPv4 address | - | Yes |
| ping_count | integer | 1-10 | 3 | No |
| ping_timeout | integer | 1-30 | 2 | No |

**Validation Rules**:
- At least 2 interface sections MUST be defined
- Each interface section MUST have unique name
- Interface names MUST be valid UCI identifiers (alphanumeric + underscore)
- Device names MUST match Linux interface naming conventions
- Ping targets MUST be valid IPv4 addresses
- Metric values 900+ are reserved for internal use (probe routes only)

---

## DR-2: Status Communication

### DR-2.1 Status via ubus
**ID**: DR-2.1
**Priority**: High
**Description**: Status information SHALL be exposed via ubus object `mini-mwan` with method `status`.

**ubus Method**: `mini-mwan.status`

**JSON Response Structure**:
```json
{
  "mode": "failover|multiuplink",
  "timestamp": 1234567890,
  "check_interval": 30,
  "interfaces": [
    {
      "device": "eth0",
      "ping_target": "8.8.8.8",
      "routing_class": "usable",
      "status_since": "1234567890",
      "last_check": "1234567890",
      "latency": 12.5,
      "gateway": "192.168.1.1",
      "rx_bytes": 123456,
      "tx_bytes": 654321
    }
  ]
}
```

**Field Specifications**:

#### Global Fields
| Field | Type | Description |
|-------|------|-------------|
| mode | string | Current operation mode (failover or multiuplink) |
| timestamp | integer | Unix epoch of last status update |
| check_interval | integer | Current check interval in seconds |

#### Interface Fields
| Field | Type | Description |
|-------|------|-------------|
| device | string | Physical interface name |
| ping_target | string | IP address used for connectivity checks |
| routing_class | string | One of: `absent`, `down`, `unconfigured`, `probe_only`, `usable` |
| status_since | string | Unix epoch of last routing_class change |
| last_check | string | Unix epoch of last health check |
| latency | float | Average ping latency in milliseconds (0 if not usable) |
| gateway | string | Gateway IP address (empty for P2P or when unavailable) |
| rx_bytes | integer | Received bytes counter |
| tx_bytes | integer | Transmitted bytes counter |

**Status Characteristics**:
- Status MUST be updated after each monitoring cycle
- Status MUST be accessible via ubus for LuCI and other clients
- Status contains no sensitive data
- Unavailable ubus object indicates daemon not running

---

## DR-3: Log File Format

### DR-3.1 Application Log Structure
**ID**: DR-3.1
**Priority**: High
**Description**: Logs SHALL be written to `/var/log/mini-mwan.log`.

**Log Entry Format**:
```
[YYYY-MM-DD HH:MM:SS] <message>
```

**Message Categories**:

| Category | Example |
|----------|---------|
| Startup | `Mini-MWAN daemon starting` |
| Class transition | `eth0: Interface UP (latency: 12.50 ms)` |
| Class transition | `eth0: Interface UP but unusable (connectivity lost)` |
| Class transition | `eth0: Interface UP but unconfigured (no IPv4 gateway)` |
| Route Change | `Intervention: /sbin/ip route add default via 192.168.1.1 dev eth0 metric 10` |
| Configuration | `ERROR: Both WAN interfaces must be configured` |
| Probe | `Probe: /bin/ping -I eth0 -c 3 -W 2 1.1.1.1` |

**Log Rotation**:
- Log rotation is handled by OpenWrt's logd
- No size limits enforced by daemon
- Logs MAY be lost on reboot (stored in /var which is tmpfs)

### DR-3.2 Syslog Integration
**ID**: DR-3.2
**Priority**: Medium
**Description**: All log messages SHALL also be sent to syslog.

**Syslog Format**:
- Facility: LOG_USER
- Tag: `mini-mwan`
- Priority: LOG_INFO (normal operations), LOG_ERR (errors), LOG_WARNING (warnings)

---

## DR-4: Runtime Data Structures

### DR-4.1 State Model: Config vs State vs Status

Mini-MWAN distinguishes between three types of data:

#### Config (Immutable from UCI)
Configuration loaded from `/etc/config/mini-mwan`. Never changes at runtime.
- **Global settings**: mode, check_interval, audit
- **Interface config**: device, metric, weight, ping_target, ping_count, ping_timeout

#### State (Mutable, Ephemeral)
Runtime state discovered each cycle. NOT persisted across daemon restarts.

**State persisted across config reloads** (stored in `interface_state` table):
These fields survive UCI config reloads but are refreshed each cycle:
- `routing_class` - Current routing class (absent|down|unconfigured|probe_only|usable)
  - Used to detect state transitions and log changes
- `does_exist` - Whether the interface exists in the kernel  
  - Used to detect interface disappearance/appearance between cycles
- `status_since` - Timestamp of last routing_class change
  - Used for status display (how long in current state)

**State computed fresh each cycle** (stored temporarily for current cycle's work):
These are discovered from kernel/ubus each cycle, then persisted in `interface_state` for the NEXT cycle's baseline:
- `alive` - Derived from current routing_class == "usable"
- `gateway` - Discovered via ubus network.interface.dump
- `latency` - Measured via ping
- `ipv6_gateway` - Discovered via ubus (for dual-stack routing)
- `point_to_point` - Detected via ip link show

**State communicated via ubus** (status output for Luci):
The following fields are included in the ubus status response for Luci display:
- All state fields above
- Network statistics (rx_bytes, tx_bytes) from sysfs

**Note**: The `interface_state` table serves two purposes:
1. Persists state across config reloads (for transition detection)
2. Provides the current cycle's state for route decisions and status output

#### Status (Presentation Layer)
Merged view for display via ubus. Includes both config and ephemeral state.
- All interface fields from state
- Network statistics (rx_bytes, tx_bytes)

### DR-4.2 Interface State Object (Ephemeral)
**ID**: DR-4.2
**Priority**: High
**Description**: Internal interface state representation. This is rebuilt each cycle.

**Lua Table Structure**:
```lua
{
    enabled = true,                   -- boolean (from config)
    device = "eth0",                  -- string (from config)
    metric = 1,                       -- integer (from config)
    weight = 3,                       -- integer (from config)
    ping_target = "1.1.1.1",         -- string (from config)
    ping_count = 3,                   -- integer (from config)
    ping_timeout = 2,                 -- integer (from config)
    point_to_point = false,           -- boolean (discovered fresh)
    routing_class = "usable",         -- string: absent|down|unconfigured|probe_only|usable (persisted for transitions)
    alive = true,                     -- boolean: true only when routing_class is "usable"
    does_exist = true,                -- boolean: false when routing_class is "absent" (persisted for disappearance detection)
    status_since = 1698765432,        -- integer (unix epoch, persisted across reloads)
    latency = 12.5,                   -- number (float, measured fresh each cycle)
    gateway = "192.168.1.1",          -- string (discovered via ubus, fresh each cycle)
    ipv6_gateway = "2001:db8::1",     -- string (discovered via ubus, fresh each cycle)
    last_check = 1698765432           -- integer (unix epoch, current cycle timestamp)
}
```

**Invariants**:
- `routing_class` MUST be one of: "absent", "down", "unconfigured", "probe_only", "usable"
- `routing_class` is computed fresh each cycle from kernel state, ubus state, and ping result
- `status_since` MUST be updated when `routing_class` changes
- `alive` MUST be true only when `routing_class == "usable"`
- `gateway` MAY be nil for P2P interfaces or when DHCP is incomplete
- `latency` is `"?"` when `routing_class` is not "usable"
- `does_exist` is persisted across config reloads to detect interface disappearance/appearance
- `routing_class` is persisted across config reloads to detect and log state transitions

### DR-4.3 Persistent State Table (Across Config Reloads)
**ID**: DR-4.3
**Priority**: High
**Description**: State that survives configuration reloads (but not daemon restarts).

**Lua Table Structure**:
```lua
interface_state = {
    ["eth0"] = {
        routing_class = "usable",       -- persisted: needed for transition detection
        does_exist = true,              -- persisted: needed to detect disappearance
        status_since = 1698765432,      -- persisted: for status display
    },
    ["eth1"] = { ... }
}
```

**Persistence Scope**:
- Data persists across configuration reloads (UCI changes)
- Data DOES NOT persist across daemon restarts
- Data DOES NOT persist across system reboots
- Purpose: Prevent status flapping during config updates, enable transition logging

**Fields that Persist**:
| Field | Purpose | Why Persist? |
|-------|---------|--------------|
| `routing_class` | Transition detection | Log when state changes between cycles |
| `does_exist` | Interface disappearance | Detect when USB dongle removed or tunnel down |
| `status_since` | UI display | Show how long interface has been in current state |

**Fields that Do NOT Persist**:
| Field | Reason |
|-------|--------|
| `alive` | Derived from `routing_class` (not stored separately) |
| `latency` | Measured fresh via ping each cycle; reported in ubus status |
| `gateway` | Discovered fresh via ubus each cycle; reported in ubus status |
| `ipv6_gateway` | Discovered fresh via ubus each cycle; reported in ubus status |
| `point_to_point` | Detected fresh via ip link each cycle; used internally for routing |

**Note**: These fields are computed fresh each cycle and included in the ubus status output for Luci display. They are not persisted because they change frequently based on current network state.

### DR-4.4 Runtime State Usage Summary
**ID**: DR-4.4
**Priority**: High

#### State Persistence Rules
1. **Persisted across config reloads**:
   - `routing_class` - To detect and log state transitions
   - `does_exist` - To detect interface disappearance/appearance
   - `status_since` - To track how long in current state

2. **Rebuilt each cycle**:
   - All discovered state (gateways, latency, existence check results)
   - `alive` - Derived from current `routing_class`
   - `last_check` - Current timestamp

3. **Never persisted**:
   - Any field derived from other fields
   - Any field that changes too frequently to be useful

---

## DR-5: External Interface Dependencies

### DR-5.1 netifd ubus Interface
**ID**: DR-5.1
**Priority**: Critical
**Description**: Gateway discovery via netifd's ubus API using libubus library.

**Implementation**:
```lua
local data = conn:call("network.interface", "dump", {})
```

**Expected Response Structure** (Lua table):
```json
{
    "up": true,
    "pending": false,
    "available": true,
    "device": "eth0",
    "ipv4-address": [
        {
            "address": "192.168.1.100",
            "mask": 24
        }
    ],
    "route": [
        {
            "target": "0.0.0.0",
            "mask": 0,
            "nexthop": "192.168.1.1",
            "source": "192.168.1.100/24"
        }
    ]
}
```

**Data Extraction**:
- Gateway SHALL be extracted from route array
- Look for entry where `target="0.0.0.0"` AND `mask=0`
- Extract `nexthop` field as gateway IP only if it is not `"0.0.0.0"` — netifd encodes P2P routes with `nexthop="0.0.0.0"` which means "no gateway"
- Return nil if no matching route found or nexthop is `"0.0.0.0"`

**Error Handling**:
- Invalid JSON → Log error, return nil
- Missing route array → Return nil
- Empty response → Return nil

### DR-5.2 ip command Interface
**ID**: DR-5.2
**Priority**: Critical
**Description**: Interface state and route management via iproute2.

**Commands Used**:

| Command | Purpose | Expected Output |
|---------|---------|-----------------|
| `ip addr show dev <iface>` | Check interface exists and is UP | Interface details or error |
| `ip route show` | List current routes | Route table entries |
| `ip route replace default via <gw> dev <iface> metric <m>` | Set route with gateway | No output on success |
| `ip route replace default dev <iface> metric <m>` | Set P2P route | No output on success |
| `ip route delete default via <gw> dev <iface>` | Remove specific route | No output on success |
| `ip -6 addr show dev <iface>` | Check for IPv6 addresses | IPv6 addresses or empty |

**Output Parsing**:
- Interface UP detection: Look for `<.*UP.*>` in output
- Route parsing: Parse text format (no JSON available)

### DR-5.3 ping command Interface
**ID**: DR-5.3
**Priority**: Critical
**Description**: Connectivity testing via ICMP ping.

**Command Format**:
```bash
ping -I <device> -c <count> -W <timeout> -w <deadline> <target>
```

**Expected Output** (success):
```
PING 1.1.1.1 (1.1.1.1) from 192.168.1.100 eth0: 56(84) bytes of data.
64 bytes from 1.1.1.1: icmp_seq=1 ttl=57 time=12.3 ms
...
--- 1.1.1.1 ping statistics ---
3 packets transmitted, 3 received, 0% packet loss, time 2003ms
rtt min/avg/max/mdev = 11.2/12.1/13.5/0.9 ms
```

**Data Extraction**:
- Received packets: Extract from `<n> packets received`
- Average latency: Extract from `rtt min/avg/max/mdev = X/Y/Z/W` (Y value)
- Success: received > 0

---

## DR-6: File System Requirements

### DR-6.1 File Locations
**ID**: DR-6.1
**Priority**: Critical
**Description**: Standard file system locations.

| File/Directory | Purpose | Writable | Persistent |
|----------------|---------|----------|------------|
| `/etc/config/mini-mwan` | Configuration | Yes | Yes (flash) |
| `/usr/bin/mini-mwan.lua` | Daemon executable | No | Yes (flash) |
| `/etc/init.d/mini-mwan` | Init script | No | Yes (flash) |
| `/var/log/mini-mwan.log` | Application log | Yes | No (tmpfs) |
| `/var/run/mini-mwan.pid` | PID file (managed by procd) | Yes | No (tmpfs) |
| `/sys/class/net/<dev>/statistics/` | Network stats | No | No (sysfs) |

### DR-6.2 File Permissions
**ID**: DR-6.2
**Priority**: High
**Description**: Required file permissions.

| File | Owner | Group | Mode | Rationale |
|------|-------|-------|------|-----------|
| `/etc/config/mini-mwan` | root | root | 0600 | Prevent unauthorized config changes |
| `/usr/bin/mini-mwan.lua` | root | root | 0755 | Executable by root |
| `/etc/init.d/mini-mwan` | root | root | 0755 | Executable init script |
| `/var/log/mini-mwan.log` | root | root | 0644 | Readable for troubleshooting |

---