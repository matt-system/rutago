import type { CapacitorConfig } from '@capacitor/cli';
const config: CapacitorConfig = {
  appId: 'cl.survival.mesh',
  appName: 'SURVIVAL',
  webDir: 'dist',
  bundledWebRuntime: false,
  ios: { contentInset: 'automatic' },
  android: { allowMixedContent: false }
};
export default config;