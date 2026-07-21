#!/usr/bin/lua

--[[
Mini-MWAN Daemon
Manages multi-WAN failover and load balancing
]]--

-- Conditionally load OpenWRT-specific dependencies
-- In test mode, these will be mocked via dependency injection
local uci, nixio, ubus, uloop, unixio
if not os.getenv("MINI_MWAN_TEST_MODE") then
  uci = require("uci")
  nixio = require("nixio")
  unixio = require("nixio.util")
  ubus = require("ubus")
  uloop = require("uloop")
else
  -- Test mode: use standard JSON if available, or it will be mocked
  local ok, cjson = pcall(require, "cjson")
end

-- Configuration
local LOG_FILE = "/var/log/mini-mwan.log"

-- Persistent interface state (survives config reloads)
local interface_state = {}

-- Global state for ubus (shared across work cycles)
local current_status = {
  mode = "unknown",
  timestamp = 0,
  check_interval = 0,
  interfaces = {}
}

-- Global ubus connection moved to deps table for better testability

-- Dependencies table (defaults to real implementations)
-- In production: uses real OpenWrt modules
-- In test mode: must be completely replaced via set_dependencies()
local deps = {
  log = function(msg, priority)
    nixio.syslog(priority, msg)
  end,
  sleep = function(seconds)
    nixio.nanosleep(seconds)
  end,
  time = os.time,
  open_file = io.open,
  uci_cursor = function()
    return uci.cursor()
  end,
  -- Ubus connection with 5 second timeout to prevent hangs
  ubus_connect = function()
    local conn = ubus.connect()
    if conn then
      conn.timeout = 5  -- 5 second timeout for ubus operations
    end
    return conn
  end,
  uloop_init = function()
    return uloop.init()
  end,
  uloop_timer = function(callback)
    return uloop.timer(callback)
  end,
  uloop_run = function()
    return uloop.run()
  end,
  -- Command execution with timeout
  exec = function(args)
    local rd, wr = nixio.pipe()
    local pid = nixio.fork()

    if pid == 0 then
      -- Use the functional style: nixio.dup(source_obj, dest_obj)
      nixio.dup(wr, nixio.stdout)
      rd:close()
      wr:close()
      local _, errmsg, errno = nixio.exec(args[1], unpack(args, 2))
      nixio.syslog("err", string.format("exec failed: %s", errmsg or "unknown error"))
      os.exit(errno or 1)
    else
      wr:close()
      -- Wait for process with timeout (10 seconds)
      local status, elapsed = nixio.waitpid(pid, 10000)  -- 10s timeout
      local output
      if status then
        output = rd:readall()
      else
        -- Process timed out - log warning
        nixio.syslog("warning", string.format("Command timeout after %dms: %s", elapsed, table.concat(args, " ")))
        output = ""
      end
      rd:close()
      return output
    end
  end
}

-- Allow dependency injection for testing
local function set_dependencies(new_deps)
  for k, v in pairs(new_deps) do
    deps[k] = v
  end
  -- Reset connection to force fresh connection with new deps
  deps.ubus_conn = nil
end

-- Logging function
-- Uses syslog for centralized logging (standard on OpenWRT)
local function log(msg, priority)
  priority = priority or "info"
  deps.log(msg, priority)
end

-- argv-style probe: no shell, no injection risk
-- Gradually replaces system_probe(cmd) call sites
local function system_exec(args)
  log(string.format("Probe: %s", table.concat(args, " ")), "debug")
  return deps.exec(args)
end

-- Execute state-changing system intervention (ip route add/replace/delete)
-- Logged at notice level (5) - important to track configuration changes
local function system_intervention_argv(args)
  log(string.format("Intervention: %s", table.concat(args, " ")), "notice") -- notice
  return deps.exec(args)
end

