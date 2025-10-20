-- CBI model for mini-mwan configuration

local m, s, o

m = Map("mini-mwan", translate("Mini-MWAN Configuration"),
    translate("Configure Mini Multi-WAN management settings"))

s = m:section(TypedSection, "mini-mwan", translate("General Settings"))
s.anonymous = true
s.addremove = false

-- Enable/Disable option
o = s:option(Flag, "enabled", translate("Enable"),
    translate("Enable or disable the mini-mwan service"))
o.rmempty = false
o.default = "0"

-- Check interval option
o = s:option(Value, "check_interval", translate("Check Interval"),
    translate("Interval in seconds to check WAN connections"))
o.datatype = "range(5,3600)"
o.default = "30"
o.placeholder = "30"
o.rmempty = false

return m
