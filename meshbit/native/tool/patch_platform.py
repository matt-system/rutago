from pathlib import Path
import plistlib
import re

root = Path(__file__).resolve().parents[1]
manifest = root / "android/app/src/main/AndroidManifest.xml"
if manifest.exists():
    text = manifest.read_text()
    permissions = """
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADVERTISE" />
    <uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
    <uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />
    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />
"""
    if "android.permission.BLUETOOTH_SCAN" not in text:
        text = text.replace("<application", permissions + "\n    <application", 1)
    text = re.sub(r'android:label="[^"]+"', 'android:label="MESHBIT"', text, count=1)
    manifest.write_text(text)

plist = root / "ios/Runner/Info.plist"
if plist.exists():
    with plist.open("rb") as f:
        data = plistlib.load(f)
    data["CFBundleDisplayName"] = "MESHBIT"
    data["NSBluetoothAlwaysUsageDescription"] = "MESHBIT usa Bluetooth para descubrir teléfonos cercanos y retransmitir mensajes sin internet."
    data["NSBluetoothPeripheralUsageDescription"] = "MESHBIT usa Bluetooth para permitir que otros teléfonos cercanos se conecten a este dispositivo."
    with plist.open("wb") as f:
        plistlib.dump(data, f)
print("Platform permissions configured.")
