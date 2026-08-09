import SwiftUI
import RealityKit

/// Hosts the scene and routes touches to the controller.
///
/// The touch handling is the part that changed most. SceneKit put a hit test on
/// the view: give it a screen point, get back everything under it, sorted. There
/// is no such thing here — SwiftUI's spatial gestures resolve the entity
/// themselves and hand it over, and only entities that opted in with an
/// `InputTargetComponent` are candidates.
///
/// That is a better arrangement than it first looks. Every ray used to hit every
/// surface in the room and the code then sifted for one belonging to the cat; now
/// the cat is the only thing listening, and the controller never needs to know
/// what a view is.
struct SceneContainerView: View {
    let controller: GameSceneController

    /// Where the last drag was on screen. The controller still wants this in
    /// points, because petting speed is measured in how fast the finger moves
    /// rather than how far the hand travels in the room.
    @State private var lastDrag: CGPoint?

    var body: some View {
        RealityView { content in
            // Non-AR: a virtual camera looking at a room, not the device's camera
            // looking at the world.
            content.camera = .virtual
            content.environment = .default

            // Depth of field and HDR survive the move off SceneKit's camera.
            // Bloom, vignette and colour fringing do not, and are not faked here.
            content.renderingEffects.depthOfField = RenderQuality.wantsDepthOfField ? .automatic : .disabled
            content.renderingEffects.antialiasing = RenderQuality.wantsAntialiasing ? .automatic : .none
            content.renderingEffects.dynamicRange = .high
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
                .onEnded { value in
                    controller.handleTap(on: value.entity,
                                         at: value.convert(value.location3D, from: .local, to: .scene))
                }
        )
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { value in
                    let world = value.convert(value.location3D, from: .local, to: .scene)
                    guard let previous = lastDrag else {
                        lastDrag = value.location
                        controller.beginPan(at: value.location, on: value.entity, worldPoint: world)
                        return
                    }
                    let delta = CGPoint(x: value.location.x - previous.x,
                                        y: value.location.y - previous.y)
                    lastDrag = value.location
                    controller.updatePan(at: value.location, translationDelta: delta,
                                         on: value.entity, worldPoint: world)
                }
                .onEnded { _ in
                    lastDrag = nil
                    controller.endPan()
                }
        )
        // The wand is swung by dragging anywhere at all, including off the cat and
        // off every other target, so it needs a gesture aimed at no entity.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard controller.wandActive else { return }
                    let previous = lastDrag ?? value.location
                    lastDrag = value.location
                    controller.updatePan(at: value.location,
                                         translationDelta: CGPoint(x: value.location.x - previous.x,
                                                                   y: value.location.y - previous.y),
                                         on: nil, worldPoint: .zero)
                }
                .onEnded { _ in lastDrag = nil }
        )
    }
}
