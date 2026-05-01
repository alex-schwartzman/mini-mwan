--[[
Unit Tests for WAN Configuration Counting

Requirement: FR-0.1 - Minimum WAN Configuration
Priority: Critical
Description: System SHALL refuse to operate with fewer than 2 configured WAN interfaces
]]

local mocks = require("spec.helpers.mocks")

describe("FR-0.1: WAN configuration counting", function()
  local mini_mwan

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")
  end)

  it("should return 0 when no interfaces configured", function()
    assert.equals(0, mini_mwan.count_wans_configured({ interfaces = {} }))
  end)

  it("should return 0 when interfaces list is absent", function()
    assert.equals(0, mini_mwan.count_wans_configured({}))
  end)

  it("should return 1 when only one interface has a device", function()
    local config = { interfaces = {
      { device = "eth0" },
    }}
    assert.equals(1, mini_mwan.count_wans_configured(config))
  end)

  it("should return 2 when two interfaces have devices", function()
    local config = { interfaces = {
      { device = "eth0" },
      { device = "eth1" },
    }}
    assert.equals(2, mini_mwan.count_wans_configured(config))
  end)

  it("should not count interfaces with empty device string", function()
    local config = { interfaces = {
      { device = "" },
      { device = "eth1" },
    }}
    assert.equals(1, mini_mwan.count_wans_configured(config))
  end)

  it("should count non-contiguous configured interfaces", function()
    local config = { interfaces = {
      { device = "eth0" },
      { device = "" },
      { device = "eth2" },
    }}
    assert.equals(2, mini_mwan.count_wans_configured(config))
  end)

  it("should count three configured interfaces", function()
    local config = { interfaces = {
      { device = "eth0" },
      { device = "eth1" },
      { device = "eth2" },
    }}
    assert.equals(3, mini_mwan.count_wans_configured(config))
  end)
end)
