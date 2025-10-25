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

		o = s.option(form.Flag, 'enabled', _('config.settings.enabled.name'),
			_('config.settings.enabled.description'));
		o.rmempty = false;
		o.default = '0';

		o = s.option(form.ListValue, 'mode', _('config.settings.mode.name'),
			_('config.settings.mode.description'));
		o.value('failover', _('config.settings.mode.failover'));
		o.value('multiuplink', _('config.settings.mode.multiuplink'));
		o.default = 'failover';
		o.rmempty = false;

		o = s.option(form.Value, 'check_interval', _('config.settings.check_interval.name'),
			_('config.settings.check_interval.description'));
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
					return _('luci.errors.duplicate.device').format(device[i]);
				}
				if (device[i]) seen[device[i]] = true;
			}
			return true;
		};

		o = s.option(form.Flag, 'enabled', _('config.interface.enabled.name'),
			_('config.interface.enabled.description'));
		o.default = '1';
		o.editable = true;
		o.rmempty = false;

		o = s.option(form.Value, 'device', _('config.interface.device.name'),
			_('config.interface.device.description'));
		o.rmempty = false;
		o.placeholder = 'wg0';

		o = s.option(form.Value, 'metric', _('config.interface.metric.name'),
			_('config.interface.metric.description'));
		o.datatype = 'range(1,255)';
		o.default = '10';
		o.rmempty = false;

		o = s.option(form.Value, 'weight', _('config.interface.weight.name'),
			_('config.interface.weight.description'));
		o.datatype = 'range(1,10)';
		o.default = '3';
		o.rmempty = false;

		o = s.option(form.Value, 'ping_target', _('config.interface.ping_target.name'),
			_('config.interface.ping_target.description'));
		o.datatype = 'ipaddr';
		o.rmempty = false;
		o.modalonly = true;
		o.placeholder = '1.1.1.1';
		o.validate = function(section_id, value) {
			if (!value) return true;

			// Check for duplicate ping targets
			var sections = uci.sections('mini-mwan', 'interface');
			for (var i = 0; i < sections.length; i++) {
				if (sections[i]['.name'] !== section_id &&
				    sections[i].ping_target === value) {
					return _('luci.errors.duplicate.ping.target').format(value);
				}
			}
			return true;
		};

		o = s.option(form.Value, 'ping_count', _('config.interface.ping_count.name'),
			_('config.interface.ping_count.description'));
		o.datatype = 'range(1,10)';
		o.default = '3';
		o.placeholder = '3';
		o.optional = true;
		o.modalonly = true;

		o = s.option(form.Value, 'ping_timeout', _('config.interface.ping_timeout.name'),
			_('config.interface.ping_timeout.description'));
		o.datatype = 'range(1,10)';
		o.default = '2';
		o.placeholder = '2';
		o.optional = true;
		o.modalonly = true;

		return m.render();
	}
});
