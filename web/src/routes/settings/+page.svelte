<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';

	let health = $state<any>(null);

	onMount(async () => {
		try { health = await api.health(); } catch {}
	});
</script>

<svelte:head><title>Settings — SwissKnife</title></svelte:head>

<div class="page-header"><h2>Settings</h2></div>

<div class="section">
	<h3>API Gateway</h3>
	<div class="info-grid">
		<div class="info-item">
			<span class="label">Endpoint</span>
			<code>/api/v1</code>
		</div>
		<div class="info-item">
			<span class="label">Status</span>
			<span style="color:var(--color-success)">{health ? 'Connected' : 'Unknown'}</span>
		</div>
	</div>
</div>

<div class="section">
	<h3>Proxy Configuration</h3>
	<p class="hint">In development, the SvelteKit dev server proxies <code>/api/*</code> to <code>http://localhost:8443</code>.<br>
	For production, deploy the built <code>web/build/</code> folder behind a reverse proxy (nginx/caddy) that routes <code>/api/*</code> to the Go gateway.</p>
</div>

<style>
	.page-header { margin-bottom: 24px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.section { margin-bottom: 28px; }
	.section h3 { font-size: 14px; font-weight: 600; margin-bottom: 12px; color: var(--color-text-muted); }
	.hint { font-size: 13px; color: var(--color-text-muted); line-height: 1.7; }
	.hint code { background: var(--color-surface); padding: 2px 6px; border-radius: 3px; font-family: var(--font-mono); font-size: 12px; }
	.info-grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(200px, 1fr)); gap: 12px; }
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
	.info-item code { font-family: var(--font-mono); font-size: 13px; }
</style>
