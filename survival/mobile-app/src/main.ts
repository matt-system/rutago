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

async function sendFrame(frame: ChatMessage & { ttl: number }) {
  // Compact wire format keeps a short text message within a negotiated BLE ATT packet.
  const wire: WireMessage = { i: frame.id, f: frame.from, b: frame.body, t: frame.at.toString(36), h: frame.hops, l: frame.ttl };
  const bytes = encoder.encode(JSON.stringify(wire));
  if (bytes.length > 160) { setState('MENSAJE MUY LARGO', 'Reduce el texto para transmitirlo por Bluetooth.'); return 0; }
  const data = btoa(String.fromCharCode(...bytes));
  try { return (await SurvivalMesh.send({ data })).sent; } catch (e) { setState('ERROR DE ENVÍO', String(e)); return 0; }
}
async function receiveFrame(encoded: string) {
  try {
    const raw = Uint8Array.from(atob(encoded), c => c.charCodeAt(0));
    const w = JSON.parse(decoder.decode(raw)) as WireMessage;
    const frame: ChatMessage & { ttl: number } = { id: w.i, from: w.f, body: w.b, at: parseInt(w.t,36), hops: w.h, ttl: w.l };
    if (!frame.id || !frame.body || seen.has(frame.id) || frame.ttl <= 0) return;
    seen.add(frame.id); messages.push(frame); persist(); render();
    if (frame.from !== deviceId && frame.hops < 8 && running) {
      await sendFrame({ ...frame, hops: frame.hops + 1, ttl: frame.ttl - 1 });
    }
  } catch { /* Ignore invalid BLE frames. */ }
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
SurvivalMesh.addListener('frame', event => { void receiveFrame(event.data); });
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
