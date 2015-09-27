//
//  DeviceManager.swift
//  CAT
//
//  Created by Kevin Lovette on 7/18/15.
//  Copyright (c) 2015 Kevin Lovette. All rights reserved.
//

import UIKit
import CoreBluetooth


class DeviceManager: NSObject, CBCentralManagerDelegate {

    // MARK: - Singleton

    // Singleton
    static let sharedInstance = DeviceManager()

    static let kDeviceUUIDs = "catUUIDs"
    
    // Central Manager
    var centralManager: CBCentralManager?
    var centralQueue: dispatch_queue_t = dispatch_queue_create("com.ioio.centralQueue", DISPATCH_QUEUE_SERIAL)
/*
    let centralOptions = [
        /// A Boolean value that specifies whether the system should display a warning dialog to the user if Bluetooth is powered off when the central manager is instantiated.
        CBCentralManagerOptionShowPowerAlertKey: false,
        /// A string (an instance of NSString) containing a unique identifier (UID) for the central manager that is being instantiated.
        /// The system uses this UID to identify a specific central manager. As a result, the UID must remain the same for subsequent executions
        /// of the app in order for the central manager to be successfully restored.
        CBCentralManagerOptionRestoreIdentifierKey: "CATCentral"
    ]
*/
    var reconnectHandler: Device.ConnectHandler?
    var disconnectHandler: Device.DisconnectHandler?

    // MARK: - Initialization

    override init() {
        super.init()

        let defaults = NSUserDefaults.standardUserDefaults()
        if let ids = defaults.stringArrayForKey(DeviceManager.kDeviceUUIDs) as? [String] {
            NSLog("DeviceManager  deviceUUIDs: \(ids)")
        }
    }

    func startCentral(reconnectHandler: Device.ConnectHandler? = nil, disconnectHandler: Device.DisconnectHandler? = nil) {
        self.reconnectHandler = reconnectHandler
        self.disconnectHandler = disconnectHandler

        // self.centralManager = CBCentralManager(delegate: self, queue: self.centralQueue, options: self.centralOptions)
        self.centralManager = CBCentralManager(delegate: self, queue: self.centralQueue)
        NSLog("CentralManager init")
    }
    
/*
    // Restore state - only if the 'bluetooth-central' background mode is specified
    func centralManager(central: CBCentralManager!,
                        willRestoreState dict: [NSObject : AnyObject]!) {
        NSLog("willRestoreState \(dict)")
    }
*/

    
    //--------------------------------------------------------------------------------
    //
    // Scan
    //

    // MARK: - Scan state

    var scanning = false
    typealias DiscoverCompletionHandler = (device: Device) -> Void
    var scanDiscoverHandler: DiscoverCompletionHandler?

    var devices = [Device]()
    
    let scanServiceUUIDs = [CBUUID(string: "1130FBD0-6D61-422A-8939-042DD56B1EF5")]
    // let scanOptions: [NSObject : AnyObject]? = nil   
    let scanOptions = [
        /// A Boolean value that specifies whether the scan should run without duplicate filtering.
        CBCentralManagerScanOptionAllowDuplicatesKey: false,
        /// An array (an instance of NSArray) of service UUIDs (represented by CBUUID objects) that you want to scan for.
        /// Specifying this scan option causes the central manager to also scan for peripherals soliciting any of the services contained in the array.
        // CBCentralManagerScanOptionSolicitedServiceUUIDsKey: [CBUUID(string: "1130FBD0-6D61-422A-8939-042DD56B1EF5")]
    ]

    // MARK: - Scan

    /// Scan for peripherals that match the CAT service UUID broadcast in the advertising packet. Call the discoverHandler when a device is discovered.
    func startScan(discoverHandler: DiscoverCompletionHandler? = nil) {
        if let manager = self.centralManager {
            if manager.state == CBCentralManagerState.PoweredOn {
                self.scanDiscoverHandler = discoverHandler
                // start scanning
                manager.scanForPeripheralsWithServices(self.scanServiceUUIDs, options: self.scanOptions)
                self.scanning = true
            }
        }
    }
    func stopScan() {
        if let manager = self.centralManager {
            if manager.state == CBCentralManagerState.PoweredOn {
                // stop scanning
                manager.stopScan()
                self.scanDiscoverHandler = nil
                self.scanning = false
            }
        }
    }
    
    // MARK: - Scan - CBCentralManagerDelegate

