import type { PluginListenerHandle } from '@capacitor/core';
export interface Peer { id: string; name: string; rssi?: number; connected: boolean; }
export interface MeshFrame { data: string; peerId?: string; }
export interface SurvivalMeshPlugin {
  start(options?: { deviceName?: string }): Promise<{ deviceId: string; scanning: boolean; advertising: boolean }>;
  stop(): Promise<void>;
  send(options: { data: string; peerId?: string }): Promise<{ sent: number }>;
  getPeers(): Promise<{ peers: Peer[] }>;
  addListener(eventName: 'frame', listenerFunc: (frame: MeshFrame) => void): Promise<PluginListenerHandle>;
  addListener(eventName: 'peer', listenerFunc: (peer: Peer) => void): Promise<PluginListenerHandle>;
  addListener(eventName: 'state', listenerFunc: (state: { state: string; detail?: string }) => void): Promise<PluginListenerHandle>;
}