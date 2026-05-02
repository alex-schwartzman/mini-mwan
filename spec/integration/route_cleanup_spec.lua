--[[
Integration Tests for Route Cleanup

Requirement: FR-2.4 - Route Cleanup
Priority: Medium
Description: System SHALL manage the routing table to prevent conflicts and clean up duplicate routes
]]

local mocks = require("spec.helpers.mocks")

describe("FR-2.4: Route Cleanup - Duplicate Route Handling", function()
  local mini_mwan
  local default_config

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")

    -- Default config (immutable, from UCI)
    default_config = {
      mode = "failover",
      check_interval = 30,
      interfaces = {
        {
          device = "eth0",
          metric = 10,
          ping_target = "1.1.1.1",
          ping_count = 3,
          ping_timeout = 2,
          enabled = true,
        }
      }
    }
  end)

  describe("Scenario: External tool created duplicate routes", function()
    it("should flush and re-add correct route when duplicates exist", function()
      -- GIVEN: Multiple duplicate routes for eth0 with different metrics
      -- Simulate external tool (like surfshark) creating multiple routes
      local exec_responses = {
        -- Interface is UP and pingable
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        -- ip route show returns multiple routes
        ["ip route show default dev eth0"] = [[
default via 192.168.1.1 dev eth0 metric 10
default dev eth0 scope link metric 21
default dev eth0 scope link metric 22
default dev eth0 scope link metric 23
]],
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Stale routes removed via flush, correct route re-added
      mocks.assert_route_set("192.168.1.1", "eth0", 10)

      local route_cmds = mocks.get_route_commands()
      local was_flushed = false
      local no_individual_deletes = true
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route flush default dev eth0") then
          was_flushed = true
        end
        if cmd:match("ip route delete") then
          no_individual_deletes = false
        end
      end

      assert.is_true(was_flushed, "Should flush routes when duplicates exist")
      assert.is_true(no_individual_deletes, "Should use flush rather than individual deletes")
    end)

    it("should flush and re-add when a route without explicit metric exists", function()
      -- GIVEN: Correct route plus a no-metric stale route
      local exec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ip route show default dev eth0"] = [[
default via 192.168.1.1 dev eth0 metric 10
default dev eth0 scope link
]],
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Routes flushed and correct one re-added
      mocks.assert_route_set("192.168.1.1", "eth0", 10)

      local route_cmds = mocks.get_route_commands()
      local was_flushed = false
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route flush default dev eth0") then
          was_flushed = true
        end
      end
      assert.is_true(was_flushed, "Should flush when stale no-metric route exists")
    end)

    it("should flush and re-add when multiple routes share the same gateway", function()
      -- GIVEN: Multiple routes for the same gateway at different metrics
      local exec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ip route show default dev eth0"] = [[
default via 192.168.1.1 dev eth0 metric 10
default via 192.168.1.1 dev eth0 metric 15
default via 192.168.1.1 dev eth0 metric 20
]],
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Flush clears all, correct route re-added at metric 10
      mocks.assert_route_set("192.168.1.1", "eth0", 10)

      local route_cmds = mocks.get_route_commands()
      local was_flushed = false
      local no_individual_deletes = true
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route flush default dev eth0") then
          was_flushed = true
        end
        if cmd:match("ip route delete") then
          no_individual_deletes = false
        end
      end

      assert.is_true(was_flushed, "Should flush duplicate routes")
      assert.is_true(no_individual_deletes, "Should use flush rather than individual deletes")
    end)
  end)

  describe("Scenario: No duplicate routes", function()
    it("should not intervene when route is already correct", function()
      -- GIVEN: Only our route exists (no duplicates)
      local exec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        -- Only one route (ours)
        ["ip route show default dev eth0"] = [[
default via 192.168.1.1 dev eth0 metric 10
]],
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Route is already correct — no 'ip route' interventions at all
      local route_cmds = mocks.get_route_commands()
      local intervention_count = 0

      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route replace") or cmd:match("ip route delete") or cmd:match("ip route flush") then
          intervention_count = intervention_count + 1
        end
      end

      assert.equals(0, intervention_count, "Should not issue any route interventions when route is already correct")
    end)
  end)

  describe("Scenario: P2P interface with duplicates", function()
    it("should flush and re-add for P2P interfaces with duplicate routes", function()
      -- GIVEN: P2P interface (no gateway) with duplicates
      local p2p_config = {
        mode = "failover",
        check_interval = 30,
        interfaces = {
          {
            device = "wg0",
            metric = 10,
            ping_target = "10.0.0.1",
            ping_count = 3,
            ping_timeout = 2,
            enabled = true,
          }
        }
      }

      local exec_responses = {
        ["ip link show dev wg0"] = "12: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP>",
        ["ip addr show dev wg0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev wg0"] = "",
        ["ping.*wg0"] = mocks.mock_ping_success(50.0),
        -- P2P interface with duplicate routes
        ["ip route show default dev wg0"] = [[
default dev wg0 metric 10
default dev wg0 metric 21
default dev wg0 metric 22
]],
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "wg0", gateway = nil }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(p2p_config)

      -- THEN: Flush clears duplicates, correct P2P route re-added
      mocks.assert_p2p_route_set("wg0", 10)

      local route_cmds = mocks.get_route_commands()
      local was_flushed = false
      local no_individual_deletes = true
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route flush default dev wg0") then
          was_flushed = true
        end
        if cmd:match("ip route delete") then
          no_individual_deletes = false
        end
      end

      assert.is_true(was_flushed, "Should flush duplicate P2P routes")
      assert.is_true(no_individual_deletes, "Should use flush rather than individual deletes")
    end)
  end)
end)
