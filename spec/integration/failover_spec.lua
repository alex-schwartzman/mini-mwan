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
        -- Primary interface (eth0) - UP and pingable
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        -- Backup interface (eth1) - UP and pingable
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.2),
        ["ip %-6 addr show dev eth1"] = ""  -- No IPv6
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
        ["ping.*eth0"] = mocks.mock_ping_failure(),  -- FAILED
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        -- Backup interface (eth1) - UP and pingable
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_success(20.0),  -- OK
        ["ip %-6 addr show dev eth1"] = "",  -- No IPv6
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
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),
        ["ip %-6 addr show dev eth1"] = ""  -- No IPv6
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
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),        -- Now working
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),
        ["ip %-6 addr show dev eth1"] = ""  -- No IPv6
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
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0"] = mocks.mock_ping_failure(),  -- FAILED
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_failure(),  -- FAILED
        ["ip %-6 addr show dev eth1"] = ""  -- No IPv6
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
        ["ip link show dev eth0"] = "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\n    link/ether 60:cf:84:ee:10:68 brd ff:ff:ff:ff:ff:ff",
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        -- VPN tunnel (wg0) - no gateway (P2P)
        ["ip link show dev wg0"] = "12: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP> mtu 1220 qdisc noqueue state UNKNOWN mode DEFAULT group default qlen 1000\n    link/none",
        ["ip addr show dev wg0"] = mocks.mock_interface_up(),
        ["ping.*wg0"] = mocks.mock_ping_success(50.0),
        ["ip %-6 addr show dev wg0"] = ""  -- No IPv6
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
        ["ip link show dev eth0"] = "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\n    link/ether 60:cf:84:ee:10:68 brd ff:ff:ff:ff:ff:ff",
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0"] = mocks.mock_ping_success(10.0),
        ["ip %-6 addr show dev eth0"] = "",  -- No IPv6

        -- wan2 (eth1) - shared medium interface healthy with gateway
        ["ip link show dev eth1"] = "4: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc mq state UP mode DEFAULT group default qlen 1000\n    link/ether 60:cf:84:ee:10:69 brd ff:ff:ff:ff:ff:ff",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1"] = mocks.mock_ping_success(15.0),
        ["ip %-6 addr show dev eth1"] = ""  -- No IPv6
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
end)
