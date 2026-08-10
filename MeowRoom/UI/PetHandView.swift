import SwiftUI

/// The little gloved hand that follows a finger while petting.
///
/// It exists to answer a question the game could not otherwise answer: whether
/// the stroke is landing. A swipe that misses the cat and a swipe at a cat that
/// has had enough look exactly the same from the player's side — nothing moves,
/// and there is no cursor, no highlight and no sound to say which of the two
/// happened. So the hand reports it: solid and stroking when the finger is on the
/// cat, faint and still when it is not, and drawing back when the cat is done.
///
/// Drawn rather than shipped as an asset, like everything else here, and drawn in
/// SwiftUI rather than in the scene: it belongs to the finger, not to the room. A
/// hand in the room would be occluded by the cat it is petting, would need to be
/// lit, and would have to be placed in three dimensions from a gesture that only
/// ever reports two.
struct PetHandView: View {
    /// The finger is inside the cat's hit box.
    var onCat: Bool
    /// The cat is close enough and willing to be touched.
    var canPet: Bool
    /// It has had enough, so the hand pulls back rather than aiming.
    var overstimulated: Bool
    /// How hard the stroking is landing, 0...1.
    var intensity: Float

    /// Drives the stroke. One phase, so the hand, its tilt and its trailing arcs
    /// all move together rather than each on a timer of its own.
    @State private var stroking = false

    private var active: Bool { onCat && canPet && !overstimulated }

    /// Three states worth telling apart, and they have to look different at a
    /// glance in a dark room: landing, aimed at nothing, and refused.
    private var shown: Double {
        if overstimulated { return onCat ? 0.95 : 0.5 }
        if !canPet { return 0.4 }
        return onCat ? 1 : 0.42
    }

    private var tint: Color {
        if overstimulated { return Color(red: 0.98, green: 0.44, blue: 0.42) }
        return active ? .white : Color.white.opacity(0.75)
    }

    var body: some View {
        ZStack {
            // Motion arcs, the cartoon shorthand for "this is moving". Only when
            // the stroke is landing — they are the whole difference between a hand
            // resting on a cat and a hand petting one.
            if active {
                ForEach(0..<2, id: \.self) { i in
                    StrokeArc()
                        .stroke(tint.opacity(0.55 - Double(i) * 0.2),
                                style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .frame(width: 26, height: 18)
                        .offset(x: -20 - CGFloat(i) * 7, y: 2)
                        .opacity(stroking ? 0.2 : 1)
                }
            }

            GlovedHand()
                .fill(tint)
                .overlay(GlovedHand().stroke(Color.black.opacity(0.55), lineWidth: 1.6))
                .frame(width: 34, height: 38)
                // The stroke itself: a short sweep with a wrist tilt, which reads
                // as petting where a straight slide reads as dragging.
                .rotationEffect(.degrees(active ? (stroking ? -13 : 9) : 0), anchor: .bottom)
                .offset(x: active ? (stroking ? -7 : 7) : 0)
        }
        .compositingGroup()
        .opacity(shown)
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        .animation(.easeInOut(duration: 0.16), value: onCat)
        .onAppear { stroking = true }
        .animation(active
                   // Faster the brisker the stroke, but never so fast it blurs.
                   ? .easeInOut(duration: Double(0.46 - 0.22 * min(1, max(0, intensity))))
                       .repeatForever(autoreverses: true)
                   : .default,
                   value: stroking)
        .accessibilityHidden(true)
    }
}

/// A cartoon glove: rounded palm, three folded fingers, a pointing index and a
/// thumb, with a cuff. Built from arcs rather than a font or an image so it stays
/// crisp at any size and needs nothing in the bundle.
private struct GlovedHand: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()

        // Palm.
        p.addRoundedRect(in: CGRect(x: w * 0.16, y: h * 0.40, width: w * 0.66, height: h * 0.42),
                         cornerSize: CGSize(width: w * 0.24, height: w * 0.24))

        // Index finger, pointing up and slightly in — the one doing the stroking.
        p.addRoundedRect(in: CGRect(x: w * 0.40, y: h * 0.06, width: w * 0.20, height: h * 0.44),
                         cornerSize: CGSize(width: w * 0.10, height: w * 0.10))

        // Two more knuckles beside it, shorter, so the hand reads as a hand rather
        // than as a mitten.
        p.addRoundedRect(in: CGRect(x: w * 0.60, y: h * 0.22, width: w * 0.18, height: h * 0.30),
                         cornerSize: CGSize(width: w * 0.09, height: w * 0.09))
        p.addRoundedRect(in: CGRect(x: w * 0.22, y: h * 0.26, width: w * 0.18, height: h * 0.26),
                         cornerSize: CGSize(width: w * 0.09, height: w * 0.09))

        // Thumb, tucked along the left edge.
        p.addRoundedRect(in: CGRect(x: w * 0.02, y: h * 0.50, width: w * 0.26, height: h * 0.16),
                         cornerSize: CGSize(width: w * 0.08, height: w * 0.08))

        // Cuff.
        p.addRoundedRect(in: CGRect(x: w * 0.20, y: h * 0.78, width: w * 0.58, height: h * 0.18),
                         cornerSize: CGSize(width: w * 0.07, height: w * 0.07))
        return p
    }
}

/// One of the little curved lines trailing the hand.
private struct StrokeArc: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.midY),
                       control: CGPoint(x: rect.midX, y: rect.minY - rect.height * 0.3))
        return p
    }
}
