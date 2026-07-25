<script lang="ts">
	import { onMount } from 'svelte';
	import { page } from '$app/stores';
	import { api } from '$lib/api/client';
	import StatusBadge from '$lib/components/StatusBadge.svelte';

	let vms = $state<any[]>([]);
	let loading = $state(true);
	let error = $state('');

	onMount(async () => {
		try {
			vms = (await api.listVMs()) || [];
		} catch (e: any) {
			error = e.message;
		} finally {
			loading = false;
		}
	});
</script>

<svelte:head><title>VMs — SwissKnife</title></svelte:head>

<div class="page-header">
	<h2>Virtual Machines</h2>
</div>

{#if loading}
	<div class="state">Loading...</div>
{:else if error}
	<div class="state error">{error}</div>
{:else}
	<div class="table-wrap">
		<table>
			<thead>
				<tr><th>VMID</th><th>Name</th><th>Node</th><th>Status</th><th>CPU</th><th>Memory</th><th>Disk</th></tr>
			</thead>
			<tbody>
				{#each vms as vm}
					<tr>
						<td><a href="/vms/{vm.vmid}">{vm.vmid}</a></td>
						<td>{vm.name || '-'}</td>
						<td>{vm.node || '-'}</td>
						<td><StatusBadge status={vm.status} /></td>
						<td>{vm.cpus || '-'}</td>
						<td>{vm.maxmem ? (vm.maxmem / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
						<td>{vm.maxdisk ? (vm.maxdisk / 1024 / 1024 / 1024).toFixed(1) + ' GB' : '-'}</td>
					</tr>
				{/each}
			</tbody>
		</table>
	</div>
{/if}

<style>
	.page-header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 20px; }
	.page-header h2 { font-size: 18px; font-weight: 600; }
	.state { padding: 40px; text-align: center; color: var(--color-text-muted); }
	.state.error { color: var(--color-danger); }
	.table-wrap { overflow-x: auto; }
	table { width: 100%; border-collapse: collapse; font-size: 13px; }
	th, td { text-align: left; padding: 10px 14px; border-bottom: 1px solid var(--color-border); }
	th { color: var(--color-text-dim); font-weight: 500; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; }
	td { color: var(--color-text); }
	tr:hover td { background: var(--color-surface-hover); }
</style>
