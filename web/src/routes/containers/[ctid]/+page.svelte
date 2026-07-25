<script lang="ts">
	import { onMount, onDestroy } from 'svelte';
	import { page } from '$app/stores';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let ctid = $derived($page.params.ctid ?? '');
	let ct = $state<any>(null);
	let loading = $state(true);
	let error = $state('');
	let polling = $state(false);

	const POLL_INTERVAL = 10000;
	let intervalId: ReturnType<typeof setInterval> | null = null;

	async function fetchCT() {
		try { ct = await api.getContainer(ctid); } catch {}
	}

	onMount(async () => {
		try {
			ct = await api.getContainer(ctid);
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
			intervalId = setInterval(fetchCT, POLL_INTERVAL);
		}
	}

	onDestroy(() => {
		if (intervalId) clearInterval(intervalId);
	});

	async function powerAction(action: string) {
		try {
			await api.post(`/containers/${ctid}/${action}`);
			ct = await api.getContainer(ctid);
		} catch (e: any) {
			error = e.message;
		}
	}

	// Derive network interfaces from container fields
	let networks = $derived.by(() => {
		if (!ct) return [];
		const nics: { name: string; ip?: string; bridge?: string }[] = [];
		for (const [key, val] of Object.entries(ct)) {
			if (key.startsWith('net')) {
				const parts = String(val).split(',');
				const ipPart = parts.find(p => p.startsWith('ip='))?.split('=')[1];
				const bridge = parts.find(p => p.startsWith('bridge='))?.split('=')[1];
				nics.push({ name: key, ip: ipPart, bridge });
			}
		}
		return nics;
	});
</script>

<svelte:head><title>Container {ctid} — Pulsar</title></svelte:head>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else if ct}
	<div class="page-header">
		<div>
			<h2>Container {ctid}</h2>
			<span class="subtitle">{ct.name || 'Unnamed'}</span>
		</div>
		<div class="actions">
			<button onclick={() => powerAction('start')} disabled={ct.status === 'running'}>Start</button>
			<button onclick={() => powerAction('stop')} disabled={ct.status !== 'running'}>Stop</button>
			<button onclick={() => powerAction('shutdown')} disabled={ct.status !== 'running'}>Shutdown</button>
			<button class="poll-btn" onclick={togglePolling}>
				{polling ? '⏹ Polling' : '⏱ Poll'}
			</button>
		</div>
	</div>

	<div class="info-grid">
		<div class="info-item"><span class="label">Status</span><StatusBadge status={ct.status} /></div>
		<div class="info-item"><span class="label">Node</span>{ct.node || '-'}</div>
		<div class="info-item"><span class="label">CPUs</span>{ct.cpus || '-'}</div>
		<div class="info-item"><span class="label">Memory</span>{ct.maxmem ? (ct.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Swap</span>{ct.maxswap ? (ct.maxswap / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Disk</span>{ct.maxdisk ? (ct.maxdisk / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</div>
		<div class="info-item"><span class="label">Uptime</span>{ct.uptime ? Math.floor(ct.uptime / 3600) + 'h ' + Math.floor((ct.uptime % 3600) / 60) + 'm' : '-'}</div>
	</div>

	{#if ct.ostype || ct.template !== undefined || ct.onboot !== undefined || ct.tags}
		<div class="section">
			<h3>Configuration</h3>
			<div class="info-grid">
				{#if ct.ostype}<div class="info-item"><span class="label">OS Type</span>{ct.ostype}</div>{/if}
				{#if ct.template !== undefined}<div class="info-item"><span class="label">Template</span>{ct.template ? 'Yes' : 'No'}</div>{/if}
				{#if ct.onboot !== undefined}<div class="info-item"><span class="label">Start on Boot</span>{ct.onboot ? 'Yes' : 'No'}</div>{/if}
				{#if ct.tags}<div class="info-item"><span class="label">Tags</span>{ct.tags}</div>{/if}
			</div>
		</div>
	{/if}

	{#if networks.length > 0}
		<div class="section">
			<h3>Network Interfaces</h3>
			<div class="table-wrap">
				<table>
					<thead>
						<tr><th>Device</th><th>IP Address</th><th>Bridge</th></tr>
					</thead>
					<tbody>
						{#each networks as net}
							<tr>
								<td>{net.name}</td>
								<td><code>{net.ip || '-'}</code></td>
								<td>{net.bridge || '-'}</td>
							</tr>
						{/each}
					</tbody>
				</table>
			</div>
		</div>
	{/if}
{/if}

<style>
	.page-header { display: flex; align-items: flex-start; justify-content: space-between; margin-bottom: 24px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.subtitle { font-size: 13px; color: var(--color-text-muted); }
	.actions { display: flex; gap: 8px; flex-wrap: wrap; }
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
	.poll-btn { border-color: var(--color-accent) !important; color: var(--color-accent) !important; }
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
	td code { font-family: var(--font-mono); font-size: 12px; color: var(--color-text-muted); }
	tr:hover td { background: var(--color-surface-hover); }
</style>
