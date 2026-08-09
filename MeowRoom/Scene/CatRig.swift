import Foundation
import RealityKit
import UIKit

/// One leg: hip → knee → ankle → paw. Solved with two-bone IK so the paws stay planted.
struct LegRig {
    var hip = Entity()
    var knee = Entity()
    var ankle = Entity()
    var paw = Entity()
    var isFront = true
    var side: Float = 1          // -1 = the cat's left, +1 = right
    var upperLength: Float = 0.08
    var lowerLength: Float = 0.07
    var pawLength: Float = 0.03
    /// Rest position of the foot in body space.
    var restFoot = SIMD3<Float>.zero
    /// Rest position of the hip in body space.
    var restHip = SIMD3<Float>.zero
    /// Phase offset in the walk cycle, 0...1.
    var gaitPhase: Float = 0
    /// Which way the middle joint folds.
    var bendSign: Float = 1

    /// Where each bone points at rest, as the pitch that would take a bone lying
    /// along -Y to it.
    ///
    /// The IK solves for a direction; a joint is given a rotation. Those are the
    /// same number only if the bone rests pointing straight down, which is true of
    /// a rig somebody built for the solver and false of a modelled cat — this one
    /// carries its upper foreleg well forward of vertical. Solving as though it did
    /// not left every leg off by that angle, which on a curled cat meant a hind
    /// leg driven straight through the floor.
    var restUpper: Float = 0
    var restLower: Float = 0
    var restPaw: Float = 0
}

/// Everything the animator needs to pose the cat.
final class CatRig {
    let appearance: CatAppearance

    let root = Entity()          // world placement (position + yaw)
    let body = Entity()          // vertical bob, crouch, lean
    var spine = Entity()         // torso, pitch/roll
    var neck = Entity()
    var head = Entity()
    var jaw = Entity()
    var tailRoot = Entity()      // fixed 180° yaw: local +Z runs down the tail
    var tailPitch = Entity()     // animated lift / sway of the tail base

    var tailSegments: [Entity] = []
    var legs: [LegRig] = []
    var earL = Entity()
    var earR = Entity()
    var eyeL = Entity()
    var eyeR = Entity()
    var lidUpperL = Entity()
    var lidUpperR = Entity()
    var lidLowerL = Entity()
    var lidLowerR = Entity()
    var whiskerRoots: [Entity] = []
    var chestNode = Entity()
    var bellyNode = Entity()
    /// Parts thin enough to light up from behind — ears, nose, paw pads.
    /// `Translucency` drives their emission from where the sun actually is.
    var translucentParts: [TranslucentPart] = []
    var collarNode: Entity?

    /// Set when the cat is the modelled one rather than the generated one: the
    /// single skinned surface, and the joint entities the animator poses. The
    /// animator never looks at either — `ModelCatBuilder.syncPose` copies the one
    /// into the other after it has run.
    var skinnedBody: Entity?
    var skinJoints: [Entity] = []
    /// Fur shells, bound to the same skeleton as the body they cover.
    var skinnedShells: [Entity] = []
    /// Where the chest joint sits at rest. The animator stretches the torso by
    /// moving it, rather than by scaling it: a joint's scale runs down the rest
    /// of the skeleton, so squashing the chest for a loaf would also squash the
    /// head that hangs off it.
    var chestRest = SIMD3<Float>.zero

    /// Which part of the cat an entity belongs to.
    ///
    /// SceneKit's hit test returned a world coordinate, and the zone used to be
    /// worked out by converting that into the spine's space and comparing it
    /// against the torso's dimensions. iOS gestures do not carry a 3D location —
    /// `location3D` is a visionOS affordance — so what is left is the entity, and
    /// the entity turns out to be the better answer anyway: the cat is already
    /// built out of named joints, so an ear is an ear rather than a point that
    /// happens to be far enough forward and high enough up.
    func zone(for entity: Entity) -> PetZone {
        var node: Entity? = entity
        while let current = node {
            if current === earL || current === earR { return .head }
            if current === jaw { return .chin }
            if current === head { return current.name.hasPrefix("muzzle") ? .cheek : .head }
            if current === tailRoot || current === tailPitch { return .tail }
            if tailSegments.contains(where: { $0 === current }) { return .tail }
            if legs.contains(where: { $0.hip === current || $0.knee === current || $0.ankle === current }) {
                return .paw
            }
            if current === bellyNode { return .belly }
            if current === neck || current === chestNode { return .chin }
            if current === spine || current === body { return .back }
            node = current.parent
        }
        return .back
    }

    /// Cached measurements used by the animator.
    var bodyHeight: Float = 0.22
    var torsoLength: Float = 0.26
    var torsoRadius: Float = 0.075

    init(appearance: CatAppearance) {
        self.appearance = appearance
    }
}
