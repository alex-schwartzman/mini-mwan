--[[
Mock Helpers for Mini-MWAN Tests

This module provides reusable mocks for testing mini-mwan functionality.
]]

local M = {}

-- Command history tracking
M.executed_commands = {}

-- Log history tracking
M.logged_messages = {}

-- Reset all mocks to initial state
function M.reset()
  M.executed_commands = {}
  M.logged_messages = {}
end

-- Track executed command
function M.track_command(cmd)
  table.insert(M.executed_commands, cmd)
end

-- Find commands matching pattern
function M.find_commands(pattern)
  local matches = {}
  for _, cmd in ipairs(M.executed_commands) do
    if cmd:match(pattern) then
      table.insert(matches, cmd)
    end
  end
  return matches
end

-- Check if command was executed
function M.was_executed(pattern)
  return #M.find_commands(pattern) > 0
end

-- Get route commands only
function M.get_route_commands()
  return M.find_commands("ip route")
end

-- Mock exec function builder (argv-style, no shell)
function M.build_exec_mock(responses)
  --[[
  Build exec mock that returns different responses based on command pattern

  Usage:
    local mock = M.build_exec_mock({
      ["ping.*eth0"] = "3 packets transmitted, 3 received",
    })
  ]]
  return function(args)
    local cmd = table.concat(args, " ")
    M.track_command(cmd)
    for pattern, response in pairs(responses) do
      if cmd:match(pattern) then
        return response
      end
    end
    return ""
  end
end

-- Mock successful ping response
function M.mock_ping_success(latency)
  latency = latency or 12.5
  local min_latency = latency - 1
  local max_latency = latency + 1
  return string.format([[
PING 1.1.1.1 (1.1.1.1): 56 data bytes
64 bytes from 1.1.1.1: seq=0 ttl=57 time=%.3f ms
64 bytes from 1.1.1.1: seq=1 ttl=57 time=%.3f ms
64 bytes from 1.1.1.1: seq=2 ttl=57 time=%.3f ms

--- 1.1.1.1 ping statistics ---
3 packets transmitted, 3 packets received, 0%% packet loss
round-trip min/avg/max = %.3f/%.3f/%.3f ms
]], min_latency, latency, max_latency, min_latency, latency, max_latency)
end

-- Mock failed ping response
function M.mock_ping_failure()
  return [[
PING 1.1.1.1 (1.1.1.1): 56(84) bytes of data.
--- 1.1.1.1 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss, time 2003ms
]]
end

-- Mock failed ping response
function M.ip_route_show_eth0_default()
  return [[
default via 192.168.68.1 dev eth0 proto static src 192.168.68.158 metric 1
default via 192.168.10.1 dev eth1 proto static src 192.168.10.4 metric 900
]]
end

-- Mock ubus network.interface dump with multiple interfaces
-- Returns Lua table (as libubus would), not JSON string
function M.mock_ubus_network_dump(interfaces)
  --[[
  Build ubus network.interface dump response with multiple interfaces

  Usage:
    local mock = M.mock_ubus_network_dump({
      { l3_device = "eth0", gateway = "192.168.1.1" },
      { l3_device = "eth1", gateway = "192.168.2.1" },
      { l3_device = "wg0", gateway = nil },  -- P2P interface
    })
  ]]
  local interface_list = {}
  for _, iface in ipairs(interfaces) do
    local routes = {}
    if iface.gateway then
      table.insert(routes, {
        target = "0.0.0.0",
        mask = 0,
        nexthop = iface.gateway
      })
    end

    table.insert(interface_list, {
      l3_device = iface.l3_device,
      route = routes
    })
  end

  -- Return Lua table directly (as libubus conn:call() would)
  return { interface = interface_list }
end

-- Mock interface UP state
function M.mock_interface_up()
  return "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP"
end

-- Mock interface DOWN state
function M.mock_interface_down()
  return "3: eth0: <BROADCAST,MULTICAST> mtu 1500 qdisc fq_codel state DOWN"
end

-- Mock UCI cursor
function M.mock_uci_cursor(config_data)
  --[[
  Build UCI cursor mock with predefined config

  Usage:
    local cursor = M.mock_uci_cursor({
      settings = {
        enabled = "1",
        mode = "failover",
        check_interval = "30"
      },
      interfaces = {
        wan1 = { device = "eth0", metric = "1", ... },
        wan2 = { device = "eth1", metric = "2", ... }
      }
    })
  ]]
  return {
    load = function(self, name) end,
    get = function(self, config, section, option)
      if config_data[section] then
        return config_data[section][option]
      end
    end,
    foreach = function(self, config, type, callback)
      if type == "interface" and config_data.interfaces then
        for name, data in pairs(config_data.interfaces) do
          local section = {}
          for k, v in pairs(data) do
            section[k] = v
          end
          section['.name'] = name
          callback(section)
        end
      end
    end
  }
