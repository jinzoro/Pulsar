<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let nodes = $state<any[]>([]);
	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			nodes = (await api.listNodes()) || [];
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head><title>Nodes — SwissKnife</title></svelte:head>

<div class="page-header"><h2>Nodes</h2></div>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else}
	<div class="table-wrap">
		<table>
			<thead>
				<tr><th>Name</th><th>Status</th><th>CPU</th><th>Memory</th><th>Disk</th><th>Uptime</th></tr>
			</thead>
			<tbody>
				{#each nodes as node}
					<tr>
						<td><a href="/nodes/{node.node || node.name}">{node.node || node.name}</a></td>
						<td><StatusBadge status={node.status} /></td>
						<td>{node.cpu != null ? (node.cpu * 100).toFixed(1) + '%' : '-'}</td>
						<td>{node.maxmem ? (node.mem / 1024 / 1024 / 1024).toFixed(1) + ' / ' + (node.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
						<td>{node.maxdisk ? (node.disk / 1024 / 1024 / 1024).toFixed(1) + ' / ' + (node.maxdisk / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
						<td>{node.uptime ? Math.floor(node.uptime / 3600) + 'h' : '-'}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
{/if}

<style>
	.page-header { margin-bottom: 20px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.state { padding: 40px; text-align: center; color: var(--color-text-muted); }
	.state.error { color: var(--color-danger); }
	.table-wrap { overflow-x: auto; }
	table { width: 100%; border-collapse: collapse; font-size: 13px; }
	th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid var(--color-border); }
	th { color: var(--color-text-dim); font-weight: 500; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
	td { color: var(--color-text); }
	tr:hover td { background: var(--color-surface-hover); }
</style>
