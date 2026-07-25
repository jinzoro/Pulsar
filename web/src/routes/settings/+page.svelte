<script lang="ts">
	import { onMount } from 'svelte';
	import { api } from '$lib/api/client';

	let health = $state<any>(null);

	// Settings persisted to localStorage
	let apiKey = $state(localStorage.getItem('pulsar_api_key') || '');
	let proxmoxHost = $state(localStorage.getItem('pulsar_proxmox_host') || '');
	let darkMode = $state(localStorage.getItem('pulsar_dark_mode') !== 'false');

	let saved = $state(false);

	onMount(async () => {
		try { health = await api.health(); } catch {}
	});

	function saveSetting(key: string, value: string) {
		localStorage.setItem(key, value);
		saved = true;
		setTimeout(() => saved = false, 2000);
	}

	function toggleDarkMode() {
		darkMode = !darkMode;
		localStorage.setItem('pulsar_dark_mode', String(darkMode));
		document.documentElement.setAttribute('data-theme', darkMode ? 'dark' : 'light');
		saved = true;
		setTimeout(() => saved = false, 2000);
	}
</script>

<svelte:head><title>Settings — Pulsar</title></svelte:head>

<div class="page-header">
	<h2>Settings</h2>
	{#if saved}<span class="saved-badge">Saved</span>{/if}
</div>

<div class="section">
	<h3>API Gateway</h3>
	<div class="info-grid">
		<div class="info-item">
			<span class="label">Endpoint</span>
			<code>/api/v1</code>
		</div>
		<div class="info-item">
			<span class="label">Status</span>
			<span style="color:var(--color-success)" class:dim={!health}>{health ? 'Connected' : 'Unknown'}</span>
		</div>
	</div>
</div>

<div class="section">
	<h3>Authentication</h3>
	<div class="field">
		<label for="api-key">API Key</label>
		<div class="input-row">
			<input
				id="api-key"
				type="password"
				bind:value={apiKey}
				placeholder="Enter your Pulsar API key"
			/>
			<button onclick={() => saveSetting('pulsar_api_key', apiKey)}>Save</button>
		</div>
		<p class="hint">Stored locally in browser. Sent as <code>X-API-Key</code> header.</p>
	</div>
</div>

<div class="section">
	<h3>Proxmox Connection</h3>
	<div class="field">
		<label for="proxmox-host">Proxmox Host</label>
		<div class="input-row">
			<input
				id="proxmox-host"
				type="text"
				bind:value={proxmoxHost}
				placeholder="e.g. proxmox.example.com:8006"
			/>
			<button onclick={() => saveSetting('pulsar_proxmox_host', proxmoxHost)}>Save</button>
		</div>
		<p class="hint">Overrides the default Proxmox host configured on the server.</p>
	</div>
</div>

<div class="section">
	<h3>Appearance</h3>
	<div class="field">
		<label for="theme-toggle">Theme</label>
		<div class="toggle-row">
			<span id="theme-label">Dark Mode</span>
			<button id="theme-toggle" class="toggle" aria-labelledby="theme-label" onclick={toggleDarkMode} class:active={darkMode}>
				<span class="toggle-knob" class:right={darkMode}></span>
			</button>
		</div>
	</div>
</div>

<div class="section">
	<h3>Proxy Configuration</h3>
	<p class="hint">In development, the SvelteKit dev server proxies <code>/api/*</code> to <code>http://localhost:8443</code>.<br>
	For production, deploy the built <code>web/build/</code> folder behind a reverse proxy (nginx/caddy) that routes <code>/api/*</code> to the Go gateway.</p>
</div>

<style>
	.page-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 24px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.saved-badge { font-size: 11px; color: var(--color-success); background: rgba(34, 197, 94, 0.15); padding: 3px 10px; border-radius: 4px; }
	.section { margin-bottom: 28px; }
	.section h3 { font-size: 14px; font-weight: 600; margin-bottom: 12px; color: var(--color-text-muted); }
	.hint { font-size: 12px; color: var(--color-text-dim); line-height: 1.6; margin-top: 6px; }
	.hint code { background: var(--color-surface); padding: 1px 5px; border-radius: 3px; font-family: var(--font-mono); font-size: 11px; }
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
	.field { margin-bottom: 16px; }
	.field label { display: block; font-size: 13px; font-weight: 500; margin-bottom: 6px; color: var(--color-text); }
	.input-row { display: flex; gap: 8px; max-width: 480px; }
	.input-row input {
		flex: 1;
		padding: 9px 12px;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		background: var(--color-surface);
		color: var(--color-text);
		font-family: var(--font-mono);
		font-size: 13px;
		outline: none;
		transition: border-color 0.15s;
	}
	.input-row input:focus { border-color: var(--color-accent); }
	.input-row input::placeholder { color: var(--color-text-dim); }
	.input-row button {
		padding: 9px 18px;
		border: 1px solid var(--color-accent);
		border-radius: var(--radius-sm);
		background: var(--color-accent);
		color: #fff;
		cursor: pointer;
		font-size: 12px;
		font-weight: 500;
		white-space: nowrap;
	}
	.input-row button:hover { background: var(--color-accent-hover); }
	.toggle-row { display: flex; align-items: center; gap: 12px; }
	.toggle-row span { font-size: 13px; }
	.toggle {
		width: 44px;
		height: 24px;
		border-radius: 12px;
		border: none;
		background: var(--color-border);
		cursor: pointer;
		position: relative;
		padding: 0;
		transition: background 0.2s;
	}
	.toggle.active { background: var(--color-accent); }
	.toggle-knob {
		position: absolute;
		top: 3px;
		left: 3px;
		width: 18px;
		height: 18px;
		border-radius: 50%;
		background: #fff;
		transition: left 0.2s;
	}
	.toggle-knob.right { left: 23px; }
	.dim { opacity: 0.5; }
</style>
