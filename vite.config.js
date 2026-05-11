import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// https://vite.dev/config/
export default defineConfig({
  plugins: [react()],
  define: {
    // Inject the build timestamp as a global constant
    // The JSON.stringify wrapper turns the string into a valid JS literal at build time
    __BUILD_TIME__: JSON.stringify(new Date().toISOString())
  }
})
