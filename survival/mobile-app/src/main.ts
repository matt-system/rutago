import { SurvivalMesh } from '@survival/mesh';
import './style.css';

type ChatMessage = { id: string; from: string; body: string; at: number; hops: number; };
type WireChunk = { peerId: string; id: string; index: number; total: number; bytes: Uint8Array };
const $ = (selector: string) => document.querySelector<HTMLElement>(selector)!;
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const storeKey = 'survival-mesh-messages-v1';
const seenKey = 'survival-mesh-seen-v1';
const CHUNK_DATA = 12; // 6-byte header + 12 bytes payload = 18 bytes, safe at default BLE MTU.
let messages: ChatMessage[] = JSON.parse(localStorage.getItem(storeKey) || '[]');
let seen = new Set<string>(JSON.parse(localStorage.getItem(seenKey) || '[]'));
let running = false;
let deviceId = localStorage.getItem('survival-mesh-device') || crypto.randomUUID();
const assemblies = new Map<string, { total: number; chunks: Map<number, Uint8Array>; updated: number }>();

function persist() {
  localStorage.setItem(storeKey, JSON.stringify(messages.slice(-500)));
  localStorage.setItem(seenKey, JSON.stringify([...seen].slice(-2000)));
}
function render() {
  const list = $('#messages');
  list.innerHTML = messages.map(m => `<article class="msg ${m.from === deviceId ? 'mine' : ''}"><small>${m.from === deviceId ? 'TÚ' : 'DISPOSITIVO '+m.from.slice(0,6)} · ${new Date(m.at).toLocaleTimeString()}</small><p>${escapeHtml(m.body)}</p><small>saltos: ${m.hops}</small></article>`).join('');
  list.scrollTop = list.scrollHeight;
  $('#count').textContent = String(messages.length);
}
function escapeHtml(s: string) { return s.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!)); }
function setState(s: string, detail = '') { $('#status').textContent = s; $('#detail').textContent = detail; }
function bytesToBase64(bytes: Uint8Array) { let binary = ''; for (const b of bytes) binary += String.fromCharCode(b); return btoa(binary); }
function base64ToBytes(value: string) { return Uint8Array.from(atob(value), c => c.charCodeAt(0)); }

async function sendFrame(frame: object): Promise<number> {
  const payload = encoder.encode(JSON.stringify(frame));
  const id = crypto.getRandomValues(new Uint8Array(4));
  const total = Math.ceil(payload.length / CHUNK_DATA);
  if (total > 255) throw new Error('Mensaje demasiado largo');
  let connected = 0;
  for (let index = 0; index < total; index++) {
    const part = payload.slice(index * CHUNK_DATA, (index + 1) * CHUNK_DATA);
    const packet = new Uint8Array(6 + part.length);
    packet.set(id, 0); packet[4] = index; packet[5] = total; packet.set(part, 6);
    try {
      const result = await SurvivalMesh.send({ data: bytesToBase64(packet) });
      connected = Math.max(connected, result.sent);
    } catch (e) { console.warn('BLE chunk failed', e); }
    // Give CoreBluetooth and Android GATT time to drain their transmit queues.
    await new Promise(resolve => setTimeout(resolve, 35));
  }
  return connected;
}

async function receiveChunk(encoded: string, peerId = 'unknown') {
  try {
    const packet = base64ToBytes(encoded);
    if (packet.length < 7) return;
    const id = Array.from(packet.slice(0, 4)).map(n => n.toString(16).padStart(2, '0')).join('');
    const index = packet[4], total = packet[5];
    if (!total || index >= total) return;
    const key = peerId + ':' + id;
    let assembly = assemblies.get(key);
    if (!assembly) { assembly = { total, chunks: new Map(), updated: Date.now() }; assemblies.set(key, assembly); }
    if (assembly.total !== total) { assemblies.delete(key); return; }
    assembly.chunks.set(index, packet.slice(6)); assembly.updated = Date.now();
    if (assembly.chunks.size !== total) return;
    const length = Array.from(assembly.chunks.values()).reduce((sum, part) => sum + part.length, 0);
    const joined = new Uint8Array(length); let offset = 0;
    for (let i = 0; i < total; i++) { const part = assembly.chunks.get(i); if (!part) return; joined.set(part, offset); offset += part.length; }
    assemblies.delete(key);
    await receiveFrame(bytesToBase64(joined));
  } catch { /* Ignore malformed or partial BLE packets. */ }
}
async function receiveFrame(encoded: string) {
  try {
    const frame = JSON.parse(decoder.decode(base64ToBytes(encoded))) as ChatMessage & { ttl: number };
    if (!frame.id || !frame.body || seen.has(frame.id) || frame.ttl <= 0) return;
    seen.add(frame.id);
    messages.push(frame); persist(); render();
    if (frame.from !== deviceId && frame.hops < 8 && running) {
      await sendFrame({ ...frame, hops: frame.hops + 1, ttl: frame.ttl - 1 });
    }
  } catch { /* Ignore invalid frames. */ }
}
async function start() {
  if (running) return;
  setState('CONECTANDO', 'Solicitando acceso Bluetooth…');
  try {
    const result = await SurvivalMesh.start({ deviceName: 'SURVIVAL' });
    deviceId = result.deviceId || deviceId;
    localStorage.setItem('survival-mesh-device', deviceId);
    running = true;
    setState('RADIO ACTIVA', 'Buscando y conectando teléfonos cercanos. Mantén esta pantalla abierta.');
  } catch (e) { setState('SIN CONEXIÓN', String(e)); }
}
async function stop() { await SurvivalMesh.stop(); running = false; setState('DESCONECTADO', 'Bluetooth detenido.'); }
async function sendMessage() {
  const input = $('#compose') as HTMLInputElement;
  const body = input.value.trim(); if (!body) return;
  if (!running) { setState('RADIO DETENIDA', 'Primero pulsa INICIAR RADIO.'); return; }
  const frame: ChatMessage & { ttl: number } = { id: crypto.randomUUID(), from: deviceId, body, at: Date.now(), hops: 0, ttl: 8 };
  seen.add(frame.id); messages.push(frame); persist(); render(); input.value = '';
  const sent = await sendFrame(frame);
  setState('RADIO ACTIVA', sent ? `Paquetes enviados por ${sent} enlace(s) Bluetooth.` : 'Mensaje guardado. Todavía no hay un teléfono conectado.');
}
SurvivalMesh.addListener('frame', event => receiveChunk(event.data, event.peerId));
SurvivalMesh.addListener('peer', peer => {
  const peers = $('#peers');
  peers.textContent = peer.connected ? 'Conectado: ' + peer.name : 'Detectado: ' + peer.name;
});
SurvivalMesh.addListener('state', state => { if (state.state === 'error') setState('ERROR BLUETOOTH', state.detail || ''); });
$('#start').addEventListener('click', start);
$('#stop').addEventListener('click', stop);
$('#send').addEventListener('click', sendMessage);
$('#compose').addEventListener('keydown', e => { if ((e as KeyboardEvent).key === 'Enter') sendMessage(); });
$('#clear').addEventListener('click', () => { messages = []; seen.clear(); persist(); render(); });
$('#device').textContent = deviceId.slice(0, 8);
render();
