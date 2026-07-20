--[[
Unit Tests for Status Update via ubus

Requirement: FR-4.2 - Status via ubus
Priority: High
Description: System SHALL expose current status via ubus for external consumption
]]

local mocks = require("spec.helpers.mocks")

describe("FR-4.2: Status Update", function()
  local mini_mwan
  local test_config

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")

    -- Test config (immutable, from UCI)
    test_config = {
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
  end)

  describe("ubus status publishing", function()
    it("should publish status via ubus after work cycle", function()
      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",
        ["ip route show default"] = "",
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.2),
      })
      local deps, ubus_mock = mocks.build_deps({
        exec = exec_mock,
        time = function() return 1698765432 end,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Registering ubus and running work cycle
      mini_mwan.register_ubus()
      mini_mwan.work(test_config)

      -- THEN: Status should be available via ubus
      local status = ubus_mock.call_method("mini-mwan", "status")
      assert.is_not_nil(status)
      assert.equals("failover", status.mode)
      assert.equals(1698765432, status.timestamp)
      assert.equals(30, status.check_interval)
    end)

    it("should include correct global fields", function()
      -- GIVEN: Config with specific mode and check_interval
      test_config.mode = "multiuplink"
      test_config.check_interval = 60

      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth1"] = "",
        ["ip route show default"] = "",
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.2),
      })
      local deps, ubus_mock = mocks.build_deps({
        exec = exec_mock,
        time = function() return 9999999999 end,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Registering ubus and running work
      mini_mwan.register_ubus()
      mini_mwan.work(test_config)

      -- THEN: Status via ubus should contain correct global fields
      local status = ubus_mock.call_method("mini-mwan", "status")
      assert.equals("multiuplink", status.mode)
      assert.equals(9999999999, status.timestamp)
      assert.equals(60, status.check_interval)
    end)

    it("should include all interface fields", function()
      -- GIVEN: Complete work cycle with all mocks
      local exec_mock = mocks.build_exec_mock({
        -- Gateway discovery
        -- Interface status
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.2),
        ["ip %-6 addr show dev eth1"] = "",
        -- Route cleanup
        ["ip route show default"] = "",
      })

      local file_mock = mocks.build_file_mock({
        ["/sys/class/net/eth0/statistics/rx_bytes"] = "111",
        ["/sys/class/net/eth0/statistics/tx_bytes"] = "222",
        ["/sys/class/net/eth1/statistics/rx_bytes"] = "333",
        ["/sys/class/net/eth1/statistics/tx_bytes"] = "444",
      })

      local deps, ubus_mock = mocks.build_deps({
        exec = exec_mock,
        open_file = file_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
          })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Registering ubus and running work
      mini_mwan.register_ubus()
      mini_mwan.work(test_config)

      -- THEN: ubus status should contain all interface fields
      local status = ubus_mock.call_method("mini-mwan", "status")
      assert.is_not_nil(status.interfaces)
      assert.equals(2, #status.interfaces)

      local iface1 = status.interfaces[1]
      assert.equals("eth0", iface1.device)
      assert.equals("1.1.1.1", iface1.ping_target)
      assert.is_not_nil(iface1.routing_class)
      assert.is_not_nil(iface1.latency)
      assert.is_not_nil(iface1.gateway)
      assert.equals(111, iface1.rx_bytes)
      assert.equals(222, iface1.tx_bytes)

      local iface2 = status.interfaces[2]
      assert.equals("eth1", iface2.device)
      assert.is_not_nil(iface2.routing_class)
      assert.is_not_nil(iface2.latency)
      assert.is_not_nil(iface2.gateway)
      assert.equals(333, iface2.rx_bytes)
      assert.equals(444, iface2.tx_bytes)
    end)

    it("should convert network stats to numbers", function()
      -- GIVEN: Complete work cycle with large network stats
      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip addr show dev eth1"] = mocks.mock_interface_up(),
        ["ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.2),
        ["ip %-6 addr show dev eth1"] = "",
        ["ip route show default"] = "",
      })

      local file_mock = mocks.build_file_mock({
        ["/sys/class/net/eth0/statistics/rx_bytes"] = "1234567890",
        ["/sys/class/net/eth0/statistics/tx_bytes"] = "9876543210",
        ["/sys/class/net/eth1/statistics/rx_bytes"] = "5555555555",
        ["/sys/class/net/eth1/statistics/tx_bytes"] = "6666666666",
      })

      local deps, ubus_mock = mocks.build_deps({
        exec = exec_mock,
        open_file = file_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" },
          { l3_device = "eth1", gateway = "192.168.2.1" }
          })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Registering ubus and running work
      mini_mwan.register_ubus()
      mini_mwan.work(test_config)

      -- THEN: ubus status should have network stats as numbers
      local status = ubus_mock.call_method("mini-mwan", "status")
      assert.equals("number", type(status.interfaces[1].rx_bytes))
      assert.equals("number", type(status.interfaces[1].tx_bytes))
      assert.equals(1234567890, status.interfaces[1].rx_bytes)
      assert.equals(9876543210, status.interfaces[1].tx_bytes)
    end)

    it("should handle missing network stats gracefully", function()
      -- GIVEN: Network stats unavailable (empty response)
      local exec_mock = mocks.build_exec_mock({
        ["cat /sys/class/net/eth0/statistics/rx_bytes"] = "",
        ["cat /sys/class/net/eth0/statistics/tx_bytes"] = "",
        ["cat /sys/class/net/eth1/statistics/rx_bytes"] = "",
        ["cat /sys/class/net/eth1/statistics/tx_bytes"] = "",
      })
      local deps, ubus_mock = mocks.build_deps({ exec = exec_mock })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Registering ubus and running work
      mini_mwan.register_ubus()
      mini_mwan.work(test_config)

      -- THEN: ubus status should default to 0 for missing stats
      local status = ubus_mock.call_method("mini-mwan", "status")
      assert.equals(0, status.interfaces[1].rx_bytes)
      assert.equals(0, status.interfaces[1].tx_bytes)
    end)

    it("should include IPv6 gateway when available", function()
      -- GIVEN: Interface with both IPv4 and IPv6 gateways
      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
        ["ip route show default"] = "",
      })
      local deps, ubus_mock = mocks.build_deps({
        exec = exec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1", ipv6_gateway = "2001:db8::1" }
        })
      })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Registering ubus and running work
      mini_mwan.register_ubus()
      mini_mwan.work(test_config)

      -- THEN: ubus status should include IPv6 gateway
      local status = ubus_mock.call_method("mini-mwan", "status")
      assert.is_not_nil(status.interfaces[1].ipv6_gateway)
      assert.equals("2001:db8::1", status.interfaces[1].ipv6_gateway)
    end)
  end)

end)
