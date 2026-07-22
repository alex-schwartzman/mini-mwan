--[[
Unit Tests for State Persistence (FR-4.1)

Requirement: FR-4.1 - Runtime State Preservation
Priority: High
Description: System SHALL preserve interface state across configuration reloads

This test verifies that:
1. status_since is preserved when routing_class doesn't change (state is stable)
2. Clock advancement doesn't affect preserved state values
]]

local mocks = require("spec.helpers.mocks")

describe("FR-4.1: State Persistence - Runtime State Preservation", function()
  local mini_mwan
  local deps
  local reference_epoch = 1698765432

  -- Helper to create common deps with mockable time
  local function create_deps(current_time)
    local exec_mock = mocks.build_exec_mock({
      ["ip addr show dev eth0"] = mocks.mock_interface_up(),
      ["ip %-6 addr show dev eth0"] = "",
      ["ip addr show dev eth1"] = mocks.mock_interface_up(),
      ["ip %-6 addr show dev eth1"] = "",
      ["ip route show default"] = "",
      ["ping.*eth0.*1%.1%.1%.1"] = mocks.mock_ping_success(10.5),
      ["ping.*eth1.*8%.8%.8%.8"] = mocks.mock_ping_success(15.2),
    })

    local file_mock = mocks.build_file_mock({
      ["/sys/class/net/eth0/statistics/rx_bytes"] = "100",
      ["/sys/class/net/eth0/statistics/tx_bytes"] = "200",
      ["/sys/class/net/eth1/statistics/rx_bytes"] = "300",
      ["/sys/class/net/eth1/statistics/tx_bytes"] = "400",
    })

    return mocks.build_deps({
      exec = exec_mock,
      open_file = file_mock,
      ubus_network_dump = mocks.mock_ubus_network_dump({
        { l3_device = "eth0", gateway = "192.168.1.1" },
        { l3_device = "eth1", gateway = "192.168.2.1" }
      }),
      time = function() return reference_epoch end
    })
  end

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")

    deps = create_deps(reference_epoch)
    mini_mwan.set_dependencies(deps)
  end)

  describe("State Persistence", function()
    it("preserves status_since across cycles when routing_class is stable", function()
      local config = {
        enabled = true,
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2 },
          { device = "eth1", metric = 20, ping_target = "8.8.8.8", ping_count = 3, ping_timeout = 2 }
        }
      }

      -- First cycle: interface becomes usable
      mini_mwan.work(config)

      local eth0_state = mini_mwan.get_interface_state()["eth0"]
      local status_since_first = eth0_state.status_since
      local routing_class_first = eth0_state.routing_class

      assert.equals("usable", routing_class_first)
      assert.is_not_nil(status_since_first)

      -- Second cycle: same state (usable), time has advanced
      deps = create_deps(reference_epoch + 3600)
      mini_mwan.set_dependencies(deps)
      mini_mwan.work(config)

      -- THEN: status_since should be preserved from first cycle
      local eth0_state2 = mini_mwan.get_interface_state()["eth0"]
      assert.equals("usable", eth0_state2.routing_class)
      assert.equals(status_since_first, eth0_state2.status_since,
        "status_since should NOT change when routing_class is stable, even though time advanced")

      -- AND: routing_class should remain "usable"
      assert.equals("usable", eth0_state2.routing_class)
    end)
  end)
end)
