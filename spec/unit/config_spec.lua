--[[
Unit Tests for Configuration Management

Requirement: FR-3.x - Configuration Management
Priority: Critical
Description: System SHALL load configuration from UCI with proper defaults and validation
]]

local mocks = require("spec.helpers.mocks")

describe("FR-3: Configuration Management", function()
  local mini_mwan

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")
  end)

  describe("load_config() - Global settings", function()
    it("should load enabled flag correctly", function()
      -- GIVEN: UCI config with enabled=1
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "30" },
        interfaces = {}
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should return enabled=true
      assert.is_true(config.enabled)
    end)

    it("should detect disabled state", function()
      -- GIVEN: UCI config with enabled=0
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "0", mode = "failover", check_interval = "30" },
        interfaces = {}
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should return enabled=false
      assert.is_false(config.enabled)
    end)

    it("should load mode setting", function()
      -- GIVEN: UCI config with mode=multiuplink
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "multiuplink", check_interval = "30" },
        interfaces = {}
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should return correct mode
      assert.equals("multiuplink", config.mode)
    end)

    it("should default mode to failover if missing", function()
      -- GIVEN: UCI config without mode setting
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", check_interval = "30" },
        interfaces = {}
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should default to failover
      assert.equals("failover", config.mode)
    end)

    it("should load check_interval as number", function()
      -- GIVEN: UCI config with check_interval=60
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "60" },
        interfaces = {}
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should convert to number
      assert.equals(60, config.check_interval)
      assert.equals("number", type(config.check_interval))
    end)

    it("should default check_interval to 30 if missing", function()
      -- GIVEN: UCI config without check_interval
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover" },
        interfaces = {}
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should default to 30
      assert.equals(30, config.check_interval)
    end)

    it("should load audit log level", function()
      -- GIVEN: UCI config with audit=debug
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "30", audit = "debug" },
        interfaces = {}
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should load log level
      assert.equals("debug", config.log_level)
    end)

    it("should default log_level to emerg if missing", function()
      -- GIVEN: UCI config without audit setting
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "30" },
        interfaces = {}
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should default to emerg
      assert.equals("emerg", config.log_level)
    end)
  end)

  describe("load_config() - Interface configuration", function()
    it("should load interface with all required fields", function()
      -- GIVEN: UCI config with one interface
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "30" },
        interfaces = {
          wan1 = {
            device = "eth0",
            metric = "10",
            weight = "5",
            ping_target = "1.1.1.1",
            ping_count = "3",
            ping_timeout = "2"
          }
        }
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should load interface correctly
      assert.equals(1, #config.interfaces)
      local iface = config.interfaces[1]
      assert.equals("eth0", iface.device)
      assert.equals(10, iface.metric)
      assert.equals(5, iface.weight)
      assert.equals("1.1.1.1", iface.ping_target)
      assert.equals(3, iface.ping_count)
      assert.equals(2, iface.ping_timeout)
    end)

    it("should load multiple interfaces", function()
      -- GIVEN: UCI config with three interfaces
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "multiuplink", check_interval = "30" },
        interfaces = {
          wan1 = { device = "eth0", metric = "10", ping_target = "1.1.1.1" },
          wan2 = { device = "eth1", metric = "20", ping_target = "8.8.8.8" },
          wan3 = { device = "wlan0", metric = "30", ping_target = "9.9.9.9" }
        }
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should load all interfaces (metrics determine priority, not order)
      assert.equals(3, #config.interfaces)

      -- Verify all devices are present
      local devices = {}
      for _, iface in ipairs(config.interfaces) do
        devices[iface.device] = true
      end
      assert.is_true(devices["eth0"])
      assert.is_true(devices["eth1"])
      assert.is_true(devices["wlan0"])
    end)

    it("should apply default metric if missing", function()
      -- GIVEN: Interface without metric
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "30" },
        interfaces = {
          wan1 = { device = "eth0", ping_target = "1.1.1.1" }
        }
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should default metric to 10
      assert.equals(10, config.interfaces[1].metric)
    end)

    it("should apply default weight if missing", function()
      -- GIVEN: Interface without weight
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "multiuplink", check_interval = "30" },
        interfaces = {
          wan1 = { device = "eth0", metric = "10", ping_target = "1.1.1.1" }
        }
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should default weight to 3
      assert.equals(3, config.interfaces[1].weight)
    end)

    it("should apply default ping_count if missing", function()
      -- GIVEN: Interface without ping_count
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "30" },
        interfaces = {
          wan1 = { device = "eth0", metric = "10", ping_target = "1.1.1.1" }
        }
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should default ping_count to 3
      assert.equals(3, config.interfaces[1].ping_count)
    end)

    it("should apply default ping_timeout if missing", function()
      -- GIVEN: Interface without ping_timeout
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "30" },
        interfaces = {
          wan1 = { device = "eth0", metric = "10", ping_target = "1.1.1.1" }
        }
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should default ping_timeout to 2
      assert.equals(2, config.interfaces[1].ping_timeout)
    end)

    it("should load minimal valid configuration", function()
      -- GIVEN: LuCI writes minimal config with only required fields
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1" },  -- Only enabled, rest default
        interfaces = {
          wan1 = { device = "eth0", ping_target = "1.1.1.1" },  -- Only required fields
          wan2 = { device = "eth1", ping_target = "8.8.8.8" }
        }
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should apply all defaults
      assert.is_true(config.enabled)
      assert.equals("failover", config.mode)
      assert.equals(30, config.check_interval)
      assert.equals("emerg", config.log_level)
      assert.equals(2, #config.interfaces)
      assert.equals(10, config.interfaces[1].metric)
      assert.equals(3, config.interfaces[1].weight)
      assert.equals(3, config.interfaces[1].ping_count)
      assert.equals(2, config.interfaces[1].ping_timeout)
    end)

    it("should handle VLAN interface names", function()
      -- GIVEN: Interface with VLAN naming (eth0.100)
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "30" },
        interfaces = {
          wan_vlan = { device = "eth0.100", metric = "10", ping_target = "1.1.1.1" }
        }
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: Should load VLAN device name correctly
      assert.equals("eth0.100", config.interfaces[1].device)
    end)

    it("should convert string numbers to integers", function()
      -- GIVEN: UCI config with string representations of numbers
      local uci_mock = mocks.mock_uci_cursor({
        settings = { enabled = "1", mode = "failover", check_interval = "45" },
        interfaces = {
          wan1 = {
            device = "eth0",
            metric = "15",
            weight = "7",
            ping_target = "1.1.1.1",
            ping_count = "5",
            ping_timeout = "3"
          }
        }
      })
      local deps = mocks.build_deps({ uci_cursor = function() return uci_mock end })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Loading config
      local config = mini_mwan.load_config()

      -- THEN: All numeric fields should be numbers, not strings
      assert.equals("number", type(config.check_interval))
      assert.equals("number", type(config.interfaces[1].metric))
      assert.equals("number", type(config.interfaces[1].weight))
      assert.equals("number", type(config.interfaces[1].ping_count))
      assert.equals("number", type(config.interfaces[1].ping_timeout))
    end)
  end)
end)
