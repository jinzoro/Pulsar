<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let nodeName = $derived($page.params.node);
	let node = $state<any>(null);
	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			node = await api.getNodeStatus(nodeName);
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head><title>Node {nodeName} — SwissKnife</title></svelte:head>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else if node}
	<div class="page-header">
		<h2>Node: {nodeName}</h2>
	</div>
	<div class="info-grid">
		<div class="info-item"><span class="label">Status</span><StatusBadge status={node.status} /></div>
		<div class="info-item"><span class="label">CPU</span>{(node.cpu * 100).toFixed(1)}%</div>
		<div class="info-item"><span class="label">Memory</span>{node.maxmem ? (node.mem / 1024 / 1024 / 1024).toFixed(1) + ' / ' + (node.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Disk</span>{node.maxdisk ? (node.disk / 1024 / 1024 / 1024).toFixed(1) + ' / ' + (node.maxdisk / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Uptime</span>{node.uptime ? Math.floor(node.uptime / 86400) + 'd ' + Math.floor((node.uptime % 86400) / 3600) + 'h' : '-'}</div>
	</div>
{/if}

<style>
	.page-header { margin-bottom: 24px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.state { padding: 40px; text-align: center; color: var(--color-text-muted); }
	.state.error { color: var(--color-danger); }
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
</style>
