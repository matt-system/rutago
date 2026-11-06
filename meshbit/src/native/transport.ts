import { NativeEventEmitter, NativeModules, Platform } from "react-native";

type MeshbitNativeTransport = {
  getStatus(): Promise<{ available: boolean; state: string }>;
  start(): Promise<void>;
  stop(): Promise<void>;
};

const NativeTransport = NativeModules.MeshbitTransport as MeshbitNativeTransport | undefined;

export const meshbitTransportAvailable = Boolean(NativeTransport);

export async function getTransportStatus() {
  if (!NativeTransport) {
    return { available: false, state: "native-module-not-installed", platform: Platform.OS };
  }
  return NativeTransport.getStatus();
}

export async function startTransport() {
  if (!NativeTransport) throw new Error("Meshbit native Bluetooth transport is not installed in this build.");
  return NativeTransport.start();
}

export async function stopTransport() {
  if (!NativeTransport) return;
  return NativeTransport.stop();
}
