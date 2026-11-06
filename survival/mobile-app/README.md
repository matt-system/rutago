# SURVIVAL native radio chat (foreground MVP)

This directory is the native Android/iOS application. It is separate from the Cloudflare Pages PWA.

## Radio behavior
- BLE GATT service UUID: `8F3A0001-7B2C-4D91-A8F0-535552564956`
- RX characteristic accepts writes; TX characteristic sends notifications.
- Both platforms advertise and scan while the chat screen is open.
- Android asks for Bluetooth Scan/Connect/Advertise permissions (Android 12+) and location permission for BLE scanning on Android 11 and earlier.
- iOS requires Bluetooth privacy descriptions in the app Info.plist.
- Keep SURVIVAL open in the foreground on both phones for this first test version.
- No Internet, Wi-Fi, mobile data, Cloudflare Worker, or backend is involved in radio delivery.

## Build
From `survival/mobile-app`:
```sh
npm install
npm run build
npx cap add android
npx cap sync android
```
Open the generated Android project in Android Studio and build/install the debug APK.

For iOS, run on macOS with Xcode:
```sh
npx cap add ios
npx cap sync ios
```
Add these keys to `ios/App/App/Info.plist`:
- `NSBluetoothAlwaysUsageDescription`: SURVIVAL usa Bluetooth para enviar mensajes directamente a teléfonos cercanos, sin Internet.
- `NSBluetoothPeripheralUsageDescription`: SURVIVAL permite que otros teléfonos cercanos se conecten para intercambiar mensajes offline.

Then open `ios/App/App.xcworkspace` in Xcode, select a development team, and run on a physical iPhone. A simulator cannot test BLE radio.

## Physical test checklist
1. Install the native build on one Android and one iPhone.
2. Enable Bluetooth on both. Grant the requested permissions.
3. Open the Chat screen on both and tap **INICIAR RADIO**.
4. Keep both screens awake and the apps in foreground, phones close together.
5. Wait for a peer to show as detected/connected.
6. Send a short text from Android to iPhone, then reverse direction.
7. Repeat with airplane mode enabled and Wi-Fi/mobile data disabled. Bluetooth must remain on.
8. Test disconnect/reconnect and confirm local history remains.

## Important limitations of this first transport
- This is a BLE GATT relay network, not the Bluetooth SIG Mesh profile.
- Current message frame is deliberately compact for BLE MTU limits; long messages are rejected rather than silently truncated.
- The current MVP does not yet provide end-to-end encryption, delivery receipts, durable retry queues, or background operation.
- Store-and-forward relays only while the app is active and a phone receives a frame.
- Do not use as an emergency service until radio delivery, reconnection, security, and multi-hop behavior have been field-tested.
