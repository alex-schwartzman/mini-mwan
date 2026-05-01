--[[
Integration Tests for Logging

Requirement: FR-5.3 - Audit Logging
Priority: Medium
Description: System SHALL log executed commands at appropriate verbosity levels
]]

local mocks = require("spec.helpers.mocks")

describe("FR-5.3: Audit Logging - Integration", function()
  local mini_mwan

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")
  end)

  describe("Scenario: Normal cycle (nothing changed)", function()
    it("should log ping results at debug level", function()
      -- GIVEN: Normal healthy interface
      local config = {
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
      }
      local argvexec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip route show default dev eth0"] = "",  -- No duplicates
        ["ping.*eth0"] = mocks.mock_ping_success(10.5),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps, ubus_mock, log_mock = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
       })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Should have logged ping success at debug level
      local debug_msgs = log_mock.get_messages_by_priority("debug")
      local found_ping_success = false
      for _, msg in ipairs(debug_msgs) do
        if msg.message:match("Ping successful") then
          found_ping_success = true
          break
        end
      end
      assert.is_true(found_ping_success, "Should log ping success at debug level")
    end)

    it("should log probe commands at debug level", function()
      -- GIVEN: Normal healthy interface
      local config = {
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
      }
      local argvexec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip route show default dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.5),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps, ubus_mock, log_mock = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Should have logged probe commands (ubus, ip addr, ping) at debug level
      local debug_msgs = log_mock.get_messages_by_priority("debug")

      local found_ubus_probe = false
      local found_ip_probe = false
      local found_ping_probe = false

      for _, msg in ipairs(debug_msgs) do
        if msg.message:match("Probe: ubus call network%.interface dump") then
          found_ubus_probe = true
        end
        if msg.message:match("Probe: ip addr show") then
          found_ip_probe = true
        end
        if msg.message:match("Probe: ping") then
          found_ping_probe = true
        end
      end

      assert.is_true(found_ubus_probe, "Should log ubus probe at debug level")
      assert.is_true(found_ip_probe, "Should log ip addr probe at debug level")
      assert.is_true(found_ping_probe, "Should log ping probe at debug level")
    end)
  end)

  describe("Scenario: Routes changed (interface comes up)", function()
    it("should log route interventions at notice level", function()
      -- GIVEN: Interface that needs route setup
      local config = {
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
      }
      local argvexec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip route show default dev eth0"] = "",  -- No existing routes
        ["ping.*eth0"] = mocks.mock_ping_success(10.5),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps, ubus_mock, log_mock = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle (will set routes)
      mini_mwan.work(config)

      -- THEN: Should have logged route intervention at notice level
      local notice_msgs = log_mock.get_messages_by_priority("notice")
      local found_route_intervention = false

      for _, msg in ipairs(notice_msgs) do
        if msg.message:match("Intervention: ip route replace default") then
          found_route_intervention = true
          break
        end
      end

      assert.is_true(found_route_intervention, "Should log route intervention at notice level")
    end)

    it("should log route cleanup interventions at notice level", function()
      -- GIVEN: Interface with duplicate routes that need cleanup
      local config = {
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
      }
      local argvexec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.5),
        -- Duplicate routes exist
        ["ip route show default dev eth0"] = [[
default via 192.168.1.1 dev eth0 metric 10
default via 192.168.1.1 dev eth0 metric 21
]],
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps, ubus_mock, log_mock = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle (will clean up duplicates)
      mini_mwan.work(config)

      -- THEN: Should have logged route delete interventions at notice level
      local notice_msgs = log_mock.get_messages_by_priority("notice")
      local found_delete_intervention = false

      for _, msg in ipairs(notice_msgs) do
        if msg.message:match("Intervention: ip route delete default") then
          found_delete_intervention = true
          break
        end
      end

      assert.is_true(found_delete_intervention, "Should log route delete intervention at notice level")
    end)
  end)

  describe("Scenario: Interface state transitions", function()
    it("should log interface DOWN transition at info level", function()
      -- GIVEN: Interface that was UP and then goes DOWN
      local config = {
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
      }
      local argvexec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip route show default dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_failure(),  -- 100% packet loss
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps, ubus_mock, log_mock = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle (interface will go DOWN due to ping failure)
      mini_mwan.work(config)

      -- THEN: Should have logged state transition at info level
      local info_msgs = log_mock.get_messages_by_priority("info")
      local found_down_transition = false

      for _, msg in ipairs(info_msgs) do
        if msg.message:match("eth0") and msg.message:match("DOWN") then
          found_down_transition = true
          break
        end
      end

      assert.is_true(found_down_transition, "Should log interface DOWN transition at info level")
    end)

    it("should log interface UP transition at info level with latency", function()
      -- GIVEN: Interface that was DOWN and then comes UP
      local config = {
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
      }
      local argvexec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ip route show default dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(12.5),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps, ubus_mock, log_mock = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = "192.168.1.1" }
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle (interface will go UP)
      mini_mwan.work(config)

      -- THEN: Should have logged state transition at info level with latency
      local info_msgs = log_mock.get_messages_by_priority("info")
      local found_up_transition = false

      for _, msg in ipairs(info_msgs) do
        if msg.message:match("eth0") and msg.message:match("UP") and msg.message:match("latency") then
          found_up_transition = true
          break
        end
      end

      assert.is_true(found_up_transition, "Should log interface UP transition at info level with latency")
    end)
  end)

  describe("Scenario: Degradation detection", function()
    it("should log degradation warning when interface has no gateway", function()
      -- GIVEN: Regular interface without gateway (DHCP incomplete)
      local config = {
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
        }
      }

      local exec_responses = {
        ["ip link show dev eth0"] = "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP>",  -- Not P2P
        ["ip route show default"] = "",
      }
      local argvexec_responses = {
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.5),
      }

      local exec_mock = mocks.build_exec_mock(exec_responses)
      local argvexec_mock = mocks.build_argvexec_mock(argvexec_responses)
      local deps, ubus_mock, log_mock = mocks.build_deps({
        exec = exec_mock,
        argvexec = argvexec_mock,
        ubus_network_dump = mocks.mock_ubus_network_dump({
          { l3_device = "eth0", gateway = nil } -- No gateway
          })
         })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running work cycle
      mini_mwan.work(config)

      -- THEN: Should have logged degradation warning
      local warning_msgs = log_mock.get_messages_by_priority("warning")
      local found_degradation = false

      for _, msg in ipairs(warning_msgs) do
        if msg.message:match("DEGRADED") and msg.message:match("missing gateway") then
          found_degradation = true
          break
        end
      end

      assert.is_true(found_degradation, "Should log degradation warning at warning level")
    end)
  end)
end)
