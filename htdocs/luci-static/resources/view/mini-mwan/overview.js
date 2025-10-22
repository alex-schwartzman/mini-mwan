'use strict';
'require view';
'require form';
'require uci';
'require ui';

return view.extend({
	load: function() {
		return uci.load('mini-mwan');
	},

	render: function() {
		var m, s, o;

		m = new form.Map('mini-mwan', _('Mini Multi-WAN'),
			_('Lightweight multi-WAN management for WireGuard VPN tunnels with failover and load balancing support.'));

		// Global settings section
		s = m.section(form.TypedSection, 'settings', _('Global Settings'));
		s.anonymous = true;
		s.addremove = false;

		o = s.option(form.Flag, 'enabled', _('Enable'),
			_('Enable Mini Multi-WAN service. At least two WAN interfaces must be configured.'));
		o.rmempty = false;
		o.default = '0';

		o = s.option(form.ListValue, 'mode', _('Mode'),
			_('Operating mode: failover (primary/backup) or multi-uplink (load balancing)'));
		o.value('failover', _('Failover (Primary/Backup)'));
		o.value('multiuplink', _('Multi-Uplink (Load Balancing)'));
		o.default = 'failover';
		o.rmempty = false;

		o = s.option(form.Value, 'check_interval', _('Check Interval'),
			_('How often to check WAN connectivity (seconds)'));
		o.datatype = 'range(10,3600)';
		o.default = '30';
		o.placeholder = '30';
		o.rmempty = false;

		// WAN Interfaces section
		s = m.section(form.GridSection, 'interface', _('WAN Interfaces'),
			_('Configure WAN interfaces for multi-WAN management. Typically WireGuard tunnels (wg0, wg1, etc).'));
		s.anonymous = false;
		s.addremove = true;
		s.nodescriptions = true;
		s.sortable = true;

		s.modaltitle = function(section_id) {
			return _('WAN Interface') + ' » ' + section_id;
		};

		s.addremove = true;
		s.addtitle = _('Add WAN Interface');

		// Validation for duplicate devices
		s.validate = function(section_id) {
			var device = this.cfgsections().map(function(sid) {
				return uci.get('mini-mwan', sid, 'device');
			});

			var seen = {};
			for (var i = 0; i < device.length; i++) {
				if (device[i] && seen[device[i]]) {
					return _('Duplicate device "%s" found. Each interface must use a unique device.').format(device[i]);
				}
				if (device[i]) seen[device[i]] = true;
			}
			return true;
		};

		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = '1';
		o.editable = true;
		o.rmempty = false;

		o = s.option(form.Value, 'device', _('Device'),
			_('Network interface device (e.g., wg0, wg1, eth1)'));
		o.rmempty = false;
		o.placeholder = 'wg0';

		o = s.option(form.Value, 'metric', _('Metric'),
			_('Route metric (lower = higher priority)'));
		o.datatype = 'range(1,255)';
		o.default = '10';
		o.rmempty = false;

		o = s.option(form.Value, 'weight', _('Weight'),
			_('Traffic distribution weight (multi-uplink mode)'));
		o.datatype = 'range(1,10)';
		o.default = '3';
		o.rmempty = false;

		o = s.option(form.Value, 'ping_target', _('Ping Target'),
			_('IP address to ping for connectivity check'));
		o.datatype = 'ipaddr';
		o.rmempty = false;
		o.placeholder = '1.1.1.1';
		o.validate = function(section_id, value) {
			if (!value) return true;

			// Check for duplicate ping targets
			var sections = uci.sections('mini-mwan', 'interface');
			for (var i = 0; i < sections.length; i++) {
				if (sections[i]['.name'] !== section_id &&
				    sections[i].ping_target === value) {
					return _('Ping target "%s" is already used by another interface').format(value);
				}
			}
			return true;
		};

		o = s.option(form.Value, 'ping_count', _('Ping Count'),
			_('Number of ping attempts'));
		o.datatype = 'range(1,10)';
		o.default = '3';
		o.placeholder = '3';
		o.optional = true;

		o = s.option(form.Value, 'ping_timeout', _('Timeout'),
			_('Ping timeout (seconds)'));
		o.datatype = 'range(1,10)';
		o.default = '2';
		o.placeholder = '2';
		o.optional = true;

		return m.render();
	}
});
