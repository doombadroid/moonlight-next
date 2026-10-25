//
//  FrameInterpolator.swift
//  MoonLume
//
//  x2 frame interpolation for the VideoToolbox renderer. Between each pair of decoded frames,
//  iOS 26's low-latency frame interpolation (VTFrameProcessor) draws one more frame stamped
//  halfway between them, so a 60 fps stream fills a 120 Hz screen. A frame in between can't be
//  drawn until the next real one has arrived, so this adds about half a frame of latency, and
//  the extra GPU work costs battery.
//  Adapted from VoidLink (GPLv3), Stream/FrameInterpolator.swift.
//

import CoreMedia
import VideoToolbox
import os

@objc(MNFrameInterpolator) final class MNFrameInterpolator: NSObject {
    /// Gets every frame to show, in order, on the interpolator's queue. The flag marks drawn frames.
    typealias Output = (CMSampleBuffer, Bool) -> Void

    /// True when this device and OS can interpolate frames.
    @objc static var isSupported: Bool {
        #if targetEnvironment(simulator)
        return false
        #else
        if #available(iOS 26.0, *) {
            return VTLowLatencyFrameInterpolationConfiguration.isSupported
        }
        return false
        #endif
    }

    private let output: Output
    private let queue = DispatchQueue(label: "com.doombadroid.moonlume.interpolator", qos: .userInteractive)
    private var previousPTS = CMTime.invalid
    private var engine: AnyObject? // Engine; iOS 26 only, so it's kept untyped here
    private var engineSize = (0, 0)
    private let log = Logger(subsystem: "com.doombadroid.moonlume", category: "interpolation")
    /// Frames submitted but not yet processed. Decoding never waits for the interpolator, so when it
    /// falls behind (thermal throttling, GPU work refused in the background) frames pass straight
    /// through instead of piling up, with their latency and decoder buffers, on the queue.
    private var backlog = 0
    private let backlogLock = NSLock()

    @objc init(output: @escaping Output) {
        self.output = output
    }

    /// Queues a decoded frame. restart: frames before this one don't lead into it (an IDR frame).
    @objc func submit(_ frame: CMSampleBuffer, restart: Bool) {
        backlogLock.lock()
        backlog += 1
        let behind = backlog > 2
        backlogLock.unlock()
        queue.async {
            if behind {
                // The next frame doesn't follow on from this one's predecessor: no drawn frame
                self.previousPTS = .invalid
                self.output(frame, false)
            } else {
                self.process(frame, restart: restart)
            }
            self.backlogLock.lock()
            self.backlog -= 1
            self.backlogLock.unlock()
        }
    }

    @objc func stop() {
        queue.async { self.engine = nil }
    }

    private func process(_ frame: CMSampleBuffer, restart: Bool) {
        let pts = CMSampleBufferGetPresentationTimeStamp(frame)
        let follows = !restart && previousPTS.isValid && pts > previousPTS
        let midpoint = follows
            ? previousPTS + CMTimeMultiplyByFloat64(pts - previousPTS, multiplier: 0.5)
            : pts - CMTime(value: 1, timescale: 1000)
        previousPTS = pts

        if let middle = interpolate(frame, midpoint: midpoint, follows: follows) {
            output(middle, true)
        } else {
            // Nothing drawn (first frame, after a loss, or interpolation failed): show this frame
            // early instead, so every 120 Hz refresh still gets a frame
            var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: midpoint, decodeTimeStamp: .invalid)
            var early: CMSampleBuffer?
            _ = CMSampleBufferCreateCopyWithNewTiming(allocator: nil, sampleBuffer: frame, sampleTimingEntryCount: 1,
                                                  sampleTimingArray: &timing, sampleBufferOut: &early)
            if let early {
                output(early, false)
            }
        }
        output(frame, false)
    }

    private func interpolate(_ frame: CMSampleBuffer, midpoint: CMTime, follows: Bool) -> CMSampleBuffer? {
        #if targetEnvironment(simulator)
        return nil
        #else
        guard #available(iOS 26.0, *), let image = CMSampleBufferGetImageBuffer(frame) else { return nil }
        let size = (CVPixelBufferGetWidth(image), CVPixelBufferGetHeight(image))
        if size != engineSize {
            engineSize = size
            engine = Engine(for: image)
            if engine == nil {
                log.error("Interpolation unavailable for \(size.0)x\(size.1) frames, pixel format \(CVPixelBufferGetPixelFormatType(image))")
            }
        }
        guard let engine = engine as? Engine else { return nil }
        return engine.interpolate(image, pts: CMSampleBufferGetPresentationTimeStamp(frame), midpoint: midpoint,
                                  follows: follows, log: log)
        #endif
    }
}

#if !targetEnvironment(simulator)
/// One interpolation session, built for one decoded frame size.
@available(iOS 26.0, *)
private final class Engine {
    private let processor = VTFrameProcessor()
    private let transfer: VTPixelTransferSession
    private let sourcePool: CVPixelBufferPool
    private let destinationPool: CVPixelBufferPool
    private var previous: VTFrameProcessorFrame?
    private var formatDescription: CMVideoFormatDescription?

