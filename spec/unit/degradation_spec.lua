--[[
Unit Tests for Degradation Detection

Requirement: FR-1.6 - Degradation Detection
Priority: High
Description: System SHALL detect configuration issues that prevent normal interface operation
]]

local mocks = require("spec.helpers.mocks")

describe("FR-1.6: Degradation Detection", function()
  local mini_mwan

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")
  end)

  describe("check_degradation()", function()
    local first_iface_cfg
    local first_iface_state

    before_each(function()
      -- Standard interface object
      first_iface_cfg = {
        device = "eth0",
        metric = 1,
      }
      first_iface_state = {
        gateway = nil,
        degraded = 0,
        degraded_reason = ""
      }
    end)

    describe("Requirement: Regular interface without gateway", function()
      it("should mark as degraded with reason 'no_gateway'", function()
        -- GIVEN: Regular interface with no gateway (DHCP incomplete)
        local deps = mocks.build_deps({})
        mini_mwan.set_dependencies(deps)

        -- WHEN: Checking degradation
        mini_mwan.check_degradation(first_iface_cfg, first_iface_state)

        -- THEN: Should be marked degraded
        assert.equals(1, first_iface_state.degraded)
        assert.equals("no_gateway", first_iface_state.degraded_reason)
      end)
    end)

    describe("Requirement: P2P interface without gateway", function()
      it("should NOT mark as degraded", function()
        -- GIVEN: P2P interface with no gateway (expected for VPN)
        local iface_cfg = {
          device = "wg0",
          }
        local iface_state = {
          gateway = nil,
          degraded = 0,
          degraded_reason = "",
          point_to_point = true  -- P2P interface (VPN/tunnel)
        }

        local deps = mocks.build_deps({})
        mini_mwan.set_dependencies(deps)

        -- WHEN: Checking degradation
        mini_mwan.check_degradation(iface_cfg, iface_state)

        -- THEN: Should NOT be degraded (normal for P2P)
        assert.equals(0, iface_state.degraded)
        assert.equals("", iface_state.degraded_reason)
      end)

      it("should allow route setting without gateway", function()
        -- GIVEN: P2P interface without gateway
        local iface_cfg = {
          device = "wg0",
          metric = 1,
          }
        local iface_state = {
          gateway = nil,
          degraded = 0,
        degraded_reason = "",
        point_to_point = true  -- P2P interface
        }

        local exec_mock = mocks.build_exec_mock({})
        local deps = mocks.build_deps({ exec = exec_mock })
        mini_mwan.set_dependencies(deps)

        -- WHEN: Setting route
        mini_mwan.set_route(iface_cfg, iface_state)

        -- THEN: Should create P2P route (no "via" clause)
        mocks.assert_p2p_route_set("wg0", 1)
      end)
    end)

    describe("Requirement: Interface with IPv6 address", function()
      it("should mark as degraded with reason 'ipv6_detected'", function()
        -- GIVEN: Interface with IPv6 address
        first_iface_state.gateway= "192.168.1.1"  -- Has IPv4 gateway

        -- Simulate IPv6 address found (note: %-6 escapes the dash)
        local exec_mock = mocks.build_argvexec_mock({
          ["ip %-6 addr show dev eth0"] = "inet6 fe80::1/64 scope global"
        })
        local deps = mocks.build_deps({ argvexec = exec_mock })
        mini_mwan.set_dependencies(deps)

        -- WHEN: Checking degradation
        local result_state = mini_mwan.check_degradation(first_iface_cfg, first_iface_state)

        -- THEN: Should be degraded (IPv6 not supported)
        assert.equals(1, result_state.degraded)
        assert.equals("ipv6_detected", result_state.degraded_reason)
      end)
    end)

    describe("Requirement: Regular interface with gateway", function()
      it("should NOT mark as degraded", function()
        -- GIVEN: Regular interface with gateway (healthy, no IPv6)
        first_iface_state.gateway = "192.168.1.1"

        -- Mock no IPv6
        local exec_mock = function(cmd)
          return ""  -- No IPv6 found
        end
        local deps = mocks.build_deps({ exec = exec_mock })
        mini_mwan.set_dependencies(deps)

        -- WHEN: Checking degradation
        local result_state = mini_mwan.check_degradation(first_iface_cfg, first_iface_state)

        -- THEN: Should be healthy
        assert.equals(0, result_state.degraded)
        assert.equals("", result_state.degraded_reason)
      end)
    end)

    describe("Requirement: Auto-recovery from degraded state", function()
      it("should clear degraded flag when gateway appears", function()
        -- GIVEN: Interface was degraded but now has gateway
        local iface_state = {
          gateway = "192.168.1.1",  -- Gateway now available
          degraded = 1,
          degraded_reason = "no_gateway"
        }

        -- Mock no IPv6
        local exec_mock = function(cmd)
          return ""  -- No IPv6 found
        end
        local deps = mocks.build_deps({ exec = exec_mock })
        mini_mwan.set_dependencies(deps)

        -- WHEN: Checking degradation again
        local result_state = mini_mwan.check_degradation(first_iface_cfg, iface_state)

        -- THEN: Should be healthy now (auto-recovered)
        assert.equals(0, result_state.degraded)
        assert.equals("", result_state.degraded_reason)
      end)
    end)
  end)
end)
