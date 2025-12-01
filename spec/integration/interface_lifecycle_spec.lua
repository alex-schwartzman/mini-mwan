--[[
Integration Tests for Interface Lifecycle (Disappearance/Reappearance)

Requirement: FR-1.2, FR-5.1 - Interface State Detection and Event Logging
Priority: High
Description: System SHALL detect and log interface disappearance (USB dongle removed, tunnel down)
]]

local mocks = require("spec.helpers.mocks")

describe("Interface Lifecycle - Disappearance and Reappearance", function()
	local mini_mwan

	before_each(function()
		mocks.reset()
		mini_mwan = require("mini-mwan.files.mini-mwan")
	end)

	describe("Scenario: Interface disappears (USB dongle removed)", function()
		it("should detect and log interface disappearance with warning level", function()
			-- GIVEN: Interface that was UP in previous cycle
			local config = {
				mode = "failover",
				check_interval = 30,
				interfaces = {
					{ device = "usb0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
				}
			}

			-- First cycle: interface exists and is UP
			local exec_responses_cycle1 = {
				["ip addr show dev usb0"] = mocks.mock_interface_up(),
				["ip link show dev usb0"] = "3: usb0: <BROADCAST,MULTICAST,UP,LOWER_UP>",
				["ping.*usb0"] = mocks.mock_ping_success(15.0),
				["ip %-6 addr show dev usb0"] = "",
				["ip route show default dev usb0"] = "",
			}

			local exec_mock = mocks.build_exec_mock(exec_responses_cycle1)
			local deps, ubus_mock, log_mock = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "usb0", gateway = "192.168.1.1" }
					})
				})
			mini_mwan.set_dependencies(deps)

			-- Run first cycle
			mini_mwan.work(config)

			-- Reset log for second cycle
			log_mock.reset()

			-- Second cycle: interface disappeared (USB dongle removed)
			local exec_responses_cycle2 = {
				["ip addr show dev usb0"] = "Device \"usb0\" does not exist.",
				["ip link show dev usb0"] = "Device \"usb0\" does not exist.",
				["ip %-6 addr show dev usb0"] = "",
				["ip route show default"] = "",
			}

			exec_mock = mocks.build_exec_mock(exec_responses_cycle2)
			deps, ubus_mock, log_mock = mocks.build_deps({ exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "usb0", gateway = "192.168.1.1" }
					})
				})
			mini_mwan.set_dependencies(deps)

			-- WHEN: Running second cycle
			mini_mwan.work(config)

			-- THEN: Should log disappearance at warning level
			local warning_msgs = log_mock.get_messages_by_priority("warning")
			local found_disappeared = false

			for _, msg in ipairs(warning_msgs) do
				if msg.message:match("usb0") and msg.message:match("DISAPPEARED") then
					found_disappeared = true
					break
				end
			end

			assert.is_true(found_disappeared, "Should log interface disappearance at warning level")
		end)
	end)

	describe("Scenario: Interface reappears (USB dongle reconnected)", function()
		it("should detect and log interface reappearance with info level", function()
			-- GIVEN: Interface that didn't exist in previous cycle
			local config = {
				mode = "failover",
				check_interval = 30,
				interfaces = {
					{ device = "usb0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
				}
			}

			-- First cycle: interface doesn't exist
			local exec_responses_cycle1 = {
				["ip addr show dev usb0"] = "Device \"usb0\" does not exist.",
				["ip link show dev usb0"] = "Device \"usb0\" does not exist.",
				["ip %-6 addr show dev usb0"] = "",
				["ip route show default"] = "",
			}

			local exec_mock = mocks.build_exec_mock(exec_responses_cycle1)
			local deps, ubus_mock, log_mock = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "usb0", gateway = "192.168.1.1" }
					})
				})
			mini_mwan.set_dependencies(deps)

			-- Run first cycle
			mini_mwan.work(config)

			-- Reset log for second cycle
			log_mock.reset()

			-- Second cycle: interface reappeared (USB dongle reconnected)
			local exec_responses_cycle2 = {
				["ip addr show dev usb0"] = mocks.mock_interface_up(),
				["ip link show dev usb0"] = "3: usb0: <BROADCAST,MULTICAST,UP,LOWER_UP>",
				["ping.*usb0"] = mocks.mock_ping_success(15.0),
				["ip %-6 addr show dev usb0"] = "",
				["ip route show default dev usb0"] = "",
			}

			exec_mock = mocks.build_exec_mock(exec_responses_cycle2)
			deps, ubus_mock, log_mock = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "usb0", gateway = "192.168.1.1" }
					})
				})
			mini_mwan.set_dependencies(deps)

			-- WHEN: Running second cycle
			mini_mwan.work(config)

			-- THEN: Should log reappearance at info level
			local info_msgs = log_mock.get_messages_by_priority("info")
			local found_appeared = false

			for _, msg in ipairs(info_msgs) do
				if msg.message:match("usb0") and msg.message:match("APPEARED") then
					found_appeared = true
					break
				end
			end

			assert.is_true(found_appeared, "Should log interface reappearance at info level")
		end)
	end)

	describe("Scenario: VPN tunnel goes down and comes back up", function()
		it("should detect tunnel disappearance and reappearance", function()
			-- GIVEN: VPN tunnel interface
			local config = {
				mode = "failover",
				check_interval = 30,
				interfaces = {
					{ device = "wg0", metric = 10, ping_target = "10.0.0.1", ping_count = 3, ping_timeout = 2, enabled = true }
				}
			}

			-- First cycle: tunnel exists and is UP
			local exec_responses_cycle1 = {
				["ip addr show dev wg0"] = mocks.mock_interface_up(),
				["ip link show dev wg0"] = "5: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP>",
				["ping.*wg0"] = mocks.mock_ping_success(5.0),
				["ip %-6 addr show dev wg0"] = "",
				["ip route show default dev wg0"] = "",
			}

			local exec_mock = mocks.build_exec_mock(exec_responses_cycle1)
			local deps, ubus_mock, log_mock = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "wg0", gateway = nil } -- P2P, no gateway
					})
				})
			mini_mwan.set_dependencies(deps)

			-- Run first cycle
			mini_mwan.work(config)

			-- Reset log
			log_mock.reset()

			-- Second cycle: tunnel disappeared
			local exec_responses_cycle2 = {
				["ip addr show dev wg0"] = "Device \"wg0\" does not exist.",
				["ip link show dev wg0"] = "Device \"wg0\" does not exist.",
				["ip %-6 addr show dev wg0"] = "",
				["ip route show default"] = "",
			}

			exec_mock = mocks.build_exec_mock(exec_responses_cycle2)
			deps, ubus_mock, log_mock = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "wg0", gateway = nil }
					})
				 })
			mini_mwan.set_dependencies(deps)

			-- WHEN: Running second cycle
			mini_mwan.work(config)

			-- THEN: Should log tunnel disappearance
			local warning_msgs = log_mock.get_messages_by_priority("warning")
			local found_disappeared = false

			for _, msg in ipairs(warning_msgs) do
				if msg.message:match("wg0") and msg.message:match("DISAPPEARED") then
					found_disappeared = true
					break
				end
			end

			assert.is_true(found_disappeared, "Should log VPN tunnel disappearance")

			-- Reset log
			log_mock.reset()

			-- Third cycle: tunnel reappeared
			local exec_responses_cycle3 = {
				["ip addr show dev wg0"] = mocks.mock_interface_up(),
				["ip link show dev wg0"] = "5: wg0: <POINTOPOINT,NOARP,UP,LOWER_UP>",
				["ping.*wg0"] = mocks.mock_ping_success(5.0),
				["ip %-6 addr show dev wg0"] = "",
				["ip route show default dev wg0"] = "",
			}

			exec_mock = mocks.build_exec_mock(exec_responses_cycle3)
			deps, ubus_mock, log_mock = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "wg0", gateway = nil }
					})
				 })
			mini_mwan.set_dependencies(deps)

			-- WHEN: Running third cycle
			mini_mwan.work(config)

			-- THEN: Should log tunnel reappearance
			local info_msgs = log_mock.get_messages_by_priority("info")
			local found_appeared = false

			for _, msg in ipairs(info_msgs) do
				if msg.message:match("wg0") and msg.message:match("APPEARED") then
					found_appeared = true
					break
				end
			end

			assert.is_true(found_appeared, "Should log VPN tunnel reappearance")
		end)
	end)

	describe("Scenario: Interface state remains non-existent", function()
		it("should not log disappearance on every cycle once already disappeared", function()
			-- GIVEN: Interface that doesn't exist
			local config = {
				mode = "failover",
				check_interval = 30,
				interfaces = {
					{ device = "usb0", metric = 10, ping_target = "1.1.1.1", ping_count = 3, ping_timeout = 2, enabled = true }
				}
			}

			local exec_responses = {
				["ip addr show dev usb0"] = "Device \"usb0\" does not exist.",
				["ip link show dev usb0"] = "Device \"usb0\" does not exist.",
				["ip %-6 addr show dev usb0"] = "",
				["ip route show default"] = "",
			}

			local exec_mock = mocks.build_exec_mock(exec_responses)
			local deps, ubus_mock, log_mock = mocks.build_deps({
				exec = exec_mock,
				ubus_network_dump = mocks.mock_ubus_network_dump({
					{ l3_device = "usb0", gateway = "192.168.1.1" }
					})
				 })
			mini_mwan.set_dependencies(deps)

			-- Run first cycle
			mini_mwan.work(config)

			-- Reset log
			log_mock.reset()

			-- Run second cycle (interface still doesn't exist)
			exec_mock = mocks.build_exec_mock(exec_responses)
			deps, ubus_mock, log_mock = mocks.build_deps({ exec = exec_mock })
			mini_mwan.set_dependencies(deps)

			-- WHEN: Running second cycle
			mini_mwan.work(config)

			-- THEN: Should NOT log DISAPPEARED again (state didn't change)
			local warning_msgs = log_mock.get_messages_by_priority("warning")
			local found_disappeared = false

			for _, msg in ipairs(warning_msgs) do
				if msg.message:match("DISAPPEARED") then
					found_disappeared = true
					break
				end
			end

			assert.is_false(found_disappeared, "Should not log DISAPPEARED when state hasn't changed")
		end)
	end)
end)
