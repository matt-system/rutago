# Meshbit

Aplicación Android/iOS en desarrollo, con portal web de instalación independiente.

## Estado honesto de la build 0.2.0
- [x] Base Expo / React Native Android+iOS
- [x] Interfaz terminal
- [x] Sandbox efímero: los textos de prueba ya no se guardan en SQLite sin cifrar
- [x] Portal de descarga desplegado en Cloudflare
- [ ] Integración E2EE con Matrix Rust SDK (Olm/Megolm, verificación de dispositivos y almacenamiento criptográfico)
- [ ] Adaptador nativo BLE GATT central + peripheral para Android e iOS
- [ ] Cola de mensajes cifrados, IDs únicos, TTL, deduplicación y retransmisión multi-hop
- [ ] Transporte online de ciphertext y sincronización
- [ ] Pruebas automatizadas de protocolo y pruebas físicas entre Android/iPhone
- [ ] Builds firmadas APK/AAB e iOS/TestFlight

## Decisiones técnicas y seguridad
No se implementa criptografía propia. La integración E2EE prevista usa Matrix Rust SDK, mantenido por Element/Matrix.org y usado por Element X; incluye cifrado E2EE y gestión de dispositivos/llaves. La app deberá verificar dispositivos, persistir el estado criptográfico de forma segura y no aceptar degradación silenciosa a texto plano.

El paquete react-native-ble-plx se retiró: su documentación declara que no implementa el modo BLE Peripheral, necesario para que un teléfono anuncie un servicio GATT y pueda actuar como nodo retransmisor. Meshbit requiere módulos nativos separados para CoreBluetooth en iOS y BluetoothGattServer/BluetoothLeAdvertiser en Android, además del cliente central en ambos sistemas. El comportamiento en segundo plano tiene restricciones del sistema operativo y debe probarse en teléfonos reales.

## Advertencia
Esta build NO ofrece mensajería real, cifrado E2EE ni Bluetooth mesh. El sandbox no transmite mensajes y solo mantiene el texto en memoria mientras la pantalla está abierta. No usar para información sensible.

## Desarrollo
npm install
npx expo start

BLE y los SDK nativos requieren development builds; Expo Go no es suficiente.

## Native build automation

GitHub Actions workflows are configured for an Android debug APK and an iOS Simulator build. They run on pushes to this feature branch that modify `meshbit/**`, and can also be started manually from the repository Actions tab. Download successful build artifacts from the corresponding workflow run. The iOS Simulator artifact is not installable on a physical iPhone. A signed iOS device build still requires Apple Developer signing credentials. The current app remains a local sandbox: E2EE and BLE transport are not implemented.
