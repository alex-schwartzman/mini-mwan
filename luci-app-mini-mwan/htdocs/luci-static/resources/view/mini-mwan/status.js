'use strict';
'require view';
'require rpc';
'require ui';
'require poll';

var callMiniMwanStatus = rpc.declare({
	object: 'mini-mwan',
	method: 'status',
	expect: { }
});

return view.extend({
	load: function() {
		return callMiniMwanStatus().catch(function(err) {
			return null;
		});
	},

	parseStatus: function(data) {
		if (!data) return null;

		// Data is already JSON from ubus, just add name field to interfaces
		var status = {
			mode: data.mode || '',
			timestamp: data.timestamp || 0,
			check_interval: data.check_interval || 30,
			interfaces: []
		};

		// Map interfaces and add 'name' field (device becomes name for UI)
		if (data.interfaces) {
			for (var i = 0; i < data.interfaces.length; i++) {
				var iface = data.interfaces[i];
				status.interfaces.push({
					name:          iface.device,
					device:        iface.device,
					routing_class: iface.routing_class || 'absent',
					status_since:  iface.status_since || '',
					last_check:    iface.last_check || '',
					latency:       iface.latency || 0,
					gateway:       iface.gateway || '',
					ping_target:   iface.ping_target || '',
					rx_bytes:      iface.rx_bytes || 0,
					tx_bytes:      iface.tx_bytes || 0
				});
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

	formatBytes: function(bytes) {
		if (!bytes || bytes === 0) return _('None');

		var units = [_('B'), _('KB'), _('MB'), _('GB'), _('TB')];
		var k = 1024;
		var i = Math.floor(Math.log(bytes) / Math.log(k));

		if (i >= units.length) i = units.length - 1;

		return (bytes / Math.pow(k, i)).toFixed(2) + ' ' + units[i];
	},

	formatTimestamp: function(timestamp) {
		if (!timestamp || timestamp === '') return 'Never';
		var d = new Date(parseInt(timestamp) * 1000);
		return d.toLocaleString();
	},

	getStatusBadge: function(iface) {
		var badges = {
			'absent':       '<span style="color: #f44336; font-weight: bold;">✖ '  + _('Not Found')      + '</span>',
			'down':         '<span style="color: #f44336; font-weight: bold;">↓ '  + _('Down')           + '</span>',
			'unconfigured': '<span style="color: #FF9800; font-weight: bold;">⚠ '  + _('Unconfigured')   + '</span>',
			'probe_only':   '<span style="color: #FF9800; font-weight: bold;">⚠ '  + _('No Connectivity')+ '</span>',
			'usable':       '<span style="color: #4CAF50; font-weight: bold;">● '  + _('UP')             + '</span>',
		};
		return badges[iface.routing_class] || badges['absent'];
	},

	getRowStyle: function(iface) {
		var rc = iface.routing_class;
		if (rc === 'absent' || rc === 'down')         return 'background-color: #ffebee;';
		if (rc === 'unconfigured' || rc === 'probe_only') return 'background-color: #fff9c4;';
		return '';
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
					E('td', {}, E('strong', {}, _('Last status check of WAN interfaces:'))),
					E('td', {}, this.formatTimestamp(status.timestamp))
				])
			])
		]);
		html.appendChild(globalInfo);

		// Interface status table
		var table = E('table', { 'class': 'table cbi-section-table' }, [
			E('tr', { 'class': 'tr table-titles' }, [
				E('th', { 'class': 'th' }, _('Device')),
				E('th', { 'class': 'th' }, _('Status')),
				E('th', { 'class': 'th' }, _('Since')),
				E('th', { 'class': 'th' }, _('Latency')),
				E('th', { 'class': 'th' }, _('Traffic (RX/TX)')),
				E('th', { 'class': 'th' }, _('Ping Target')),
				E('th', { 'class': 'th' }, _('Gateway')),
				E('th', { 'class': 'th' }, _('Last Check'))
			])
		]);

		for (var i = 0; i < status.interfaces.length; i++) {
			var iface = status.interfaces[i];

			var rx = this.formatBytes(parseInt(iface.rx_bytes) || 0);
			var tx = this.formatBytes(parseInt(iface.tx_bytes) || 0);
			var traffic = rx + ' / ' + tx;

			var rowStyle = this.getRowStyle(iface);

			table.appendChild(E('tr', { 'class': 'tr', 'style': rowStyle }, [
				E('td', { 'class': 'td' }, E('strong', {}, iface.name)),  // name is now the device name
				E('td', { 'class': 'td' }, E('span', {}, this.getStatusBadge(iface))),
				E('td', { 'class': 'td' }, this.formatTimestamp(iface.status_since)),
				E('td', { 'class': 'td' }, iface.latency ? parseFloat(iface.latency).toFixed(2) + ' ms' : '-'),
				E('td', { 'class': 'td' }, traffic),
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
			return callMiniMwanStatus().then(L.bind(function(data) {
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
