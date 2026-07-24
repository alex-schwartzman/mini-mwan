--[[
Integration Tests for Multiuplink Mode

Requirement: FR-2.2 - Multiuplink Mode
Priority: High
Description: System SHALL provide multiuplink mode where traffic is load-balanced
             across all operational interfaces
]]

local mocks = require("spec.helpers.mocks")

describe("FR-2.2: Multiuplink Mode - End to End", function()
  local mini_mwan

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")
  end)

  describe("Scenario: All interfaces UP", function()
    it("should create multipath route with all interfaces and configured weights", function()
      -- GIVEN: Two interfaces configured in multiuplink mode, both UP
      local config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          {
            device = "eth0",
            metric = 10,
            weight = 3,
            ping_target = "1.1.1.1",
            ping_count = 3,
            ping_timeout = 2,
            enabled = true,
          },
          {
            device = "eth1",
            metric = 20,
            weight = 5,
            ping_target = "8.8.8.8",
            ping_count = 3,
            ping_timeout = 2,
            enabled = true,
          }
        }
      }

      local exec_responses = {
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.2),
        -- Both interfaces UP
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",

        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",

        -- Route cleanup
        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        -- ubus returns both interfaces with gateways
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle in multiuplink mode
      mini_mwan.work(config)

      -- THEN: Should create multipath route with both interfaces
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 3 },
        { gateway = "192.168.2.1", device = "eth1", weight = 5 }
      })
    end)

    it("should handle three interfaces with different weights", function()
      -- GIVEN: Three interfaces in multiuplink mode
      local config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, weight = 2, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth1", metric = 20, weight = 3, ping_target = "8.8.8.8", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth2", metric = 30, weight = 5, ping_target = "1.0.0.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ping.*eth1"] = mocks.mock_ping_success(12.0),
        ["ping.*eth2"] = mocks.mock_ping_success(8.0),
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",
        ["ip addr show dev eth2"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth2"] = "",
        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" },
          { l3_device = "eth2", gateway = "192.168.3.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Should create multipath route with all three interfaces
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 2 },
        { gateway = "192.168.2.1", device = "eth1", weight = 3 },
        { gateway = "192.168.3.1", device = "eth2", weight = 5 }
      })
    end)
  end)

  describe("Scenario: One interface up but loses packets (unusable)", function()
    it("should create multipath route with only those UP interfaces which pass pings", function()
      -- GIVEN: Two interfaces, one UP, one DOWN
      local config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          {
            device = "eth0",
            metric = 10,
            weight = 3,
            ping_target = "1.1.1.1",
            ping_count = 3,
            ping_timeout = 2,
            enabled = true,
          },
          {
            device = "eth1",
            metric = 20,
            weight = 5,
            ping_target = "8.8.8.8",
            ping_count = 3,
            ping_timeout = 2,
            enabled = true,
          }
        }
      }

      local exec_responses = {
        -- eth0 is UP
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),

        -- eth1 is UP but NOT pingable (connection lost)
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",
        ["ping.*eth1"] = mocks.mock_ping_failure(),

        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Multipath route should only include eth0 (the UP interface)
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 3 }
      })

      -- AND: DOWN interface should have metric 900 route (for ping tests)
      local route_cmds = mocks.get_route_commands()
      local found_metric_900 = false
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("eth1") and cmd:match("metric 900") then
          found_metric_900 = true
          break
        end
      end
      assert.is_true(found_metric_900, "UP but unusable interface should have metric 900 route")
    end)
  end)

  describe("Scenario: All interfaces DOWN", function()
    it("should not create multipath route, only metric 900 routes", function()
      -- GIVEN: Two interfaces, both DOWN
      local config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, weight = 3, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth1", metric = 20, weight = 5, ping_target = "8.8.8.8", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
        -- Both interfaces UP but NOT pingable
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",

        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",

        ["ip route show default"] = "",
        ["ping.*eth0"] = mocks.mock_ping_failure(),
        ["ping.*eth1"] = mocks.mock_ping_failure(),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Should NOT create multipath route
      local route_cmds = mocks.get_route_commands()
      local found_multipath = false
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("^ip route replace default nexthop") then
          found_multipath = true
          break
        end
      end
      assert.is_false(found_multipath, "Should not create multipath route when all interfaces are down")

      -- AND: Both interfaces should have metric 900 routes
      local eth0_has_900 = false
      local eth1_has_900 = false
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("eth0") and cmd:match("metric 900") then
          eth0_has_900 = true
        end
        if cmd:match("eth1") and cmd:match("metric 900") then
          eth1_has_900 = true
        end
      end
      assert.is_true(eth0_has_900, "eth0 should have metric 900 route")
      assert.is_true(eth1_has_900, "eth1 should have metric 900 route")
    end)
  end)

  describe("Scenario: P2P interface in multiuplink", function()
    it("should include P2P interface in multipath route without gateway", function()
      -- GIVEN: Regular interface and P2P interface (VPN)
      local config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, weight = 3, ping_target = "1.1.1.1",  ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "wg0",  metric = 20, weight = 5, ping_target = "10.0.0.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
        -- eth0 is regular interface
        ["ip addr show dev eth0"]     = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip link show dev eth0"] = "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>",
        ["ping.*eth0"]                = mocks.mock_ping_success(10.0),
        -- wg0 is P2P interface
        ["ip addr show dev wg0"]      = mocks.mock_interface_up(),
        ["ip %-6 addr show dev wg0"]  = "",
        ["ip link show dev wg0"]      = "12: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP>",
        ["ping.*wg0"]  = mocks.mock_ping_success(50.0),

        ["ip route show default"]     = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        -- eth0 has gateway, wg0 doesn't (P2P)
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "wg0",  gateway = nil }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Multipath route should include both (eth0 with gateway, wg0 without)
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 3 },
        { device = "wg0",          weight = 5 } -- P2P without gateway
      })
    end)
  end)

  describe("Scenario: Degraded interface in multiuplink", function()
    it("should skip degraded interface (no gateway) in multipath route", function()
      -- GIVEN: eth0 healthy, eth1 degraded (no gateway)
      local config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, weight = 3, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth1", metric = 20, weight = 5, ping_target = "8.8.8.8", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
        -- Both are shared medium (not P2P)
        ["ip link show dev eth0"] = "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>",
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),

        ["ip link show dev eth1"] = "4: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP>",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),

        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        -- eth0 has gateway, eth1 doesn't (degraded - DHCP incomplete)
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = nil }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Only eth0 should be in multipath route (eth1 is degraded)
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 3 }
      })

      -- AND: eth1 should NOT have any routes (degraded interfaces are skipped)
      local route_cmds = mocks.get_route_commands()
      local eth1_routes = 0
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("eth1") and not cmd:match("delete") then
          eth1_routes = eth1_routes + 1
        end
      end
      assert.equals(0, eth1_routes, "Degraded interface should not have routes")
    end)
  end)

  describe("Scenario: Interface recovery in multiuplink", function()
    it("should add recovered interface to multipath route", function()
      -- This test simulates two work cycles:
      -- Cycle 1: eth1 is down
      -- Cycle 2: eth1 recovers

      local config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, weight = 3, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth1", metric = 20, weight = 5, ping_target = "8.8.8.8", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      -- CYCLE 1: eth1 is down
      local exec_responses_cycle1 = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",
        ["ip route show default"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ping.*eth1"] = mocks.mock_ping_failure(), -- DOWN
      }

      local exec_mock = mocks.build_exec_mock(exec_responses_cycle1)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- First work cycle
      mini_mwan.work(config)

      -- Verify only eth0 in multipath
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 3 }
      })

      -- CYCLE 2: eth1 recovers
      mocks.reset()

      local exec_responses_cycle2 = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",
        ["ip route show default"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ping.*eth1"] = mocks.mock_ping_success(15.0), -- Now UP
      }

      exec_mock = mocks.build_exec_mock(exec_responses_cycle2)
      deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- Second work cycle
      mini_mwan.work(config)

      -- Verify both interfaces now in multipath
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 3 },
        { gateway = "192.168.2.1", device = "eth1", weight = 5 }
      })
    end)
  end)

  describe("Scenario: IPv6 multipath with mixed IPv6 gateway availability", function()
    it("should only include interfaces with IPv6 gateway in IPv6 multipath route", function()
      -- GIVEN: Three interfaces with different IPv6 capabilities
      -- eth0: both IPv4 and IPv6 gateway
      -- eth1: IPv4 gateway only (no IPv6)
      -- wg0: IPv4 gateway only (P2P, no IPv6)
      local config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, weight = 3, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth1", metric = 20, weight = 5, ping_target = "8.8.8.8", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "wg0",  metric = 30, weight = 2, ping_target = "10.0.0.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
        -- All interfaces UP
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip addr show dev wg0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip %-6 addr show dev eth1"] = "",
        ["ip %-6 addr show dev wg0"] = "",
        -- All ping successful
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.0),
        ["ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.0),
        ["ping.*wg0"] = mocks.mock_ping_success(50.0),
        -- No existing routes
        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        -- eth0 has both IPv4 and IPv6, others don't
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1", ipv6_gateway = "2001:db8::1" },
          { l3_device = "eth1", gateway = "192.168.2.1" },
          { l3_device = "wg0",  gateway = "10.0.0.254" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: IPv4 multipath route should include all three interfaces
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 3 },
        { gateway = "192.168.2.1", device = "eth1", weight = 5 },
        { gateway = "10.0.0.254", device = "wg0", weight = 2 }
      })

      -- AND: IPv6 multipath route should only include eth0 (has IPv6 gateway)
      local ipv6_cmd_found = false
      local ipv6_cmd = ""
      for _, cmd in ipairs(mocks.executed_commands) do
        if cmd:match("/sbin/ip %-6 route replace default") then
          ipv6_cmd_found = true
          ipv6_cmd = cmd
          break
        end
      end
      assert.is_true(ipv6_cmd_found, "IPv6 multipath route should be created")

      -- Verify eth0 with IPv6 gateway is present
      assert.is_true(ipv6_cmd:match("nexthop via 2001:db8::1 dev eth0 weight 3") ~= nil,
        "IPv6 route should include eth0 with IPv6 gateway")
      -- Verify eth1 is NOT in IPv6 route (no IPv6 gateway)
      assert.is_true(ipv6_cmd:match("eth1") == nil,
        "IPv6 route should not include eth1 (no IPv6 gateway)")
      -- Verify wg0 is NOT in IPv6 route (no IPv6 gateway)
      assert.is_true(ipv6_cmd:match("wg0") == nil,
        "IPv6 route should not include wg0 (no IPv6 gateway)")
    end)
  end)

  describe("Scenario: 16 interfaces (scalability test)", function()
    it("should handle 16 interfaces in multipath route", function()
      -- GIVEN: 16 interfaces configured in multiuplink mode
      local config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          -- 16 interfaces with different metrics and weights
          { device = "eth0",  metric = 10, weight = 3,  ping_target = "1.1.1.1",  ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth1",  metric = 20, weight = 3,  ping_target = "8.8.8.8",  ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth2",  metric = 30, weight = 3,  ping_target = "9.9.9.9",  ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth3",  metric = 40, weight = 3,  ping_target = "208.67.222.222", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth4",  metric = 50, weight = 3,  ping_target = "1.0.0.1",  ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth5",  metric = 60, weight = 3,  ping_target = "8.8.4.4",  ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth6",  metric = 70, weight = 3,  ping_target = "192.168.1.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth7",  metric = 80, weight = 3,  ping_target = "192.168.2.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth8",  metric = 90, weight = 3,  ping_target = "192.168.3.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth9",  metric = 100, weight = 3, ping_target = "192.168.4.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth10", metric = 110, weight = 3, ping_target = "192.168.5.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth11", metric = 120, weight = 3, ping_target = "192.168.6.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth12", metric = 130, weight = 3, ping_target = "192.168.7.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth13", metric = 140, weight = 3, ping_target = "192.168.8.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth14", metric = 150, weight = 3, ping_target = "192.168.9.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth15", metric = 160, weight = 3, ping_target = "192.168.10.1", ping_count = 3, ping_timeout = 2, enabled = true },
        }
      }

      -- Build exec responses for all 16 interfaces
      local exec_responses = {
        ["ip route show default"] = "",
      }
      for i = 0, 15 do
        local eth = "eth" .. i
        local ping_target = config.interfaces[i + 1].ping_target
        exec_responses["ip addr show dev " .. eth] = mocks.mock_interface_up()
        exec_responses["ip %-6 addr show dev " .. eth] = ""
        -- Escape dots for regex pattern matching (e.g., "1.1.1.1" -> "1%.1%.1%.1")
        local escaped_target = ping_target:gsub("%.", "%%.")
        exec_responses["ping.*" .. eth .. ".*" .. escaped_target] = mocks.mock_ping_success(10.0)
      end

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local ubus_interfaces = {}
      for i = 0, 15 do
        table.insert(ubus_interfaces, {
          l3_device = "eth" .. i,
          gateway = "192.168." .. (i % 256) .. ".1"
        })
      end

      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump(ubus_interfaces)
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Should create multipath route with all 16 interfaces
      -- Build expected multipath route with all 16 interfaces
      local expected_nexthops = {}
      for i = 0, 15 do
        table.insert(expected_nexthops, {
          gateway = "192.168." .. (i % 256) .. ".1",
          device = "eth" .. i,
          weight = 3
        })
      end
      mocks.assert_multipath_route(expected_nexthops)
    end)
  end)
end)