    /// This method is called when peripherals are discovered during scanning.
    func centralManager(central: CBCentralManager!,
                        didDiscoverPeripheral peripheral: CBPeripheral!,
                        advertisementData: [NSObject : AnyObject]!,
                        RSSI: NSNumber!) {
        if findDevice(peripheral.identifier) == nil {
            NSLog("didDiscoverPeripheral \(peripheral)")
        }

        var device = getDevice(peripheral)
        // notify the device of the adv data
        device.didDiscover(advertisementData)

        // feedback to the UI
        if let handler = self.scanDiscoverHandler {
            handler(device: device)
        }
    }

    func getDevice(peripheral: CBPeripheral) -> Device {
        if let device = findDevice(peripheral.identifier) {
            return device
        } else {
            var device = Device(peripheral: peripheral)
            self.devices.append(device)
            return device
        }
    }

    func findDevice(uuid: NSUUID) -> Device? {
        for device in self.devices {
            if device.identifier == uuid.UUIDString {
                return device
            }
        }
        return nil
    }
    

    //--------------------------------------------------------------------------------
    //
    // Connect
    //

    // MARK: - Connect

    var connectOptions = [
        /// A Boolean value that specifies whether the system should display an alert for a given peripheral if the app is suspended when a successful connection is made.
        CBConnectPeripheralOptionNotifyOnConnectionKey: false,
        /// A Boolean value that specifies whether the system should display a disconnection alert for a given peripheral if the app is suspended at the time of the disconnection.
        CBConnectPeripheralOptionNotifyOnDisconnectionKey: false,
        /// A Boolean value that specifies whether the system should display an alert for all notifications received from a given peripheral if the app is suspended at the time.
        CBConnectPeripheralOptionNotifyOnNotificationKey: false,
    ]

    func connect(device: Device, connectHandler: Device.ConnectHandler? = nil) {
        if device.isConnected() {
            return
        }
        if let manager = self.centralManager {
            if manager.state == CBCentralManagerState.PoweredOn {
                if let peripheral = device.peripheral {
                    device.connect(connectHandler: connectHandler)
                    manager.connectPeripheral(peripheral, options: self.connectOptions)
                }
            }
        }
    }

    func disconnect(device: Device, disconnectHandler: Device.DisconnectHandler? = nil) {
        if let manager = self.centralManager {
            if manager.state == CBCentralManagerState.PoweredOn {
                if let peripheral = device.peripheral {
                    device.disconnect(disconnectHandler: disconnectHandler)
                    manager.cancelPeripheralConnection(peripheral)
                }
            }
        }
    }

/*
    func disconnectDevices(selectedDevice: Device, completionHandler: (() -> Void)? = nil) {
        for device in self.devices {
            if device != selectedDevice {
                if device.isConnected() {
                    self.disconnect(device)
                }
            }
        }
    }
*/
    
    // MARK: - Connect - CBCentralManagerDelegate

    func centralManager(central: CBCentralManager!,
                        didConnectPeripheral peripheral: CBPeripheral!) {
        if let device = findDevice(peripheral.identifier) {
            if let handler = self.reconnectHandler {
                handler(device: device)
            }

            device.didConnect()
        } else {
            // Should never get here.
        }
    }
    func centralManager(central: CBCentralManager!,
                        didDisconnectPeripheral peripheral: CBPeripheral!,
                        error: NSError!) {
        if let device = findDevice(peripheral.identifier) {
            if let handler = self.disconnectHandler {
                handler(device: device)
            }

            device.didDisconnect(error)
        } else {
            // Should never get here.
        }
    }
    func centralManager(central: CBCentralManager!,
                        didFailToConnectPeripheral peripheral: CBPeripheral!,
                        error: NSError!) {
        if let device = findDevice(peripheral.identifier) {
            device.didFailToConnect(error)
        } else {
            // Should never get here.
        }
    }


    //--------------------------------------------------------------------------------
    //
    // Reconnect
    //

    // MARK: - Reconnect

    func clearReconnectUUIDs() {
        let defaults = NSUserDefaults.standardUserDefaults()
        defaults.removeObjectForKey(DeviceManager.kDeviceUUIDs)

        let ids = defaults.stringArrayForKey(DeviceManager.kDeviceUUIDs) as? [String]
        NSLog("clearReconnectUUIDs: \(ids)")
    }

    func setReconnectUUID(device: Device) {
        let defaults = NSUserDefaults.standardUserDefaults()

        // peripheral UUID for reconnect
        var ids = [device.identifier]
        // set list of UUIDs
        defaults.setObject(ids, forKey: DeviceManager.kDeviceUUIDs)

        let newIds = defaults.stringArrayForKey(DeviceManager.kDeviceUUIDs) as? [String]
        NSLog("setReconnectUUIDs: \(newIds)")
    }

