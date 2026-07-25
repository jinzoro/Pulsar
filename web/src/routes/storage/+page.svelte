<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';

	let storage = $state<any[]>([]);
	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			storage = (await api.listStorage()) || [];
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head><title>Storage — Pulsar</title></svelte:head>

<div class="page-header"><h2>Storage</h2></div>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else}
	<div class="table-wrap">
		<table>
			<thead>
				<tr><th>Name</th><th>Type</th><th>Status</th><th>Content</th><th>Used</th><th>Total</th><th>Usage</th></tr>
			</thead>
			<tbody>
				{#each storage as store}
					<tr>
						<td>{store.storage}</td>
						<td>{store.type}</td>
						<td>{store.status}</td>
						<td>{store.content || '-'}</td>
						<td>{store.used ? (store.used / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
						<td>{store.total ? (store.total / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
						<td>
							<div class="bar-bg">
								<div class="bar-fill" style="width: {store.percent || 0}%"></div>
							</div>
							<span class="pct">{(store.percent || 0).toFixed(1)}%</span>
						</td>
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
	.bar-bg { display: inline-block; width: 80px; height: 6px; background: var(--color-border); border-radius: 3px; vertical-align: middle; }
	.bar-fill { height: 100%; background: var(--color-accent); border-radius: 3px; transition: width 0.3s; }
	.pct { margin-left: 6px; font-size: 12px; color: var(--color-text-muted); }
</style>
