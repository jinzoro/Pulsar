const API_BASE = '/api/v1';

export interface APIResponse<T = unknown> {
	success: boolean;
	data?: T;
	error?: string;
}

async function request<T>(path: string, options: RequestInit = {}): Promise<T> {
	const res = await fetch(`${API_BASE}${path}`, {
		headers: { 'Content-Type': 'application/json', ...options.headers as Record<string, string> },
		...options
	});
	const json: APIResponse<T> = await res.json();
	if (!json.success) throw new Error(json.error || 'API error');
	return json.data as T;
}

export const api = {
	get: <T>(path: string) => request<T>(path),
	post: <T>(path: string, body?: unknown) => request<T>(path, { method: 'POST', body: body ? JSON.stringify(body) : undefined }),
	put: <T>(path: string, body?: unknown) => request<T>(path, { method: 'PUT', body: body ? JSON.stringify(body) : undefined }),
	delete: <T>(path: string) => request<T>(path, { method: 'DELETE' }),

	// Convenience endpoints
	health: () => api.get<{ status: string }>('/health'),
	clusterStatus: () => api.get<any>('/cluster/status'),
	clusterResources: (type?: string) => api.get<any>(`/cluster/resources${type ? `?type=${type}` : ''}`),
	listVMs: () => api.get<any[]>('/vms'),
	getVM: (vmid: string) => api.get<any>(`/vms/${vmid}`),
	createVM: (data: any) => api.post<any>('/vms', data),
	deleteVM: (vmid: string) => api.delete(`/vms/${vmid}`),
	startVM: (vmid: string) => api.post(`/vms/${vmid}/start`),
	stopVM: (vmid: string) => api.post(`/vms/${vmid}/stop`),
	shutdownVM: (vmid: string) => api.post(`/vms/${vmid}/shutdown`),
	listNodes: () => api.get<any[]>('/nodes'),
	getNode: (node: string) => api.get<any>(`/nodes/${node}`),
	getNodeStatus: (node: string) => api.get<any>(`/nodes/${node}/status`),
	listContainers: () => api.get<any[]>('/containers'),
	getContainer: (ctid: string) => api.get<any>(`/containers/${ctid}`),
	listStorage: () => api.get<any[]>('/storage'),
	listPools: () => api.get<any[]>('/pools'),
	listBackups: () => api.get<any[]>('/backups'),
	nodeMetrics: () => api.get<any>('/metrics/nodes'),
	clusterMetrics: () => api.get<any>('/metrics/cluster'),

	// VM config / resources
	getVMConfig: (vmid: string) => api.get<any>(`/vms/${vmid}/config`),
	getVMSnapshots: (vmid: string) => api.get<any[]>(`/vms/${vmid}/snapshots`),

	// Node resources
	getNodeVMs: (node: string) => api.get<any[]>(`/nodes/${node}/vms`),
	getNodeContainers: (node: string) => api.get<any[]>(`/nodes/${node}/containers`),

	// Pools
	getPool: (poolid: string) => api.get<any>(`/pools/${poolid}`),
};
