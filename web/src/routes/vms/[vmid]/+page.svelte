<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let vmid = $derived($page.params.vmid);
	let vm = $state<any>(null);
	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			vm = await api.getVM(vmid);
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
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
</script>

<svelte:head><title>VM {vmid} — SwissKnife</title></svelte:head>

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
{/if}

<style>
	.page-header { display: flex; align-items: flex-start; justify-content: space-between; margin-bottom: 24px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.subtitle { font-size: 13px; color: var(--color-text-muted); }
	.actions { display: flex; gap: 8px; }
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
