<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let ctid = $derived($page.params.ctid);
	let ct = $state<any>(null);
	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			ct = await api.getContainer(ctid);
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head><title>Container {ctid} — SwissKnife</title></svelte:head>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else if ct}
	<div class="page-header">
		<h2>Container {ctid}</h2>
		<span class="subtitle">{ct.name || 'Unnamed'}</span>
	</div>
	<div class="info-grid">
		<div class="info-item"><span class="label">Status</span><StatusBadge status={ct.status} /></div>
		<div class="info-item"><span class="label">Node</span>{ct.node || '-'}</div>
		<div class="info-item"><span class="label">Memory</span>{ct.maxmem ? (ct.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Disk</span>{ct.maxdisk ? (ct.maxdisk / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
	</div>
{/if}

<style>
	.page-header { display: flex; align-items: center; gap: 12px; margin-bottom: 24px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.subtitle { font-size: 13px; color: var(--color-text-muted); }
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
