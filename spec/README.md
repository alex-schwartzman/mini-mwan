# Mini-MWAN Test Suite

This directory contains the test suite for Mini-MWAN using [busted](https://olivinelabs.com/busted/) testing framework.

## Prerequisites

Install testing dependencies:

```bash
# Install busted (testing framework)
luarocks install busted

# Install luacov (code coverage)
luarocks install luacov

# Install luacov-html (HTML coverage reports)
luarocks install cluacov
```

## Architecture: Config vs State Separation

Mini-MWAN follows a clean separation between **immutable configuration** and **mutable runtime state**, implementing an MVP (Model-View-Presenter) pattern:

### Config (Immutable - from UCI)
Read-only configuration loaded from `/etc/config/mini-mwan`:
- **Global settings**: `mode`, `check_interval`
- **Interface config fields**: `name`, `device`, `metric`, `weight`, `ping_target`, `ping_count`, `ping_timeout`, `enabled`, `point_to_point`

Config is **never modified** by mini-mwan at runtime. It can only be changed by UCI/LuCI.

### State (Mutable - ephemeral)
Runtime state discovered and measured by the daemon:
- `status` - Current interface status (up/down/disabled/interface_down)
- `status_since` - Timestamp when status last changed
- `latency` - Measured ping latency in milliseconds
- `gateway` - Discovered gateway address (via `ubus network.interface dump`)
- `degraded` - Whether interface has configuration issues (0 or 1)
- `degraded_reason` - Reason for degradation (no_gateway/ipv6_detected)
- `last_check` - Timestamp of last probe

State is **ephemeral** - it's rebuilt on every daemon loop iteration.

### Status (Published via ubus - for LuCI)
Status information is a **presentation layer** that merges config + state for display in LuCI. Mini-mwan publishes it via ubus (`mini-mwan.status` method) - the JSON format is consumed by LuCI and other monitoring tools.

### Key Functions
- `load_config()` → Returns immutable config from UCI
- `probe_state(config)` → Discovers/collects mutable state based on config
- `set_routes_for_failover(usable_ifaces)` → Sets routes in main table with configured metrics
- `set_route_multiuplink(usable_ifaces)` → Sets multipath route in main table
- `update_status(config, state)` → Merges both into global status object served via ubus

### Routing Table Scope

**Important:** Mini-mwan manages routes **only in the main routing table**.

- All `ip route` commands operate on the main table (default behavior)
- If you have policy-based routing with `ip rule` lookups into custom tables, those rules take **precedence** over mini-mwan's routes
- This is a **feature**: advanced users can use custom routing tables to bypass or override mini-mwan when needed

Example of policy routing overriding mini-mwan:
```bash
# Mini-mwan sets routes in main table
ip route show table main
# default via 192.168.1.1 dev eth0 metric 1

# But policy routing can override this
ip rule show
# 0:    from all lookup local
# 100:  from 10.0.0.0/24 lookup vpn_table  ← Takes precedence!
# 32766: from all lookup main
# 32767: from all lookup default
```

In this example, traffic from `10.0.0.0/24` will use the `vpn_table` routing table, completely bypassing mini-mwan's routes in the main table.

### Function Signature Pattern
All major functions follow this pattern:
```lua
-- Functions take both config and state as separate parameters
function handle_something(config, state)
    -- Read from config (immutable)
    local mode = config.mode

    -- Mutate state (mutable)
    state.interfaces[1].status = "up"

    -- Return modified state
    return state
end

-- Interface-level functions take individual config and state
function check_degradation(iface_cfg, iface_state)
    -- Read from config
    if not iface_cfg.point_to_point then
        -- Mutate state
        iface_state.degraded = 1
    end
end
```

## Test Structure

```
spec/
├── unit/              # Unit tests for individual functions
│   ├── gateway_spec.lua         # FR-1.3: Gateway discovery
│   ├── degradation_spec.lua     # FR-1.6: Degradation detection
│   └── ...
├── integration/       # End-to-end integration tests
│   ├── failover_spec.lua        # FR-2.1: Failover mode
│   ├── multiuplink_spec.lua     # FR-2.2: Multiuplink mode
│   └── ...
├── helpers/           # Reusable test helpers
│   └── mocks.lua                # Mock functions and assertions
└── README.md          # This file
```

## Running Tests

### Run all tests
```bash
busted
```

### Run unit tests only
```bash
busted --config=unit
```

### Run integration tests only
```bash
busted --config=integration
```

### Run specific test file
```bash
busted spec/unit/gateway_spec.lua
```

### Run with coverage
```bash
busted --coverage
luacov
cat luacov.report.out
```

### Run verbose
```bash
busted --verbose
```

### Run and show pending tests
```bash
busted --suppress-pending=false
```

## Writing Tests

### Unit Test Template

```lua
local mocks = require("spec.helpers.mocks")

describe("Feature: Your Feature Name", function()
	local mini_mwan

	before_each(function()
		mocks.reset()
		mini_mwan = require("mini-mwan.files.mini-mwan")
	end)

	it("should do something specific", function()
		-- GIVEN: Setup test conditions with config and state
		local iface_cfg = {
			device = "eth0",
			metric = 1,
			point_to_point = false
		}
		local iface_state = {
			gateway = "192.168.1.1",
			status = "unknown",
			degraded = 0,
			degraded_reason = "",
			latency = 0
		}

		local deps = mocks.build_deps({
			exec = mocks.build_exec_mock({
				["command pattern"] = "expected output"
			})
		})
		mini_mwan.set_dependencies(deps)

		-- WHEN: Execute the function under test
		mini_mwan.some_function(iface_cfg, iface_state)

		-- THEN: Assert expected behavior (state may be mutated)
		assert.equals("expected", iface_state.some_field)
	end)
end)
```

### Integration Test Template

```lua
local mocks = require("spec.helpers.mocks")

describe("Scenario: End-to-end test", function()
	local mini_mwan

	before_each(function()
		mocks.reset()
		mini_mwan = require("mini-mwan.files.mini-mwan")
	end)

	it("should handle complete workflow", function()
		-- GIVEN: Complete system with config and state
		local config = {
			mode = "failover",
			check_interval = 30,
			interfaces = {
				{
					device = "eth0",
					metric = 1,
					ping_target = "1.1.1.1",
					ping_count = 3,
					ping_timeout = 2,
					enabled = true,
					point_to_point = false
				}
			}
		}

		local state = {
			interfaces = {
				{
					gateway = "192.168.1.1",
					status = "unknown",
					degraded = 0,
					degraded_reason = "",
					latency = 0
				}
			}
		}

		local exec_mock = mocks.build_exec_mock({
			["ubus call network.interface dump"] = mocks.mock_ubus_with_gateway("eth0", "192.168.1.1"),
			["ping.*eth0"] = mocks.mock_ping_success(10.0),
			["ip addr show dev eth0"] = mocks.mock_interface_up(),
			["ip %-6 addr show dev eth0"] = ""  -- No IPv6
		})

		local deps = mocks.build_deps({ exec = exec_mock })
		mini_mwan.set_dependencies(deps)

		-- WHEN: Running complete mode handler
		state = mini_mwan.set_routes_for_failover(config, state)

		-- THEN: Verify routing commands
		mocks.assert_route_set("192.168.1.1", "eth0", 1)
	end)
end)
```

## Mock Helpers

The `spec/helpers/mocks.lua` module provides:

### Command Tracking
```lua
mocks.reset()                       -- Reset command history
mocks.track_command(cmd)            -- Track a command
mocks.find_commands(pattern)        -- Find commands matching pattern
mocks.was_executed(pattern)         -- Check if command was run
mocks.get_route_commands()          -- Get only route commands
```

### Mock Builders
```lua
-- Build exec mock with pattern-based responses
local exec_mock = mocks.build_exec_mock({
	["ubus call network.interface dump"] = mocks.mock_ubus_with_gateway("eth0", "192.168.1.1"),
	["ping.*eth0"] = "3 packets transmitted, 3 received"
})

-- Build complete dependency mock
local deps = mocks.build_deps({
	exec = custom_exec,
	time = function() return 1234567890 end
})
```

### Response Generators
```lua
mocks.mock_ping_success(12.5)                        -- Successful ping with latency
mocks.mock_ping_failure()                            -- Failed ping
mocks.mock_ubus_network_dump({...})                  -- ubus dump with multiple interfaces
mocks.mock_interface_up()                            -- Interface UP state
mocks.mock_interface_down()                          -- Interface DOWN state
```

### Assertions
```lua
mocks.assert_route_set("192.168.1.1", "eth0", 1)   -- Assert route was set
mocks.assert_p2p_route_set("wg0", 1)                -- Assert P2P route was set
mocks.assert_route_deleted("192.168.1.1", "eth0")  -- Assert route was deleted
```

## Requirements Traceability

Tests are tagged with requirement IDs in comments:

```lua
--[[
Requirement: FR-1.3 - Gateway Discovery
Priority: Critical
Description: System SHALL automatically discover gateway addresses
]]
```

This allows tracing tests back to requirements in `requirements/` directory.

### Generate Coverage Report

```bash
# Run tests with coverage
busted --coverage

# Generate report
luacov

# View coverage by file
cat luacov.report.out

# Generate HTML report (if cluacov installed)
luacov-html
open luacov-html/index.html
```

## Continuous Integration

For CI environments, use the `ci` configuration:

```bash
# Run tests with JSON output and coverage
busted --config=ci > test-results.json

# Check exit code
if [ $? -eq 0 ]; then
    echo "Tests passed"
else
    echo "Tests failed"
    exit 1
fi
```

## Best Practices

### 1. Keep Tests Independent
- Each test should be self-contained
- Use `before_each()` to reset state
- Don't rely on test execution order

### 2. Use Descriptive Names
```lua
-- Good
it("should mark regular interface without gateway as degraded", function() ... end)

-- Bad
it("test1", function() ... end)
```

### 3. Follow Given-When-Then Structure
```lua
it("should do something", function()
	-- GIVEN: Setup preconditions
	local config = { ... }

	-- WHEN: Execute action
	local result = function_under_test(config)

	-- THEN: Verify expectations
	assert.equals(expected, result)
end)
```

### 4. Test One Thing Per Test
```lua
-- Good: Focused test
it("should return gateway from ubus", function()
	local gateway_map = probe_all_gateways()
	assert.<TODO>
end)

-- Bad: Multiple unrelated assertions
it("should work", function()
	assert.equals(gateway, "192.168.1.1")
	assert.equals(status, "up")
	assert.equals(latency, 10.0)
	-- Too many responsibilities
end)
```

### 5. Use Mocks Appropriately
- Mock external dependencies (exec, file I/O, time)
- Don't mock the code you're testing
- Keep mocks simple and focused

## Troubleshooting

### "module 'mini-mwan.files.mini-mwan' not found"
- Ensure `.busted` has correct `lpath`
- Check file exists at `mini-mwan/files/mini-mwan.lua`
- Try absolute path in require

### Tests hang or timeout
- Check for infinite loops in code
- Ensure `deps.sleep` is mocked (don't actually sleep in tests)
- Use `--verbose` to see where it hangs

### Coverage reports empty
- Ensure `--coverage` flag is used
- Check `.busted` has `coverage = true`
- Run `luacov` after `busted` completes

## Next Steps

1. **Add more tests** for uncovered requirements
2. **Integrate into CI/CD** pipeline

## Resources

- [Busted Documentation](https://olivinelabs.com/busted/)
- [LuaCov Documentation](https://keplerproject.github.io/luacov/)
- [Mini-MWAN Requirements](../requirements/README.md)
- [Lua Testing Best Practices](http://olivinelabs.com/busted/#best-practices)