end

-- Mock file I/O
function M.mock_file_io()
  local files = {}

  return {
    open = function(path, mode)
      if not files[path] then
        files[path] = {
          content = "",
          closed = false
        }
      end

      local file = files[path]

      return {
        write = function(self, data)
          file.content = file.content .. data
        end,
        read = function(self, format)
          return file.content
        end,
        close = function(self)
          file.closed = true
        end
      }
    end,
    get_content = function(path)
      return files[path] and files[path].content or nil
    end
  }
end

-- Mock file reading (for sysfs stats, etc)
function M.build_file_mock(file_contents)
  --[[
  Build file mock that returns different content based on file path

  Usage:
    local file_mock = M.build_file_mock({
      ["/sys/class/net/eth0/statistics/rx_bytes"] = "1234567",
      ["/sys/class/net/eth0/statistics/tx_bytes"] = "7654321",
    })
  ]]
  return function(path, mode)
    if file_contents[path] then
      return {
        read = function(self, format)
          return file_contents[path]
        end,
        close = function(self) end
      }
    end
    -- Return nil for files not in the mock
    return nil
  end
end

-- Mock logging function
function M.mock_log()
  --[[
  Build log mock that:
  1. Saves ALL logs regardless of level
  2. Records each log with its priority level
  3. Tests can verify correct priority levels were used

  Usage:
    local log_mock = M.mock_log()
    deps.log = log_mock.log
    -- ... run tests ...
    local all_messages = log_mock.get_messages()
    local debug_msgs = log_mock.get_messages_by_priority("debug")
    -- Verify no debug messages when log level is "err"
    assert.equals(0, #debug_msgs)
  ]]
  local LOG_FILE = "/var/log/mini-mwan.log"
  local log_file_content = ""

  return {
    log = function(msg, priority)
      priority = priority or "info"

      -- Track ALL messages with their priority
      local entry = {
        message = msg,
        priority = priority,
        timestamp = os.date("%Y-%m-%d %H:%M:%S")
      }
      table.insert(M.logged_messages, entry)

      -- Also write to mock log file (for test visibility)
      local log_line = string.format("[%s] [%s] %s\n", entry.timestamp, priority, msg)
      log_file_content = log_file_content .. log_line
    end,
    get_messages = function()
      return M.logged_messages
    end,
    get_messages_by_priority = function(priority)
      local filtered = {}
      for _, entry in ipairs(M.logged_messages) do
        if entry.priority == priority then
          table.insert(filtered, entry)
        end
      end
      return filtered
    end,
    get_log_file_content = function()
      return log_file_content
    end,
    reset = function()
      M.logged_messages = {}
      log_file_content = ""
    end
  }
end

-- Mock ubus connection
function M.mock_ubus()
  local registered_objects = {}
  local last_reply = nil
  local conn_instance

  -- Storage for ubus call responses (for mocking network.interface dump, etc)
  local ubus_call_responses = {}

  conn_instance = {
    add = function(self, methods)
      -- Store registered methods for verification
      for object_name, object_methods in pairs(methods) do
        registered_objects[object_name] = object_methods
      end
    end,
    reply = function(self, req, data)
      -- Store the last reply for verification
      last_reply = data
    end,
    call = function(self, namespace, method, args)
      -- Mock ubus calls (e.g., network.interface dump)
      local key = namespace .. "." .. method
      if ubus_call_responses[key] then
        return ubus_call_responses[key]
      end
      -- Return nil if not mocked
      return nil
    end,
    close = function(self)
      -- No-op
    end,
    -- Test helper: set response for ubus call
    set_call_response = function(namespace, method, response)
      local key = namespace .. "." .. method
      ubus_call_responses[key] = response
    end
  }

  return {
    -- This is what deps.ubus_connect() will call
    connect = function()
      return conn_instance
    end,
    -- Test helper: call a registered ubus method and return what it replied
    call_method = function(object, method, msg)
      msg = msg or {}
      if registered_objects[object] and registered_objects[object][method] then
        local handler = registered_objects[object][method][1]
        local mock_req = {}
        -- Call the handler - it will call conn_instance:reply()
        handler(mock_req, msg)
        return last_reply
      end
      return nil
    end,
    -- Test helper: get what was registered
    get_registered_objects = function()
      return registered_objects
    end,
    -- Test helper: reset state
    reset = function()
      registered_objects = {}
      last_reply = nil
    end
  }
end

-- Build complete dependency mock
function M.build_deps(overrides)
  --[[
  Build complete dependency object with optional overrides

  Usage:
    local deps, ubus_mock, log_mock = M.build_deps({
      exec = custom_exec_function,
      time = function() return 1234567890 end,
      ubus_network_dump = mocks.mock_ubus_network_dump({...})  -- optional
    })

  Returns: deps table, ubus_mock object, log_mock object
  ]]
  overrides = overrides or {}

  -- Default ubus mock
  local ubus_mock = overrides.ubus_mock or M.mock_ubus()

  -- If ubus_network_dump response is provided, configure it in the mock
  if overrides.ubus_network_dump then
    local conn = ubus_mock.connect()
    conn.set_call_response("network.interface", "dump", overrides.ubus_network_dump)
  end

  -- Default log mock
  local log_mock = overrides.log_mock or M.mock_log()

  local deps = {
    log = overrides.log or log_mock.log,
    sleep = overrides.sleep or function(seconds) end,
    time = overrides.time or function() return 1698765432 end,
    open_file = overrides.open_file or M.mock_file_io().open,
    uci_cursor = overrides.uci_cursor or function()
      return M.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "30", audit = "err" },
        interfaces = {}
      })
    end,
    exec = overrides.exec or M.build_exec_mock({}),
    ubus_connect = overrides.ubus_connect or function()
      return ubus_mock.connect()
    end,
    uloop_init = overrides.uloop_init or function() end,
    uloop_timer = overrides.uloop_timer or function(callback)
      -- Return mock timer object
      return {
        set = function(self, ms) end
      }
    end,
    uloop_run = overrides.uloop_run or function() end
  }

  return deps, ubus_mock, log_mock
