import { defineConfig } from 'vite';

export default defineConfig({
  build: {
    outDir: 'dist',
    emptyOutDir: true,
    cssCodeSplit: false,
    rollupOptions: {
      output: {
        entryFileNames: 'app.js',
        assetFileNames: (assetInfo) => {
          const assetNames = assetInfo.names || (assetInfo.name ? [assetInfo.name] : []);
          if (assetNames.includes('style.css')) {
            return 'app.css';
          }
          return '[name][extname]';
        },
      },
    },
  },
});
