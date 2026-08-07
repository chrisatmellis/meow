import SwiftUI

@main
struct MeowApp: App {
    @StateObject private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    init() {
#if DEBUG
        WorldClock.applyDebugEnvironment()
#endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(model.viewModel)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .onChange(of: scenePhase) { _, phase in
                    model.handleScenePhase(phase == .active)
                }
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            switch model.screen {
            case .creator:
                CharacterCreatorView()
                    .transition(.opacity)
            case .game:
                GameView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: model.screen)
        .sheet(isPresented: $model.showAwayLog) {
            AwayLogView(entries: model.awayLog, catName: model.save.profile.name)
                .presentationDetents([.medium])
        }
    }
}

struct AwayLogView: View {
    let entries: [String]
    let catName: String
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("While you were away")
                .font(.title2.weight(.semibold))
            VStack(alignment: .leading, spacing: 12) {
                ForEach(Array(entries.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .top, spacing: 10) {
                        Circle()
                            .fill(Color.accentColor.opacity(0.7))
                            .frame(width: 6, height: 6)
                            .padding(.top, 7)
                        Text(line)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("Say hello to \(catName)")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(26)
    }
}
