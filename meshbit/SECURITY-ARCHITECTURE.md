# Meshbit — arquitectura de seguridad y transporte

## Primera etapa: mensajería online cifrada 1 a 1
- La identidad local tiene una clave Curve25519 para cifrado y una clave Ed25519 para firmas.
- Las claves privadas y el token de sesión se guardan en Expo SecureStore.
- Cada mensaje usa una clave efímera Curve25519 nueva, un nonce aleatorio y cifrado autenticado TweetNaCl box dirigido a la clave pública del destinatario.
- El emisor firma el sobre (ID, destinatario, clave efímera pública, nonce y ciphertext) con Ed25519.
- El destinatario verifica la firma y descifra localmente.
- Cloudflare D1 conserva solo el sobre cifrado y los datos mínimos de entrega. El Worker autentica por token aleatorio; en D1 se almacena únicamente el hash SHA-256 del token.
- Los mensajes se eliminan al confirmar recepción o al expirar a los siete días.

## Límites y controles pendientes
- No es Signal Protocol: falta un ratchet de doble vía, rotación/recuperación de claves y soporte multi-dispositivo.
- Una clave pública descargada del directorio necesita verificación independiente de huella para evitar sustitución maliciosa.
- La pérdida del dispositivo implica pérdida de identidad en esta versión.
- Requiere pruebas físicas entre dos dispositivos, inspección del tráfico y revisión independiente antes de uso sensible.

## Segunda etapa: Bluetooth LE mesh
- El mismo sobre cifrado se podrá transportar por Internet o BLE sin modificar el ciphertext.
- iOS: CoreBluetooth central + peripheral manager, capacidades background y restauración de estado.
- Android: BluetoothLeScanner + BluetoothLeAdvertiser + GATT client/server.
- Paquetes con ID único, TTL/hop limit, deduplicación, expiración y límites de tamaño.
- Store-and-forward solo retransmite ciphertext; los nodos intermedios no poseen claves.
- El alcance y funcionamiento en segundo plano dependen de proximidad, batería, permisos y restricciones del sistema operativo.

## Puertas de seguridad antes de producción
1. Pruebas automatizadas de cifrado/descifrado y rechazo de firmas inválidas.
2. Pruebas físicas entre dos cuentas y dos teléfonos.
3. Verificación de huellas por canal independiente.
4. Inspección de tráfico y logs: ningún mensaje en claro ni claves privadas en el backend.
5. Pruebas de pérdida/recuperación de dispositivo y rotación de claves.
6. Auditoría externa.
7. Pruebas BLE Android↔Android, iPhone↔iPhone y Android↔iPhone cuando comience la segunda etapa.
