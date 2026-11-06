# Meshbit

Aplicación móvil Android/iOS y web de pruebas. Esta rama es independiente del código de RutaGo.

## Estado
- [x] Base de proyecto Expo / React Native compartida para Android e iOS
- [x] Interfaz terminal y almacenamiento local de mensajes de prueba
- [ ] Identidad criptográfica y verificación de claves
- [ ] Mensajería E2E auditada
- [ ] Transporte online con sincronización
- [ ] Transporte BLE mesh entre Android/iOS
- [ ] Builds firmadas y publicación en tiendas

**Importante:** esta primera entrega es un prototipo de interfaz y almacenamiento local. No ofrece todavía mensajería real ni cifrado E2E. No usar para información sensible.

## Desarrollo
`npm install`
`npx expo start`

Para builds de dispositivo se requiere configurar EAS y credenciales de firma de Android/iOS. BLE necesita development builds; Expo Go no basta.
