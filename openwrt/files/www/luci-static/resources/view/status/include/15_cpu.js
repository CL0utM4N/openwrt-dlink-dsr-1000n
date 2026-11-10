'use strict';
'require baseclass';
'require fs';

/*
 * Overview: CPU usage, from the kernel's /proc/stat counters.
 * Usage is measured between two refreshes of the overview page (it polls every few
 * seconds); on the first load it samples twice, half a second apart.
 * "Network (softirq)" is time the kernel spends processing packets, which is where most
 * of a router's work happens.
 */

var prev = null;

function sample() {
	return L.resolveDefault(fs.read('/proc/stat'), '').then(function(data) {
		var line = (data || '').split(/\n/)[0] || '';
		var f = line.trim().split(/\s+/).slice(1).map(function(v) { return parseInt(v) || 0; });
		/* user nice system idle iowait irq softirq steal */
		if (f.length < 7)
			return null;
		return {
			user: f[0] + f[1],
			system: f[2],
			idle: f[3] + f[4],
			irq: f[5],
			softirq: f[6],
			total: f.slice(0, 8).reduce(function(a, b) { return a + b; }, 0)
		};
	});
}

function delta(a, b) {
	var dt = b.total - a.total;
	if (dt <= 0)
		return null;
	var pct = function(k) { return 100 * (b[k] - a[k]) / dt; };
	return {
		busy: 100 - pct('idle'),
		user: pct('user'),
		system: pct('system') + pct('irq'),
		softirq: pct('softirq'),
		idle: pct('idle')
	};
}

function bar(pct) {
	var p = Math.max(0, Math.min(100, pct));
	return E('div', {
		'class': 'cbi-progressbar',
		'title': '%.1f%%'.format(p)
	}, E('div', { 'style': 'width:%.2f%%'.format(p) }));
}

return baseclass.extend({
	title: _('CPU'),

	load: function() {
		var first = prev ? Promise.resolve(prev)
			: sample().then(function(s) {
				return new Promise(function(res) { window.setTimeout(function() { res(s); }, 500); });
			});

		return first.then(function(a) {
			return sample().then(function(b) {
				var d = (a && b) ? delta(a, b) : null;
				prev = b;
				return d;
			});
		});
	},

	render: function(d) {
		if (!d)
			return E('em', {}, _('CPU usage unavailable'));

		var rows = [
			[ _('Usage'),             d.busy ],
			[ _('User programs'),     d.user ],
			[ _('Kernel'),            d.system ],
			[ _('Network (softirq)'), d.softirq ],
			[ _('Idle'),              d.idle ]
		];

		var table = E('table', { 'class': 'table' });
		rows.forEach(function(r) {
			table.appendChild(E('tr', { 'class': 'tr' }, [
				E('td', { 'class': 'td left', 'width': '33%' }, [ r[0] ]),
				E('td', { 'class': 'td left' }, [ bar(r[1]), ' ', '%.1f%%'.format(r[1]) ])
			]));
		});
		return table;
	}
});
