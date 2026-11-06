# Meshbit — arquitectura de seguridad y transporte

## Objetivo
Mensajes de extremo a extremo que mantengan el mismo ciphertext al viajar por Internet, BLE directo o nodos intermedios. Los relays no reciben claves de descifrado.

## E2EE
- Integrar Matrix Rust SDK / matrix-sdk-crypto mediante bindings nativos oficiales UniFFI (Swift y Kotlin).
- Usar sesiones Olm para comunicación entre dispositivos y Megolm para salas/grupos, con gestión de claves, rotación y recuperación según las capacidades del SDK.
- Verificar identidad y dispositivos mediante cross-signing / SAS. Mostrar claramente dispositivos no verificados y no compartirles claves de salas.
- Guardar secretos y estado criptográfico con almacenamiento nativo protegido; nunca enviar claves privadas al Worker.
- El backend Cloudflare solo enruta y almacena ciphertext y metadatos mínimos. Minimizar metadatos y definir retención.
- No diseñar un protocolo criptográfico propio ni presentar cifrado como activo antes de completar pruebas de interoperabilidad y revisión.

## BLE mesh
react-native-ble-plx solo cubre operaciones BLE central y no ofrece el modo peripheral requerido para teléfono-a-teléfono bidireccional. Por eso no se usa como solución mesh.

Implementar una capa nativa:
- iOS: CoreBluetooth central + peripheral manager; declarar capacidades de background, restauración de estado y UUID de servicio propio.
- Android: BluetoothLeScanner + BluetoothLeAdvertiser + GATT client/server; permisos runtime para versiones Android soportadas.
- Protocolo de paquetes: versión, message_id aleatorio, sender_key_id, TTL/hop_limit, timestamp aproximado y ciphertext opaco.
- Retransmisión store-and-forward con deduplicación, límites de tamaño/cola, expiración y protección contra loops.
- El relay no modifica ni descifra ciphertext.
- BLE no promete alcance ilimitado: cada salto depende de proximidad, radio, batería, permisos y que el SO mantenga el proceso/servicio activo.

## Transporte online
- Un mismo sobre cifrado viaja por WebSocket/HTTP online o por BLE.
- Cloudflare Durable Objects pueden coordinar presencia/entrega, pero nunca terminan el cifrado ni poseen las claves.
- La app debe soportar reintentos, ACK, orden parcial y deduplicación.

## Puertas de seguridad antes de producción
1. Pruebas de vector criptográfico y compatibilidad con otro cliente Matrix.
2. Verificación SAS y cross-signing entre dos dispositivos.
3. Inspección de tráfico: ningún mensaje en claro en backend/logs.
4. Pruebas de restauración de claves, cambio de dispositivo y pérdida de sesión.
5. Pruebas BLE GATT Android↔Android, iPhone↔iPhone y Android↔iPhone, con app foreground/background.
6. Pruebas de replay, duplicados, TTL, mensajes grandes y nodos maliciosos.
7. Auditoría externa antes de prometer seguridad para comunicaciones sensibles.
