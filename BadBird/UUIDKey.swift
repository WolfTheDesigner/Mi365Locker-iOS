//
//  UUIDKey.swift
//  BadBird
//
//  Created by Trevor Beaton on 12/3/16.
//  Copyright © 2016 Vanguard Logic LLC. All rights reserved.
//

import CoreBluetooth

// Nordic UART Service UUIDs
enum BLEUUIDs {
    nonisolated(unsafe) static let service = CBUUID(string: "6e400001-b5a3-f393-e0a9-e50e24dcca9e")
    nonisolated(unsafe) static let tx = CBUUID(string: "6e400002-b5a3-f393-e0a9-e50e24dcca9e")
    nonisolated(unsafe) static let rx = CBUUID(string: "6e400003-b5a3-f393-e0a9-e50e24dcca9e")
}

// Mi365 scooter commands
enum Mi365Command {
    static let lock: [UInt8]   = [0x55, 0xAA, 0x03, 0x20, 0x03, 0x70, 0x01, 0x68, 0xFF]
    static let unlock: [UInt8] = [0x55, 0xAA, 0x03, 0x20, 0x03, 0x71, 0x01, 0x67, 0xFF]
}
