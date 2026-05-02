--[[
Unit Tests for Interface Routing Class Computation

Requirement: FR-1.6 - Interface Classification
Priority: High
Description: System SHALL compute the correct routing class based on kernel state,
             routing info availability, and ping connectivity.
]]

local mocks = require("spec.helpers.mocks")

describe("FR-1.6: Interface Routing Class - compute_routing_class()", function()
  local mini_mwan

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")
  end)

  local function eth0_cfg()
    return { device = "eth0", metric = 1, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2 }
  end

  local function fresh_state(overrides)
    local s = { does_exist = false, routing_class = nil, alive = nil,
                latency = "?", status_since = nil, gateway = nil, point_to_point = false }
    for k, v in pairs(overrides or {}) do s[k] = v end
    return s
  end

  describe("Regular interface without gateway (DHCP incomplete)", function()
    it("should return 'unconfigured'", function()
      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
      })
      mini_mwan.set_dependencies(mocks.build_deps({ exec = exec_mock }))

      assert.equals("unconfigured", mini_mwan.compute_routing_class(eth0_cfg(), fresh_state()))
    end)
  end)

  describe("P2P interface without gateway", function()
    it("should NOT return 'unconfigured' (gateway is irrelevant for P2P)", function()
      local wg0_cfg = { device = "wg0", metric = 1, ping_target = "10.0.0.1", ping_count = 3, ping_timeout = 2 }
      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev wg0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev wg0"] = "",
        ["ping.*wg0"] = mocks.mock_ping_success(50.0),
      })
      mini_mwan.set_dependencies(mocks.build_deps({ exec = exec_mock }))

      local result = mini_mwan.compute_routing_class(wg0_cfg, fresh_state({ point_to_point = true }))
      assert.equals("usable", result)
    end)

    it("should allow route setting without gateway", function()
      mini_mwan.set_dependencies(mocks.build_deps())

      mini_mwan.enforce_route_state(
        { cfg = { device = "wg0", metric = 1 }, state = { gateway = nil, point_to_point = true } },
        1
      )

      mocks.assert_p2p_route_set("wg0", 1)
    end)
  end)

  describe("Interface with global IPv6 address", function()
    it("should return 'unconfigured' (IPv6 not supported)", function()
      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "inet6 fe80::1/64 scope global",
      })
      mini_mwan.set_dependencies(mocks.build_deps({ exec = exec_mock }))

      local result = mini_mwan.compute_routing_class(eth0_cfg(), fresh_state({ gateway = "192.168.1.1" }))
      assert.equals("unconfigured", result)
    end)
  end)

  describe("Regular interface with gateway and connectivity", function()
    it("should return 'usable'", function()
      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.5),
      })
      mini_mwan.set_dependencies(mocks.build_deps({ exec = exec_mock }))

      local result = mini_mwan.compute_routing_class(eth0_cfg(), fresh_state({ gateway = "192.168.1.1" }))
      assert.equals("usable", result)
    end)
  end)

  describe("Auto-recovery: gateway appears after being unconfigured", function()
    it("should return 'usable'", function()
      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_success(10.5),
      })
      mini_mwan.set_dependencies(mocks.build_deps({ exec = exec_mock }))

      local state = fresh_state({ routing_class = "unconfigured", gateway = "192.168.1.1" })
      local result = mini_mwan.compute_routing_class(eth0_cfg(), state)
      assert.equals("usable", result)
    end)
  end)

  describe("Interface with kernel UP but no connectivity", function()
    it("should return 'probe_only'", function()
      local exec_mock = mocks.build_exec_mock({
        ["ip addr show dev eth0"] = mocks.mock_interface_up(),
        ["ip %-6 addr show dev eth0"] = "",
        ["ping.*eth0"] = mocks.mock_ping_failure(),
      })
      mini_mwan.set_dependencies(mocks.build_deps({ exec = exec_mock }))

      local result = mini_mwan.compute_routing_class(eth0_cfg(), fresh_state({ gateway = "192.168.1.1" }))
      assert.equals("probe_only", result)
    end)
  end)
end)
