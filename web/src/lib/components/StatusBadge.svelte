<script lang="ts">
	let { status = 'unknown' }: { status?: string } = $props();
	const colorMap: Record<string, string> = {
		running: 'var(--color-success)',
		started: 'var(--color-success)',
		stopped: 'var(--color-text-dim)',
		error: 'var(--color-danger)',
		unknown: 'var(--color-warning)',
	};
</script>

<span class="badge" style="--badge-color: {colorMap[status] || colorMap['unknown']}">
	<span class="dot"></span>
	{status}
</span>

<style>
	.badge {
		display: inline-flex;
		align-items: center;
		gap: 5px;
		font-size: 12px;
		color: var(--badge-color);
		text-transform: capitalize;
	}
	.dot {
		width: 7px;
		height: 7px;
		border-radius: 50%;
		background: var(--badge-color);
	}
</style>
