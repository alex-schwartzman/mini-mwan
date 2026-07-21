--[[
Integration Tests for Failover Mode

Requirement: FR-2.1 - Failover Mode
Priority: Critical
Description: System SHALL provide failover mode where interfaces are prioritized by metric,
            with automatic failover to backup interfaces
]]

local mocks = require("spec.helpers.mocks")

describe("FR-2.1: Failover Mode - End to End", function()
  local mini_mwan
  local default_config
  local default_state

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
          metric = 1,
          ping_target = "1.1.1.1",
          ping_count = 3,
          ping_timeout = 2,
          enabled = true,
          },
        {
          device = "eth1",
          metric = 2,
          ping_target = "8.8.8.8",
          ping_count = 3,
          ping_timeout = 2,
          enabled = true,
          }
      }
    }

    -- Default state (mutable, ephemeral)
    default_state = {
      interfaces = {
        {
          device = "eth0",
          point_to_point = false,
          gateway = "192.168.1.1",
          does_exist = false,
          is_up = false,
          degraded = 0,
          degraded_reason = "",
          latency = 0
        },
        {
          device = "eth1",
          point_to_point = false,
          gateway = "192.168.2.1",
          does_exist = false,
          is_up = false,
          degraded = 0,
          degraded_reason = "",
          latency = 0
        }
      }
    }
  end)

  describe("Scenario: Both interfaces healthy", function()
    it("should use primary (lowest metric) interface", function()
      -- GIVEN: Two interfaces configured, both UP
      local exec_responses = {
        -- Primary interface (eth0) - UP
        ["/sbin/ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["/sbin/ip %-6 addr show dev eth0"] = "", -- No IPv6

        -- Backup interface (eth1) - UP
        ["/sbin/ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["/sbin/ip %-6 addr show dev eth1"] = "",  -- No IPv6

        ["/bin/ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["/bin/ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.2),
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

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Primary route should be set
      mocks.assert_route_set("192.168.1.1", "eth0", 1)

      -- AND: Backup route should also be set (for quick failover)
      mocks.assert_route_set("192.168.2.1", "eth1", 2)
    end)
  end)

  describe("Scenario: Primary fails, backup takes over", function()
    it("should use backup interface when primary is down", function()
      -- GIVEN: Primary is DOWN, backup is UP
      local exec_responses = {
        -- Primary interface (eth0) - UP but NOT pingable (connection lost)
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        -- Backup interface (eth1) - UP and pingable
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",  -- No IPv6

        ["ping.*eth0"] = mocks.mock_ping_failure(),  -- FAILED
        ["ping.*eth1"] = mocks.mock_ping_success(20.0),  -- OK

        ["ip route show"] = mocks.ip_route_show_eth0_default()
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

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Backup should be used as primary
      mocks.assert_route_set("192.168.2.1", "eth1", 2)

      -- AND: Failed primary should have high metric (900) to allow pings
      mocks.assert_route_set("192.168.1.1", "eth0", 900)
    end)
  end)

  describe("Scenario: Primary down interface recovers", function()
    it("should restore primary when it comes back up", function()
      -- Simulation: Run two cycles
      -- Cycle 1: Primary down, backup used
      -- Cycle 2: Primary recovers, becomes primary again

      -- CYCLE 1: Primary down
      local exec_responses_cycle1 = {
        ["ip addr show dev eth0"] = mocks.mock_interface_down(),  -- Interface DOWN
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",  -- No IPv6
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),
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

      -- First run - primary down
      mini_mwan.work(default_config)

      -- Verify backup is being used
      mocks.assert_route_set("192.168.2.1", "eth1", 2)

      -- CYCLE 2: Primary recovers
      mocks.reset()

      local exec_responses_cycle2 = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),  -- Now UP
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",  -- No IPv6
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),        -- Now working
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),
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

      -- Second run - primary recovered
      mini_mwan.work(default_config)

      -- Verify primary is now being used again
      mocks.assert_route_set("192.168.1.1", "eth0", 1)
    end)
  end)

  describe("Scenario: Both interfaces fail", function()
    it("should log warning but not crash", function()
      -- GIVEN: All interfaces down
      local exec_responses = {
        -- Regular interface (eth0) - has gateway
        ["ip link show dev eth0"] =
        "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\n    link/ether 60:cf:84:ee:10:68 brd ff:ff:ff:ff:ff:ff",

        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",  -- No IPv6

        ["ping.*eth0"] = mocks.mock_ping_failure(),  -- FAILED
        ["ping.*eth1"] = mocks.mock_ping_failure(),  -- FAILED
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
      -- THEN: Should not crash, should log warning
      assert.has_no.errors(function()
        mini_mwan.work(default_config)
      end)

      -- Should log: "WARNING: No WAN connections are available!"
    end)
  end)

  describe("Scenario: VPN tunnel with ISP failover", function()
    it("should handle P2P interface (no gateway) correctly", function()
      -- GIVEN: Regular interface (eth0) and VPN tunnel (wg0)
      local exec_responses = {
        -- Regular interface (eth0) - has gateway
        ["ip link show dev eth0"] =
        "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\n    link/ether 60:cf:84:ee:10:68 brd ff:ff:ff:ff:ff:ff",
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        -- VPN tunnel (wg0) - no gateway (P2P)
        ["ip link show dev wg0"] =
        "12: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1220 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\n    link/none",
        ["ip addr show dev wg0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev wg0"] = "",  -- No IPv6

        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ping.*wg0"] = mocks.mock_ping_success(50.0),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        -- ubus returns both: eth0 with gateway, wg0 without (P2P)
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "wg0", gateway = nil }  -- P2P, no gateway
        })
      })
      mini_mwan.set_dependencies(deps)

      -- Custom config with P2P interface
      local vpn_config = {
        enabled = true,
        mode = "failover",
        check_interval = 30,
        interfaces = {
          {
            device = "eth0",
            metric = 1,
            ping_target = "1.1.1.1",
            ping_count = 3,
            ping_timeout = 2,
            enabled = true,
              },
          {
            device = "wg0",
            metric = 2,
            ping_target = "10.0.0.1",
            ping_count = 3,
            ping_timeout = 2,
            enabled = true,
            }
        }
      }

      -- WHEN: Running work cycle
      mini_mwan.work(vpn_config)

      -- THEN: Regular interface should have route with gateway
      mocks.assert_route_set("192.168.1.1", "eth0", 1)

      -- AND: P2P interface should have route without gateway
      mocks.assert_p2p_route_set("wg0", 2)
    end)
  end)

  describe("Scenario: Degraded interface should be skipped", function()
    it("should not route through shared medium interface without gateway", function()
      -- GIVEN: wan1 is degraded (no gateway, DHCP incomplete), wan2 is healthy
      local exec_responses = {
        -- wan1 (eth0) - shared medium interface UP but no gateway (DHCP incomplete)
        ["ip link show dev eth0"] =
        "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\n    link/ether 60:cf:84:ee:10:68 brd ff:ff:ff:ff:ff:ff",


        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        -- wan2 (eth1) - shared medium interface healthy with gateway
        ["ip link show dev eth1"] =
        "4: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\n    link/ether 60:cf:84:ee:10:69 brd ff:ff:ff:ff:ff:ff",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",  -- No IPv6

        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        -- ubus returns eth0 without gateway (degraded), eth1 with gateway
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = nil },  -- No gateway (DHCP incomplete)
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(default_config)

      -- THEN: Only wan2 should have a route (wan1 is degraded and skipped)
      mocks.assert_route_set("192.168.2.1", "eth1", 2)

      -- AND: wan1 should NOT have any route (degraded interfaces are skipped entirely)
      local route_cmds = mocks.get_route_commands()
      local eth0_routes = 0
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("eth0") and not cmd:match("delete") then
          eth0_routes = eth0_routes + 1
        end
      end
      assert.equals(0, eth0_routes, "Degraded shared medium interface should not have routes set")
    end)
  end)

  describe("Scenario: Switch from multiuplink to failover mode", function()
    it("should replace multipath route with single routes when mode changes", function()
      -- First, run in multiuplink mode
      local multiuplink_config = {
        mode = "multiuplink",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, weight = 3, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth1", metric = 20, weight = 5, ping_target = "8.8.8.8", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses_multi = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",
        ["ip route show default"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses_multi)
      local deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- First cycle: multiuplink mode
      mini_mwan.work(multiuplink_config)
      mocks.assert_multipath_route({
        { gateway = "192.168.1.1", device = "eth0", weight = 3 },
        { gateway = "192.168.2.1", device = "eth1", weight = 5 }
      })

      -- Reset for second cycle
      mocks.reset()

      -- Second config: switch to failover mode
      local failover_config = {
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true },
          { device = "eth1", metric = 20, ping_target = "8.8.8.8", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses_failover = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",
        ["ip route show default dev eth0"] = "",
        ["ip route show default dev eth1"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),
      }

      exec_mock = mocks.build_exec_mock(exec_responses_failover)
      deps = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle in failover mode
      mini_mwan.work(failover_config)

      -- THEN: Should have single routes (not multipath) for each interface
      mocks.assert_route_set("192.168.1.1", "eth0", 10)
      mocks.assert_route_set("192.168.2.1", "eth1", 20)

      -- AND: No multipath route should exist
      local route_cmds = mocks.get_route_commands()
      local multipath_found = false
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("ip route replace default nexthop") then
          multipath_found = true
          break
        end
      end
      assert.is_false(multipath_found, "Should not have multipath route in failover mode")
    end)
  end)

  describe("Scenario: IPv4-only routing (IPv6 should not be routed when IPv4 fails)", function()
    it("should NOT set IPv6 route when interface is probe_only (IPv4 ping fails but IPv6 gateway exists)", function()
      -- GIVEN: Interface has both IPv4 and IPv6 gateways, but IPv4 ping fails
      -- This simulates: interface was usable with dual-stack, then IPv4 connectivity lost
      local config = {
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

      local exec_responses = {
        -- Interface is UP
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",

        -- IPv4 ping FAILS (connectivity lost)
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_failure(),

        -- Route cleanup - no existing routes
        ["ip route show default dev eth0"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        -- ubus returns both IPv4 and IPv6 gateways
        ubus_network_dump = mocks.mock_ubus_network_dump({
          {
            l3_device = "eth0",
            gateway = "192.168.1.1",  -- IPv4 gateway
            ipv6_gateway = "2001:db8::1"  -- IPv6 gateway (but IPv4 is down)
          }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle (interface will be probe_only)
      mini_mwan.work(config)

      -- THEN: Only IPv4 probe route (metric 900) should be set
      -- IPv6 route should NOT be set because IPv4 is not usable (fail-closed)
      mocks.assert_route_set("192.168.1.1", "eth0", 900)

      -- AND: No IPv6 route commands should be executed
      local route_cmds = mocks.get_route_commands()
      local ipv6_route_found = false
      for _, cmd in ipairs(route_cmds) do
        if cmd:match("-6") and cmd:match("route add") then
          ipv6_route_found = true
          break
        end
      end
      assert.is_false(ipv6_route_found, "Should NOT set IPv6 route when IPv4 connectivity is lost")
    end)

    it("should set both IPv4 and IPv6 routes when interface is usable (dual-stack)", function()
      -- GIVEN: Interface has both IPv4 and IPv6 gateways, and IPv4 ping succeeds
      local config = {
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

      local exec_responses = {
        -- Interface is UP
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",

        -- IPv4 ping SUCCEEDS
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),

        -- No existing routes
        ["ip route show default dev eth0"] = "",
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local deps = mocks.build_deps({
        exec = exec_mock,
        -- ubus returns both IPv4 and IPv6 gateways
        ubus_network_dump = mocks.mock_ubus_network_dump({
          {
            l3_device = "eth0",
            gateway = "192.168.1.1",  -- IPv4 gateway
            ipv6_gateway = "2001:db8::1"  -- IPv6 gateway
          }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle (interface will be usable)
      mini_mwan.work(config)

      -- THEN: Both IPv4 and IPv6 routes should be set
      mocks.assert_route_set("192.168.1.1", "eth0", 10)

      -- AND: IPv6 route should also be set
      local ipv6_route_found = false
      for _, cmd in ipairs(mocks.executed_commands) do
        if cmd:match("/sbin/ip %-6 route add default via 2001:db8::1 dev eth0 metric 10") then
          ipv6_route_found = true
          break
        end
      end
      assert.is_true(ipv6_route_found, "Should set IPv6 route when IPv4 connectivity is OK (dual-stack)")
    end)
  end)
end)
