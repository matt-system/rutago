import Foundation
import Capacitor
import CoreBluetooth
import UIKit

@objc(SurvivalMeshPlugin)
public class SurvivalMeshPlugin: CAPPlugin, CAPBridgedPlugin, CBCentralManagerDelegate, CBPeripheralManagerDelegate, CBPeripheralDelegate {
    public let identifier = "SurvivalMeshPlugin"
    public let jsName = "SurvivalMesh"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "start", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "stop", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "send", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPeers", returnType: CAPPluginReturnPromise)
    ]
    private let serviceUUID = CBUUID(string: "8F3A0001-7B2C-4D91-A8F0-535552564956")
    private let rxUUID = CBUUID(string: "8F3A0002-7B2C-4D91-A8F0-535552564956")
    private let txUUID = CBUUID(string: "8F3A0003-7B2C-4D91-A8F0-535552564956")
    private var central: CBCentralManager!
    private var peripheralManager: CBPeripheralManager!
    private var peers: [UUID: CBPeripheral] = [:]
    private var characteristics: [UUID: CBCharacteristic] = [:]
    private var subscribed: [CBCentral] = []
    private var rx: CBMutableCharacteristic!
    private var tx: CBMutableCharacteristic!
    private var deviceName = "SURVIVAL"
    private var started = false

    public override func load() {
        central = CBCentralManager(delegate: self, queue: nil, options: nil)
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil, options: nil)
    }
    @objc public func start(_ call: CAPPluginCall) {
        deviceName = call.getString("deviceName") ?? "SURVIVAL"
        started = true
        if central.state == .poweredOn { central.scanForPeripherals(withServices: [serviceUUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]) }
        if peripheralManager.state == .poweredOn { publishService() }
        call.resolve(["deviceId": UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString, "scanning": central.state == .poweredOn, "advertising": peripheralManager.state == .poweredOn])
    }
    @objc public func stop(_ call: CAPPluginCall) {
        started = false; central.stopScan(); peripheralManager.stopAdvertising(); peripheralManager.removeAllServices()
        call.resolve()
    }
    private func publishService() {
        peripheralManager.stopAdvertising(); peripheralManager.removeAllServices()
        rx = CBMutableCharacteristic(type: rxUUID, properties: [.write, .writeWithoutResponse], value: nil, permissions: [.writeable])
        tx = CBMutableCharacteristic(type: txUUID, properties: [.notify, .read], value: nil, permissions: [.readable])
        let service = CBMutableService(type: serviceUUID, primary: true); service.characteristics = [rx, tx]
        peripheralManager.add(service)
    }
    @objc public func send(_ call: CAPPluginCall) {
        guard let encoded = call.getString("data"), let data = Data(base64Encoded: encoded) else { call.reject("Frame base64 inválido"); return }
        guard data.count <= 20 else { call.reject("El paquete BLE supera 20 bytes"); return }
        var sent = 0
        for (id, characteristic) in characteristics {
            if let target = peers[id], target.state == .connected {
                guard target.canSendWriteWithoutResponse, data.count <= target.maximumWriteValueLength(for: .withoutResponse) else { continue }
                target.writeValue(data, for: characteristic, type: .withoutResponse); sent += 1
            }
        }
        if tx != nil && !subscribed.isEmpty {
            let ok = peripheralManager.updateValue(data, for: tx, onSubscribedCentrals: nil)
            if ok { sent += subscribed.count }
        }
        call.resolve(["sent": sent])
    }
    @objc public func getPeers(_ call: CAPPluginCall) {
        let rows = peers.map { id, p in ["id": id.uuidString, "name": p.name ?? "SURVIVAL", "connected": p.state == .connected] as [String: Any] }
        call.resolve(["peers": rows])
    }
    public func centralManagerDidUpdateState(_ manager: CBCentralManager) {
        notifyListeners("state", data: ["state": manager.state == .poweredOn ? "ready" : "unavailable", "detail": "Bluetooth central"])
        if started && manager.state == .poweredOn { manager.scanForPeripherals(withServices: [serviceUUID], options: nil) }
    }
    public func peripheralManagerDidUpdateState(_ manager: CBPeripheralManager) {
        notifyListeners("state", data: ["state": manager.state == .poweredOn ? "ready" : "unavailable", "detail": "Bluetooth peripheral"])
        if started && manager.state == .poweredOn { publishService() }
    }
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if error == nil && started { peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [serviceUUID], CBAdvertisementDataLocalNameKey: deviceName]) }
        else if let error { notifyListeners("state", data: ["state": "error", "detail": error.localizedDescription]) }
    }
    public func centralManager(_ manager: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        peers[p.identifier] = p; p.delegate = self
        notifyListeners("peer", data: ["id": p.identifier.uuidString, "name": p.name ?? deviceName, "rssi": RSSI.intValue, "connected": p.state == .connected])
        if p.state == .disconnected { manager.connect(p, options: nil) }
    }
    public func centralManager(_ manager: CBCentralManager, didConnect p: CBPeripheral) {
        notifyListeners("peer", data: ["id": p.identifier.uuidString, "name": p.name ?? deviceName, "connected": true])
        p.discoverServices([serviceUUID])
    }
    public func centralManager(_ manager: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        notifyListeners("peer", data: ["id": p.identifier.uuidString, "name": p.name ?? deviceName, "connected": false])
        if started { manager.connect(p, options: nil) }
    }
    public func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        guard let service = p.services?.first(where: { $0.uuid == serviceUUID }) else { return }; p.discoverCharacteristics([rxUUID, txUUID], for: service)
    }
    public func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        for c in service.characteristics ?? [] {
            if c.uuid == rxUUID { characteristics[p.identifier] = c }
            if c.uuid == txUUID { p.setNotifyValue(true, for: c) }
        }
    }
    public func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        if let data = c.value { notifyListeners("frame", data: ["data": data.base64EncodedString(), "peerId": p.identifier.uuidString]) }
    }
    public func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        if !subscribed.contains(where: { $0.identifier == central.identifier }) { subscribed.append(central) }
    }
    public func peripheralManager(_ manager: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        subscribed.removeAll(where: { $0.identifier == central.identifier })
    }
    public func peripheralManager(_ manager: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let data = request.value { notifyListeners("frame", data: ["data": data.base64EncodedString(), "peerId": request.central.identifier.uuidString]) }
            manager.respond(to: request, withResult: .success)
        }
    }
}