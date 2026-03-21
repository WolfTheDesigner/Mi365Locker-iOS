//
//  UartModuleViewController.swift
//  BadBird
//
//  Created by Trevor Beaton on 12/4/16.
//  Copyright © 2016 Vanguard Logic LLC. All rights reserved.
//

import UIKit
import CoreBluetooth
import os

class UartModuleViewController: UIViewController, UITextViewDelegate, UITextFieldDelegate {
    private static let logger = Logger(subsystem: "com.mi365locker", category: "UART")

    // MARK: - UI
    @IBOutlet weak var baseTextView: UITextView!
    @IBOutlet weak var sendButton: UIButton!
    @IBOutlet weak var inputTextField: UITextField!
    @IBOutlet weak var scrollView: UIScrollView!
    @IBOutlet weak var switchUI: UISwitch!

    // MARK: - Data
    var peripheral: CBPeripheral!
    private var consoleAsciiText = NSMutableAttributedString()
    private var notificationObserver: (any NSObjectProtocol)?
    private let keyboardScrollOffset: CGFloat = 250

    override func viewDidLoad() {
        super.viewDidLoad()

        guard peripheral != nil else {
            fatalError("UartModuleViewController requires a peripheral to be set before presentation")
        }

        navigationItem.backBarButtonItem = UIBarButtonItem(title: "Back", style: .plain, target: nil, action: nil)
        baseTextView.delegate = self
        inputTextField.delegate = self

        baseTextView.layer.borderWidth = 3.0
        baseTextView.layer.borderColor = UIColor.blue.cgColor
        baseTextView.layer.cornerRadius = 3.0
        baseTextView.text = ""

        inputTextField.layer.borderWidth = 2.0
        inputTextField.layer.borderColor = UIColor.blue.cgColor
        inputTextField.layer.cornerRadius = 3.0

    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        consoleAsciiText = NSMutableAttributedString()
        baseTextView.attributedText = consoleAsciiText
        updateIncomingData()
    }

    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        if let observer = notificationObserver {
            NotificationCenter.default.removeObserver(observer)
            notificationObserver = nil
        }
    }

    func updateIncomingData() {
        notificationObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name(rawValue: "Notify"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }

            let appendString = "\n"
            let myFont = UIFont(name: "Helvetica Neue", size: 15.0) ?? UIFont.systemFont(ofSize: 15.0)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: myFont,
                .foregroundColor: UIColor.red
            ]
            let attribString = NSAttributedString(
                string: "[Incoming]: " + BLEConnectionState.shared.lastReceivedValue + appendString,
                attributes: attributes
            )
            self.consoleAsciiText.append(attribString)
            self.baseTextView.attributedText = self.consoleAsciiText
        }
    }

    @IBAction func clickSendAction(_ sender: AnyObject) {
        outgoingData()
    }

    func outgoingData() {
        let inputText = inputTextField.text ?? ""
        guard !inputText.isEmpty else { return }

        let myFont = UIFont(name: "Helvetica Neue", size: 15.0) ?? UIFont.systemFont(ofSize: 15.0)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: myFont,
            .foregroundColor: UIColor.blue
        ]

        let attribString = NSAttributedString(
            string: "[Outgoing]: " + inputText + "\n",
            attributes: attributes
        )
        consoleAsciiText.append(attribString)
        baseTextView.attributedText = consoleAsciiText
        inputTextField.text = ""
    }

    // MARK: - BLE Write

    func sendCommand(lock: Bool) {
        let bytes = lock ? Mi365Command.lock : Mi365Command.unlock
        let data = Data(bytes)

        guard let peripheral = BLEConnectionState.shared.peripheral,
              let characteristic = BLEConnectionState.shared.txCharacteristic else {
            Self.logger.error("BLE not connected — cannot send command")
            return
        }
        peripheral.writeValue(data, for: characteristic, type: .withoutResponse)
    }

    func writeCharacteristic(val: Int8) {
        guard let peripheral = BLEConnectionState.shared.peripheral,
              let characteristic = BLEConnectionState.shared.txCharacteristic else {
            Self.logger.error("BLE not connected — cannot write characteristic")
            return
        }
        var value = val
        let data = Data(bytes: &value, count: MemoryLayout<Int8>.size)
        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }

    // MARK: - UITextViewDelegate

    func textViewShouldBeginEditing(_ textView: UITextView) -> Bool {
        if textView === baseTextView {
            inputTextField.resignFirstResponder()
            return false
        }
        return true
    }

    func textFieldDidBeginEditing(_ textField: UITextField) {
        scrollView.setContentOffset(CGPoint(x: 0, y: keyboardScrollOffset), animated: true)
    }

    func textFieldDidEndEditing(_ textField: UITextField) {
        scrollView.setContentOffset(CGPoint(x: 0, y: 0), animated: true)
    }

    // MARK: - Switch Action

    @IBAction func switchAction(_ sender: Any) {
        let locking = switchUI.isOn
        BLEConnectionState.shared.isLocked = locking

        if locking {
            Self.logger.info("Switch: Lock ON")
            sendCommand(lock: true)
            writeCharacteristic(val: 1)
        } else {
            Self.logger.info("Switch: Lock OFF")
            sendCommand(lock: false)
            writeCharacteristic(val: 0)
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        view.endEditing(true)
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        outgoingData()
        return true
    }
}
