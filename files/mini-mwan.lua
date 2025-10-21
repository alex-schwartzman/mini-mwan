#!/usr/bin/lua

--[[
Mini-MWAN Daemon
Manages multi-WAN failover and load balancing
]]--

local uci = require("uci")
local nixio = require("nixio")
local fs = require("nixio.fs")

-- Configuration
local cursor = uci.cursor()
local LOG_FILE = "/var/log/mini-mwan.log"
local STATUS_FILE = "/var/run/mini-mwan.status"

-- Logging function
local function log(msg)
	local timestamp = os.date("%Y-%m-%d %H:%M:%S")
	local log_msg = string.format("[%s] %s\n", timestamp, msg)

	-- Write to log file
	local f = io.open(LOG_FILE, "a")
	if f then
		f:write(log_msg)
		f:close()
	end

	-- Also write to syslog
	os.execute(string.format("logger -t mini-mwan '%s'", msg))
end

-- Execute command and capture output
local function exec(cmd)
	local handle = io.popen(cmd)
	if not handle then
		return nil, "Failed to execute command"
	end

	local output = handle:read("*a")
	handle:close()
	return output
end

-- Ping check function
local function check_ping(target, count, timeout)
	count = count or 3
	timeout = timeout or 2

	local cmd = string.format("ping -c %d -W %d %s 2>&1", count, timeout, target)
	local output = exec(cmd)

	if not output then
		return false, 0
	end

	-- Parse ping statistics
	local received = output:match("(%d+) received")
	if received and tonumber(received) > 0 then
		-- Parse average latency
		local avg_latency = output:match("min/avg/max[^=]+=.-/(.-)/")
		return true, tonumber(avg_latency) or 0
	end

	return false, 0
end

-- Get gateway for interface
local function get_gateway(iface)
	local cmd = string.format("ip route show dev %s | grep default | awk '{print $3}'", iface)
	local output = exec(cmd)
	if output then
		return output:match("(%S+)")
	end
	return nil
end

-- Add/update default route
local function set_route(gateway, metric, iface)
	-- Remove existing default route for this interface
	exec(string.format("ip route del default via %s dev %s 2>/dev/null", gateway, iface))

	-- Add new default route with metric
	local cmd = string.format("ip route add default via %s dev %s metric %d", gateway, iface, metric)
	local result = exec(cmd)

	log(string.format("Set route: gw=%s iface=%s metric=%d", gateway, iface, metric))
	return true
end

-- Remove default route
local function remove_route(gateway, iface)
	local cmd = string.format("ip route del default via %s dev %s 2>/dev/null", gateway, iface)
	exec(cmd)
	log(string.format("Removed route: gw=%s iface=%s", gateway, iface))
end

-- Load configuration
local function load_config()
	cursor:load("mini-mwan")

	local config = {
		enabled = cursor:get("mini-mwan", "settings", "enabled") == "1",
		mode = cursor:get("mini-mwan", "settings", "mode") or "failover",
		check_interval = tonumber(cursor:get("mini-mwan", "settings", "check_interval")) or 30,
		interfaces = {}
	}

	-- Load all interface configurations dynamically
	cursor:foreach("mini-mwan", "interface", function(section)
		local iface = {
			name = section['.name'],
			enabled = section.enabled == "1",
			device = section.device,
			metric = tonumber(section.metric) or 10,
			weight = tonumber(section.weight) or 3,
			ping_target = section.ping_target,
			ping_count = tonumber(section.ping_count) or 3,
			ping_timeout = tonumber(section.ping_timeout) or 2,
			status = "unknown",
			latency = 0,
			gateway = nil
		}

		if iface.device and iface.device ~= "" then
			iface.gateway = get_gateway(iface.device)
		end

		table.insert(config.interfaces, iface)
	end)

	return config
end

