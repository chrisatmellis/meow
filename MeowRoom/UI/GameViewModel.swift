import Foundation
import SwiftUI

/// Everything the HUD renders. Updated from the render loop at 4 Hz.
final class GameViewModel: ObservableObject {
    @Published var needs = CatNeeds()
    @Published var room = RoomState()
    @Published var bond: Float = 0
    @Published var activityCaption: String = "settling in"
    @Published var isOverstimulated = false
    @Published var canPet = false
    @Published var purring = false
    @Published var timeString: String = ""
    @Published var phaseName: String = ""
    @Published var catName: String = "Mochi"

    @Published var toast: String? = nil
    @Published var wandMode = false
    @Published var showCareSheet = false
    @Published var showNeeds = true

    private var toastTask: DispatchWorkItem?

    func flash(_ message: String) {
        toastTask?.cancel()
        withAnimation(.easeOut(duration: 0.2)) { toast = message }
        let task = DispatchWorkItem { [weak self] in
            withAnimation(.easeIn(duration: 0.4)) { self?.toast = nil }
        }
        toastTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6, execute: task)
    }
}
