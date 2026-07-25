<script lang="ts">
	import { page } from '$app/stores';

	const nav = [
		{ href: '/', label: 'Dashboard', icon: '⊞' },
		{ href: '/vms', label: 'Virtual Machines', icon: '⬡' },
		{ href: '/containers', label: 'Containers', icon: '▣' },
		{ href: '/nodes', label: 'Nodes', icon: '⬟' },
		{ href: '/storage', label: 'Storage', icon: '◷' },
		{ href: '/settings', label: 'Settings', icon: '⚙' },
	];

	let collapsed = $state(false);
</script>

<aside class="sidebar" class:collapsed>
	<div class="brand">
		<img src="/logo.png" alt="Pulsar" class="logo-img" />
		<span class="title">Pulsar</span>
	</div>
	<nav>
		{#each nav as item}
			<a href={item.href} class:active={$page.url.pathname === item.href}>
				<span class="icon">{item.icon}</span>
				<span class="label">{item.label}</span>
			</a>
		{/each}
	</nav>
	<button class="collapse-btn" onclick={() => collapsed = !collapsed}>
		{collapsed ? '▸' : '◂'}
	</button>
</aside>

<style>
	.sidebar {
		position: fixed;
		top: 0;
		left: 0;
		width: var(--sidebar-width);
		height: 100vh;
		background: var(--color-sidebar);
		border-right: 1px solid var(--color-border);
		display: flex;
		flex-direction: column;
		transition: width 0.2s;
		z-index: 100;
		overflow: hidden;
	}
	.sidebar.collapsed { width: 56px; }
	.brand {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 16px;
		border-bottom: 1px solid var(--color-border);
	}
	.logo-img { width: 28px; height: 28px; flex-shrink: 0; }
	.title { font-weight: 600; font-size: 15px; white-space: nowrap; }
	.sidebar.collapsed .title { display: none; }
	nav { flex: 1; padding: 8px; display: flex; flex-direction: column; gap: 2px; }
	nav a {
		display: flex;
		align-items: center;
		gap: 10px;
		padding: 10px 12px;
		border-radius: var(--radius-sm);
		color: var(--color-text-muted);
		font-size: 13px;
		transition: all 0.15s;
		white-space: nowrap;
	}
	nav a:hover { background: var(--color-surface-hover); color: var(--color-text); }
	nav a.active { background: var(--color-accent-muted); color: var(--color-accent); }
	.icon { font-size: 16px; width: 20px; text-align: center; flex-shrink: 0; }
	.sidebar.collapsed .label { display: none; }
	.collapse-btn {
		margin: 8px;
		padding: 8px;
		background: none;
		border: 1px solid var(--color-border);
		border-radius: var(--radius-sm);
		color: var(--color-text-dim);
		cursor: pointer;
		font-size: 14px;
		text-align: center;
	}
	.collapse-btn:hover { background: var(--color-surface-hover); color: var(--color-text); }
</style>
