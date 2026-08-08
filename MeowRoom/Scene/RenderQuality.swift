import Foundation
import Metal
import SceneKit
import UIKit

/// The room leans on a fairly heavy post stack — HDR, bloom, screen-space ambient
/// occlusion, depth of field and soft shadows. That is fine on a recent phone and
/// not fine on an old one, so the expensive parts are chosen once at launch.
enum RenderQuality {

    enum Tier {
        case low, medium, high
    }

    /// Chosen from GPU capability, with memory used only to rule devices out.
    ///
    /// The old gate demanded 5.5 GB for `high`. An iPhone 13 has 4 GB, so the phone
    /// this game is aimed at landed on `medium` — one fur shell, no depth of field —
    /// and every choice made "for the high tier" was dead on arrival. 5.5 GB is a
    /// Pro-only threshold, and it was measuring the wrong thing anyway: what decides
    /// whether a room this small can afford 2048² shadows and 16 samples is the GPU,
    /// not how many apps fit in the background.
    ///
    /// `.apple7` is the A14 family — iPhone 12 and up — which is also where the
    /// deployment target sits. The memory floor stays, but only to exclude the 3 GB
    /// devices where texture memory, not shading, is what runs out.
    static let tier: Tier = {
        let gigabytes = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if gigabytes < 3.5 { return .low }
        if MTLCreateSystemDefaultDevice()?.supportsFamily(.apple7) == true { return .high }
        return .medium
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

    /// Multiplier on the segment counts of the cat's procedural meshes.
    ///
    /// The counts in `CatBuilder` are written for the high tier and scaled from
    /// here, so a weaker device gets a coarser cat rather than a different one.
    static var meshDetail: Float {
        switch tier {
        case .high: return 1.0
        case .medium: return 0.85
        case .low: return 0.65
        }
    }

    /// The character creator is a head close-up filling the screen, and it used to
    /// render the identical gameplay muzzle — sized for a cat two metres away. It
    /// gets a finer one; there is nothing else in that scene to pay for it.
    static let previewMeshDetail: Float = 1.5

    static var dustMotes: Bool { tier != .low }

    static var preferredFramesPerSecond: Int { tier == .low ? 30 : 60 }
}
