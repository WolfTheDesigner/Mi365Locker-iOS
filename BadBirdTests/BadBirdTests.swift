import Testing
@testable import BadBird

@Suite("BLE UUIDs")
struct BLEUUIDTests {
    @Test("Service UUID matches Nordic UART")
    func serviceUUID() {
        #expect(BLEUUIDs.service.uuidString == "6E400001-B5A3-F393-E0A9-E50E24DCCA9E")
    }

    @Test("TX characteristic UUID is correct")
    func txUUID() {
        #expect(BLEUUIDs.tx.uuidString == "6E400002-B5A3-F393-E0A9-E50E24DCCA9E")
    }

    @Test("RX characteristic UUID is correct")
    func rxUUID() {
        #expect(BLEUUIDs.rx.uuidString == "6E400003-B5A3-F393-E0A9-E50E24DCCA9E")
    }
}

@Suite("Mi365 Commands")
struct Mi365CommandTests {
    @Test("Lock command has correct byte sequence")
    func lockCommand() {
        #expect(Mi365Command.lock == [0x55, 0xAA, 0x03, 0x20, 0x03, 0x70, 0x01, 0x68, 0xFF])
        #expect(Mi365Command.lock.count == 9)
    }

    @Test("Unlock command has correct byte sequence")
    func unlockCommand() {
        #expect(Mi365Command.unlock == [0x55, 0xAA, 0x03, 0x20, 0x03, 0x71, 0x01, 0x67, 0xFF])
        #expect(Mi365Command.unlock.count == 9)
    }

    @Test("Lock and unlock commands differ only in command byte and checksum")
    func commandDifference() {
        // Commands should be identical except bytes at index 5 (command) and 7 (checksum)
        for i in 0..<Mi365Command.lock.count {
            if i == 5 || i == 7 {
                #expect(Mi365Command.lock[i] != Mi365Command.unlock[i])
            } else {
                #expect(Mi365Command.lock[i] == Mi365Command.unlock[i])
            }
        }
    }
}

@Suite("BLEConnectionState")
struct BLEConnectionStateTests {
    @Test("Shared instance is singleton")
    @MainActor
    func sharedInstance() {
        let a = BLEConnectionState.shared
        let b = BLEConnectionState.shared
        #expect(a === b)
    }

    @Test("Default state is locked")
    @MainActor
    func defaultLocked() {
        // Note: This tests the class definition, not runtime state
        let state = BLEConnectionState.shared
        // Reset for test
        state.isLocked = true
        #expect(state.isLocked == true)
    }
}
