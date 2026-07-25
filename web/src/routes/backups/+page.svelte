<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let backups = $state<any[]>([]);
	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			backups = (await api.listBackups()) || [];
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head><title>Backups — Pulsar</title></svelte:head>

<div class="page-header"><h2>Backups</h2></div>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else if backups.length === 0}
	<div class="state">No backups found.</div>
{:else}
	<div class="table-wrap">
		<table>
			<thead>
				<tr><th>VMID</th><th>Name</th><th>Node</th><th>Type</th><th>Status</th><th>Size</th><th>Date</th></tr>
			</thead>
			<tbody>
				{#each backups as backup}
					<tr>
						<td>{backup.vmid}</td>
						<td>{backup.name || '-'}</td>
						<td>{backup.node || '-'}</td>
						<td>{backup.type || '-'}</td>
						<td><StatusBadge status={backup.status} /></td>
						<td>{backup.size ? (backup.size / 1024 / 1024 / 1024).toFixed(2) + ' GB' : '-'}</td>
						<td>{backup.ctime ? new Date(backup.ctime * 1000).toLocaleString() : '-'}</td>
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