-- Ping check function through specific interface
local function check_ping(target, count, timeout, device)
  count = count or 3
  timeout = timeout or 2

  -- Ping through specific interface using source routing
    -- Use -I to specify interface
  local deadline = (count * timeout) + 2
  local args = {"/bin/ping", "-I", device, "-c", tostring(count), "-W", tostring(timeout), "-w", tostring(deadline), target}
  local output = system_exec(args)

  if not output then
    log(string.format("Ping failed: no output from command for device: %s", device), "err")  -- err
    return false, 0
  end

  -- Parse ping statistics
  local received = output:match("(%d+) packets received")
  if not received then
    log(string.format("Ping failed: could not parse output for device: %s", device), "err")
    return false, 0
  end

  if tonumber(received) > 0 then
    -- Parse average latency
    local avg_latency = output:match("min/avg/max[^=]+=.-/(.-)/")
    log(string.format("Ping successful: %s %s", target, avg_latency), "debug")
    return true, avg_latency
  end

  log(string.format("Ping failed: 0 packets received to %s via %s", target, device), "debug")
  return false, 0
end

-- Check if interface exists and is UP
-- Returns: (does_exist: boolean, is_up: boolean)
local function check_interface_is_up(iface)
  local output = system_exec({"/sbin/ip", "addr", "show", "dev", iface})

  if not output then
    log(string.format("Failed to start ip addr show for iface: %s", iface), "err")
    return false, false  -- some serious problem - binary not found or so
  end

  if output:match("does not exist") then
    log(string.format("Device does not exist: %s", iface), "notice")
    return false, false  -- Device doesn't exist
  end

  -- Check if interface has UP flag
  -- Example: "3: wan: <BROADCAST,MULTICAST,UP,LOWER_UP>"
  if output:match("<[^>]*UP[^>]*>") then
    return true, true  -- Exists and is UP
  end

  return true, false  -- Exists but is DOWN
end

-- Get network statistics for interface (TX/RX bytes)
local function get_interface_stats(device)
  if not device or device == "" then
    return "0", "0"
  end

  -- Helper function to read a single stat file
  local function read_stat(stat_name)
    local path = string.format("/sys/class/net/%s/statistics/%s", device, stat_name)
    local file = deps.open_file(path, "r")
    if file then
      local content = file:read("*l") -- Read one line, automatically strips newline
      file:close()
      if content and content ~= "" then
        return content
      end
    end
    return "0"
  end

  local rx_bytes = read_stat("rx_bytes")
  local tx_bytes = read_stat("tx_bytes")

  return rx_bytes, tx_bytes
end

-- Probe all gateways from network dump (call once per cycle)
-- Returns device -> gateway map for O(1) lookups
-- P2P interfaces and interfaces without gateways will not be in the map
-- IPv4 gateway is required for routing class determination
-- IPv6 gateway is discovered for dual-stack routing
local function probe_all_gateways()
  -- Use libubus directly instead of shelling out to ubus binary
  -- conn is either initialized by register_ubus() or we get it from deps
  if not deps.ubus_conn then
    deps.ubus_conn = deps.ubus_connect()
  end

  if not deps.ubus_conn then
    log("Failed to connect to ubus", "err")
    return {}, {}
  end

  log("Probe: ubus call network.interface dump", "debug")
  local data = deps.ubus_conn:call("network.interface", "dump", {})

  local ipv4_gateway_map = {}
  local ipv6_gateway_map = {}

  if not data then
    log("Failed to call network.interface dump via ubus", "err")
    return {}, {}
  end

  -- data.interface is already a Lua table from libubus (no JSON parsing needed)
  if data.interface then
    for _, iface in ipairs(data.interface) do
      if iface.l3_device and iface.route then
        for _, route in ipairs(iface.route) do
          -- nexthop "0.0.0.0" means P2P/no-gateway in netifd — not a real gateway
          if route.target == "0.0.0.0" and route.mask == 0 and
             route.nexthop and route.nexthop ~= "0.0.0.0" then
            -- Determine if IPv4 or IPv6 based on gateway address format
            if route.nexthop:match("%.") then
              ipv4_gateway_map[iface.l3_device] = route.nexthop
            elseif route.nexthop:match(":") then
              ipv6_gateway_map[iface.l3_device] = route.nexthop
            end
          end
          -- Also look for IPv6 default route (::/0)
          if route.target == "::" and route.mask == 0 and
             route.nexthop and route.nexthop ~= "::" then
            ipv6_gateway_map[iface.l3_device] = route.nexthop
          end
        end
      end
    end
  end

  return ipv4_gateway_map, ipv6_gateway_map
