<script lang="ts">
	let { title = 'Dashboard' }: { title?: string } = $props();
</script>

<header class="topbar">
	<h1>{title}</h1>
	<div class="actions">
		<span class="badge-api">API :8443</span>
		<span class="badge-status">● Connected</span>
	</div>
</header>

<style>
	.topbar {
		height: var(--topbar-height);
		background: var(--color-sidebar);
		border-bottom: 1px solid var(--color-border);
		display: flex;
		align-items: center;
		justify-content: space-between;
		padding: 0 24px;
	}
	h1 { font-size: 16px; font-weight: 600; }
	.actions { display: flex; align-items: center; gap: 12px; }
	.badge-api {
		font-size: 11px;
		padding: 3px 8px;
		border-radius: 4px;
		background: var(--color-accent-muted);
		color: var(--color-accent);
		font-family: var(--font-mono);
	}
	.badge-status {
		font-size: 12px;
		color: var(--color-success);
	}
</style>
