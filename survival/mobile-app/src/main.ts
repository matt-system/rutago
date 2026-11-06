import { SurvivalMesh } from '@survival/mesh';
import './style.css';

type ChatMessage = { id: string; from: string; body: string; at: number; hops: number; };
const $ = (selector: string) => document.querySelector<HTMLElement>(selector)!;
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const storeKey = 'survival-mesh-messages-v1';
const seenKey = 'survival-mesh-seen-v1';
let messages: ChatMessage[] = JSON.parse(localStorage.getItem(storeKey) || '[]');
let seen = new Set<string>(JSON.parse(localStorage.getItem(seenKey) || '[]'));
let running = false;
let deviceId = localStorage.getItem('survival-mesh-device') || crypto.randomUUID();

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
async function sendFrame(frame: object) {
  const data = btoa(String.fromCharCode(...encoder.encode(JSON.stringify(frame))));
  try { const result = await SurvivalMesh.send({ data }); return result.sent; } catch { return 0; }
}
async function receiveFrame(encoded: string) {
  try {
    const raw = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
    const frame = JSON.parse(decoder.decode(raw)) as ChatMessage & { ttl: number };
    if (!frame.id || !frame.body || seen.has(frame.id) || frame.ttl <= 0) return;
    seen.add(frame.id);
    messages.push(frame); persist(); render();
    // Store-and-forward: retransmit once, with a bounded hop count and TTL.
    if (frame.from !== deviceId && frame.hops < 8) {
      await sendFrame({ ...frame, hops: frame.hops + 1, ttl: frame.ttl - 1 });
    }
  } catch { /* Ignore malformed or partial BLE payloads. */ }
}
async function start() {
  if (running) return;
  setState('CONECTANDO', 'Solicitando acceso Bluetooth…');
  try {
    const result = await SurvivalMesh.start({ deviceName: 'SURVIVAL' });
    deviceId = result.deviceId || deviceId;
    localStorage.setItem('survival-mesh-device', deviceId);
    running = true;
    setState('BUSCANDO EQUIPOS', 'Mantén SURVIVAL abierta y Bluetooth encendido.');
  } catch (e) { setState('SIN CONEXIÓN', String(e)); }
}
async function stop() { await SurvivalMesh.stop(); running = false; setState('DESCONECTADO', 'Bluetooth detenido.'); }
async function sendMessage() {
  const input = $('#compose') as HTMLInputElement;
  const body = input.value.trim(); if (!body) return;
  const frame: ChatMessage & { ttl: number } = { id: crypto.randomUUID(), from: deviceId, body, at: Date.now(), hops: 0, ttl: 8 };
  seen.add(frame.id); messages.push(frame); persist(); render(); input.value = '';
  const sent = await sendFrame(frame);
  setState(running ? 'RADIO ACTIVA' : 'GUARDADO EN ESTE TELÉFONO', sent ? `Transmitido a ${sent} conexión(es) directa(s).` : 'No hay teléfonos conectados todavía. Se conserva en este equipo.');
}
SurvivalMesh.addListener('frame', event => receiveFrame(event.data));
SurvivalMesh.addListener('peer', peer => {
  const peers = $('#peers');
  peers.textContent = peer.connected ? 'Equipo conectado: ' + peer.name : 'Equipo detectado: ' + peer.name;
});
SurvivalMesh.addListener('state', state => { if (state.state === 'error') setState('ERROR BLUETOOTH', state.detail || ''); });
$('#start').addEventListener('click', start);
$('#stop').addEventListener('click', stop);
$('#send').addEventListener('click', sendMessage);
$('#compose').addEventListener('keydown', e => { if ((e as KeyboardEvent).key === 'Enter') sendMessage(); });
$('#clear').addEventListener('click', () => { messages = []; seen.clear(); persist(); render(); });
$('#device').textContent = deviceId.slice(0, 8);
render();