end

-- Detect if interface is point-to-point (VPN, PPP, tunnel) or shared medium (ethernet)
-- Point-to-point interfaces have POINTOPOINT flag set in ip link output
local function detect_point_to_point(device)
  if not device or device == "" then
    return false
  end

  local output = system_exec({ "/sbin/ip", "link", "show", "dev", device })
  if not output or output == "" then
    return false
  end

  -- Check for POINTOPOINT flag (note: uppercase in kernel output)
  return output:match("POINTOPOINT") ~= nil
end

-- Compute the routing class for one interface based on three orthogonal facts:
--   is_up           — kernel UP flag (ip addr show)
--   has_routing_info — gateway present (ethernet) OR point-to-point (wg0/tun0)
--   alive           — ping returned packets
--
-- Returns one of: "absent" | "down" | "unconfigured" | "probe_only" | "usable"
-- Also sets iface_state.latency, iface_state.does_exist, iface_state.alive.
local function compute_routing_class(iface_cfg, iface_state)
  local device = iface_cfg.device

  local does_exist, is_up = check_interface_is_up(device)

  -- Log interface disappearance / reappearance (distinct from routing-class transitions)
  if iface_state.does_exist and not does_exist then
    log(string.format("%s: Interface DISAPPEARED (USB dongle removed? tunnel down?)", device), "warning")
  elseif not iface_state.does_exist and does_exist then
    log(string.format("%s: Interface APPEARED (device reconnected)", device), "info")
  end
  iface_state.does_exist = does_exist

  if not does_exist then
    iface_state.alive = false
    iface_state.latency = "?"
    return "absent"
  end

  if not is_up then
    iface_state.alive = false
    iface_state.latency = "?"
    return "down"
  end

  local has_ipv4_routing_info = iface_state.point_to_point or
                                  (iface_state.gateway and iface_state.gateway ~= "")

  if not has_ipv4_routing_info then
    iface_state.alive = false
    iface_state.latency = "?"
    return "unconfigured"
  end

  local alive, latency = check_ping(iface_cfg.ping_target, iface_cfg.ping_count, iface_cfg.ping_timeout, device)
  if alive then
    iface_state.alive = true
    iface_state.latency = latency
    return "usable"
  else
    iface_state.alive = false
    iface_state.latency = "?"
    return "probe_only"
  end
end

-- Log a routing-class transition at info level (silent when class unchanged).
local function log_state_transition(device, old_class, new_class, iface_state)
  if old_class == new_class then return end
  local msg
  if new_class == "down" then
    msg = string.format("%s: Interface DOWN", device)
  elseif new_class == "unconfigured" then
    msg = string.format("%s: Interface UP but unconfigured (no IPv4 gateway)", device)
  elseif new_class == "probe_only" then
    msg = string.format("%s: Interface UP but unusable (IPv4 connectivity lost)", device)
  elseif new_class == "usable" then
    local ipv6_log = ""
    if iface_state.ipv6_gateway and iface_state.ipv6_gateway ~= "" then
      ipv6_log = string.format(" (IPv6 gateway: %s)", iface_state.ipv6_gateway)
    end
    msg = string.format("%s: Interface UP (latency: %s ms%s)", device, iface_state.latency or "?", ipv6_log)
  end
  if msg then log(msg, "info") end
end