end

-- Assertion helpers
function M.assert_route_set(gateway, device, metric)
  --[[
  Assert that a route was set with specific parameters
  ]]
  local pattern = string.format("/sbin/ip route replace default via %s dev %s metric %d",
    gateway, device, metric)
  local found = false
  for _, cmd in ipairs(M.executed_commands) do
    if cmd == pattern then
      found = true
      break
    end
  end

  if not found then
    error(string.format("Expected route not found: %s\nExecuted commands:\n%s",
      pattern, table.concat(M.executed_commands, "\n")))
  end
end

function M.assert_p2p_route_set(device, metric)
  --[[
  Assert that a P2P route (without gateway) was set
  ]]
  local pattern = string.format("/sbin/ip route replace default dev %s metric %d",
    device, metric)
  local found = false
  for _, cmd in ipairs(M.executed_commands) do
    if cmd == pattern then
      found = true
      break
    end
  end

  if not found then
    error(string.format("Expected P2P route not found: %s", pattern))
  end
end

function M.assert_route_deleted(gateway, device)
  --[[
  Assert that a route was deleted
  ]]
  local pattern = string.format("ip route delete default via %s dev %s",
    gateway, device)
  local found = false
  for _, cmd in ipairs(M.executed_commands) do
    if cmd:match(pattern) then
      found = true
      break
    end
  end

  if not found then
    error(string.format("Expected route delete not found: %s", pattern))
  end
end

function M.assert_multipath_route(expected_nexthops)
  --[[
  Assert that a multipath route was created with expected nexthops

  Usage:
    M.assert_multipath_route({
      { gateway = "192.168.1.1", device = "eth0", weight = 3 },
      { device = "wg0", weight = 5 }  -- P2P without gateway
    })
  ]]
  -- Find the multipath route command
  local multipath_cmd = nil
  for _, cmd in ipairs(M.executed_commands) do
    if cmd:match("/sbin/ip route replace default nexthop") then
      multipath_cmd = cmd
      break
    end
  end

  if not multipath_cmd then
    error("No multipath route command found in executed commands")
  end

  -- Verify each expected nexthop is in the command
  for _, nexthop in ipairs(expected_nexthops) do
    local pattern
    if nexthop.gateway then
      pattern = string.format("nexthop via %s dev %s weight %d",
        nexthop.gateway, nexthop.device, nexthop.weight)
    else
      pattern = string.format("nexthop dev %s weight %d",
        nexthop.device, nexthop.weight)
    end

    if not multipath_cmd:match(pattern:gsub("%-", "%%-")) then
      error(string.format("Expected nexthop not found in multipath route:\nExpected: %s\nActual command: %s",
        pattern, multipath_cmd))
    end
  end
end

return M
