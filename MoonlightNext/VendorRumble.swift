//
//  VendorRumble.swift
//  MoonLume
//
//  Rumble for clamp controllers whose motors iOS doesn't drive: the Razer Kishi V3 Pro XL and
//  the GameSir G8+ MFi take motor levels over their own ExternalAccessory protocol (declared in
//  Info.plist's UISupportedExternalAccessoryProtocols).
//
//  Packet formats adapted from VoidLink (GPLv3), KishiV3ProXLRumbler.swift (nicobatalla) and
//  GameSirG8MFiRumbler.swift (chrisnch).
//

import ExternalAccessory
import GameController

@objc final class MNVendorRumble: NSObject, StreamDelegate {
    @objc static let shared = MNVendorRumble()

    private struct Pad {
        let accessoryProtocol: String
        /// GameController's vendor name for the pad
        let vendorMatch: (String) -> Bool
        let accessoryMatch: (EAAccessory) -> Bool
        /// Motor levels 0-255 → bytes on the wire
        let packet: (_ low: UInt8, _ high: UInt8, _ sequence: UInt8) -> Data
        /// The G8+ lets go of a level after a moment, so a running level is sent again at this interval
        let resend: TimeInterval?
    }

    private static func contains(_ text: String, _ word: String) -> Bool {
        text.range(of: word, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    private static let pads = [
        // Verified by VoidLink on RZ06-0547 firmware 1.01.000
        Pad(accessoryProtocol: "com.razer.kishicontrollerv2",
            vendorMatch: { MNVendorRumble.contains($0, "Razer Kishi") },
            accessoryMatch: { MNVendorRumble.contains($0.modelNumber, "RZ06") && $0.manufacturer.caseInsensitiveCompare("Razer") == .orderedSame },
            packet: { low, high, sequence in
                // Payload: report 1, then 15 zero bits, the two 8-bit levels and a padding bit, in a
                // 65-byte block; framed with a sequence number, length 75 and an XOR checksum
                let payload: [UInt8] = [1, 0, low >> 7, (low << 1) | (high >> 7), high << 1] + [UInt8](repeating: 0, count: 60)
                var frame: [UInt8] = [0, sequence, 0, 75, 0, 65, 0x16, 0x0E] + payload
                frame += [frame.dropFirst(2).reduce(0, ^), 0]
                return Data(frame)
            },
            resend: nil),
        Pad(accessoryProtocol: "com.xiaoji.M2boot",
            vendorMatch: { MNVendorRumble.contains($0, "GameSir") && MNVendorRumble.contains($0, "G8+") && MNVendorRumble.contains($0, "MFi") },
            accessoryMatch: { $0.manufacturer.caseInsensitiveCompare("GameSir") == .orderedSame && $0.modelNumber.caseInsensitiveCompare("G8+ MFi") == .orderedSame },
            packet: { low, high, _ in Data([0x04, low, 0x01, high, 0x01, 0, 0, 0, 0]) },
            resend: 0.167),
    ]

    private var session: EASession?
    private var pad: Pad?
    /// Bytes of the packet being written; a byte stream must finish a packet before the next one
    private var writing = Data()
    /// The newest level to send after it; older ones are dropped
    private var next: Data?
    private var sequence: UInt8 = 0x17
    private var resendTimer: Timer?
    /// Between a stream's start and its stop (main thread); levels queued after the stop are dropped
    private var active = false

    private static func pad(for controller: GCController?) -> Pad? {
        guard let vendor = controller?.vendorName else { return nil }
        return pads.first { $0.vendorMatch(vendor) }
    }

    @objc(handles:) func handles(_ controller: GCController?) -> Bool {
        MNVendorRumble.pad(for: controller) != nil
    }

    /// True when the controller is one of these pads, so its levels went to the accessory instead
    /// of GameController's haptics. Any thread.
    @objc(rumble:low:high:) func rumble(_ controller: GCController?, low: UInt16, high: UInt16) -> Bool {
        guard let pad = MNVendorRumble.pad(for: controller) else { return false }
        // 0-65535 → 0-255, rounded
        let l = UInt8((UInt32(low) * 255 + 32767) / 65535), h = UInt8((UInt32(high) * 255 + 32767) / 65535)
        DispatchQueue.main.async {
            guard self.active else { return }
            self.send(l, h, pad: pad)
        }
        return true
    }

    /// A stream starts; main thread.
    @objc func start() {
        active = true
    }

    /// Motors off and the channel closed, at the end of a stream. Main thread.
    @objc func stop() {
        active = false
        DispatchQueue.main.async {
            guard let pad = self.pad, self.session != nil else { return }
            self.send(0, 0, pad: pad)
            // Give the stop packet a moment to go out
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.close() }
        }
    }

    private func send(_ low: UInt8, _ high: UInt8, pad: Pad) {
        if self.pad?.accessoryProtocol != pad.accessoryProtocol { close() }
        self.pad = pad
        guard open(pad) else { return }
        sequence &+= 1
        next = pad.packet(low, high, sequence)
        resendTimer?.invalidate()
        resendTimer = nil
        if let interval = pad.resend, low > 0 || high > 0 {
            let packet = next
            let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
                guard let self else { return }
                if self.next == nil { self.next = packet }
                self.flush()
            }
            RunLoop.main.add(t, forMode: .common)
            resendTimer = t
        }
        flush()
    }

    private func open(_ pad: Pad) -> Bool {
        if session != nil { return true }
        guard let accessory = EAAccessoryManager.shared().connectedAccessories.first(where: {
                  $0.isConnected && $0.protocolStrings.contains(pad.accessoryProtocol) && pad.accessoryMatch($0)
              }),
              let session = EASession(accessory: accessory, forProtocol: pad.accessoryProtocol),
              let input = session.inputStream, let output = session.outputStream else { return false }
        self.session = session
        for stream in [input, output] as [Stream] {
            stream.delegate = self
            stream.schedule(in: .main, forMode: .common)
            stream.open()
        }
        return true
    }

    private func flush() {
        guard let output = session?.outputStream, output.streamStatus == .open else { return }
        while output.hasSpaceAvailable {
            if writing.isEmpty {
                guard let packet = next else { return }
                writing = packet
                next = nil
            }
            let written = writing.withUnsafeBytes { output.write($0.bindMemory(to: UInt8.self).baseAddress!, maxLength: writing.count) }
            if written < 0 {
                close()
                return
            }
            if written == 0 { return }
            writing.removeFirst(written)
        }
    }

    private func close() {
        resendTimer?.invalidate()
        resendTimer = nil
        if let session {
            for stream in [session.inputStream, session.outputStream].compactMap({ $0 }) as [Stream] {
                stream.close()
                stream.remove(from: .main, forMode: .common)
                stream.delegate = nil
            }
        }
        session = nil
        writing = Data()
        next = nil
    }

    func stream(_ stream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted, .hasSpaceAvailable:
            flush()
        case .hasBytesAvailable:
            // Replies aren't needed, but they have to be read so the accessory doesn't stall
            guard let input = stream as? InputStream else { return }
            var buffer = [UInt8](repeating: 0, count: 256)
            while input.hasBytesAvailable, input.read(&buffer, maxLength: buffer.count) > 0 {}
        case .errorOccurred, .endEncountered:
            close()
        default:
            break
        }
    }
}
