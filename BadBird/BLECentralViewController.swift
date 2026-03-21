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
import os

@MainActor
final class BLEConnectionState {
    static let shared = BLEConnectionState()
    init() {}

    var txCharacteristic: CBCharacteristic?
    var rxCharacteristic: CBCharacteristic?
    var peripheral: CBPeripheral?
    var lastReceivedValue = ""
    var isLocked = true
}

class BLECentralViewController: UIViewController, @preconcurrency CBCentralManagerDelegate, @preconcurrency CBPeripheralDelegate, UITableViewDelegate, UITableViewDataSource {
    private static let logger = Logger(subsystem: "com.mi365locker", category: "BLE")

    // MARK: - Data
    var centralManager: CBCentralManager!
    var rssiValues: [NSNumber] = []
    var peripherals: [CBPeripheral] = []
    var scanTimer: Timer?
    private let scanTimeoutInterval: TimeInterval = 17

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
        Self.logger.debug("View Cleared")
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        Self.logger.debug("Stop Scanning")
        centralManager?.stopScan()
        scanTimer?.invalidate()
        scanTimer = nil
    }

    // MARK: - Scanning

    func startScan() {
        peripherals = []
        rssiValues = []

        scanTimer?.invalidate()
        centralManager?.scanForPeripherals(withServices: [BLEUUIDs.service], options: [CBCentralManagerScanOptionAllowDuplicatesKey: false])
        scanTimer = Timer.scheduledTimer(timeInterval: scanTimeoutInterval, target: self, selector: #selector(cancelScan), userInfo: nil, repeats: false)
    }

    @objc func cancelScan() {
        centralManager?.stopScan()
        Self.logger.debug("Scan Stopped")
        Self.logger.info("Number of Peripherals Found: \(self.peripherals.count, privacy: .public)")
    }

    func refreshScanView() {
        baseTableView.reloadData()
    }

    // MARK: - Connection Management

    func disconnectFromDevice() {
        guard let peripheral = BLEConnectionState.shared.peripheral else { return }
        centralManager?.cancelPeripheralConnection(peripheral)
    }

    func restoreCentralManager() {
        centralManager?.delegate = self
    }

    func connectToDevice() {
        guard let peripheral = BLEConnectionState.shared.peripheral else {
            Self.logger.error("No peripheral to connect to")
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
        Self.logger.info("Connection complete")
        Self.logger.debug("Peripheral info: \(String(describing: peripheral), privacy: .public)")

        centralManager?.stopScan()
        Self.logger.debug("Scan Stopped")

        peripheral.delegate = self
        peripheral.discoverServices([BLEUUIDs.service])

        let storyboard = UIStoryboard(name: "Main", bundle: nil)
        guard let uartViewController = storyboard.instantiateViewController(withIdentifier: "UartModuleViewController") as? UartModuleViewController else {
            Self.logger.error("Failed to instantiate UartModuleViewController")
            return
        }
        uartViewController.peripheral = peripheral
        navigationController?.pushViewController(uartViewController, animated: true)
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: (any Error)?) {
        if let error {
            Self.logger.error("Failed to connect to peripheral: \(error.localizedDescription, privacy: .public)")
        }
    }

    func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: (any Error)?) {
        Self.logger.info("Disconnected")
        BLEConnectionState.shared.peripheral = nil
        BLEConnectionState.shared.txCharacteristic = nil
        BLEConnectionState.shared.rxCharacteristic = nil
    }

    // MARK: - CBPeripheralDelegate

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: (any Error)?) {
        if let error {
            Self.logger.error("Error discovering services: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard let services = peripheral.services else { return }

        for service in services {
            peripheral.discoverCharacteristics([BLEUUIDs.tx, BLEUUIDs.rx], for: service)
        }
        Self.logger.debug("Discovered Services: \(String(describing: services), privacy: .public)")
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: (any Error)?) {
        if let error {
            Self.logger.error("Error discovering characteristics: \(error.localizedDescription, privacy: .public)")
            return
        }

        guard let characteristics = service.characteristics else { return }

        Self.logger.info("Found \(characteristics.count, privacy: .public) characteristics!")

        for characteristic in characteristics {
            if characteristic.uuid.isEqual(BLEUUIDs.rx) {
                BLEConnectionState.shared.rxCharacteristic = characteristic
                peripheral.setNotifyValue(true, for: characteristic)
                peripheral.readValue(for: characteristic)
                Self.logger.debug("Rx Characteristic: \(characteristic.uuid.uuidString, privacy: .public)")
            }
            if characteristic.uuid.isEqual(BLEUUIDs.tx) {
                BLEConnectionState.shared.txCharacteristic = characteristic
                Self.logger.debug("Tx Characteristic: \(characteristic.uuid.uuidString, privacy: .public)")
            }
            peripheral.discoverDescriptors(for: characteristic)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            Self.logger.error("Error reading characteristic: \(error.localizedDescription, privacy: .public)")
            return
        }
        if characteristic == BLEConnectionState.shared.rxCharacteristic {
            guard let value = characteristic.value,
                  let asciiString = String(data: value, encoding: .utf8) else { return }
            BLEConnectionState.shared.lastReceivedValue = asciiString
            Self.logger.debug("Value Received: \(asciiString, privacy: .public)")
            NotificationCenter.default.post(name: NSNotification.Name(rawValue: "Notify"), object: nil)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverDescriptorsFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            Self.logger.error("\(error.localizedDescription, privacy: .public)")
            return
        }
        guard let descriptors = characteristic.descriptors else { return }
        for descriptor in descriptors {
            Self.logger.debug("Descriptor: \(String(describing: descriptor.description), privacy: .public)")
            Self.logger.debug("Rx Value \(String(describing: BLEConnectionState.shared.rxCharacteristic?.value), privacy: .public)")
            Self.logger.debug("Tx Value \(String(describing: BLEConnectionState.shared.txCharacteristic?.value), privacy: .public)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic, error: (any Error)?) {
        if let error {
            Self.logger.error("Error changing notification state: \(error.localizedDescription, privacy: .public)")
        } else {
            Self.logger.debug("Characteristic's value subscribed")
        }

        if characteristic.isNotifying {
            Self.logger.debug("Subscribed. Notification has begun for: \(characteristic.uuid.uuidString, privacy: .public)")
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic, error: (any Error)?) {
        guard error == nil else {
            Self.logger.error("Error writing value: \(error!.localizedDescription, privacy: .public)")
            return
        }
        Self.logger.debug("Message sent")
    }

    func peripheral(_ peripheral: CBPeripheral, didWriteValueFor descriptor: CBDescriptor, error: (any Error)?) {
        guard error == nil else {
            Self.logger.error("Error writing descriptor: \(error!.localizedDescription, privacy: .public)")
            return
        }
        Self.logger.debug("Succeeded!")
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
        BLEConnectionState.shared.peripheral = peripherals[indexPath.row]
        connectToDevice()
    }

    // MARK: - CBManagerState

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            Self.logger.info("Bluetooth Enabled")
            startScan()
        } else {
            Self.logger.warning("Bluetooth Disabled- Make sure your Bluetooth is turned on")

            let alertVC = UIAlertController(title: "Bluetooth is not enabled", message: "Make sure that your bluetooth is turned on", preferredStyle: .alert)
            let action = UIAlertAction(title: "OK", style: .default) { _ in
                self.dismiss(animated: true, completion: nil)
            }
            alertVC.addAction(action)
            present(alertVC, animated: true, completion: nil)
        }
    }
}
