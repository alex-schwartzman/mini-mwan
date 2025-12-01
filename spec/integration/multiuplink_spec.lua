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
        -- Both interfaces UP and pingable
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ip %-6 addr show dev eth0"] = "",

        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.2),
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
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_success(12.0),
        ["ip %-6 addr show dev eth1"] = "",
        ["ip addr show dev eth2"] = mocks.mock_interface_up(),
        ["ping.*eth2"] = mocks.mock_ping_success(8.0),
        ["ip %-6 addr show dev eth2"] = "",
        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({ exec = exec_mock,
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

  describe("Scenario: One interface DOWN", function()
    it("should create multipath route with only UP interfaces", function()
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
        -- eth0 is UP and pingable
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ip %-6 addr show dev eth0"] = "",

        -- eth1 is UP but NOT pingable (connection lost)
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_failure(),
        ["ip %-6 addr show dev eth1"] = "",

        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({ exec = exec_mock,
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
      assert.is_true(found_metric_900, "DOWN interface should have metric 900 route")
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
        ["ping.*eth0"] = mocks.mock_ping_failure(),
        ["ip %-6 addr show dev eth0"] = "",

        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_failure(),
        ["ip %-6 addr show dev eth1"] = "",

        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({ exec = exec_mock,
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
          { device = "eth0", metric = 10, weight = 3, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "wg0", metric = 20, weight = 5, ping_target = "10.0.0.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
        -- eth0 is regular interface
        ["ip link show dev eth0"] = "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>",
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ip %-6 addr show dev eth0"] = "",

        -- wg0 is P2P interface
        ["ip link show dev wg0"] = "12: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP>",
        ["ip addr show dev wg0"] = mocks.mock_interface_up(),
        ["ping.*wg0"] = mocks.mock_ping_success(50.0),
        ["ip %-6 addr show dev wg0"] = "",

        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({ exec = exec_mock,
        -- eth0 has gateway, wg0 doesn't (P2P)
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "wg0", gateway = nil }
          })
        })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Multipath route should include both (eth0 with gateway, wg0 without)
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 3 },
        { device = "wg0", weight = 5 }  -- P2P without gateway
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
        ["ip link show dev eth1"] = "4: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP>",

        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ip %-6 addr show dev eth0"] = "",

        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),
        ["ip %-6 addr show dev eth1"] = "",

        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({ exec = exec_mock,
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
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_failure(),  -- DOWN
        ["ip %-6 addr show dev eth1"] = "",
        ["ip route show default"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses_cycle1)
      local deps = mocks.build_deps({ exec = exec_mock,
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
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),  -- Now UP
        ["ip %-6 addr show dev eth1"] = "",
        ["ip route show default"] = "",
      }

      exec_mock = mocks.build_exec_mock(exec_responses_cycle2)
      deps = mocks.build_deps({ exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
          }) })
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
end)
