//
//  BLECentralViewController.swift
//  BadBird
//
//  Created by Trevor Beaton on 11/29/16.
//  Copyright © 2016 Vanguard Logic LLC. All rights reserved.
//

import Foundation
import UIKit
import CoreBluetooth

// Shared BLE state accessible from @MainActor context
@MainActor var txCharacteristic: CBCharacteristic?
@MainActor var rxCharacteristic: CBCharacteristic?
@MainActor var blePeripheral: CBPeripheral?
@MainActor var characteristicASCIIValue = ""
@MainActor var isLocked = true

class BLECentralViewController: UIViewController, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate, UITableViewDelegate, UITableViewDataSource {

    // MARK: - Data
    var centralManager: CBCentralManager!
    var rssiValues: [NSNumber] = []
    var peripherals: [CBPeripheral] = []
    var scanTimer: Timer?

    // MARK: - UI
    @IBOutlet weak var baseTableView: UITableView!
    @IBOutlet weak var refreshButton: UIBarButtonItem!

    @IBAction func refreshAction(_ sender: AnyObject) {
        disconnectFromDevice()
        peripherals = []
        rssiValues = []
        baseTableView.reloadData()
        startScan()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        baseTableView.delegate = self
        baseTableView.dataSource = self
        baseTableView.reloadData()

        centralManager = CBCentralManager(delegate: self, queue: nil)
        let backButton = UIBarButtonItem(title: "Disconnect", style: .plain, target: nil, action: nil)
        navigationItem.backBarButtonItem = backButton
    }

    override func viewDidAppear(_ animated: Bool) {
        disconnectFromDevice()
        super.viewDidAppear(animated)
        refreshScanView()
        print("View Cleared")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        print("Stop Scanning")
        centralManager?.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - Scanning

    func startScan() {
        peripherals = []
        isLocked = !isLocked
        print(isLocked ? "Now Locking..." : "Now Unlocking...")

        scanTimer?.invalidate()
        centralManager?.scanForPeripherals(withServices: [BLEService_UUID], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer = Timer.scheduledTimer(timeInterval: 17, target: self, selector: #selector(cancelScan), userInfo: nil, repeats: false)
    }

    @objc func cancelScan() {
        centralManager?.stopScan()
        print("Scan Stopped")
        print("Number of Peripherals Found: \(peripherals.count)")
    }

    func refreshScanView() {
        baseTableView.reloadData()
    }

    // MARK: - Connection Management

    func disconnectFromDevice() {
        guard let peripheral = blePeripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    func restoreCentralManager() {
        centralManager?.delegate = self
    }

    func connectToDevice() {
        guard let peripheral = blePeripheral else {
            print("No peripheral to connect to")
            return
        }
        centralManager?.connect(peripheral, options: nil)
    }

    // MARK: - CBCentralManagerDelegate

    func centralManager(_ central: CBCentralManager, didDiscover peripheral: CBPeripheral, advertisementData: [String: Any], rssi RSSI: NSNumber) {
        if peripherals.contains(peripheral) { return }

        self.peripherals.append(peripheral)
        self.rssiValues.append(RSSI)
        peripheral.delegate = self
        self.baseTableView.reloadData()
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        print("*****************************")
        print("Connection complete")
        print("Peripheral info: \(String(describing: peripheral))")

        centralManager?.stopScan()
        print("Scan Stopped")

        peripheral.delegate = self
        peripheral.discoverServices([BLEService_UUID])

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let uartViewController = storyboard.instantiateViewController(withIdentifier: "UartModuleViewController") as? UartModuleViewController else {
            print("Failed to instantiate UartModuleViewController")
            return
        }
        uartViewController.peripheral = peripheral
        navigationController?.pushViewController(uartViewController, animated: true)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        if let error {
            print("Failed to connect to peripheral: \(error.localizedDescription)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        print("Disconnected")
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            print("Error discovering services: \(error.localizedDescription)")
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics([BLE_Characteristic_uuid_Tx, BLE_Characteristic_uuid_Rx], for: service)
        }
        print("Discovered Services: \(services)")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error {
            print("Error discovering characteristics: \(error.localizedDescription)")
            return
        }

        guard let characteristics = service.characteristics else { return }

        print("Found \(characteristics.count) characteristics!")

        for characteristic in characteristics {
            if characteristic.uuid.isEqual(BLE_Characteristic_uuid_Rx) {
                rxCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
                print("Rx Characteristic: \(characteristic.uuid)")
            }
            if characteristic.uuid.isEqual(BLE_Characteristic_uuid_Tx) {
                txCharacteristic = characteristic
                print("Tx Characteristic: \(characteristic.uuid)")
            }
            peripheral.discoverDescriptors(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if characteristic == rxCharacteristic {
            guard let value = characteristic.value,
                  let asciiString = String(data: value, encoding: .utf8) else { return }
            characteristicASCIIValue = asciiString
            print("Value Received: \(asciiString)")
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "Notify"), object: nil)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            print("\(error.localizedDescription)")
            return
        }
        guard let descriptors = characteristic.descriptors else { return }
        for descriptor in descriptors {
            print("Descriptor: \(String(describing: descriptor.description))")
            print("Rx Value \(String(describing: rxCharacteristic?.value))")
            print("Tx Value \(String(describing: txCharacteristic?.value))")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            print("Error changing notification state: \(error.localizedDescription)")
        } else {
            print("Characteristic's value subscribed")
        }

        if characteristic.isNotifying {
            print("Subscribed. Notification has begun for: \(characteristic.uuid)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil else {
            print("Error writing value: \(error!.localizedDescription)")
            return
        }
        print("Message sent")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: (any Error)?) {
        guard error == nil else {
            print("Error writing descriptor: \(error!.localizedDescription)")
            return
        }
        print("Succeeded!")
    }

    // MARK: - UITableViewDataSource

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return peripherals.count
    }

    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "BlueCell") as? PeripheralTableViewCell else {
            return UITableViewCell()
        }
        let peripheral = peripherals[indexPath.row]
        let rssi = rssiValues[indexPath.row]

        cell.peripheralLabel.text = peripheral.name ?? "Unknown"
        cell.rssiLabel.text = "RSSI: \(rssi)"

        return cell
    }

    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        blePeripheral = peripherals[indexPath.row]
        connectToDevice()
    }

    // MARK: - CBManagerState

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            print("Bluetooth Enabled")
            startScan()
        } else {
            print("Bluetooth Disabled- Make sure your Bluetooth is turned on")

            let alertVC = UIAlertController(title: "Bluetooth is not enabled", message: "Make sure that your bluetooth is turned on", preferredStyle: .alert)
            let action = UIAlertAction(title: "OK", style: .default) { _ in
                self.dismiss(animated: true, completion: nil)
            }
            alertVC.addAction(action)
            present(alertVC, animated: true, completion: nil)
        }
    }
}
