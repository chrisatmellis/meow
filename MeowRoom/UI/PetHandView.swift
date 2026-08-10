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

/// A cartoon glove, palm down, of the sort that would rest on a cat's back:
/// the back of the hand, four fingers hanging off the front edge, a thumb along
/// the near side, and a cuff where the wrist leaves toward the arm.
///
/// Palm down and fingers together, deliberately. The first version had one finger
/// standing proud of two shorter ones — meant as an index finger doing the
/// stroking, and unmistakable as something else entirely the moment it was
/// rendered. Four fingers of near-equal length hanging in a row cannot be read
/// that way, and it is also simply what a hand petting a cat looks like.
///
/// Built from rounded rectangles rather than a font or an image so it stays crisp
/// at any size and needs nothing in the bundle.
private struct GlovedHand: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        var p = Path()

        // Cuff, at the back, where the wrist would carry on to an arm.
        p.addRoundedRect(in: CGRect(x: w * 0.30, y: h * 0.02, width: w * 0.52, height: h * 0.20),
                         cornerSize: CGSize(width: w * 0.08, height: w * 0.08))

        // The back of the hand.
        p.addRoundedRect(in: CGRect(x: w * 0.14, y: h * 0.16, width: w * 0.72, height: h * 0.46),
                         cornerSize: CGSize(width: w * 0.22, height: w * 0.22))

        // Four fingers along the front edge, hanging toward the cat. Graduated a
        // little so it is a hand rather than a comb, and never by enough for one
        // to stand out from the others.
        let lengths: [CGFloat] = [0.20, 0.25, 0.24, 0.19]
        for (i, length) in lengths.enumerated() {
            let x = w * (0.16 + CGFloat(i) * 0.18)
            p.addRoundedRect(in: CGRect(x: x, y: h * 0.54, width: w * 0.155, height: h * length),
                             cornerSize: CGSize(width: w * 0.077, height: w * 0.077))
        }

        // Thumb, tucked along the near side.
        p.addRoundedRect(in: CGRect(x: w * 0.02, y: h * 0.34, width: w * 0.24, height: h * 0.15),
                         cornerSize: CGSize(width: w * 0.075, height: w * 0.075))
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
