import Foundation
import UIKit

/// Touch feedback. A purring cat under your hand is mostly a *feeling*, so the
/// haptics here are as much a part of petting as the sound is.
enum Haptics {

    static var enabled = true

    private static let light = UIImpactFeedbackGenerator(style: .light)
    private static let soft = UIImpactFeedbackGenerator(style: .soft)
    private static let medium = UIImpactFeedbackGenerator(style: .medium)
    private static let notice = UINotificationFeedbackGenerator()
    private static let selection = UISelectionFeedbackGenerator()

    private static var purrPhase: Float = 0
    private static var lastPurrTick: TimeInterval = 0

    /// Call once when the game scene appears so the Taptic Engine is warm.
    static func prepare() {
        guard enabled else { return }
        onMain {
            light.prepare()
            soft.prepare()
            medium.prepare()
            notice.prepare()
        }
    }

    /// A steady, low pulse that tracks the purr's intensity. Called every frame
    /// from the render loop; it rate-limits itself.
    static func purr(level: Float) {
        guard enabled, level > 0.08 else { return }
        let now = Date().timeIntervalSinceReferenceDate
        // Roughly 6 Hz at a full purr, slowing as it fades.
        let interval = TimeInterval(0.34 - 0.18 * clamp(level))
        guard now - lastPurrTick >= interval else { return }
        lastPurrTick = now
        onMain { soft.impactOccurred(intensity: CGFloat(0.25 + 0.45 * clamp(level))) }
    }

    /// The moment a stroke lands on the cat.
    static func petStroke(intensity: Float) {
        guard enabled else { return }
        onMain { light.impactOccurred(intensity: CGFloat(0.2 + 0.5 * clamp(intensity))) }
    }

    /// "That is enough."
    static func warning() {
        guard enabled else { return }
        onMain { notice.notificationOccurred(.warning) }
    }

    static func success() {
        guard enabled else { return }
        onMain { notice.notificationOccurred(.success) }
    }

    /// Landing after a jump, or the teacup hitting the tatami.
    static func thud() {
        guard enabled else { return }
        onMain { medium.impactOccurred(intensity: 0.7) }
    }

    /// The collar bell.
    static func jingle() {
        guard enabled else { return }
        onMain { light.impactOccurred(intensity: 0.35) }
    }

    static func tick() {
        guard enabled else { return }
        onMain { selection.selectionChanged() }
    }

    private static func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread { block() } else { DispatchQueue.main.async(execute: block) }
    }
}
