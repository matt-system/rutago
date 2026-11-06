import { registerPlugin } from '@capacitor/core';
import type { SurvivalMeshPlugin } from './definitions';
export * from './definitions';
export const SurvivalMesh = registerPlugin<SurvivalMeshPlugin>('SurvivalMesh');