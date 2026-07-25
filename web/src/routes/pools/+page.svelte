<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';

	let pools = $state<any[]>([]);
	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			pools = (await api.listPools()) || [];
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head><title>Pools — Pulsar</title></svelte:head>

<div class="page-header"><h2>Pools</h2></div>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else if pools.length === 0}
	<div class="state">No pools found.</div>
{:else}
	<div class="table-wrap">
		<table>
			<thead>
				<tr><th>Pool ID</th><th>Members</th><th>Comment</th></tr>
			</thead>
			<tbody>
				{#each pools as pool}
					<tr>
						<td><strong>{pool.poolid || pool.pool}</strong></td>
						<td>{pool.members ? pool.members.length : 0}</td>
						<td>{pool.comment || '-'}</td>
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
