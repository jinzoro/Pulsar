<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let vmid = $derived($page.params.vmid ?? '');
	let vm = $state<any>(null);
	let config = $state<any>(null);
	let snapshots = $state<any[]>([]);
	let loading = $state(true);
	let error = $state('');
	let polling = $state(false);

	const POLL_INTERVAL = 10000;
	let intervalId: ReturnType<typeof setInterval> | null = null;

	async function fetchVM() {
		try {
			vm = await api.getVM(vmid);
		} catch (e: any) {
			error = e.message;
		}
	}

	async function fetchConfig() {
		try {
			config = await api.getVMConfig(vmid);
		} catch { /* optional */ }
	}

	async function fetchSnapshots() {
		try {
			snapshots = (await api.getVMSnapshots(vmid)) || [];
		} catch { /* optional */ }
	}

	onMount(async () => {
		try {
			vm = await api.getVM(vmid);
			await Promise.all([fetchConfig(), fetchSnapshots()]);
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});

	function togglePolling() {
		if (intervalId) {
			clearInterval(intervalId);
			intervalId = null;
			polling = false;
		} else {
			polling = true;
			intervalId = setInterval(() => {
				fetchVM();
				fetchConfig();
			}, POLL_INTERVAL);
		}
	}

	onDestroy(() => {
		if (intervalId) clearInterval(intervalId);
	});

	async function powerAction(action: string) {
		try {
			if (action === 'start') await api.startVM(vmid);
			else if (action === 'stop') await api.stopVM(vmid);
			else if (action === 'shutdown') await api.shutdownVM(vmid);
			vm = await api.getVM(vmid);
		} catch (e: any) {
			error = e.message;
		}
	}

	// Derive network interfaces from config
	let networks = $derived.by(() => {
		if (!config) return [];
		const nics: { name: string; mac: string; model: string; bridge: string }[] = [];
		for (const [key, val] of Object.entries(config)) {
			if (key.startsWith('net')) {
				const parts = String(val).split(',');
				const modelMac = parts[0] ? parts[0].split('=') : [];
				const bridge = parts.find(p => p.startsWith('bridge='))?.split('=')[1] || '';
				nics.push({
					name: key,
					mac: modelMac[1] || '',
					model: modelMac[0] || '',
					bridge,
				});
			}
		}
		return nics;
	});

	// Derive disks from config
	let disks = $derived.by(() => {
		if (!config) return [];
		const diskList: { name: string; size: string; format?: string; storage?: string }[] = [];
		const diskPrefixes = ['virtio', 'scsi', 'sata', 'ide'];
		for (const [key, val] of Object.entries(config)) {
			if (diskPrefixes.some(p => key.startsWith(p))) {
				const parts = String(val).split(',');
				const sizePart = parts[0] || '';
				const format = parts.find(p => p.startsWith('format='))?.split('=')[1];
				const storage = parts.find(p => !p.includes('=') && p.includes(':'))?.split(':')[0];
				diskList.push({ name: key, size: sizePart, format, storage });
			}
		}
		return diskList;
	});
</script>

<svelte:head><title>VM {vmid} — Pulsar</title></svelte:head>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else if vm}
	<div class="page-header">
		<div>
			<h2>VM {vmid}</h2>
			<span class="subtitle">{vm.name || 'Unnamed'}</span>
		</div>
		<div class="actions">
			<button onclick={() => powerAction('start')} disabled={vm.status === 'running'}>Start</button>
			<button onclick={() => powerAction('stop')} disabled={vm.status !== 'running' && vm.status !== 'started'}>Stop</button>
			<button onclick={() => powerAction('shutdown')} disabled={vm.status !== 'running' && vm.status !== 'started'}>Shutdown</button>
			<button class="poll-btn" onclick={togglePolling}>
				{polling ? '⏹ Polling' : '⏱ Poll'}
			</button>
		</div>
	</div>

	<div class="info-grid">
		<div class="info-item"><span class="label">Status</span><StatusBadge status={vm.status} /></div>
		<div class="info-item"><span class="label">Node</span>{vm.node || '-'}</div>
		<div class="info-item"><span class="label">CPUs</span>{vm.cpus || '-'}</div>
		<div class="info-item"><span class="label">Memory</span>{vm.maxmem ? (vm.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Disk</span>{vm.maxdisk ? (vm.maxdisk / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Uptime</span>{vm.uptime ? Math.floor(vm.uptime / 3600) + 'h ' + Math.floor((vm.uptime % 3600) / 60) + 'm' : '-'}</div>
	</div>

	{#if config}
		<div class="section">
			<h3>Configuration</h3>
			<div class="info-grid">
				{#if config.ostype}<div class="info-item"><span class="label">OS Type</span>{config.ostype}</div>{/if}
				{#if config.boot}<div class="info-item"><span class="label">Boot Order</span>{config.boot}</div>{/if}
				{#if config.onboot !== undefined}<div class="info-item"><span class="label">Start on Boot</span>{config.onboot ? 'Yes' : 'No'}</div>{/if}
				{#if config.tags}<div class="info-item"><span class="label">Tags</span>{config.tags}</div>{/if}
				{#if config.balloon !== undefined}<div class="info-item"><span class="label">Balloon Min</span>{config.balloon} MB</div>{/if}
				{#if config.agent !== undefined}<div class="info-item"><span class="label">QEMU Agent</span>{String(config.agent)}</div>{/if}
			</div>
		</div>

		{#if networks.length > 0}
			<div class="section">
				<h3>Network Interfaces</h3>
				<div class="table-wrap">
					<table>
						<thead>
							<tr><th>Device</th><th>Model</th><th>MAC Address</th><th>Bridge</th></tr>
						</thead>
						<tbody>
							{#each networks as net}
								<tr>
									<td>{net.name}</td>
									<td>{net.model}</td>
									<td><code>{net.mac}</code></td>
									<td>{net.bridge || '-'}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</div>
		{/if}

		{#if disks.length > 0}
			<div class="section">
				<h3>Disks</h3>
				<div class="table-wrap">
					<table>
						<thead>
							<tr><th>Device</th><th>Size / Path</th><th>Format</th><th>Storage</th></tr>
						</thead>
						<tbody>
							{#each disks as disk}
								<tr>
									<td>{disk.name}</td>
									<td><code>{disk.size}</code></td>
									<td>{disk.format || '-'}</td>
									<td>{disk.storage || '-'}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</div>
		{/if}

		{#if snapshots.length > 0}
			<div class="section">
				<h3>Snapshots ({snapshots.length})</h3>
				<div class="table-wrap">
					<table>
						<thead>
							<tr><th>Name</th><th>Description</th><th>RAM</th><th>Created</th></tr>
						</thead>
						<tbody>
							{#each snapshots as snap}
								<tr>
									<td>{snap.name}</td>
									<td>{snap.description || '-'}</td>
									<td>{snap.ram ? 'Yes' : 'No'}</td>
									<td>{snap.snaptime ? new Date(snap.snaptime * 1000).toLocaleString() : '-'}</td>
								</tr>
							{/each}
						</tbody>
					</table>
				</div>
			</div>
		{/if}
	{/if}
{/if}

<style>
	.page-header { display: flex; align-items: flex-start; justify-content: space-between; margin-bottom: 24px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.subtitle { font-size: 13px; color: var(--color-text-muted); }
	.actions { display: flex; gap: 8px; flex-wrap: wrap; }
	.actions button {
		padding: 7px 16px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		color: var(--color-text);
		cursor: pointer;
		font-size: 12px;
	}
	.actions button:hover:not(:disabled) { background: var(--color-surface-hover); border-color: var(--color-accent); }
	.actions button:disabled { opacity: 0.4; cursor: not-allowed; }
	.poll-btn { border-color: var(--color-accent) !important; color: var(--color-accent) !important; }
	.state { padding: 40px; text-align: center; color: var(--color-text-muted); }
	.state.error { color: var(--color-danger); }
	.section { margin-bottom: 24px; }
	.section h3 { font-size: 14px; font-weight: 600; margin-bottom: 12px; color: var(--color-text-muted); }
	.info-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(180px, 1fr)); gap: 12px; }
	.info-item {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		padding: 14px 16px;
		display: flex;
		flex-direction: column;
		gap: 4px;
		font-size: 13px;
	}
	.info-item .label { font-size: 11px; color: var(--color-text-dim); text-transform: uppercase; letter-spacing: 0.5px; }
	.table-wrap { overflow-x: auto; }
	table { width: 100%; border-collapse: collapse; font-size: 13px; }
	th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid var(--color-border); }
	th { color: var(--color-text-dim); font-weight: 500; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
	td { color: var(--color-text); }
	td code { font-family: var(--font-mono); font-size: 12px; color: var(--color-text-muted); }
	tr:hover td { background: var(--color-surface-hover); }
</style>
