<script lang="ts">
	import '../app.css';
	import Sidebar from '$lib/components/Sidebar.svelte';
	import Topbar from '$lib/components/Topbar.svelte';
	let { children }: { children: import('svelte').Snippet } = $props();
</script>

<Sidebar />
<div class="main">
	<Topbar />
	<main>
		{@render children()}
	</main>
</div>

<style>
	.main {
		margin-left: var(--sidebar-width);
		min-height: 100vh;
		display: flex;
		flex-direction: column;
		transition: margin-left 0.2s;
	}
	main {
		flex: 1;
		padding: 24px;
		overflow-y: auto;
	}
</style>