    func addReconnectUUID(device: Device) {
        // add peripheral UUID for reconnect
        let id = device.identifier
        let defaults = NSUserDefaults.standardUserDefaults()

        var ids: [String]?

        // get existing list of UUIDs
        if let reconnectIds = defaults.stringArrayForKey(DeviceManager.kDeviceUUIDs) as? [String] {
            ids = [String](reconnectIds)
            // add peripheral UUID
            ids!.append(id)
        } else {
            ids = [id]
        }

        // save list of UUIDs
        defaults.setObject(ids, forKey: DeviceManager.kDeviceUUIDs)

        let newIds = defaults.stringArrayForKey(DeviceManager.kDeviceUUIDs) as? [String]
        NSLog("addReconnectUUID: \(newIds)")
    }

    func reconnectPeripheralNSUUIDs() -> [NSUUID] {
        let defaults = NSUserDefaults.standardUserDefaults()

        // remove for testing
//        clearReconnectUUIDs()

        var ids = [NSUUID]()

        if let uuids = defaults.stringArrayForKey(DeviceManager.kDeviceUUIDs) {
            for uuid in uuids {
                if let nsuuid = NSUUID(UUIDString: uuid as! String) {
                    ids.append(nsuuid)
                }
            }
        }

        return ids
    }

    func reconnect() {
        // get peripheral UUIDs to reconnect to
        let peripheralNSUUIDs = self.reconnectPeripheralNSUUIDs()

        // get peripherals
        let peripherals = self.centralManager!.retrievePeripheralsWithIdentifiers(peripheralNSUUIDs)

        // rconnect to peripherals
        for obj in peripherals {
            if let peripheral = obj as? CBPeripheral {
                var device = getDevice(peripheral)

                NSLog("  reconnect: \(device.name)")
                // connect to device
                self.connect(device)
            }
        }
    }

    // MARK: - Reconnect - CBCentralManagerDelegate

    /// This method returns the result of a retrieveConnectedPeripherals call. Since the array of currently connected peripherals can include those connected to the system by other apps, you typically implement this method to reconnect the peripherals in which your app is interested.
    func centralManager(central: CBCentralManager!,
                        didRetrieveConnectedPeripherals peripherals: [AnyObject]!) {
        NSLog("didRetrieveConnectedPeripherals \(peripherals)")
    }

    
    /// This method returns the result of a call to retrievePeripherals: with an array of the peripherals that the central manager was able to match to the provided universally unique identifiers (UUIDs). You typically implement this method to reconnect to a known peripheral.
    func centralManager(central: CBCentralManager!,
                        didRetrievePeripherals peripherals: [AnyObject]!) {
        NSLog("didRetrievePeripherals \(peripherals)")
    }


    
    // MARK: - CentralManager State - CBCentralManagerDelegate

    // CentralManager state update
    func centralManagerDidUpdateState(central: CBCentralManager!) {

        switch ( central.state ) {
        case CBCentralManagerState.Unknown:
            self.unknown()
        case CBCentralManagerState.Resetting:
            self.resetting()
        case CBCentralManagerState.Unsupported:
            self.unsupported()
        case CBCentralManagerState.Unauthorized:
            self.unauthorized()
        case CBCentralManagerState.PoweredOff:
            self.poweredOff()
        case CBCentralManagerState.PoweredOn:
            self.poweredOn()

        default:
            break
        }
    }

    func unknown() {
        NSLog("centralManagerDidUpdateState: Unknown - The current state of the central manager is unknown; an update is imminent.")
    }
    func resetting() {
        NSLog("centralManagerDidUpdateState: Resetting - The connection with the system service was momentarily lost; an update is imminent.")
    }
    func unsupported() {
        NSLog("centralManagerDidUpdateState  Unsupported    The platform/hardware doesn't support Bluetooth Low Energy.")
        // Handle missing BLE hardware
    }
    func unauthorized() {
        NSLog("centralManagerDidUpdateState  Unauthorized   The app is not authorized to use Bluetooth Low Energy.")
        // Ask user for permission
    }

    func poweredOff() {
        NSLog("  PoweredOff")
    }

    func poweredOn() {
        NSLog("  PoweredOn")
        //self.reconnect()

        // reconnect to known peripherals
        // if self.autoReconnect {
        //     self.reconnect()
        // }
    }

}
