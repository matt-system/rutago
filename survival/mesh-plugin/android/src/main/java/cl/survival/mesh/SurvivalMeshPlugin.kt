package cl.survival.mesh

import android.Manifest
import android.bluetooth.*
import android.bluetooth.le.*
import android.content.Context
import android.os.ParcelUuid
import android.util.Base64
import com.getcapacitor.*
import com.getcapacitor.annotation.CapacitorPlugin
import com.getcapacitor.annotation.Permission
import com.getcapacitor.annotation.PermissionCallback
import com.getcapacitor.annotation.PermissionCallback
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap

@CapacitorPlugin(
    name = "SurvivalMesh",
    permissions = [
        Permission(alias = "bluetooth", strings = [
            Manifest.permission.BLUETOOTH_SCAN,
            Manifest.permission.BLUETOOTH_CONNECT,
            Manifest.permission.BLUETOOTH_ADVERTISE,
            Manifest.permission.ACCESS_FINE_LOCATION
        ])
    ]
)
class SurvivalMeshPlugin : Plugin() {
    companion object {
        val SERVICE = UUID.fromString("8F3A0001-7B2C-4D91-A8F0-535552564956")
        val RX = UUID.fromString("8F3A0002-7B2C-4D91-A8F0-535552564956")
        val TX = UUID.fromString("8F3A0003-7B2C-4D91-A8F0-535552564956")
    }
    private lateinit var adapter: BluetoothAdapter
    private var scanner: BluetoothLeScanner? = null
    private var advertiser: BluetoothLeAdvertiser? = null
    private var server: BluetoothGattServer? = null
    private var scanCallback: ScanCallback? = null
    private val clients = ConcurrentHashMap<String, BluetoothGatt>()
    private val rxChars = ConcurrentHashMap<String, BluetoothGattCharacteristic>()
    private val txChars = ConcurrentHashMap<String, BluetoothGattCharacteristic>()
    private val connectedClientIds = ConcurrentHashMap.newKeySet<String>()
    private val connectedServers = ConcurrentHashMap<String, BluetoothDevice>()
    private val connectedClientIds = ConcurrentHashMap.newKeySet<String>()
    private var txServer: BluetoothGattCharacteristic? = null
    private var started = false
    private var deviceName = "SURVIVAL"

    @PluginMethod
    fun start(call: PluginCall) {
        deviceName = call.getString("deviceName") ?: "SURVIVAL"
        if (getPermissionState("bluetooth") != PermissionState.GRANTED) {
            requestPermissionForAlias("bluetooth", call, "startWithPermission")
            return
        }
        startWithPermission(call)
    }

    @PermissionCallback
    fun startWithPermission(call: PluginCall) {
        try {
            val manager = context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager
            adapter = manager.adapter
            if (!adapter.isEnabled) { call.reject("Activa Bluetooth para usar el chat"); return }
            started = true
            adapter.name = deviceName
            scanner = adapter.bluetoothLeScanner
            advertiser = adapter.bluetoothLeAdvertiser
            startGattServer(manager)
            startAdvertising()
            startScanning()
            val ret = JSObject()
            ret.put("deviceId", UUID.randomUUID().toString())
            ret.put("scanning", true); ret.put("advertising", true)
            call.resolve(ret)
        } catch (e: Exception) { call.reject("No se pudo iniciar BLE: ${e.message}") }
    }

