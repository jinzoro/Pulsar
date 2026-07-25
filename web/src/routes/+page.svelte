<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let loading = $state(true);
	let error = $state('');
	let metrics = $state<any>(null);
	let vms = $state<any[]>([]);
	let nodes = $state<any[]>([]);

	onMount(async () => {
		try {
			const [m, vmList, nodeList] = await Promise.all([
				api.clusterMetrics(),
				api.listVMs(),
				api.listNodes()
			]);
			metrics = m;
			vms = vmList || [];
			nodes = nodeList || [];
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});
</script>

{#if loading}
	<div class="loading">Loading dashboard...</div>
{:else if error}
	<div class="error">Failed to connect: {error}</div>
{:else}
	<div class="cards">
		<div class="card">
			<span class="card-label">Nodes</span>
			<span class="card-value">{nodes.length}</span>
		</div>
		<div class="card">
			<span class="card-label">VMs</span>
			<span class="card-value">{vms.length}</span>
		</div>
		<div class="card">
			<span class="card-label">Cluster Status</span>
			<span class="card-value" style="font-size:14px">{metrics?.status ? 'Healthy' : 'Unknown'}</span>
		</div>
		<div class="card">
			<span class="card-label">API Gateway</span>
			<span class="card-value" style="font-size:14px;color:var(--color-success)">Connected</span>
		</div>
	</div>

	<section class="section">
		<h2>Nodes</h2>
		<div class="table-wrap">
			<table>
				<thead>
					<tr><th>Name</th><th>Status</th><th>CPU</th><th>Memory</th><th>Uptime</th></tr>
				</thead>
				<tbody>
					{#each nodes as node}
						<tr>
							<td>{node.node || node.name}</td>
							<td><StatusBadge status={node.status} /></td>
							<td>{node.cpu != null ? (node.cpu * 100).toFixed(1) + '%' : '-'}</td>
							<td>{node.mem != null ? (node.mem / 1024 / 1024 / 1024).toFixed(1) + 'G' : '-'}</td>
							<td>{node.uptime ? Math.floor(node.uptime / 3600) + 'h' : '-'}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	</section>

	<section class="section">
		<h2>Virtual Machines</h2>
		<div class="table-wrap">
			<table>
				<thead>
					<tr><th>VMID</th><th>Name</th><th>Node</th><th>Status</th><th>CPU</th><th>Memory</th></tr>
				</thead>
				<tbody>
					{#each vms as vm}
						<tr>
							<td><a href="/vms/{vm.vmid}">{vm.vmid}</a></td>
							<td>{vm.name || '-'}</td>
							<td>{vm.node || '-'}</td>
							<td><StatusBadge status={vm.status} /></td>
							<td>{vm.cpus || '-'}</td>
							<td>{vm.maxmem ? (vm.maxmem / 1024 / 1024 / 1024).toFixed(1) + 'G' : '-'}</td>
						</tr>
					{/each}
				</tbody>
			</table>
		</div>
	</section>
{/if}

<style>
	.loading, .error { padding: 40px; text-align: center; color: var(--color-text-muted); font-size: 15px; }
	.error { color: var(--color-danger); }
	.cards { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 16px; margin-bottom: 28px; }
	.card {
		background: var(--color-surface);
		border: 1px solid var(--color-border);
		border-radius: var(--radius-md);
		padding: 20px;
		display: flex;
		flex-direction: column;
		gap: 8px;
	}
	.card-label { font-size: 12px; color: var(--color-text-dim); text-transform: uppercase; letter-spacing: 0.5px; }
	.card-value { font-size: 28px; font-weight: 700; color: var(--color-text); }
	.section { margin-bottom: 28px; }
	.section h2 { font-size: 15px; font-weight: 600; margin-bottom: 12px; color: var(--color-text-muted); }
	.table-wrap { overflow-x: auto; }
	table { width: 100%; border-collapse: collapse; font-size: 13px; }
	th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid var(--color-border); }
	th { color: var(--color-text-dim); font-weight: 500; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
	td { color: var(--color-text); }
	tr:hover td { background: var(--color-surface-hover); }
</style>
