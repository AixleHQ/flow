import inertia from '@inertiajs/vite';
import reactSwc from '@vitejs/plugin-react-swc';
import { defineConfig } from 'vite';
import ViteRuby from 'vite-plugin-ruby';
import tsconfigPaths from 'vite-tsconfig-paths';

export default defineConfig({
  build: {
    sourcemap: false,
  },
  plugins: [ViteRuby(), tsconfigPaths(), reactSwc(), inertia()],
  resolve: {
    extensions: ['.js', '.jsx', '.ts', '.tsx'],
  },
  server: {
    allowedHosts: ['lvh.me', 'localhost', '127.0.0.1'],
  },
});