    private fun startGattServer(manager: BluetoothManager) {
        server?.close()
        server = manager.openGattServer(context, serverCallback)
        val rx = BluetoothGattCharacteristic(RX, BluetoothGattCharacteristic.PROPERTY_WRITE or BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE, BluetoothGattCharacteristic.PERMISSION_WRITE)
        val tx = BluetoothGattCharacteristic(TX, BluetoothGattCharacteristic.PROPERTY_NOTIFY or BluetoothGattCharacteristic.PROPERTY_READ, BluetoothGattCharacteristic.PERMISSION_READ)
        tx.addDescriptor(BluetoothGattDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"), BluetoothGattDescriptor.PERMISSION_READ or BluetoothGattDescriptor.PERMISSION_WRITE))
        txServer = tx
        val service = BluetoothGattService(SERVICE, BluetoothGattService.SERVICE_TYPE_PRIMARY)
        service.addCharacteristic(rx); service.addCharacteristic(tx)
        server?.addService(service)
    }

    private fun startAdvertising() {
        val settings = AdvertiseSettings.Builder().setAdvertiseMode(AdvertiseSettings.ADVERTISE_MODE_LOW_LATENCY).setTxPowerLevel(AdvertiseSettings.ADVERTISE_TX_POWER_MEDIUM).setConnectable(true).build()
        val data = AdvertiseData.Builder().addServiceUuid(ParcelUuid(SERVICE)).setIncludeDeviceName(false).build()
        advertiser?.startAdvertising(settings, data, advertiseCallback)
    }
    private fun startScanning() {
        val filter = ScanFilter.Builder().setServiceUuid(ParcelUuid(SERVICE)).build()
        val settings = ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        scanCallback = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) {
                val d = result.device
                val id = d.address ?: return
                notifyListeners("peer", JSObject().apply {
                    put("id", id); put("name", d.name ?: "SURVIVAL"); put("rssi", result.rssi); put("connected", connectedClientIds.contains(id))
                })
                if (!clients.containsKey(id)) {
                    try { clients[id] = d.connectGatt(context, false, clientCallback, BluetoothDevice.TRANSPORT_LE) } catch (_: Exception) {}
                }
            }
            override fun onScanFailed(errorCode: Int) { notifyListeners("state", JSObject().put("state", "error").put("detail", "BLE scan error $errorCode")) }
        }
        scanner?.startScan(listOf(filter), settings, scanCallback)
    }
    private val advertiseCallback = object : AdvertiseCallback() {
        override fun onStartSuccess(settings: AdvertiseSettings) { notifyListeners("state", JSObject().put("state", "ready").put("detail", "Advertising")) }
        override fun onStartFailure(errorCode: Int) { notifyListeners("state", JSObject().put("state", "error").put("detail", "BLE advertise error $errorCode")) }
    }
    private val serverCallback = object : BluetoothGattServerCallback() {
        override fun onConnectionStateChange(device: BluetoothDevice, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) connectedServers[device.address] = device
            else connectedServers.remove(device.address)
            notifyListeners("peer", JSObject().put("id", device.address).put("name", device.name ?: "SURVIVAL").put("connected", newState == BluetoothProfile.STATE_CONNECTED))
        }
        override fun onCharacteristicWriteRequest(device: BluetoothDevice, requestId: Int, characteristic: BluetoothGattCharacteristic, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
            notifyListeners("frame", JSObject().put("data", Base64.encodeToString(value, Base64.NO_WRAP)).put("peerId", device.address))
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
        }
        override fun onDescriptorWriteRequest(device: BluetoothDevice, requestId: Int, descriptor: BluetoothGattDescriptor, preparedWrite: Boolean, responseNeeded: Boolean, offset: Int, value: ByteArray) {
            descriptor.value = value
            if (responseNeeded) server?.sendResponse(device, requestId, BluetoothGatt.GATT_SUCCESS, offset, value)
        }
    }
    private val clientCallback = object : BluetoothGattCallback() {
        override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
            if (newState == BluetoothProfile.STATE_CONNECTED) { connectedClientIds.add(gatt.device.address); gatt.requestMtu(185) }
            else { connectedClientIds.remove(gatt.device.address); clients.remove(gatt.device.address); rxChars.remove(gatt.device.address); txChars.remove(gatt.device.address); gatt.close() }
        }
        override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
            if (status == BluetoothGatt.GATT_SUCCESS) gatt.discoverServices()
            else gatt.discoverServices()
        }
        override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
            val service = gatt.getService(SERVICE) ?: return
            service.getCharacteristic(RX)?.let { rxChars[gatt.device.address] = it }
            service.getCharacteristic(TX)?.let { c ->
                txChars[gatt.device.address] = c
                gatt.setCharacteristicNotification(c, true)
                c.getDescriptor(UUID.fromString("00002902-0000-1000-8000-00805f9b34fb"))?.let { d ->
                    d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    gatt.writeDescriptor(d)
                }
            }
        }
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
            characteristic.value?.let { notifyListeners("frame", JSObject().put("data", Base64.encodeToString(it, Base64.NO_WRAP)).put("peerId", gatt.device.address)) }
        }
        override fun onCharacteristicChanged(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic, value: ByteArray) {
            notifyListeners("frame", JSObject().put("data", Base64.encodeToString(value, Base64.NO_WRAP)).put("peerId", gatt.device.address))
        }
    }

    @PluginMethod
    fun send(call: PluginCall) {
        val encoded = call.getString("data") ?: run { call.reject("Falta data"); return }
        val bytes = try { Base64.decode(encoded, Base64.DEFAULT) } catch (_: Exception) { call.reject("Base64 inválido"); return }
        var sent = 0
        for ((id, gatt) in clients) {
            val characteristic = rxChars[id] ?: continue
            characteristic.value = bytes
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
            if (gatt.writeCharacteristic(characteristic)) sent++
        }
        val tx = txServer
        if (tx != null) {
            tx.value = bytes
            for (device in connectedServers.values) if (server?.notifyCharacteristicChanged(device, tx, false) == true) sent++
        }
        call.resolve(JSObject().put("sent", sent))
    }

    @PluginMethod
    fun getPeers(call: PluginCall) {
        val arr = JSArray()
        clients.forEach { (id, gatt) -> arr.put(JSObject().put("id", id).put("name", gatt.device.name ?: "SURVIVAL").put("connected", connectedClientIds.contains(id))) }
        connectedServers.forEach { (id, d) -> arr.put(JSObject().put("id", id).put("name", d.name ?: "SURVIVAL").put("connected", true)) }
        call.resolve(JSObject().put("peers", arr))
    }

    @PluginMethod
    fun stop(call: PluginCall) {
        started = false
        try { scanCallback?.let { scanner?.stopScan(it) }; advertiser?.stopAdvertising(advertiseCallback); clients.values.forEach { it.disconnect(); it.close() }; clients.clear(); server?.close(); server = null }
        catch (_: Exception) {}
        call.resolve()
    }
}