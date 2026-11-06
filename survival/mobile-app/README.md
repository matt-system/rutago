# SURVIVAL native BLE chat

## Target for the first field test
Both phones keep SURVIVAL open in the foreground, Bluetooth enabled, and the chat screen visible. This build does not claim background or screen-off relay support.

## Build Android
The GitHub Actions workflow `.github/workflows/survival-android.yml` builds a debug APK on pushes to the `survival` branch. Download the `survival-android-debug` artifact from the successful Actions run and install it on the Android phone. Debug APKs are for testing, not Play Store distribution.

## Build iOS
On a Mac with Xcode:
1. In `survival/mobile-app`, run `npm install`, `npm run build`, `npx cap add ios`, and `npx cap sync ios`.
2. Open the generated `ios/App/App.xcworkspace` in Xcode.
3. In the app target's Info tab, add `NSBluetoothAlwaysUsageDescription` with: `SURVIVAL usa Bluetooth para encontrar teléfonos cercanos e intercambiar mensajes sin Internet.`
4. Select a valid Apple Development team and a connected iPhone, then build and install from Xcode.

An iPhone build cannot be installed on a physical iPhone until it is signed with an Apple Development/Distribution identity and provisioned for that device (or distributed through TestFlight). Do not publish an unsigned IPA as if it were installable.

## Field test
- Install the app on one Android and one iPhone.
- Enable Bluetooth and grant the requested permission.
- Keep both phones unlocked, SURVIVAL open, and tap INICIAR RADIO on each.
- Wait up to 20 seconds for discovery and GATT connection.
- Send a short test message in both directions.
- Repeat with a longer message to test BLE fragmentation.
- Turn off Wi-Fi and mobile data on both devices during the test. Bluetooth must remain on.
- Record device models, OS versions, connection status, and whether messages arrived in both directions.

## Important engineering limits
BLE is a short-range, best-effort radio. This implementation uses a custom GATT service with both central and peripheral roles and a store-and-forward message envelope. It is not Bluetooth SIG Mesh certification. A multi-hop path requires participating phones to remain active and connected; iOS may throttle scanning/advertising and the app must remain foreground for this first test.
