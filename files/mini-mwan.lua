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

-- Ping check function through specific interface
local function check_ping(target, count, timeout, device, gateway)
	count = count or 3
	timeout = timeout or 2

	-- Ping through specific interface using source routing
	-- Use -I to specify interface
	local cmd = string.format("ping -I %s -c %d -W %d %s 2>&1", device, count, timeout, target)
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
			status_since = nil,
			latency = 0,
			gateway = nil,
			last_check = nil
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
	local f = io.open(STATUS_FILE, "w")
	if f then
		f:write(string.format("mode=%s\n", config.mode))
		f:write(string.format("timestamp=%d\n", os.time()))
		f:write(string.format("check_interval=%d\n", config.check_interval))

		for _, iface in ipairs(config.interfaces) do
			f:write(string.format("\n[%s]\n", iface.name))
			f:write(string.format("device=%s\n", iface.device or ""))
			f:write(string.format("status=%s\n", iface.status))
			f:write(string.format("status_since=%s\n", iface.status_since or ""))
			f:write(string.format("last_check=%s\n", iface.last_check or ""))
			f:write(string.format("latency=%.2f\n", iface.latency))
			f:write(string.format("gateway=%s\n", iface.gateway or ""))
			f:write(string.format("ping_target=%s\n", iface.ping_target or ""))
		end
		f:close()
	end
end

-- Update interface status with timestamp tracking
local function update_interface_status(iface)
	if not (iface.enabled and iface.device and iface.ping_target) then
		iface.status = "disabled"
		iface.status_since = iface.status_since or os.time()
		iface.last_check = os.time()
		return
	end

	if not iface.gateway then
		iface.status = "no_gateway"
		iface.status_since = iface.status_since or os.time()
		iface.last_check = os.time()
		log(string.format("%s (%s): No gateway found", iface.name, iface.device))
		return
	end

	-- Ping through the specific interface
	local alive, latency = check_ping(iface.ping_target, iface.ping_count, iface.ping_timeout, iface.device, iface.gateway)
	local new_status = alive and "up" or "down"
	iface.last_check = os.time()

	-- Track status changes
	if iface.status ~= new_status then
		iface.status_since = os.time()
		log(string.format("%s (%s): Status changed from %s to %s",
			iface.name, iface.device, iface.status or "unknown", new_status))
	end

	iface.status = new_status
	iface.latency = latency

	log(string.format("%s (%s): %s (latency: %.2fms, ping via %s to %s)",
		iface.name, iface.device, iface.status, latency, iface.device, iface.ping_target))
end

-- Failover mode logic
local function handle_failover(config)
	-- Check all interfaces
	for _, iface in ipairs(config.interfaces) do
		update_interface_status(iface)
	end

	-- Sort by metric (lower = higher priority)
	local sorted_ifaces = {}
	for _, iface in ipairs(config.interfaces) do
		if iface.status == "up" then
			table.insert(sorted_ifaces, iface)
		end
	end
	table.sort(sorted_ifaces, function(a, b) return a.metric < b.metric end)

	if #sorted_ifaces == 0 then
		log("WARNING: No WAN connections are available!")
		return
	end

	-- Use the highest priority (lowest metric) interface as primary
	local primary = sorted_ifaces[1]
	set_route(primary.gateway, primary.metric, primary.device)
	log(string.format("Using %s (%s) as primary with metric %d", primary.name, primary.device, primary.metric))

	-- Set backup routes with their original metrics
	for i = 2, #sorted_ifaces do
		local backup = sorted_ifaces[i]
		set_route(backup.gateway, backup.metric, backup.device)
		log(string.format("Setting %s (%s) as backup with metric %d", backup.name, backup.device, backup.metric))
	end
end

-- Multi-uplink mode logic
local function handle_multiuplink(config)
	-- Check all interfaces
	for _, iface in ipairs(config.interfaces) do
		update_interface_status(iface)
	end

	-- Collect active interfaces
	local active_ifaces = {}
	for _, iface in ipairs(config.interfaces) do
		if iface.status == "up" then
			table.insert(active_ifaces, iface)
		end
	end

	if #active_ifaces == 0 then
		log("WARNING: No active WAN connections!")
		return
	end

	-- Setup routes with metrics for load balancing
	-- Linux kernel will use them based on metrics
	for _, iface in ipairs(active_ifaces) do
		set_route(iface.gateway, iface.metric, iface.device)
		log(string.format("Multi-uplink: %s (%s) metric %d weight %d",
			iface.name, iface.device, iface.metric, iface.weight))
	end

	-- TODO: Implement proper multipath routing with weights using:
	-- ip route add default scope global nexthop via GW1 dev DEV1 weight W1 nexthop via GW2 dev DEV2 weight W2
end

-- Main daemon loop
local function main()
	log("Mini-MWAN daemon starting")

	while true do
		local config = load_config()

		if config.enabled then
			-- Validate configuration
			local wan1_configured = config.interfaces[1] and config.interfaces[1].device and config.interfaces[1].device ~= ""
			local wan2_configured = config.interfaces[2] and config.interfaces[2].device and config.interfaces[2].device ~= ""

			if wan1_configured and wan2_configured then
				-- Run appropriate mode
				if config.mode == "failover" then
					handle_failover(config)
				elseif config.mode == "multiuplink" then
					handle_multiuplink(config)
				end

				-- Write status
				write_status(config)
			else
				log("ERROR: Both WAN interfaces must be configured")
			end
		else
			log("Service disabled, waiting...")
		end

		nixio.nanosleep(config.check_interval)
	end
end

-- Run daemon
-- Note: Signal handling is managed by procd, no custom handlers needed
main()
