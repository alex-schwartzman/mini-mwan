-- Controller for mini-mwan LuCI interface

module("luci.controller.mini-mwan", package.seeall)

function index()
    entry({"admin", "network", "mini-mwan"}, cbi("mini-mwan"), _("Mini-MWAN"), 60).dependent = false
end
