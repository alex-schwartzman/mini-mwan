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
| metric | integer | 1-999 | 10 | No |
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
- Metric values 900+ are reserved for internal use

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
| Class transition | `eth0: Interface UP but unconfigured (no gateway or IPv6 detected)` |
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

### DR-4.1 Interface State Object
**ID**: DR-4.1
**Priority**: Critical
**Description**: Internal interface state representation.

**Lua Table Structure**:
```lua
{
    enabled = true,                   -- boolean
    device = "eth0",                  -- string
    metric = 1,                       -- integer
    weight = 3,                       -- integer
    ping_target = "1.1.1.1",         -- string
    ping_count = 3,                   -- integer
    ping_timeout = 2,                 -- integer
    point_to_point = false,           -- boolean
    routing_class = "usable",         -- string: absent|down|unconfigured|probe_only|usable
    alive = true,                     -- boolean: true only when routing_class is "usable"
    does_exist = true,                -- boolean: false when routing_class is "absent"
    status_since = 1698765432,        -- integer (unix epoch)
    latency = 12.5,                   -- number (float) or "?" when not usable
    gateway = "192.168.1.1",          -- string or nil
    last_check = 1698765432           -- integer (unix epoch)
}
```

**Invariants**:
- `routing_class` MUST be one of: "absent", "down", "unconfigured", "probe_only", "usable"
- `routing_class` is computed fresh each cycle from kernel state, ubus state, and ping result
- `status_since` MUST be updated when `routing_class` changes
- `alive` MUST be true only when `routing_class == "usable"`
- `gateway` MAY be nil for P2P interfaces or when DHCP is incomplete
- `latency` is `"?"` when `routing_class` is not "usable"

### DR-4.2 Persistent State Table
**ID**: DR-4.2
**Priority**: High
**Description**: Persisted state across config reloads.

**Lua Table Structure**:
```lua
interface_state = {
    ["eth0"] = {
        routing_class = "usable",
        alive = true,
        does_exist = true,
        status_since = 1698765432,
        latency = 12.5,
        last_check = 1698765432,
    },
    ["eth1"] = { ... }
}
```

Note: The table is keyed by device name (e.g. `"eth0"`), not by UCI interface name.

**Persistence Scope**:
- Data persists across configuration reloads (UCI changes)
- Data DOES NOT persist across daemon restarts
- Data DOES NOT persist across system reboots
- Purpose: Prevent status flapping during config updates

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

## DR-7: Data Validation Requirements

### DR-7.1 Input Sanitization
**ID**: DR-7.1
**Priority**: High
**Description**: All external inputs SHALL be validated.

**Validation Rules**:

| Input Type | Validation |
|------------|------------|
| Interface name | Match `^[a-zA-Z0-9_.-]+$`, max 16 chars |
| IP address | Valid IPv4 dotted-quad format |
| Metric value | Integer 1-999 |
| Weight value | Integer 1-100 |
| Check interval | Integer 10-300 |
| Ping count | Integer 1-10 |
| Ping timeout | Integer 1-30 |
| Boolean values | Exactly "0" or "1" |
| Mode | Exactly "failover" or "multiuplink" |

### DR-7.2 Data Type Coercion
**ID**: DR-7.2
**Priority**: Medium
**Description**: Type conversion rules for configuration values.

**Coercion Rules**:
- UCI strings to integers: Use `tonumber()`, default on failure
- UCI strings to booleans: Compare to "1" exactly
- Empty strings: Treat as nil
- Missing values: Use documented defaults
- Invalid values: Log warning, use default
