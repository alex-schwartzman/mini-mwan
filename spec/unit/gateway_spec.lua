--[[
Unit Tests for Gateway Discovery

Requirement: FR-1.3 - Gateway Discovery
Priority: Critical
Description: System SHALL automatically discover gateway addresses for managed interfaces
]]

local mocks = require("spec.helpers.mocks")

describe("FR-1.3: Gateway Discovery", function()
	local mini_mwan

	before_each(function()
		-- Reset mocks before each test
		mocks.reset()

		mini_mwan = require("mini-mwan.files.mini-mwan")
	end)

	describe("when interface has default route with gateway", function()
		it("should extract gateway from ubus network.interface dump", function()
			-- GIVEN: ubus returns valid gateway info for device
			local exec_mock = mocks.build_exec_mock({})

			local deps = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "eth0", gateway = "192.168.1.1" }
					})
				 })
			mini_mwan.set_dependencies(deps)

			-- WHEN: Probing all gateways
			local gateway_map = mini_mwan.probe_all_gateways()

			-- THEN: Should return correct gateway for eth0
			assert.equals("192.168.1.1", gateway_map["eth0"])
		end)
	end)

	describe("when interface is point-to-point (no gateway)", function()
		it("should not include device in gateway map", function()
			-- GIVEN: P2P interface (VPN tunnel) with no gateway in ubus dump
			local exec_mock = mocks.build_exec_mock({})

			local deps = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "wg0", gateway = nil }
					})
				 })
			mini_mwan.set_dependencies(deps)

			-- WHEN: Probing all gateways
			local gateway_map = mini_mwan.probe_all_gateways()

			-- THEN: Should not include wg0 in map (no gateway)
			assert.is_nil(gateway_map["wg0"])
		end)
	end)

	describe("when ubus returns empty response", function()
		it("should return empty map", function()
			-- GIVEN: No output from ubus
			local exec_mock = mocks.build_exec_mock({})

			local deps = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({})
				 })
			mini_mwan.set_dependencies(deps)

			-- WHEN: Probing all gateways
			local gateway_map = mini_mwan.probe_all_gateways()

			-- THEN: Should return empty map
			assert.is_table(gateway_map)
			assert.equals(0, #gateway_map)
		end)
	end)

	describe("when multiple routes exist", function()
		it("should extract only default route (0.0.0.0/0)", function()
			-- GIVEN: Multiple routes including default in ubus dump
			local exec_mock = mocks.build_exec_mock({})

			local deps = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = {
					interface = {
						{
							l3_device = "eth0",
							route = {
								{
									target = "192.168.1.0",
									mask = 24,
									nexthop = "192.168.1.254"
								},
								{
									target = "0.0.0.0",
									mask = 0,
									nexthop = "192.168.1.1"
								}
							}
						}
					}
				}
			})
			mini_mwan.set_dependencies(deps)

			-- WHEN: Probing all gateways
			local gateway_map = mini_mwan.probe_all_gateways()

			-- THEN: Should return default route gateway only
			assert.equals("192.168.1.1", gateway_map["eth0"])
		end)
	end)

	describe("when multiple interfaces exist", function()
		it("should return gateways for all interfaces", function()
			local exec_mock = mocks.build_exec_mock({})

			local deps = mocks.build_deps({
				exec = exec_mock,
				-- GIVEN: Multiple interfaces with different gateways
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "eth0", gateway = "192.168.1.1" },
					{ l3_device = "eth1", gateway = "192.168.2.1" },
					{ l3_device = "wg0", gateway = nil }
					})
				 })
			mini_mwan.set_dependencies(deps)

			-- WHEN: Probing all gateways
			local gateway_map = mini_mwan.probe_all_gateways()

			-- THEN: Should return gateways for interfaces that have them
			assert.equals("192.168.1.1", gateway_map["eth0"])
			assert.equals("192.168.2.1", gateway_map["eth1"])
			assert.is_nil(gateway_map["wg0"])  -- P2P has no gateway
		end)
	end)
end)
