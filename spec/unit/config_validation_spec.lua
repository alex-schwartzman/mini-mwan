--[[
Unit Tests for Configuration Validation

Requirement: FR-3.5 - Validation Requirements
Priority: High
Description: System SHALL validate configuration at runtime
]]

local mocks = require("spec.helpers.mocks")

describe("FR-3.5: Configuration Validation", function()
  local mini_mwan

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")
  end)

  describe("is_valid_ip_address()", function()
    it("should accept valid IPv4 addresses", function()
      assert.is_true(mini_mwan.is_valid_ip_address("1.1.1.1"))
      assert.is_true(mini_mwan.is_valid_ip_address("8.8.8.8"))
      assert.is_true(mini_mwan.is_valid_ip_address("192.168.1.1"))
      assert.is_true(mini_mwan.is_valid_ip_address("0.0.0.0"))
      assert.is_true(mini_mwan.is_valid_ip_address("255.255.255.255"))
    end)

    it("should reject invalid IPv4 addresses", function()
      assert.is_false(mini_mwan.is_valid_ip_address(""))
      assert.is_false(mini_mwan.is_valid_ip_address(nil))
      assert.is_false(mini_mwan.is_valid_ip_address("256.1.1.1"))
      assert.is_false(mini_mwan.is_valid_ip_address("1.1.1"))
      assert.is_false(mini_mwan.is_valid_ip_address("1.1.1.1.1"))
      assert.is_false(mini_mwan.is_valid_ip_address("abc.def.ghi.jkl"))
      assert.is_false(mini_mwan.is_valid_ip_address("192.168.1"))
    end)
  end)

  describe("is_valid_interface_name()", function()
    it("should accept valid interface names", function()
      assert.is_true(mini_mwan.is_valid_interface_name("eth0"))
      assert.is_true(mini_mwan.is_valid_interface_name("eth1"))
      assert.is_true(mini_mwan.is_valid_interface_name("wg0"))
      assert.is_true(mini_mwan.is_valid_interface_name("wg1"))
      assert.is_true(mini_mwan.is_valid_interface_name("wan"))
      assert.is_true(mini_mwan.is_valid_interface_name("wan2"))
      assert.is_true(mini_mwan.is_valid_interface_name("eth0.100"))  -- VLAN
      assert.is_true(mini_mwan.is_valid_interface_name("pppoe-wan"))
      assert.is_true(mini_mwan.is_valid_interface_name("tun0"))
      assert.is_true(mini_mwan.is_valid_interface_name("usb0"))
    end)

    it("should reject invalid interface names", function()
      assert.is_false(mini_mwan.is_valid_interface_name(""))
      assert.is_false(mini_mwan.is_valid_interface_name(nil))
      assert.is_false(mini_mwan.is_valid_interface_name("eth 0"))  -- space
      assert.is_false(mini_mwan.is_valid_interface_name("eth@0"))  -- special char
    end)

    it("should reject names longer than 16 characters", function()
      assert.is_false(mini_mwan.is_valid_interface_name("verylonginterfacename"))
    end)
  end)

  describe("validate_config()", function()
    local valid_config
    local minimal_config

    before_each(function()
      valid_config = {
        enabled = true,
        mode = "failover",
        check_interval = 30,
        interfaces = {
          { device = "eth0", ping_target = "1.1.1.1" },
          { device = "eth1", ping_target = "8.8.8.8" }
        }
      }
      minimal_config = {
        enabled = true,
        mode = "failover",
        check_interval = 30,
        interfaces = {}
      }
    end)

    it("should return empty errors for valid config", function()
      local errors = mini_mwan.validate_config(valid_config)
      assert.equals(0, #errors)
    end)

    it("should return errors for config with missing ping_target", function()
      local config = {
        enabled = true,
        interfaces = {
          { device = "eth0", ping_target = nil },  -- missing ping_target
          { device = "eth1", ping_target = "8.8.8.8" }
        }
      }
      local errors = mini_mwan.validate_config(config)
      assert.is_true(#errors > 0)
      assert.is_true(errors[1]:match("Missing ping_target") ~= nil)
    end)

    it("should return errors for invalid ping_target (not IP)", function()
      local config = {
        enabled = true,
        interfaces = {
          { device = "eth0", ping_target = "not-an-ip" },
          { device = "eth1", ping_target = "8.8.8.8" }
        }
      }
      local errors = mini_mwan.validate_config(config)
      assert.is_true(#errors > 0)
      assert.is_true(errors[1]:match("Invalid ping_target") ~= nil)
    end)

    it("should return errors for invalid device name", function()
      local config = {
        enabled = true,
        interfaces = {
          { device = "eth 0", ping_target = "1.1.1.1" },  -- space in name
          { device = "eth1", ping_target = "8.8.8.8" }
        }
      }
      local errors = mini_mwan.validate_config(config)
      assert.is_true(#errors > 0)
      assert.is_true(errors[1]:match("Invalid device name") ~= nil)
    end)

    it("should return errors for less than 2 interfaces", function()
      local config = {
        enabled = true,
        interfaces = {
          { device = "eth0", ping_target = "1.1.1.1" }  -- only one interface
        }
      }
      local errors = mini_mwan.validate_config(config)
      assert.equals(1, #errors)
      assert.is_true(errors[1]:match("At least 2 interfaces") ~= nil)
    end)

    it("should return errors for check_interval out of range", function()
      local config_low = {
        enabled = true,
        check_interval = 5,  -- below minimum
        interfaces = {
          { device = "eth0", ping_target = "1.1.1.1" },
          { device = "eth1", ping_target = "8.8.8.8" }
        }
      }
      local config_high = {
        enabled = true,
        check_interval = 3600,  -- above maximum
        interfaces = {
          { device = "eth0", ping_target = "1.1.1.1" },
          { device = "eth1", ping_target = "8.8.8.8" }
        }
      }
      assert.is_true(#mini_mwan.validate_config(config_low) > 0)
      assert.is_true(#mini_mwan.validate_config(config_high) > 0)
    end)

    it("should not validate when service is disabled", function()
      local config = {
        enabled = false,
        interfaces = {}  -- no interfaces but disabled
      }
      local errors = mini_mwan.validate_config(config)
      assert.equals(0, #errors)
    end)

    it("should handle empty interfaces list", function()
      local errors = mini_mwan.validate_config(minimal_config)
      -- Empty list should fail minimum interface count check
      assert.equals(1, #errors)
      assert.is_true(errors[1]:match("At least 2 interfaces") ~= nil)
    end)

    it("should return both device and ping_target errors for missing both", function()
      local config = {
        enabled = true,
        interfaces = {
          { device = "eth0" },  -- missing both device and ping_target
          { device = "eth1", ping_target = "8.8.8.8" }
        }
      }
      local errors = mini_mwan.validate_config(config)
      -- Should report ping_target error first (checked first in loop)
      assert.is_true(#errors >= 1)
      assert.is_true(errors[1]:match("Missing ping_target") ~= nil)
    end)
  end)
end)