    init?(for image: CVPixelBuffer) {
        // The interpolator handles about 1080p at most, so bigger streams are drawn at a scaled-down
        // size (the layer scales the frames in between back up)
        let width = Double(CVPixelBufferGetWidth(image)), height = Double(CVPixelBufferGetHeight(image))
        let scale = min(1, 1920 / max(width, height), (1920 * 1080 / (width * height)).squareRoot())
        let w = Int(width * scale) & ~1, h = Int(height * scale) & ~1
        guard let configuration = VTLowLatencyFrameInterpolationConfiguration(frameWidth: w, frameHeight: h,
                                                                               numberOfInterpolatedFrames: 1)
        else { return nil }

        // Interpolate in the decoder's own pixel format when possible, else one of the same bit depth
        let native = CVPixelBufferGetPixelFormatType(image)
        let formats = configuration.supportedPixelFormats
        let tenBit: (OSType) -> Bool = { [kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_420YpCbCr10BiPlanarFullRange,
                                          kCVPixelFormatType_444YpCbCr10BiPlanarVideoRange, kCVPixelFormatType_444YpCbCr10BiPlanarFullRange].contains($0) }
        guard let format = formats.contains(native) ? Optional(native) : formats.first(where: { tenBit($0) == tenBit(native) }) ?? formats.first
        else { return nil }

        func pool(_ base: [String: Any]) -> CVPixelBufferPool? {
            var attributes = base
            attributes[kCVPixelBufferPixelFormatTypeKey as String] = format
            attributes[kCVPixelBufferWidthKey as String] = w
            attributes[kCVPixelBufferHeightKey as String] = h
            attributes[kCVPixelBufferIOSurfacePropertiesKey as String] = attributes[kCVPixelBufferIOSurfacePropertiesKey as String] ?? [String: Any]()
            var pool: CVPixelBufferPool?
            return CVPixelBufferPoolCreate(nil, nil, attributes as CFDictionary, &pool) == kCVReturnSuccess ? pool : nil
        }
        var transfer: VTPixelTransferSession?
        guard let sourcePool = pool(configuration.sourcePixelBufferAttributes),
              let destinationPool = pool(configuration.destinationPixelBufferAttributes),
              VTPixelTransferSessionCreate(allocator: nil, pixelTransferSessionOut: &transfer) == noErr,
              let transfer
        else { return nil }
        _ = VTSessionSetProperty(transfer, key: kVTPixelTransferPropertyKey_RealTime, value: kCFBooleanTrue)
        self.transfer = transfer
        self.sourcePool = sourcePool
        self.destinationPool = destinationPool
        do {
            try processor.startSession(configuration: configuration)
        } catch {
            return nil
        }
    }

    deinit {
        processor.endSession()
        VTPixelTransferSessionInvalidate(transfer)
    }

    /// Draws the frame halfway between the previous frame and this one.
    func interpolate(_ image: CVPixelBuffer, pts: CMTime, midpoint: CMTime, follows: Bool, log: Logger) -> CMSampleBuffer? {
        var source: CVPixelBuffer?
        guard CVPixelBufferPoolCreatePixelBuffer(nil, sourcePool, &source) == kCVReturnSuccess, let source,
              VTPixelTransferSessionTransferImage(transfer, from: image, to: source) == noErr,
              let current = VTFrameProcessorFrame(buffer: source, presentationTimeStamp: pts)
        else {
            previous = nil
            return nil
        }
        let previous = follows ? self.previous : nil
        self.previous = current

        var destination: CVPixelBuffer?
        guard let previous,
              CVPixelBufferPoolCreatePixelBuffer(nil, destinationPool, &destination) == kCVReturnSuccess, let destination,
              let middle = VTFrameProcessorFrame(buffer: destination, presentationTimeStamp: midpoint),
              let parameters = VTLowLatencyFrameInterpolationParameters(sourceFrame: current, previousFrame: previous,
                                                                        interpolationPhase: [0.5], destinationFrames: [middle])
        else { return nil }

        let done = DispatchSemaphore(value: 0)
        let result = OSAllocatedUnfairLock<(any Error)?>(initialState: nil)
        processor.process(parameters: parameters) { _, error in
            result.withLock { $0 = error }
            done.signal()
        }
        // A frame later than this is no use; show the real frame instead
        guard done.wait(timeout: .now() + .milliseconds(50)) == .success else {
            log.error("Interpolation timed out")
            return nil
        }
        if let failure = result.withLock({ $0 }) {
            log.error("Interpolation failed: \(failure.localizedDescription)")
            return nil
        }

        // Keep the color tags and HDR metadata of the real frame
        CVBufferPropagateAttachments(image, destination)
        if formatDescription.map({ !CMVideoFormatDescriptionMatchesImageBuffer($0, imageBuffer: destination) }) ?? true {
            formatDescription = nil
            _ = CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: destination, formatDescriptionOut: &formatDescription)
        }
        guard let formatDescription else { return nil }
        var timing = CMSampleTimingInfo(duration: .invalid, presentationTimeStamp: midpoint, decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        _ = CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: destination, formatDescription: formatDescription,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        return sample
    }
}
#endif
