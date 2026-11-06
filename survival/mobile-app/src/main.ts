import { SurvivalMesh } from '@survival/mesh';
import './style.css';

type ChatMessage = { id: string; from: string; body: string; at: number; hops: number; };
type WireMessage = { i: string; f: string; b: string; t: string; h: number; l: number; };
const $ = (selector: string) => document.querySelector<HTMLElement>(selector)!;
const encoder = new TextEncoder();
const decoder = new TextDecoder();
const storeKey = 'survival-mesh-messages-v2';
const seenKey = 'survival-mesh-seen-v2';
let messages: ChatMessage[] = JSON.parse(localStorage.getItem(storeKey) || '[]');
let seen = new Set<string>(JSON.parse(localStorage.getItem(seenKey) || '[]'));
let running = false;
let deviceId = localStorage.getItem('survival-mesh-device') || crypto.randomUUID().replaceAll('-', '').slice(0, 8);
localStorage.setItem('survival-mesh-device', deviceId);

function persist() {
  messages = messages.slice(-500);
  localStorage.setItem(storeKey, JSON.stringify(messages));
  localStorage.setItem(seenKey, JSON.stringify([...seen].slice(-2000)));
}
function render() {
  const list = $('#messages');
  list.innerHTML = messages.map(m => `<article class="msg ${m.from === deviceId ? 'mine' : ''}"><small>${m.from === deviceId ? 'TÚ' : 'DISPOSITIVO '+escapeHtml(m.from.slice(0,8))} · ${new Date(m.at).toLocaleTimeString()}</small><p>${escapeHtml(m.body)}</p><small>saltos: ${m.hops}</small></article>`).join('');
  list.scrollTop = list.scrollHeight;
  $('#count').textContent = String(messages.length);
}
function escapeHtml(s: string) { return s.replace(/[&<>"']/g, c => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]!)); }
function setState(s: string, detail = '') { $('#status').textContent = s; $('#detail').textContent = detail; }

const fragments = new Map<string, { parts: string[]; total: number; from: string; }>();
async function sendFrame(frame: ChatMessage & { ttl: number }) {
  const wire: WireMessage = { i: frame.id, f: frame.from, b: frame.body, t: frame.at.toString(36), h: frame.hops, l: frame.ttl };
  const bytes = encoder.encode(JSON.stringify(wire));
  if (bytes.length > 160) { setState('MENSAJE MUY LARGO', 'Reduce el texto para transmitirlo por Bluetooth.'); return 0; }
  const packetId = Math.floor(Math.random() * 65536);
  const chunkSize = 14, total = Math.ceil(bytes.length / chunkSize);
  let sent = 0;
  try {
    for (let index = 0; index < total; index++) {
      const chunk = bytes.slice(index * chunkSize, Math.min(bytes.length, (index + 1) * chunkSize));
      const packet = new Uint8Array(6 + chunk.length);
      packet[0] = 0x53; packet[1] = 0x56; packet[2] = packetId >> 8; packet[3] = packetId & 255; packet[4] = index; packet[5] = total;
      packet.set(chunk, 6);
      const data = btoa(String.fromCharCode(...packet));
      const result = await SurvivalMesh.send({ data });
      if (index === 0) sent = result.sent;
      if (result.sent === 0) { setState('ENVÍO INTERRUMPIDO', 'Se perdió el enlace durante la transmisión. Acércate al otro teléfono e inténtalo de nuevo.'); return 0; }
      if (index < total - 1) await new Promise(resolve => setTimeout(resolve, 65));
    }
    return sent;
  } catch (e) { setState('ERROR DE ENVÍO', String(e)); return 0; }
}
async function receiveFrame(encoded: string, peerId = 'peer') {
  try {
    const packet = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
    if (packet.length < 7 || packet[0] !== 0x53 || packet[1] !== 0x56) return;
    const packetId = (packet[2] << 8) | packet[3], index = packet[4], total = packet[5];
    if (!total || total > 16 || index >= total) return;
    const key = peerId + ':' + packetId;
    let entry = fragments.get(key);
    if (!entry) { entry = { parts: new Array(total), total, from: peerId }; fragments.set(key, entry); }
    if (entry.total !== total || entry.parts[index]) return;
    entry.parts[index] = btoa(String.fromCharCode(...packet.slice(6)));
    if (entry.parts.filter(Boolean).length !== total) return;
    fragments.delete(key);
    const joined = entry.parts.map(part => Uint8Array.from(atob(part), ch => ch.charCodeAt(0)));
    const length = joined.reduce((n, part) => n + part.length, 0), raw = new Uint8Array(length);
    let offset = 0; for (const part of joined) { raw.set(part, offset); offset += part.length; }
    const w = JSON.parse(decoder.decode(raw)) as WireMessage;
    const frame: ChatMessage & { ttl: number } = { id: w.i, from: w.f, body: w.b, at: parseInt(w.t,36), hops: w.h, ttl: w.l };
    if (!frame.id || !frame.body || seen.has(frame.id) || frame.ttl <= 0) return;
    seen.add(frame.id); messages.push(frame); persist(); render();
    if (frame.from !== deviceId && frame.hops < 8 && running) await sendFrame({ ...frame, hops: frame.hops + 1, ttl: frame.ttl - 1 });
  } catch { /* Ignore incomplete or invalid BLE frames. */ }
}
async function start() {
  if (running) return;
  setState('CONECTANDO', 'Acepta el permiso Bluetooth si el teléfono lo solicita.');
  try {
    await SurvivalMesh.start({ deviceName: 'SURVIVAL' });
    running = true;
    setState('RADIO ACTIVA', 'Buscando teléfonos SURVIVAL cercanos. Mantén esta pantalla abierta.');
  } catch (e) { setState('SIN RADIO', String(e)); }
}
async function stop() {
  await SurvivalMesh.stop(); running = false;
  setState('RADIO DETENIDA', 'Tus mensajes guardados siguen en este teléfono.');
}
async function sendMessage() {
  const input = $('#compose') as HTMLInputElement;
  const body = input.value.trim();
  if (!body) return;
  if (body.length > 80) { setState('MENSAJE MUY LARGO', 'Máximo 80 caracteres por mensaje en esta versión de radio.'); return; }
  const frame = { id: crypto.randomUUID().replaceAll('-', '').slice(0,12), from: deviceId, body, at: Date.now(), hops: 0, ttl: 8 };
  seen.add(frame.id); messages.push(frame); persist(); render(); input.value = '';
  const sent = await sendFrame(frame);
  setState(running ? 'RADIO ACTIVA' : 'SOLO EN ESTE TELÉFONO', sent ? `Enviado por Bluetooth a ${sent} conexión(es).` : 'No hay otro teléfono conectado. El mensaje quedó guardado localmente.');
}
SurvivalMesh.addListener('frame', event => { void receiveFrame(event.data, event.peerId || 'peer'); });
SurvivalMesh.addListener('peer', peer => {
  $('#peers').textContent = peer.connected ? 'Conectado: ' + peer.name : 'Detectado: ' + peer.name;
});
SurvivalMesh.addListener('state', state => {
  if (state.state === 'error' || state.state === 'unavailable') setState('REVISAR BLUETOOTH', state.detail || state.state);
});
$('#start').addEventListener('click', () => { void start(); });
$('#stop').addEventListener('click', () => { void stop(); });
$('#send').addEventListener('click', () => { void sendMessage(); });
$('#compose').addEventListener('keydown', e => { if ((e as KeyboardEvent).key === 'Enter') void sendMessage(); });
$('#clear').addEventListener('click', () => { messages = []; seen.clear(); persist(); render(); });
$('#device').textContent = deviceId;
render();
