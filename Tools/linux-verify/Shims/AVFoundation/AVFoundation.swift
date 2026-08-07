// Linux typecheck shim mirroring the AVFoundation API surface the game uses.
@_exported import Foundation

public typealias AVAudioFrameCount = UInt32
public typealias AVAudioNodeCompletionHandler = () -> Void

open class AVAudioFormat: NSObject {
    public init?(standardFormatWithSampleRate sampleRate: Double, channels: UInt32) {}
}

open class AVAudioBuffer: NSObject {}

open class AVAudioPCMBuffer: AVAudioBuffer {
    public init?(pcmFormat format: AVAudioFormat, frameCapacity: AVAudioFrameCount) {}
    open var frameLength: AVAudioFrameCount = 0
    open var frameCapacity: AVAudioFrameCount { 0 }
    open var floatChannelData: UnsafePointer<UnsafeMutablePointer<Float>>? { nil }
}

open class AVAudioNode: NSObject {}

public struct AVAudioPlayerNodeBufferOptions: OptionSet {
    public let rawValue: UInt
    public init(rawValue: UInt) { self.rawValue = rawValue }
    public static let loops = AVAudioPlayerNodeBufferOptions(rawValue: 1)
    public static let interrupts = AVAudioPlayerNodeBufferOptions(rawValue: 2)
    public static let interruptsAtLoop = AVAudioPlayerNodeBufferOptions(rawValue: 4)
}

open class AVAudioPlayerNode: AVAudioNode {
    public override init() { super.init() }
    open var volume: Float = 1
    open var pan: Float = 0
    open var rate: Float = 1
    open func play() {}
    open func pause() {}
    open func stop() {}
    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer,
                             at when: AVAudioTime?,
                             options: AVAudioPlayerNodeBufferOptions,
                             completionHandler: AVAudioNodeCompletionHandler?) {}
    open func scheduleBuffer(_ buffer: AVAudioPCMBuffer,
                             completionHandler: AVAudioNodeCompletionHandler?) {}
}

open class AVAudioTime: NSObject {}

open class AVAudioMixerNode: AVAudioNode {
    open var outputVolume: Float = 1
}

open class AVAudioEngine: NSObject {
    public override init() { super.init() }
    open var mainMixerNode: AVAudioMixerNode { AVAudioMixerNode() }
    open var outputNode: AVAudioNode { AVAudioNode() }
    open var isRunning: Bool { false }
    open func attach(_ node: AVAudioNode) {}
    open func detach(_ node: AVAudioNode) {}
    open func connect(_ node1: AVAudioNode, to node2: AVAudioNode, format: AVAudioFormat?) {}
    open func start() throws {}
    open func stop() {}
    open func pause() {}
    open func reset() {}
}

open class AVAudioSession: NSObject {
    public struct Category: RawRepresentable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let ambient = Category(rawValue: "ambient")
        public static let soloAmbient = Category(rawValue: "soloAmbient")
        public static let playback = Category(rawValue: "playback")
    }
    public struct Mode: RawRepresentable, Hashable {
        public let rawValue: String
        public init(rawValue: String) { self.rawValue = rawValue }
        public static let `default` = Mode(rawValue: "default")
    }
    public struct CategoryOptions: OptionSet {
        public let rawValue: UInt
        public init(rawValue: UInt) { self.rawValue = rawValue }
        public static let mixWithOthers = CategoryOptions(rawValue: 1)
        public static let duckOthers = CategoryOptions(rawValue: 2)
    }
    open class func sharedInstance() -> AVAudioSession { AVAudioSession() }
    open func setCategory(_ category: Category, mode: Mode, options: CategoryOptions) throws {}
    open func setActive(_ active: Bool) throws {}
}
