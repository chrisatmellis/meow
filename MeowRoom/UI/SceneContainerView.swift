import SwiftUI
import RealityKit

/// Hosts the scene and routes touches to the controller.
///
/// The touch handling is the part that changed most. SceneKit put a hit test on
/// the view: give it a screen point, get back everything under it sorted by depth,
/// with a world coordinate on each hit. There is no such thing here — SwiftUI's
/// spatial gestures resolve the entity themselves and hand that over, and only
/// entities that opted in with an `InputTargetComponent` are candidates.
///
/// Two things follow. Every ray used to hit every surface in the room and the code
/// then sifted for one belonging to the cat; now the cat is the only thing
/// listening. And there is no world coordinate on iOS — `location3D` is a visionOS
/// affordance — so which part of the cat was touched comes from the entity rather
/// than from geometry. The cat is built out of named joints, so that is the better
/// answer regardless: an ear is an ear, not a point that happens to be far enough
/// forward and high enough up.
struct SceneContainerView: View {
    let controller: GameSceneController

    /// Where the last drag was on screen. The controller still wants this in
    /// points, because petting speed is measured in how fast the finger moves
    /// rather than how far the hand travels in the room.
    @State private var lastDrag: CGPoint?

    /// Where to draw the gloved hand, and what it should be doing. Nil when no
    /// finger is down, which is the only time there is nothing to report.
    @State private var pointer: CGPoint?
    @State private var pointerState = GameSceneController.PetPointer(
        onCat: false, canPet: false, overstimulated: false, intensity: 0)
    @State private var viewSize: CGSize = .zero

    var body: some View {
        RealityView { content in
            // Non-AR: a virtual camera looking at a room, not the device's camera
            // looking at the world.
            content.camera = .virtual
            // Not `.default`. Whatever a non-AR RealityView puts behind an empty
            // frame, it is a flat unlit grey — and the one place in this room you
            // can see past the walls is the window, which is the one place a flat
            // unlit grey is unmistakable. The room is closed except for that
            // opening, so the background is only ever visible through it, and it
            // should be the same sky the garden is painted from.
            if let sky = controller.skybox { content.environment = .skybox(sky) }

            // Depth of field and HDR survive the move off SceneKit's camera.
            // Bloom, vignette and colour fringing do not, and are not faked here.
            content.renderingEffects.depthOfField = RenderQuality.wantsDepthOfField ? .enabled : .disabled
            // Antialiasing and dynamic range each have their own type rather than
            // sharing the enabled/disabled one, and neither offers a "high": the
            // choice is 4x multisampling or nothing, and the display's own range
            // or a forced standard one. `.default` is the wide one.
            content.renderingEffects.antialiasing = RenderQuality.wantsAntialiasing ? .multisample4X : .none
            content.renderingEffects.dynamicRange = .default
            content.renderingEffects.cameraGrain = .disabled
            content.renderingEffects.motionBlur = .disabled

            content.add(controller.root)
            // Held by the controller. Whether the content retains it is not
            // documented either way, and an unretained subscription is a frame
            // loop that silently stops — a still room with a live HUD.
            controller.frameLoop = content.subscribe(to: SceneEvents.Update.self) { event in
                controller.update(deltaTime: Float(event.deltaTime))
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToAnyEntity()
                .onEnded { value in controller.handleTap(on: value.entity) }
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    track(value.location)
                    guard let previous = lastDrag else {
                        lastDrag = value.location
                        controller.beginPan(at: value.location, on: value.entity)
                        return
                    }
                    let delta = CGPoint(x: value.location.x - previous.x,
                                        y: value.location.y - previous.y)
                    lastDrag = value.location
                    controller.updatePan(at: value.location, translationDelta: delta,
                                         on: value.entity)
                }
                .onEnded { _ in
                    lastDrag = nil
                    pointer = nil
                    controller.endPan()
                }
        )
        // The wand is swung by dragging anywhere at all, including off the cat and
        // off every other target, so it needs a gesture aimed at no entity.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    track(value.location)
                    guard controller.wandActive else { return }
                    let previous = lastDrag ?? value.location
                    lastDrag = value.location
                    controller.updatePan(at: value.location,
                                         translationDelta: CGPoint(x: value.location.x - previous.x,
                                                                   y: value.location.y - previous.y),
                                         on: nil)
                }
                .onEnded { _ in
                    lastDrag = nil
                    pointer = nil
                }
        )
        // The hand rides above the scene, offset up and to the right of the touch
        // so the finger covering it is not the thing it is trying to show.
        .overlay(alignment: .topLeading) {
            let posed = pointer == nil && parkedPointer != nil
            if let at = pointer ?? parkedPointer, !controller.wandActive {
                PetHandView(onCat: posed || pointerState.onCat,
                            canPet: posed || pointerState.canPet,
                            overstimulated: !posed && pointerState.overstimulated,
                            intensity: posed ? 0.6 : pointerState.intensity)
                    .frame(width: 44, height: 44)
                    .position(handPosition(for: at))
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .background {
            // Measured rather than assumed: the hit box is computed in the same
            // points the gesture reports, and the scene view is not the screen.
            GeometryReader { proxy in
                Color.clear.onAppear { viewSize = proxy.size }
                    .onChange(of: proxy.size) { viewSize = $1 }
            }
        }
    }

    /// Where to park the hand when there is no finger, so that a screenshot can
    /// show it.
    ///
    /// A simulator cannot be sent a drag — `simctl` has no way to synthesise one —
    /// so without this the hand is a drawing nobody has ever looked at, and this
    /// project has now shipped three of those. It is parked at a fixed place in
    /// the frame and forced into its landed state, which is the state worth
    /// looking at.
    ///
    /// It proves the drawing and nothing else. Whether the hit box is *on* the cat
    /// is a separate claim, and one this could not make honestly: SwiftUI would
    /// have to re-evaluate the overlay as the cat walked, and nothing here asks it
    /// to. That claim is the assertion suite's, which projects a posed cat and
    /// checks the box is centred, bigger than a thumb, contains its own middle,
    /// excludes the corners, and shrinks as the cat crosses the room.
    private var parkedPointer: CGPoint? {
        #if DEBUG
        guard ProcessInfo.processInfo.environment["MEOW_SHOW_HAND"]?.isEmpty == false,
              viewSize.width > 1 else { return nil }
        return parked
        #else
        return nil
        #endif
    }

    /// The parked position, as its own value so the overlay can tell a parked
    /// hand from a real one and show the landed state for the picture.
    private var parked: CGPoint? {
        viewSize.width > 1 ? CGPoint(x: viewSize.width * 0.44, y: viewSize.height * 0.56) : nil
    }

    /// Keeps the hand beside the finger and inside the view.
    private func handPosition(for point: CGPoint) -> CGPoint {
        let offset = CGPoint(x: point.x + 30, y: point.y - 34)
        guard viewSize.width > 0 else { return offset }
        return CGPoint(x: min(max(offset.x, 24), viewSize.width - 24),
                       y: min(max(offset.y, 24), viewSize.height - 24))
    }

    private func track(_ point: CGPoint) {
        pointer = point
        pointerState = controller.petPointer(at: point, in: viewSize)
    }
}
