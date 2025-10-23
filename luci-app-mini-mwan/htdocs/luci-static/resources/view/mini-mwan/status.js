'use strict';
'require view';
'require fs';
'require ui';
'require poll';

return view.extend({
	load: function() {
		return fs.read('/var/run/mini-mwan.status').catch(function(err) {
			return '';
		});
	},

	parseStatus: function(data) {
		if (!data) return null;

		var status = {
			mode: '',
			timestamp: 0,
			check_interval: 30,
			interfaces: []
		};

		var current_iface = null;
		var lines = data.trim().split('\n');

		for (var i = 0; i < lines.length; i++) {
			var line = lines[i].trim();
			if (!line) continue;

			// Check for interface section
			var iface_match = line.match(/^\[(.+)\]$/);
			if (iface_match) {
				current_iface = {
					name: iface_match[1],
					device: '',
					status: 'unknown',
					status_since: '',
					last_check: '',
					latency: 0,
					gateway: '',
					ping_target: ''
				};
				status.interfaces.push(current_iface);
				continue;
			}

			// Parse key=value pairs
			var kv = line.split('=');
			if (kv.length !== 2) continue;

			var key = kv[0].trim();
			var value = kv[1].trim();

			if (current_iface) {
				// Interface property
				current_iface[key] = value;
			} else {
				// Global property
				if (key === 'timestamp') {
					status.timestamp = parseInt(value);
				} else if (key === 'check_interval') {
					status.check_interval = parseInt(value);
				} else {
					status[key] = value;
				}
			}
		}

		return status;
	},

	formatDuration: function(timestamp) {
		if (!timestamp || timestamp === '') return 'Unknown';

		var now = Math.floor(Date.now() / 1000);
		var then = parseInt(timestamp);
		var diff = now - then;

		if (diff < 60) return diff + ' seconds';
		if (diff < 3600) return Math.floor(diff / 60) + ' minutes';
		if (diff < 86400) return Math.floor(diff / 3600) + ' hours';
		return Math.floor(diff / 86400) + ' days';
	},

	formatTimestamp: function(timestamp) {
		if (!timestamp || timestamp === '') return 'Never';
		var d = new Date(parseInt(timestamp) * 1000);
		return d.toLocaleString();
	},

	getStatusBadge: function(status) {
		var badges = {
			'up': '<span style="color: #4CAF50; font-weight: bold;">● UP</span>',
			'down': '<span style="color: #f44336; font-weight: bold;">● DOWN</span>',
			'interface_down': '<span style="color: #FF9800;">⚠ Interface Down</span>',
			'disabled': '<span style="color: #9E9E9E;">○ Disabled</span>',
			'no_gateway': '<span style="color: #FF9800;">⚠ No Gateway</span>',
			'unknown': '<span style="color: #9E9E9E;">? Unknown</span>'
		};
		return badges[status] || badges['unknown'];
	},

	render: function(data) {
		var status = this.parseStatus(data);

		var html = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Mini-MWAN Status')),
			E('div', { 'class': 'cbi-section' }, [
				E('div', { 'class': 'cbi-section-descr' },
					_('Real-time monitoring of WAN interface status'))
			])
		]);

		if (!status || status.interfaces.length === 0) {
			html.appendChild(E('div', { 'class': 'alert-message warning' }, [
				E('p', {}, _('No status information available. Make sure the Mini-MWAN service is running.')),
				E('p', {}, _('Check with: ') + E('code', {}, '/etc/init.d/mini-mwan status'))
			]));
			return html;
		}

		// Global info
		var globalInfo = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Service Information')),
			E('table', { 'class': 'table' }, [
				E('tr', {}, [
					E('td', { 'style': 'width: 33%' }, E('strong', {}, _('Mode:'))),
					E('td', {}, status.mode === 'failover' ? _('Failover (Primary/Backup)') : _('Multi-Uplink (Load Balancing)'))
				]),
				E('tr', {}, [
					E('td', {}, E('strong', {}, _('Check Interval:'))),
					E('td', {}, status.check_interval + ' ' + _('seconds'))
				]),
				E('tr', {}, [
					E('td', {}, E('strong', {}, _('Last Update:'))),
					E('td', {}, this.formatTimestamp(status.timestamp))
				])
			])
		]);
		html.appendChild(globalInfo);

		// Interface status table
		var table = E('table', { 'class': 'table cbi-section-table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Interface')),
				E('th', { 'class': 'th' }, _('Device')),
				E('th', { 'class': 'th' }, _('Status')),
				E('th', { 'class': 'th' }, _('Since')),
				E('th', { 'class': 'th' }, _('Latency')),
				E('th', { 'class': 'th' }, _('Ping Target')),
				E('th', { 'class': 'th' }, _('Gateway')),
				E('th', { 'class': 'th' }, _('Last Check'))
			])
		]);

		for (var i = 0; i < status.interfaces.length; i++) {
			var iface = status.interfaces[i];

			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td' }, E('strong', {}, iface.name)),
				E('td', { 'class': 'td' }, iface.device || '-'),
				E('td', { 'class': 'td' }, E('span', {}, this.getStatusBadge(iface.status))),
				E('td', { 'class': 'td' }, this.formatTimestamp(iface.status_since)),
				E('td', { 'class': 'td' }, iface.latency ? parseFloat(iface.latency).toFixed(2) + ' ms' : '-'),
				E('td', { 'class': 'td' }, iface.ping_target || '-'),
				E('td', { 'class': 'td' }, E('code', {}, iface.gateway || '-')),
				E('td', { 'class': 'td' }, this.formatDuration(iface.last_check))
			]));
		}

		var interfaceSection = E('div', { 'class': 'cbi-section' }, [
			E('h3', {}, _('Interface Status')),
			table
		]);
		html.appendChild(interfaceSection);

		// Auto-refresh notice
		html.appendChild(E('div', { 'class': 'cbi-section' }, [
			E('em', {}, _('Status updates automatically every 5 seconds'))
		]));

		return html;
	},

	handleSaveApply: null,
	handleSave: null,
	handleReset: null,

	addFooter: function() {
		// Set up auto-refresh polling
		poll.add(L.bind(function() {
			return fs.read('/var/run/mini-mwan.status').then(L.bind(function(data) {
				var container = document.querySelector('.cbi-map');
				if (container) {
					var newContent = this.render(data);
					container.parentNode.replaceChild(newContent, container);
				}
			}, this)).catch(function(err) {
				// Silently ignore errors during refresh
			});
		}, this), 5);

		return E([]);
	}
});