-- Write status file
local function write_status(config)
	local status = {
		timestamp = os.time(),
		mode = config.mode,
		interfaces = {}
	}

	for _, iface in ipairs(config.interfaces) do
		table.insert(status.interfaces, {
			name = iface.name,
			device = iface.device,
			status = iface.status,
			latency = iface.latency,
			gateway = iface.gateway
		})
	end

	local f = io.open(STATUS_FILE, "w")
	if f then
		f:write(string.format("mode=%s\n", config.mode))
		f:write(string.format("timestamp=%d\n", status.timestamp))
		for _, iface in ipairs(status.interfaces) do
			f:write(string.format("%s_status=%s\n", iface.name, iface.status))
			f:write(string.format("%s_latency=%.2f\n", iface.name, iface.latency))
			f:write(string.format("%s_gateway=%s\n", iface.name, iface.gateway or ""))
		end
		f:close()
	end
end

-- Failover mode logic
local function handle_failover(config)
	local primary = config.interfaces[1]
	local secondary = config.interfaces[2]

	-- Check both interfaces
	for _, iface in ipairs(config.interfaces) do
		if iface.enabled and iface.device and iface.ping_target and iface.gateway then
			local alive, latency = check_ping(iface.ping_target, iface.ping_count, iface.ping_timeout)
			iface.status = alive and "up" or "down"
			iface.latency = latency

			log(string.format("%s (%s): %s (latency: %.2fms)",
				iface.name, iface.device, iface.status, latency))
		else
			iface.status = "disabled"
		end
	end

	-- Manage routes based on status
	if primary.status == "up" then
		-- Primary is up, use it
		set_route(primary.gateway, primary.metric, primary.device)
		if secondary.status == "up" then
			-- Keep secondary as backup with higher metric
			set_route(secondary.gateway, secondary.metric, secondary.device)
		end
	elseif secondary.status == "up" then
		-- Primary is down, failover to secondary
		log("Primary WAN down, failing over to secondary")
		set_route(secondary.gateway, primary.metric, secondary.device)
	else
		-- Both down
		log("WARNING: Both WAN connections are down!")
	end
end

-- Multi-uplink mode logic
local function handle_multiuplink(config)
	local active_ifaces = {}

	-- Check all interfaces
	for _, iface in ipairs(config.interfaces) do
		if iface.enabled and iface.device and iface.ping_target and iface.gateway then
			local alive, latency = check_ping(iface.ping_target, iface.ping_count, iface.ping_timeout)
			iface.status = alive and "up" or "down"
			iface.latency = latency

			log(string.format("%s (%s): %s (latency: %.2fms)",
				iface.name, iface.device, iface.status, latency))

			if iface.status == "up" then
				table.insert(active_ifaces, iface)
			end
		else
			iface.status = "disabled"
		end
	end

	-- Setup load balancing routes
	if #active_ifaces > 0 then
		for _, iface in ipairs(active_ifaces) do
			set_route(iface.gateway, iface.metric, iface.device)
		end

		-- TODO: Implement proper multipath routing with weights
		-- This would require: ip route add default scope global nexthop via GW1 dev DEV1 weight W1 nexthop via GW2 dev DEV2 weight W2
	else
		log("WARNING: No active WAN connections!")
	end
end

-- Main daemon loop
local function main()
	log("Mini-MWAN daemon starting")

	while true do
		local config = load_config()

		if not config.enabled then
			log("Service disabled, waiting...")
			nixio.nanosleep(config.check_interval)
			goto continue
		end

		-- Validate configuration
		local wan1_configured = config.interfaces[1].device and config.interfaces[1].device ~= ""
		local wan2_configured = config.interfaces[2].device and config.interfaces[2].device ~= ""

		if not (wan1_configured and wan2_configured) then
			log("ERROR: Both WAN interfaces must be configured")
			nixio.nanosleep(config.check_interval)
			goto continue
		end

		-- Run appropriate mode
		if config.mode == "failover" then
			handle_failover(config)
		elseif config.mode == "multiuplink" then
			handle_multiuplink(config)
		end

		-- Write status
		write_status(config)

		::continue::
		nixio.nanosleep(config.check_interval)
	end
end

-- Signal handlers
local function cleanup()
	log("Mini-MWAN daemon stopping")
	os.exit(0)
end

-- Set up signal handlers
nixio.signal(15, cleanup) -- SIGTERM
nixio.signal(2, cleanup)  -- SIGINT

-- Run
main()
