import { sveltekit } from '@sveltejs/kit/vite';
import { defineConfig } from 'vite';

export default defineConfig({
	plugins: [sveltekit()],
	server: {
		proxy: {
			'/api': {
				target: 'http://localhost:8443',
				changeOrigin: true
			},
			'/metrics': {
				target: 'http://localhost:8443',
				changeOrigin: true
			}
		}
	}
});
