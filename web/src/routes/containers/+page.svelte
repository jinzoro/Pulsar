<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let containers = $state<any[]>([]);
	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			containers = (await api.listContainers()) || [];
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head><title>Containers — SwissKnife</title></svelte:head>

<div class="page-header"><h2>Containers</h2></div>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else}
	<div class="table-wrap">
		<table>
			<thead>
				<tr><th>CTID</th><th>Name</th><th>Node</th><th>Status</th><th>Memory</th><th>Disk</th></tr>
			</thead>
			<tbody>
				{#each containers as ct}
					<tr>
						<td><a href="/containers/{ct.vmid}">{ct.vmid}</a></td>
						<td>{ct.name || '-'}</td>
						<td>{ct.node || '-'}</td>
						<td><StatusBadge status={ct.status} /></td>
						<td>{ct.maxmem ? (ct.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
						<td>{ct.maxdisk ? (ct.maxdisk / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
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
