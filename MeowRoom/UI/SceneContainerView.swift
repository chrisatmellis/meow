import SwiftUI
import SceneKit

/// Hosts the SceneKit view and routes touches to the scene controller.
struct SceneContainerView: UIViewRepresentable {
    let controller: GameSceneController

    func makeCoordinator() -> Coordinator {
        Coordinator(controller: controller)
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView()
        view.scene = controller.scene
        view.delegate = controller
        view.rendersContinuously = true
        view.isPlaying = true
        view.allowsCameraControl = false          // the player never moves
        view.antialiasingMode = RenderQuality.antialiasing
        view.preferredFramesPerSecond = RenderQuality.preferredFramesPerSecond
        view.backgroundColor = .black
        view.autoenablesDefaultLighting = false
        view.isJitteringEnabled = false

        let tap = UITapGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handleTap(_:)))
        view.addGestureRecognizer(tap)

        let pan = UIPanGestureRecognizer(target: context.coordinator,
                                         action: #selector(Coordinator.handlePan(_:)))
        pan.maximumNumberOfTouches = 1
        view.addGestureRecognizer(pan)

        context.coordinator.view = view
        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {}

    final class Coordinator: NSObject {
        let controller: GameSceneController
        weak var view: SCNView?
        private var lastPoint: CGPoint = .zero

        init(controller: GameSceneController) {
            self.controller = controller
        }

        @objc func handleTap(_ gr: UITapGestureRecognizer) {
            guard let view else { return }
            controller.handleTap(at: gr.location(in: view), in: view)
        }

        @objc func handlePan(_ gr: UIPanGestureRecognizer) {
            guard let view else { return }
            let point = gr.location(in: view)
            switch gr.state {
            case .began:
                lastPoint = point
                controller.beginPan(at: point, in: view)
            case .changed:
                let delta = CGPoint(x: point.x - lastPoint.x, y: point.y - lastPoint.y)
                lastPoint = point
                controller.updatePan(at: point, translationDelta: delta, in: view)
            case .ended, .cancelled, .failed:
                controller.endPan()
            default:
                break
            }
        }
    }
}
