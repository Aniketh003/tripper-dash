import Foundation
import CoreBluetooth

@Observable
public final class TripperPodClient: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate, @unchecked Sendable {
    public static let shared = TripperPodClient()
    
    public var isScanning: Bool = false
    public var isConnected: Bool = false
    public var discoveredPeripherals: [CBPeripheral] = []
    public var statusMessage: String = "BLE idle"
    
    private var centralManager: CBCentralManager!
    private var activePeripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    
    // Royal Enfield Tripper Service & Characteristic UUIDs
    public static let serviceUUID = CBUUID(string: "0000fee0-0000-1000-8000-00805f9b34fb")
    public static let writeCharUUID = CBUUID(string: "0000fee1-0000-1000-8000-00805f9b34fb")
    
    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: nil)
    }
    
    public func startScanning() {
        guard centralManager.state == .poweredOn else {
            statusMessage = "Bluetooth not available"
            return
        }
        discoveredPeripherals.removeAll()
        isScanning = true
        statusMessage = "Scanning for Tripper Pod..."
        centralManager.scanForPeripherals(withServices: nil, options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
    }
    
    public func stopScanning() {
        centralManager.stopScan()
        isScanning = false
        statusMessage = "Scan stopped"
    }
    
    public func connect(to peripheral: CBPeripheral) {
        stopScanning()
        activePeripheral = peripheral
        peripheral.delegate = self
        statusMessage = "Connecting to \(peripheral.name ?? "Tripper")..."
        centralManager.connect(peripheral, options: nil)
    }
    
    public func disconnect() {
        if let p = activePeripheral {
            centralManager.cancelPeripheralConnection(p)
        }
        activePeripheral = nil
        writeCharacteristic = nil
        isConnected = false
        statusMessage = "Disconnected"
    }
    
    // MARK: - Send 20-byte Turn Instruction to Pod
    public func sendNavigationUpdate(
        turnIconId: UInt8,
        distanceMeters: UInt16,
        progressPercent: UInt8,
        streetName: String
    ) {
        guard let peripheral = activePeripheral, let char = writeCharacteristic else { return }
        
        var packet = [UInt8](repeating: 0, count: 20)
        packet[0] = 0xA1 // Nav Command
        packet[1] = turnIconId
        packet[2] = UInt8((distanceMeters >> 8) & 0xFF)
        packet[3] = UInt8(distanceMeters & 0xFF)
        packet[4] = 0x00 // Unit: 0 = meters
        packet[5] = min(100, progressPercent)
        
        let streetBytes = Array(streetName.utf8.prefix(14))
        for (i, b) in streetBytes.enumerated() {
            packet[6 + i] = b
        }
        
        peripheral.writeValue(Data(packet), for: char, type: .withoutResponse)
    }
    
    // MARK: - CBCentralManagerDelegate
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            statusMessage = "Ready to connect"
        case .poweredOff:
            statusMessage = "Bluetooth is powered off"
            isConnected = false
        default:
            statusMessage = "Bluetooth state: \(central.state.rawValue)"
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String : Any], rssi RSSI: NSNumber) {
        let name = peripheral.name ?? ""
        if name.localizedCaseInsensitiveContains("tripper") || name.localizedCaseInsensitiveContains("royal enfield") {
            if !discoveredPeripherals.contains(where: { $0.identifier == peripheral.identifier }) {
                discoveredPeripherals.append(peripheral)
            }
        }
    }
    
    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        isConnected = true
        statusMessage = "Connected to \(peripheral.name ?? "Tripper")"
        peripheral.discoverServices([Self.serviceUUID])
    }
    
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        statusMessage = "Failed to connect: \(error?.localizedDescription ?? "unknown error")"
    }
    
    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        isConnected = false
        statusMessage = "Tripper disconnected"
        writeCharacteristic = nil
    }
    
    // MARK: - CBPeripheralDelegate
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([Self.writeCharUUID], for: service)
        }
    }
    
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for char in characteristics {
            if char.uuid == Self.writeCharUUID {
                writeCharacteristic = char
                statusMessage = "Tripper Navigation Ready"
            }
        }
    }
}