-- Enforce a single default route for a device at a given metric.
-- Reads current kernel routes: if exactly one correct route already exists, does nothing.
-- Otherwise flushes all default routes for the device and adds the desired one.
-- Used for both usable interfaces (configured metric) and unusable ones (metric 900).
-- Also sets IPv6 route if IPv6 gateway is available (dual-stack support).
local function enforce_route_state(iface, target_metric)
  local device = iface.cfg.device
  local desired_gw = (iface.state.gateway and iface.state.gateway ~= "") and iface.state.gateway or nil
  local ipv6_gw = (iface.state.ipv6_gateway and iface.state.ipv6_gateway ~= "") and iface.state.ipv6_gateway or nil

  -- Check IPv4 route status
  local output = system_exec({"/sbin/ip", "route", "show", "default", "dev", device})
  local routes = {}
  if output and output ~= "" then
    for line in output:gmatch("[^\r\n]+") do
      local metric = tonumber(line:match("metric (%d+)")) or 0
      local via = line:match("via%s+(%S+)")
      table.insert(routes, { metric = metric, via = via })
    end
  end

  local ipv4_route_correct = (#routes == 1 and
                               routes[1].metric == target_metric and
                               routes[1].via == desired_gw)

  if not ipv4_route_correct then
    -- we can afford flush here, as there are backup routes are available
    -- (application won't start with less than 2 configured failover interfaces)
    system_intervention_argv({"/sbin/ip", "route", "flush", "default", "dev", device})
    local cmd = {"/sbin/ip", "route", "add", "default"}
    if desired_gw then
      table.insert(cmd, "via")
      table.insert(cmd, desired_gw)
    end
    table.insert(cmd, "dev")
    table.insert(cmd, device)
    table.insert(cmd, "metric")
    table.insert(cmd, tostring(target_metric))
    system_intervention_argv(cmd)
  end

  -- Set IPv6 route if IPv6 gateway exists (dual-stack)
  if ipv6_gw then
    local ipv6_routes = {}
    local ipv6_output = system_exec({"/sbin/ip", "-6", "route", "show", "default", "dev", device})
    if ipv6_output and ipv6_output ~= "" then
      for line in ipv6_output:gmatch("[^\r\n]+") do
        local metric = tonumber(line:match("metric (%d+)")) or 0
        local via = line:match("via%s+(%S+)")
        if via then
          table.insert(ipv6_routes, { metric = metric, via = via })
        end
      end
    end

    local ipv6_route_correct = (#ipv6_routes == 1 and
                                 ipv6_routes[1].metric == target_metric and
                                 ipv6_routes[1].via == ipv6_gw)

    if not ipv6_route_correct then
      -- Flush IPv6 default routes for this device
      system_intervention_argv({"/sbin/ip", "-6", "route", "flush", "default", "dev", device})
      local ipv6_cmd = {"/sbin/ip", "-6", "route", "add", "default", "via", ipv6_gw, "dev", device, "metric", tostring(target_metric)}
      system_intervention_argv(ipv6_cmd)
    end
  end
end

-- Load configuration from UCI (immutable)
local function load_config()
  local c = deps.uci_cursor()
  c:load("mini-mwan")

  local config = {
    enabled = c:get("mini-mwan", "settings", "enabled") == "1",
    mode = c:get("mini-mwan", "settings", "mode") or "failover",
    check_interval = tonumber(c:get("mini-mwan", "settings", "check_interval")) or 30,
    log_level = c:get("mini-mwan", "settings", "audit") or "emerg",
    interfaces = {}
  }

  -- Load all interface configurations (config only, no state)
  -- Section name is the device name (e.g., config interface 'eth0')
  c:foreach("mini-mwan", "interface", function(section)
    local iface_cfg = {
      device = section.device,
      metric = tonumber(section.metric) or 10,
      weight = tonumber(section.weight) or 3,
      ping_target = section.ping_target,
      ping_count = tonumber(section.ping_count) or 3,
      ping_timeout = tonumber(section.ping_timeout) or 2
    }

    table.insert(config.interfaces, iface_cfg)
  end)

  return config
end


local function save_interface_state(device, iface_state)
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

-- Probe state based on config (mutable, ephemeral)
-- Discovers gateways, computes routing class, logs transitions.
-- IPv4 gateway determines routing class; IPv6 gateway is added if available.
local function probe_state(config)
  local state = { interfaces = {} }

  local ipv4_gateway_map, ipv6_gateway_map = probe_all_gateways()

  for _, iface_cfg in ipairs(config.interfaces) do
    local saved = interface_state[iface_cfg.device] or {}

    local iface_state = {
      does_exist    = saved.does_exist or false,
      routing_class = saved.routing_class,   -- nil on first cycle
      alive         = saved.alive,
      status_since  = saved.status_since,
      latency       = saved.latency or "?",
      last_check    = saved.last_check,
      gateway       = ipv4_gateway_map[iface_cfg.device],  -- IPv4 gateway for routing class
      ipv6_gateway  = ipv6_gateway_map[iface_cfg.device],  -- IPv6 gateway for dual-stack
      point_to_point = detect_point_to_point(iface_cfg.device),
    }

    local old_class = iface_state.routing_class
    local new_class = compute_routing_class(iface_cfg, iface_state)

    log_state_transition(iface_cfg.device, old_class, new_class, iface_state)

    if old_class ~= new_class then
      iface_state.status_since = deps.time()
    end
    iface_state.routing_class = new_class

    save_interface_state(iface_cfg.device, iface_state)
    table.insert(state.interfaces, iface_state)
  end

  return state
end

-- Write view (presentation for LuCI/status display)
-- Merges config + state into a single view file (write and forget)
-- Update global status for ubus (replaces write_view)
local function update_status(config, state)
  -- Update global status object that will be served via ubus
  current_status.mode = config.mode
  current_status.timestamp = deps.time()
  current_status.check_interval = config.check_interval

  -- Build interfaces array
  current_status.interfaces = {}
  for i, iface_cfg in ipairs(config.interfaces) do
    local iface_state = state.interfaces[i]

    -- Get current network statistics
    local rx_bytes, tx_bytes = get_interface_stats(iface_cfg.device)

    -- Create interface status object
    table.insert(current_status.interfaces, {
      device        = iface_cfg.device or "",
      ping_target   = iface_cfg.ping_target or "",
      routing_class = iface_state.routing_class or "absent",
      status_since  = iface_state.status_since or "",
      last_check    = iface_state.last_check or "",
      latency       = iface_state.latency,
      gateway       = iface_state.gateway or "",
      ipv6_gateway  = iface_state.ipv6_gateway or "",
      rx_bytes      = tonumber(rx_bytes) or 0,
      tx_bytes      = tonumber(tx_bytes) or 0,
    })
  end
end

-- Remove or demote default routes for interfaces not managed by mini-mwan
-- Also cleans up duplicate routes for managed interfaces
local function cleanup_unmanaged_routes(config)
  -- Build list of managed devices
  local managed_devices = {}
  for _, iface in ipairs(config.interfaces) do
    if iface.device and iface.device ~= "" then
      managed_devices[iface.device] = true
    end
  end

  -- Get all current default routes (IPv4)
  local output = system_exec({"/sbin/ip", "route", "show", "default"})
  if not output or output == "" then
    output = ""
  end

  -- Parse each default route and handle unmanaged ones
  for line in output:gmatch("[^\r\n]+") do
    -- Extract device from route line
    -- Format: "default via X.X.X.X dev eth0 metric N" or "default dev eth0 metric N"
    local device = line:match("dev%s+(%S+)")

    if device and not managed_devices[device] then
      local via = line:match("via%s+(%S+)")
      if via then
        system_intervention_argv({"/sbin/ip", "route", "delete", "default", "via", via, "dev", device})
      else
        system_intervention_argv({"/sbin/ip", "route", "delete", "default", "dev", device})
      end
    end
  end

  -- Also clean up IPv6 default routes for unmanaged devices
  local ipv6_output = system_exec({"/sbin/ip", "-6", "route", "show", "default"})
  if ipv6_output and ipv6_output ~= "" then
    for line in ipv6_output:gmatch("[^\r\n]+") do
      local device = line:match("dev%s+(%S+)")
      if device and not managed_devices[device] then
        local via = line:match("via%s+(%S+)")
        if via then
          system_intervention_argv({"/sbin/ip", "-6", "route", "delete", "default", "via", via, "dev", device})
        else
          system_intervention_argv({"/sbin/ip", "-6", "route", "delete", "default", "dev", device})
        end
      end
    end
  end
end

-- Classify interfaces by routing_class.
-- Returns {usable = [...], probe_only = [...]}
-- absent / down / unconfigured interfaces are silently skipped (no route action).
local function classify_interfaces(config, state)
  local usable = {}
  local probe_only = {}

  for i, iface_cfg in ipairs(config.interfaces) do
    local iface_state = state.interfaces[i]
    local class = iface_state.routing_class
    if class == "usable" then
      table.insert(usable, { cfg = iface_cfg, state = iface_state })
    elseif class == "probe_only" then
      table.insert(probe_only, { cfg = iface_cfg, state = iface_state })
    end
  end

  return { usable = usable, probe_only = probe_only }
end

-- Give probe_only interfaces a metric-900 route so `ping -I <dev>` can detect recovery.
local function set_probe_routes(probe_only)
  for _, iface in ipairs(probe_only) do
    enforce_route_state(iface, 900)
  end
end

-- Failover mode logic
-- Receives only usable interfaces (already classified)
-- Sets routes with configured metrics - kernel handles priority automatically
local function set_routes_for_failover(usable_ifaces)
  for _, iface in ipairs(usable_ifaces) do
    enforce_route_state(iface, iface.cfg.metric)
  end
end

-- Multi-uplink mode logic with multipath routing
-- Receives only usable interfaces (already classified)
-- Creates multipath routes for both IPv4 and IPv6 with weighted load balancing
local function set_route_multiuplink(usable_ifaces)
  -- Check if any interfaces are available (for IPv4)
  if #usable_ifaces == 0 then
    log("No active WAN connections!", "warning")  -- warning
    return
  end

  -- Set IPv4 multipath route
  local cmd_args = { "/sbin/ip", "route", "replace", "default" }

  for _, iface in ipairs(usable_ifaces) do
    -- Add the nexthop keyword for every interface
    table.insert(cmd_args, "nexthop")

    -- Conditionally add the IPv4 gateway
    if iface.state.gateway and iface.state.gateway ~= "" then
      table.insert(cmd_args, "via")
      table.insert(cmd_args, iface.state.gateway)
    end

    -- Add device and weight
    table.insert(cmd_args, "dev")
    table.insert(cmd_args, iface.cfg.device)
    table.insert(cmd_args, "weight")
    table.insert(cmd_args, tostring(iface.cfg.weight))
  end

  -- Now cmd_args is a flat table: {"/sbin/ip", "route", "replace", "default", "nexthop", "via", ...}
  system_intervention_argv(cmd_args)

  -- Set IPv6 multipath route if any interface has IPv6 gateway
  local ipv6_gateway_count = 0
  for _, iface in ipairs(usable_ifaces) do
    if iface.state.ipv6_gateway and iface.state.ipv6_gateway ~= "" then
      ipv6_gateway_count = ipv6_gateway_count + 1
    end
  end

  if ipv6_gateway_count > 0 then
    local ipv6_cmd = { "/sbin/ip", "-6", "route", "replace", "default" }

    for _, iface in ipairs(usable_ifaces) do
      -- Add the nexthop keyword for every interface
      table.insert(ipv6_cmd, "nexthop")

      -- Conditionally add the IPv6 gateway
      if iface.state.ipv6_gateway and iface.state.ipv6_gateway ~= "" then
        table.insert(ipv6_cmd, "via")
        table.insert(ipv6_cmd, iface.state.ipv6_gateway)
      end

      -- Add device and weight
      table.insert(ipv6_cmd, "dev")
      table.insert(ipv6_cmd, iface.cfg.device)
      table.insert(ipv6_cmd, "weight")
      table.insert(ipv6_cmd, tostring(iface.cfg.weight))
    end

    system_intervention_argv(ipv6_cmd)
  end
end

local function count_wans_configured(config)
  local configured_count = 0
  for _, iface in ipairs(config.interfaces or {}) do
    if iface and iface.device and iface.device ~= "" then
      configured_count = configured_count + 1
    end
  end
  return configured_count
end

local function work(config)
  local state = probe_state(config)

  cleanup_unmanaged_routes(config)

  local classified = classify_interfaces(config, state)

  set_probe_routes(classified.probe_only)

  if config.mode == "failover" then
    set_routes_for_failover(classified.usable)
  elseif config.mode == "multiuplink" then
    set_route_multiuplink(classified.usable)
  end

  update_status(config, state)
end

-- Work timer callback (replaces while loop)
local work_timer
local function work_cycle()
  -- Load immutable config from UCI
  local config = load_config()

  -- Update log level filter after config reload
  nixio.setlogmask(config.log_level)

  if config.enabled then
    if count_wans_configured(config) >= 2 then
      work(config)
    else
      log("Both WAN interfaces must be configured. Refusing to work!", "err")  -- err
    end
  end

  -- Reschedule timer with current check_interval
  work_timer:set(config.check_interval * 1000)  -- milliseconds
end

-- ubus method handlers
local ubus_methods = {
  ["mini-mwan"] = {
    status = {
      function(req, msg)
        -- Return current status as JSON
        deps.ubus_conn:reply(req, current_status)
      end,
      {}  -- No parameters required
    }
  }
}

-- Register ubus methods
local function register_ubus()
  -- Connect to ubus
  deps.ubus_conn = deps.ubus_connect()
  if not deps.ubus_conn then
    log("Failed to connect to ubus", "err")
    return false
  end

  -- Register ubus methods
  deps.ubus_conn:add(ubus_methods)
  log("Registered ubus object: mini-mwan", "notice")
  return true
end

-- Run work cycle in uloop event loop
local function run_event_loop()
  -- Initialize uloop event loop
  deps.uloop_init()

  -- Create work timer
  work_timer = deps.uloop_timer(work_cycle)

  -- Start first work cycle immediately
  work_timer:set(100)  -- 100ms delay for initial run

  -- Run event loop
  deps.uloop_run()

  -- Cleanup on exit
  if deps.ubus_conn then
    deps.ubus_conn:close()
  end
end

-- Main daemon entry point
local function main()
  -- Initialize syslog
  nixio.openlog("mini-mwan")

  log("Mini-MWAN daemon starting", "notice")  -- notice

  -- Register ubus interface
  if not register_ubus() then
    return
  end

  -- Run event loop
  run_event_loop()
end

-- Export functions for testing
if os.getenv("MINI_MWAN_TEST_MODE") then
  return {
    -- in Java, we call it package-private
    -- but here in lua, we export methods for testing
    set_dependencies = set_dependencies,
    probe_all_gateways = probe_all_gateways,
    detect_point_to_point = detect_point_to_point,
    compute_routing_class = compute_routing_class,
    enforce_route_state = enforce_route_state,
    check_ping = check_ping,
    check_interface_is_up = check_interface_is_up,
    set_routes_for_failover = set_routes_for_failover,
    set_route_multiuplink = set_route_multiuplink,
    load_config = load_config,
    probe_state = probe_state,
    classify_interfaces = classify_interfaces,
    set_probe_routes = set_probe_routes,
    work = work,
    log = log,
    register_ubus = register_ubus,
    count_wans_configured = count_wans_configured
  }
else
  -- Normal operation - run daemon
  main()
end
