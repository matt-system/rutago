# Meshbit

Aplicación Android/iOS en desarrollo. El portal y el relay de mensajes están alojados en Cloudflare, separados de RutaGo.

## Estado actual
- [x] Base Expo / React Native Android+iOS.
- [x] Portal Meshbit desplegado en Cloudflare.
- [x] Base de datos D1 propia y aislada: `meshbit-private-messages`.
- [x] API de registro, directorio de claves públicas, envío, buzón y confirmación de entrega (desplegada; prueba externa pendiente).
- [~] Cifrado autenticado implementado en el cliente para mensajes 1 a 1 (TweetNaCl box + firma Ed25519); pruebas cruzadas pendientes.
- [x] Claves privadas y token de sesión guardados con Expo SecureStore.
- [~] PWA experimental Android/iOS con registro, bóveda local cifrada, verificación manual de huellas, envío/recepción E2EE y relay D1; despliegue inicial realizado, pruebas físicas pendientes.\n- [ ] Verificación integral del envío/recepción en dos cuentas y dispositivos físicos Android/iOS.
- [ ] Ratchet de doble vía / forward secrecy completa, multi-dispositivo y recuperación segura de cuenta.
- [ ] Revisión de seguridad externa.
- [ ] Bluetooth LE mesh (aplazado para una segunda etapa).
- [ ] Builds firmadas y distribución final.

## PWA de pruebas\n- Portal: https://meshbit.matthieupierremarie.workers.dev/\n- Aplicación: https://meshbit.matthieupierremarie.workers.dev/app/\n- La PWA usa TweetNaCl en el navegador y cifra la bóveda local con AES-GCM derivado mediante PBKDF2. El service worker cachea únicamente archivos estáticos y excluye las rutas `/api/`.\n- Para probar: instala la PWA en dos dispositivos, crea una cuenta diferente en cada uno, comparte los nombres de usuario y verifica manualmente las huellas por otro canal antes de conversar.\n- Esta PWA sigue siendo experimental y no implementa Signal Protocol ni Double Ratchet; no usar para información sensible o de alto riesgo.\n\n## Diseño de seguridad de esta beta
1. El teléfono genera una identidad de cifrado Curve25519 y una identidad de firma Ed25519.
2. Las claves privadas permanecen en SecureStore en el dispositivo.
3. Para cada mensaje, el emisor crea una clave Curve25519 efímera, cifra el contenido con autenticación usando la clave pública del destinatario y firma el sobre.
4. Cloudflare recibe únicamente el ciphertext, nonce, clave efímera pública, firma y metadatos mínimos de entrega.
5. El teléfono destinatario verifica la firma y descifra localmente.
6. Los mensajes pendientes se eliminan al confirmarse su recepción o al cumplir siete días.

El relay no recibe las claves privadas ni el texto plano. La API autentica cada cuenta con un token aleatorio cuyo hash se guarda en D1.

## Límites importantes
- Esta implementación inicial no es el protocolo Signal y todavía no ofrece un ratchet de doble vía ni protección completa frente al compromiso posterior de una clave del destinatario.
- La primera cuenta queda ligada al dispositivo. Si se borra la app o se pierde el teléfono, no existe recuperación de identidad.
- La huella de clave debe compararse con el contacto por un canal independiente. El directorio de claves del servidor, por sí solo, no autentica la identidad humana.
- No hay chats grupales ni sincronización multi-dispositivo.
- No usar para comunicaciones de alto riesgo hasta completar pruebas y revisión externa.
- Bluetooth mesh no está habilitado en esta etapa.

## Tests

El test automático comprueba las primitivas TweetNaCl usadas (cifrado/descifrado, firma y rechazo de alteraciones). No sustituye una prueba de extremo a extremo entre dos instalaciones ni una auditoría.

## Cloudflare
- Worker: `meshbit`
- D1: `meshbit-private-messages`
- Schema: `server/schema.sql`
- API Worker: `server/worker.js`

## Desarrollo
```bash
npm install
npm run typecheck
npm run test:crypto
npx expo start
```

Las funciones nativas requieren una build de desarrollo o release; Expo Go no es suficiente para validar el almacenamiento seguro en builds reales.
