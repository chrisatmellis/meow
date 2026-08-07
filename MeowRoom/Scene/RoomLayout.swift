import Foundation
import SceneKit

/// Single source of truth for where everything lives, shared by the room builder
/// and the cat's navigation. Units are metres; origin is the centre of the floor.
///
/// The player never moves, so the room is laid out around one fixed viewpoint:
/// sitting on a zabuton with your back to the +Z wall, looking down the length of
/// the room at the shoji windows on the -Z wall. Everything the cat routinely uses
/// is placed inside that cone of view.
enum RoomLayout {

    static let halfWidth: Float = 1.70       // ±X walls  (3.4 m wide)
    static let halfDepth: Float = 2.20       // ±Z walls  (4.4 m deep)
    static let ceilingHeight: Float = 2.42
    static let wallThickness: Float = 0.06

    /// Seated eye height, right against the near wall.
    static let cameraPosition = SCNVector3(x: 0.0, y: 1.03, z: 2.00)
    static let cameraPitch: Float = deg(-6)

    /// Bottom of the window opening — furniture tucks underneath it.
    static let windowSillHeight: Float = 0.46

    // Furniture ------------------------------------------------------------

    /// Futon along the -X side, angled into view.
    static let futonCenter = SCNVector3(x: -0.82, y: 0.0, z: -0.30)
    static let futonSize = SCNVector3(x: 0.92, y: 0.11, z: 1.85)
    static let futonTop: Float = 0.13
    static let pillowCenter = SCNVector3(x: -0.82, y: 0.16, z: -1.02)

    /// Low table (chabudai) with a teacup that is absolutely going to get knocked off.
    static let tableCenter = SCNVector3(x: 0.80, y: 0.0, z: 0.34)
    static let tableSize = SCNVector3(x: 0.72, y: 0.30, z: 0.50)
    static let tableTop: Float = 0.30

    /// Tansu chest against the +X wall, up near the window end.
    static let tansuCenter = SCNVector3(x: 1.44, y: 0.0, z: -1.28)
    static let tansuSize = SCNVector3(x: 0.44, y: 0.70, z: 0.90)

    /// Cat tree in the far -X corner, by the window.
    static let catTreeBase = SCNVector3(x: -1.26, y: 0.0, z: -1.80)
    static let catTreeMidPlatform = SCNVector3(x: -1.26, y: 0.50, z: -1.80)
    static let catTreeTopPlatform = SCNVector3(x: -1.20, y: 1.02, z: -1.86)
    static let scratchPostSpot = SCNVector3(x: -1.02, y: 0.0, z: -1.58)

    /// Round cat bed on the tatami.
    static let catBedCenter = SCNVector3(x: 0.34, y: 0.0, z: -1.18)
    static let catBedTop: Float = 0.09

    /// Feeding station under the far window, on the right.
    static let feederBase = SCNVector3(x: 1.16, y: 0.0, z: -2.02)
    static let feederBowl = SCNVector3(x: 1.16, y: 0.045, z: -1.76)
    static let fountainBase = SCNVector3(x: 0.66, y: 0.0, z: -2.02)
    static let fountainRim = SCNVector3(x: 0.66, y: 0.115, z: -1.78)

    /// Covered litter box, far side on the left.
    static let litterBoxCenter = SCNVector3(x: -0.62, y: 0.0, z: -1.94)
    static let litterEntrance = SCNVector3(x: -0.62, y: 0.0, z: -1.62)

    /// Toys.
    static let toyBasketCenter = SCNVector3(x: -0.12, y: 0.0, z: 0.62)
    static let toyMouseSpot = SCNVector3(x: 0.16, y: 0.0, z: -0.52)
    static let toyBallSpot = SCNVector3(x: -0.34, y: 0.0, z: -0.86)

    /// Paper lantern in the far +X corner.
    static let lanternCenter = SCNVector3(x: 1.42, y: 0.0, z: -1.96)
    static let lanternLightHeight: Float = 0.92

    /// Window sill the cat jumps onto to watch the garden.
    static let windowSill = SCNVector3(x: 0.10, y: windowSillHeight, z: -2.02)
    static let windowCenter = SCNVector3(x: 0.05, y: 1.20, z: -halfDepth)
    static let sideWindowCenter = SCNVector3(x: halfWidth, y: 1.25, z: -0.70)

    /// Where the cat stands when it comes over for attention. Far enough back that
    /// it sits clear of the HUD along the bottom of the screen — at the original
    /// distance a cat that came when called was half-hidden behind the status pill.
    static let playerLapSpot = SCNVector3(x: 0.06, y: 0.0, z: 0.72)
    static let playerNearSpot = SCNVector3(x: -0.10, y: 0.0, z: 0.56)

    /// Sunny patch on the tatami — slides across the floor through the day.
    static func sunPatchPosition(sky: SkyState) -> SCNVector3 {
        let t = clamp(remap(sky.sunAzimuth, deg(70), deg(290), 0, 1))
        let x = mix(1.15, -1.05, t)
        let depth = mix(-1.60, -0.55, 1 - clamp(sky.sunElevation / 1.1))
        return SCNVector3(x: x, y: 0, z: depth)
    }

    // Navigation -----------------------------------------------------------

    /// Keeps the cat inside the room and out of solid furniture.
    static func clampToWalkable(_ p: SCNVector3) -> SCNVector3 {
        var x = min(max(p.x, -halfWidth + 0.24), halfWidth - 0.24)
        var z = min(max(p.z, -halfDepth + 0.34), halfDepth - 0.55)

        // Out of the tansu chest.
        if x > tansuCenter.x - tansuSize.x * 0.5 - 0.18 &&
            abs(z - tansuCenter.z) < tansuSize.z * 0.5 + 0.10 {
            x = tansuCenter.x - tansuSize.x * 0.5 - 0.18
        }
        // Out of the cat-tree base.
        if abs(x - catTreeBase.x) < 0.26 && abs(z - catTreeBase.z) < 0.26 {
            z += 0.30
        }
        // The cat can walk under the table, so only nudge off the exact legs.
        if abs(x - tableCenter.x) < 0.05 && abs(z - tableCenter.z) < 0.05 {
            z += 0.14
        }
        return SCNVector3(x: x, y: p.y, z: z)
    }

    /// Random reachable point, biased toward the half of the room the player can see.
    static func randomFloorPoint(using g: inout SeededGenerator) -> SCNVector3 {
        let p = SCNVector3(x: g.float(-halfWidth + 0.35, halfWidth - 0.35),
                           y: 0,
                           z: g.float(-halfDepth + 0.45, halfDepth - 0.80))
        return clampToWalkable(p)
    }
}
