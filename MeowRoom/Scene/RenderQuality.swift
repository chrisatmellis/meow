import Foundation
import SceneKit
import UIKit

/// The room leans on a fairly heavy post stack — HDR, bloom, screen-space ambient
/// occlusion, depth of field and soft shadows. That is fine on a recent phone and
/// not fine on an old one, so the expensive parts are chosen once at launch.
enum RenderQuality {

    enum Tier {
        case low, medium, high
    }

    static let tier: Tier = {
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        let cores = ProcessInfo.processInfo.processorCount
        if gigabytes >= 5.5 && cores >= 6 { return .high }
        if gigabytes >= 3.5 { return .medium }
        return .low
    }()

    static var shadowMapSize: CGSize {
        switch tier {
        case .high: return CGSize(width: 2048, height: 2048)
        case .medium: return CGSize(width: 1536, height: 1536)
        case .low: return CGSize(width: 1024, height: 1024)
        }
    }

    static var shadowSampleCount: Int {
        switch tier {
        case .high: return 16
        case .medium: return 8
        case .low: return 4
        }
    }

    static var wantsDepthOfField: Bool { tier == .high }

    static var ambientOcclusionIntensity: CGFloat {
        switch tier {
        case .high: return 0.45
        case .medium: return 0.30
        case .low: return 0
        }
    }

    static var antialiasing: SCNAntialiasingMode {
        tier == .low ? .none : .multisampling2X
    }

    /// Long-haired cats get fewer fur shells on weaker hardware.
    static var maxFurShells: Int {
        switch tier {
        case .high: return 2
        case .medium: return 1
        case .low: return 0
        }
    }

    static var dustMotes: Bool { tier != .low }

    static var preferredFramesPerSecond: Int { tier == .low ? 30 : 60 }
}
