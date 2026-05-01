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
    it("should clean up duplicate routes while maintaining connectivity", function()
      -- GIVEN: Multiple duplicate routes for eth0 with different metrics
      -- Simulate external tool (like surfshark) creating multiple routes
      local exec_responses = {
        -- Interface is UP and pingable
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        -- Mock ip route show to return multiple duplicate routes
        ["ip route show default dev eth0"] = [[
default via 192.168.1.1 dev eth0 metric 10
default dev eth0 scope link metric 21
default dev eth0 scope link metric 22
default dev eth0 scope link metric 23
]],
      }
      local argvexec_responses = {
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Our route should be set first (metric 10)
      mocks.assert_route_set("192.168.1.1", "eth0", 10)

      -- AND: Duplicate routes should be deleted
      -- The system should delete metrics 21, 22, 23 (everything except the first/lowest)
      local route_cmds = mocks.get_route_commands()

      -- Count delete commands for duplicate metrics
      local delete_21 = false
      local delete_22 = false
      local delete_23 = false

      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route delete default dev eth0 metric 21") then
          delete_21 = true
        end
        if cmd:match("ip route delete default dev eth0 metric 22") then
          delete_22 = true
        end
        if cmd:match("ip route delete default dev eth0 metric 23") then
          delete_23 = true
        end
      end

      assert.is_true(delete_21, "Should delete duplicate route with metric 21")
      assert.is_true(delete_22, "Should delete duplicate route with metric 22")
      assert.is_true(delete_23, "Should delete duplicate route with metric 23")
    end)

    it("should handle routes without explicit metric", function()
      -- GIVEN: Duplicate route without explicit metric (default metric)
      local exec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",

        -- Mock ip route show with route without metric
        ["ip route show default dev eth0"] = [[
default via 192.168.1.1 dev eth0 metric 10
default dev eth0 scope link
]],
      }
      local argvexec_responses = {
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Route without metric should be deleted
      local route_cmds = mocks.get_route_commands()
      local deleted_without_metric = false

      for _, cmd in ipairs(route_cmds) do
        -- Should delete without specifying metric
        if cmd:match("ip route delete default dev eth0") and not cmd:match("metric") then
          deleted_without_metric = true
        end
      end

      assert.is_true(deleted_without_metric, "Should delete route without explicit metric")
    end)

    it("should preserve our route when cleaning duplicates", function()
      -- GIVEN: Multiple routes including our metric
      local exec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",

        ["ip route show default dev eth0"] = [[
default via 192.168.1.1 dev eth0 metric 10
default via 192.168.1.1 dev eth0 metric 15
default via 192.168.1.1 dev eth0 metric 20
]],
      }
      local argvexec_responses = {
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Our route (metric 10) should NOT be deleted
      local route_cmds = mocks.get_route_commands()
      local deleted_our_route = false

      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route delete default dev eth0 metric 10") then
          deleted_our_route = true
        end
      end

      assert.is_false(deleted_our_route, "Should NOT delete our route with metric 10")

      -- AND: Higher metric routes should be deleted
      local delete_15 = false
      local delete_20 = false

      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route delete default dev eth0 metric 15") then
          delete_15 = true
        end
        if cmd:match("ip route delete default dev eth0 metric 20") then
          delete_20 = true
        end
      end

      assert.is_true(delete_15, "Should delete duplicate with metric 15")
      assert.is_true(delete_20, "Should delete duplicate with metric 20")
    end)
  end)

  describe("Scenario: No duplicate routes", function()
    it("should work normally without unnecessary deletions", function()
      -- GIVEN: Only our route exists (no duplicates)
      local exec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",

        -- Only one route (ours)
        ["ip route show default dev eth0"] = [[
default via 192.168.1.1 dev eth0 metric 10
]],
      }
      local argvexec_responses = {
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Our route should be set
      mocks.assert_route_set("192.168.1.1", "eth0", 10)

      -- AND: No delete commands should be issued (no duplicates to clean)
      local route_cmds = mocks.get_route_commands()
      local delete_count = 0

      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route delete") then
          delete_count = delete_count + 1
        end
      end

      assert.equals(0, delete_count, "Should not issue delete commands when no duplicates exist")
    end)
  end)

  describe("Scenario: P2P interface with duplicates", function()
    it("should clean up duplicates for P2P interfaces", function()
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

        -- P2P interface with duplicate routes
        ["ip route show default dev wg0"] = [[
default dev wg0 metric 10
default dev wg0 metric 21
default dev wg0 metric 22
]],
      }
      local argvexec_responses = {
        ["ping.*wg0"] = mocks.mock_ping_success(50.0),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "wg0", gateway = nil }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(p2p_config)

      -- THEN: P2P route should be set
      mocks.assert_p2p_route_set("wg0", 10)

      -- AND: Duplicates should be deleted
      local route_cmds = mocks.get_route_commands()
      local delete_21 = false
      local delete_22 = false

      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route delete default dev wg0 metric 21") then
          delete_21 = true
        end
        if cmd:match("ip route delete default dev wg0 metric 22") then
          delete_22 = true
        end
      end

      assert.is_true(delete_21, "Should delete duplicate P2P route with metric 21")
      assert.is_true(delete_22, "Should delete duplicate P2P route with metric 22")
    end)
  end)
end)
