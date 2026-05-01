--[[
Unit Tests for Latency Measurement

Requirement: FR-1.4 - Latency Measurement
Priority: Medium
Description: System SHALL measure average round-trip latency for each interface
]]

local mocks = require("spec.helpers.mocks")

describe("FR-1.4: Latency Measurement", function()
  local mini_mwan

  before_each(function()
    mocks.reset()
    mini_mwan = require("mini-mwan.files.mini-mwan")
  end)

  describe("check_ping() latency parsing", function()
    it("should extract average latency from successful ping output", function()
      -- GIVEN: Successful ping with avg latency 82.154ms (real OpenWrt format)
      local ping_output = [[
PING 1.1.1.1 (1.1.1.1): 56 data bytes
64 bytes from 1.1.1.1: seq=0 ttl=57 time=81.305 ms
64 bytes from 1.1.1.1: seq=1 ttl=57 time=83.003 ms

--- 1.1.1.1 ping statistics ---
2 packets transmitted, 2 packets received, 0% packet loss
round-trip min/avg/max = 81.305/82.154/83.003 ms
]]

      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = ping_output }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("1.1.1.1", 2, 2, "eth0")

      -- THEN: Should succeed and extract average latency
      assert.is_true(success)
      assert.equals("82.154", latency)
    end)

    it("should extract latency with high precision", function()
      -- GIVEN: Ping with precise latency value
      local ping_output = [[
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: seq=0 ttl=56 time=23.456 ms
64 bytes from 8.8.8.8: seq=1 ttl=56 time=23.457 ms
64 bytes from 8.8.8.8: seq=2 ttl=56 time=23.458 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 23.456/23.457/23.458 ms
]]

      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = ping_output }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("8.8.8.8", 3, 2, "eth0")

      -- THEN: Should extract precise latency
      assert.is_true(success)
      assert.equals("23.457", latency)
    end)

    it("should extract latency with low single-digit value", function()
      -- GIVEN: Ping with low latency (LAN)
      local ping_output = [[
PING 192.168.1.1 (192.168.1.1): 56 data bytes
64 bytes from 192.168.1.1: seq=0 ttl=64 time=0.823 ms
64 bytes from 192.168.1.1: seq=1 ttl=64 time=0.901 ms
64 bytes from 192.168.1.1: seq=2 ttl=64 time=1.045 ms

--- 192.168.1.1 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 0.823/0.923/1.045 ms
]]

      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = ping_output }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("192.168.1.1", 3, 2, "eth0")

      -- THEN: Should extract low latency correctly
      assert.is_true(success)
      assert.equals("0.923", latency)
    end)

    it("should extract latency with high value (triple digits)", function()
      -- GIVEN: Ping with high latency (satellite or congested connection)
      local ping_output = [[
PING 8.8.8.8 (8.8.8.8): 56 data bytes
64 bytes from 8.8.8.8: seq=0 ttl=56 time=250.123 ms
64 bytes from 8.8.8.8: seq=1 ttl=56 time=251.456 ms
64 bytes from 8.8.8.8: seq=2 ttl=56 time=252.789 ms

--- 8.8.8.8 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 250.123/251.456/252.789 ms
]]

      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = ping_output }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("8.8.8.8", 3, 2, "eth0")

      -- THEN: Should extract high latency correctly
      assert.is_true(success)
      assert.equals("251.456", latency)
    end)

    it("should extract integer latency values", function()
      -- GIVEN: Ping with integer latency (no decimal)
      local ping_output = [[
PING 1.1.1.1 (1.1.1.1): 56 data bytes
64 bytes from 1.1.1.1: seq=0 ttl=57 time=10 ms
64 bytes from 1.1.1.1: seq=1 ttl=57 time=11 ms
64 bytes from 1.1.1.1: seq=2 ttl=57 time=12 ms

--- 1.1.1.1 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
round-trip min/avg/max = 10/11/12 ms
]]

      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = ping_output }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("1.1.1.1", 3, 2, "eth0")

      -- THEN: Should extract integer latency
      assert.is_true(success)
      assert.equals("11", latency)
    end)
  end)

  describe("check_ping() failure handling", function()
    it("should return false and latency 0 when ping fails (0 packets received)", function()
      -- GIVEN: Failed ping (100% packet loss)
      local ping_output = [[
PING 1.1.1.1 (1.1.1.1): 56 data bytes

--- 1.1.1.1 ping statistics ---
3 packets transmitted, 0 received, 100% packet loss
]]

      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = ping_output }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("1.1.1.1", 3, 2, "eth0")

      -- THEN: Should fail with latency 0
      assert.is_false(success)
      assert.equals(0, latency)
    end)

    it("should return false and latency 0 when ping command produces no output", function()
      -- GIVEN: Ping command returns nil (command execution failed)
      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = nil }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("1.1.1.1", 3, 2, "eth0")

      -- THEN: Should fail with latency 0
      assert.is_false(success)
      assert.equals(0, latency)
    end)

    it("should return false and latency 0 when ping output is empty string", function()
      -- GIVEN: Empty output from ping
      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = "" }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("1.1.1.1", 3, 2, "eth0")

      -- THEN: Should fail with latency 0
      assert.is_false(success)
      assert.equals(0, latency)
    end)

    it("should succeed with partial packet loss (at least 1 packet received)", function()
      -- GIVEN: Ping with partial packet loss (2 out of 3 received)
      local ping_output = [[
PING 1.1.1.1 (1.1.1.1): 56 data bytes
64 bytes from 1.1.1.1: seq=0 ttl=57 time=15.234 ms
64 bytes from 1.1.1.1: seq=2 ttl=57 time=15.789 ms

--- 1.1.1.1 ping statistics ---
3 packets transmitted, 2 packets received, 33% packet loss
round-trip min/avg/max = 15.234/15.512/15.789 ms
]]

      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = ping_output }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("1.1.1.1", 3, 2, "eth0")

      -- THEN: Should succeed (at least one packet received) with average latency
      assert.is_true(success)
      assert.equals("15.512", latency)
    end)
  end)

  describe("check_ping() edge cases", function()
    it("should handle malformed output gracefully (missing statistics line)", function()
      -- GIVEN: Ping output without round-trip statistics (incomplete output)
      local ping_output = [[
PING 1.1.1.1 (1.1.1.1): 56 data bytes
64 bytes from 1.1.1.1: seq=0 ttl=57 time=12.5 ms

--- 1.1.1.1 ping statistics ---
3 packets transmitted, 3 packets received, 0% packet loss
]]

      local deps = mocks.build_deps({ exec = mocks.build_exec_mock({ ["ping.*"] = ping_output }) })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check
      local success, latency = mini_mwan.check_ping("1.1.1.1", 3, 2, "eth0")

      -- THEN: Should succeed (packets received) but latency will be nil
      assert.is_true(success)
      assert.is_nil(latency)
    end)

    it("should use correct ping command parameters", function()
      -- GIVEN: Mock that captures executed args
      local executed_args = nil
      local exec_mock = function(args)
        executed_args = args
        mocks.track_command(table.concat(args, " "))
        return mocks.mock_ping_success(10.0)
      end
      local deps = mocks.build_deps({ exec = exec_mock })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check with specific parameters
      mini_mwan.check_ping("8.8.8.8", 5, 3, "eth1")

      -- THEN: Args should have correct parameters
      assert.is_not_nil(executed_args)
      assert.equals("/bin/ping",    executed_args[1])
      assert.equals("-I",      executed_args[2])
      assert.equals("eth1",    executed_args[3])
      assert.equals("-c",      executed_args[4])
      assert.equals("5",       executed_args[5])
      assert.equals("-W",      executed_args[6])
      assert.equals("3",       executed_args[7])
      assert.equals("8.8.8.8", executed_args[10])
    end)

    it("should use default parameters when not specified", function()
      -- GIVEN: Mock that captures executed args
      local executed_args = nil
      local exec_mock = function(args)
        executed_args = args
        mocks.track_command(table.concat(args, " "))
        return mocks.mock_ping_success(10.0)
      end
      local deps = mocks.build_deps({ exec = exec_mock })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping check without count/timeout (nil parameters)
      mini_mwan.check_ping("1.1.1.1", nil, nil, "eth0")

      -- THEN: Args should use default values (count=3, timeout=2)
      assert.is_not_nil(executed_args)
      assert.equals("3", executed_args[5], "Should use default count of 3")
      assert.equals("2", executed_args[7], "Should use default timeout of 2")
    end)

    it("should calculate correct deadline parameter", function()
      -- GIVEN: Mock that captures executed args
      local executed_args = nil
      local exec_mock = function(args)
        executed_args = args
        mocks.track_command(table.concat(args, " "))
        return mocks.mock_ping_success(10.0)
      end
      local deps = mocks.build_deps({ exec = exec_mock })
      mini_mwan.set_dependencies(deps)

      -- WHEN: Running ping with count=5, timeout=4
      mini_mwan.check_ping("1.1.1.1", 5, 4, "eth0")

      -- THEN: Deadline should be (count * timeout) + 2 = (5 * 4) + 2 = 22
      assert.is_not_nil(executed_args)
      assert.equals("-w", executed_args[8])
      assert.equals("22", executed_args[9], "Deadline should be (5*4)+2 = 22")
    end)
  end)
end)
