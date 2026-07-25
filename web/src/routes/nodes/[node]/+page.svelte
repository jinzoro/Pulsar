<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let nodeName = $derived($page.params.node ?? '');
	let node = $state<any>(null);
	let nodeVMs = $state<any[]>([]);
	let nodeCTs = $state<any[]>([]);
	let loading = $state(true);
	let error = $state('');
	let polling = $state(false);

	const POLL_INTERVAL = 10000;
	let intervalId: ReturnType<typeof setInterval> | null = null;

	async function fetchNode() {
		try { node = await api.getNodeStatus(nodeName); } catch {}
	}

	async function fetchGuests() {
		try {
			const [vms, cts] = await Promise.all([
				api.getNodeVMs(nodeName),
				api.getNodeContainers(nodeName),
			]);
			nodeVMs = vms || [];
			nodeCTs = cts || [];
		} catch { /* optional */ }
	}

	onMount(async () => {
		try {
			node = await api.getNodeStatus(nodeName);
			await fetchGuests();
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
				fetchNode();
				fetchGuests();
			}, POLL_INTERVAL);
		}
	}

	onDestroy(() => {
		if (intervalId) clearInterval(intervalId);
	});
</script>

<svelte:head><title>Node {nodeName} — Pulsar</title></svelte:head>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else if node}
	<div class="page-header">
		<h2>Node: {nodeName}</h2>
		<div class="actions">
			<button class="poll-btn" onclick={togglePolling}>
				{polling ? '⏹ Polling' : '⏱ Poll'}
			</button>
		</div>
	</div>

	<div class="info-grid">
		<div class="info-item"><span class="label">Status</span><StatusBadge status={node.status} /></div>
		<div class="info-item"><span class="label">CPU</span>{(node.cpu * 100).toFixed(1)}%</div>
		<div class="info-item"><span class="label">Memory</span>{node.maxmem ? (node.mem / 1024 / 1024 / 1024).toFixed(1) + ' / ' + (node.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Disk</span>{node.maxdisk ? (node.disk / 1024 / 1024 / 1024).toFixed(1) + ' / ' + (node.maxdisk / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Uptime</span>{node.uptime ? Math.floor(node.uptime / 86400) + 'd ' + Math.floor((node.uptime % 86400) / 3600) + 'h' : '-'}</div>
	</div>

	{#if node.pveversion || node.kversion || node.wait}
		<div class="section">
			<h3>System Info</h3>
			<div class="info-grid">
				{#if node.pveversion}<div class="info-item"><span class="label">PVE Version</span>{node.pveversion}</div>{/if}
				{#if node.kversion}<div class="info-item"><span class="label">Kernel</span>{node.kversion}</div>{/if}
				{#if node.wait !== undefined}<div class="info-item"><span class="label">I/O Wait</span>{(node.wait * 100).toFixed(1)}%</div>{/if}
			</div>
		</div>
	{/if}

	{#if nodeVMs.length > 0}
		<div class="section">
			<h3>VMs on this Node ({nodeVMs.length})</h3>
			<div class="table-wrap">
				<table>
					<thead>
						<tr><th>VMID</th><th>Name</th><th>Status</th><th>CPU</th><th>Memory</th></tr>
					</thead>
					<tbody>
						{#each nodeVMs as vm}
							<tr>
								<td><a href="/vms/{vm.vmid}">{vm.vmid}</a></td>
								<td>{vm.name || '-'}</td>
								<td><StatusBadge status={vm.status} /></td>
								<td>{vm.cpus || '-'}</td>
								<td>{vm.maxmem ? (vm.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		</div>
	{/if}

	{#if nodeCTs.length > 0}
		<div class="section">
			<h3>Containers on this Node ({nodeCTs.length})</h3>
			<div class="table-wrap">
				<table>
					<thead>
						<tr><th>CTID</th><th>Name</th><th>Status</th><th>Memory</th></tr>
					</thead>
					<tbody>
						{#each nodeCTs as ct}
							<tr>
								<td><a href="/containers/{ct.vmid}">{ct.vmid}</a></td>
								<td>{ct.name || '-'}</td>
								<td><StatusBadge status={ct.status} /></td>
								<td>{ct.maxmem ? (ct.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		</div>
	{/if}
{/if}

<style>
	.page-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.actions { display: flex; gap: 8px; }
	.poll-btn { padding: 7px 16px; border: 1px solid var(--color-accent); border-radius: var(--radius-sm); background: var(--color-surface); color: var(--color-accent); cursor: pointer; font-size: 12px; }
	.poll-btn:hover { background: var(--color-accent-muted); }
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
	tr:hover td { background: var(--color-surface-hover); }
</style>
