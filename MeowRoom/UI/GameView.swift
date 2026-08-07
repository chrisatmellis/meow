import SwiftUI

struct GameView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vm: GameViewModel

    @State private var showSettings = false

    var body: some View {
        ZStack {
            if let controller = model.controller {
                SceneContainerView(controller: controller)
                    .ignoresSafeArea()
            } else {
                // First frame after launch: building the room's meshes and textures.
                ZStack {
                    Color.black.ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                        Text("Opening the shoji…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .onAppear { model.startGame() }
            }

            VStack(spacing: 0) {
                topBar
                Spacer()
                if let toast = vm.toast {
                    Text(toast)
                        .font(.callout.weight(.medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial, in: Capsule())
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .padding(.bottom, 8)
                }
                statusLine
                bottomBar
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $vm.showCareSheet) {
            CareSheet()
                .environmentObject(model)
                .environmentObject(vm)
                .presentationDetents([.height(380)])
        }
        .sheet(isPresented: $showSettings) {
            SettingsSheet()
                .environmentObject(model)
                .environmentObject(vm)
                .presentationDetents([.medium])
        }
    }

    // MARK: - Top

    private var topBar: some View {
        VStack(spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(vm.catName)
                        .font(.title3.weight(.semibold))
                    HStack(spacing: 6) {
                        Text(vm.needs.moodLabel)
                        Text("·")
                        Text(vm.timeString)
                        Text("·")
                        Text(vm.phaseName)
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 10) {
                    Button {
                        withAnimation(.spring(duration: 0.3)) { vm.showNeeds.toggle() }
                    } label: {
                        Image(systemName: vm.showNeeds ? "chart.bar.fill" : "chart.bar")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel(vm.showNeeds ? "Hide needs" : "Show needs")
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 38, height: 38)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .accessibilityLabel("Settings")
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))

            if vm.showNeeds {
                needsPanel
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.top, 6)
    }

    private var needsPanel: some View {
        let items: [NeedKey] = [.fullness, .hydration, .rest, .bladder, .social, .play, .cleanliness, .curiosity]
        return LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
            ForEach(items, id: \.self) { key in
                NeedBar(key: key, value: vm.needs[key])
            }
        }
        .padding(12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    // MARK: - Bottom

    private var statusLine: some View {
        HStack(spacing: 8) {
            if vm.purring {
                Image(systemName: "waveform")
                    .foregroundStyle(.pink)
            }
            Text(vm.isOverstimulated
                 ? "\(vm.catName) has had quite enough, thank you"
                 : "\(vm.catName) is \(vm.activityCaption)")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if vm.canPet && !vm.isOverstimulated {
                Text("· swipe to pet")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.pink)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.bottom, 10)
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            ActionButton(icon: "hand.wave.fill", label: "Call",
                         hint: "Call \(vm.catName) over") {
                model.controller?.callCat()
            }
            ActionButton(icon: "figure.play", label: "Wand", active: vm.wandMode,
                         hint: vm.wandMode ? "Put the wand toy away" : "Take out the wand toy") {
                vm.wandMode.toggle()
                model.controller?.setWand(active: vm.wandMode)
                vm.flash(vm.wandMode ? "Drag to swing the wand" : "Wand away")
            }
            ActionButton(icon: "fish.fill", label: "Treat",
                         hint: "Toss a treat") {
                model.controller?.dropTreat()
                vm.flash("You toss a treat onto the tatami")
            }
            ActionButton(icon: "shippingbox.fill", label: "Care",
                         hint: "Feeder, fountain, litter box and lantern") {
                vm.showCareSheet = true
            }
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

// MARK: - Components

struct NeedBar: View {
    let key: NeedKey
    let value: Float

    private var tint: Color {
        switch value {
        case ..<0.25: return .red
        case ..<0.5: return .orange
        case ..<0.75: return .yellow
        default: return .green
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: key.symbol)
                .font(.system(size: 11))
                .frame(width: 16)
                .foregroundStyle(tint)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.14))
                    Capsule()
                        .fill(tint.opacity(0.85))
                        .frame(width: max(3, geo.size.width * CGFloat(clamp(value))))
                }
            }
            .frame(height: 6)
        }
        .frame(height: 18)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(key.displayName): \(Int(clamp(value) * 100)) percent")
    }
}

struct ActionButton: View {
    let icon: String
    let label: String
    var active: Bool = false
    var hint: String? = nil
    let action: () -> Void

    var body: some View {
        Button {
            Haptics.tick()
            action()
        } label: {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.caption2.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(active ? Color.accentColor.opacity(0.35) : Color.white.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .foregroundStyle(active ? Color.accentColor : Color.primary)
        .accessibilityLabel(hint ?? label)
    }
}

// MARK: - Sheets

struct CareSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Room")
                .font(.title3.weight(.semibold))

            careRow(icon: "fork.knife", title: "Automatic feeder",
                    level: vm.room.feederFood, action: "Refill") {
                model.controller?.refillFeeder()
                vm.flash("Feeder refilled")
            }
            careRow(icon: "drop.fill", title: "Water fountain",
                    level: vm.room.fountainWater, action: "Refill") {
                model.controller?.refillFountain()
                vm.flash("Fountain refilled")
            }
            careRow(icon: "tray.fill", title: "Litter box",
                    level: vm.room.litterCleanliness, action: "Scoop") {
                model.controller?.cleanLitter()
                vm.flash("Litter box scooped")
            }

            HStack(spacing: 12) {
                Toggle("Fountain running", isOn: Binding(
                    get: { vm.room.fountainOn },
                    set: { _ in model.controller?.toggleFountain() }))
                .font(.subheadline)
            }

            HStack(spacing: 12) {
                Toggle("Paper lantern", isOn: Binding(
                    get: { vm.room.lanternOn },
                    set: { _ in model.controller?.toggleLantern() }))
                .font(.subheadline)
            }

            Spacer()
        }
        .padding(24)
    }

    private func careRow(icon: String, title: String, level: Float,
                         action actionTitle: String, perform: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .frame(width: 22)
                .foregroundStyle(level < 0.25 ? Color.orange : Color.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline)
                ProgressView(value: Double(clamp(level)))
                    .tint(level < 0.25 ? Color.orange : Color.green)
            }
            Button(actionTitle) { perform() }
                .buttonStyle(.bordered)
                .font(.caption)
        }
    }
}

struct SettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var vm: GameViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var muted = CatVoice.shared.muted
    @State private var haptics = Haptics.enabled
    @State private var confirmReset = false
    @State private var timeShiftHours: Double = 0

    private var timeShiftLabel: String {
        if abs(timeShiftHours) < 0.125 { return "now" }
        let sign = timeShiftHours > 0 ? "+" : "−"
        return String(format: "%@%.2gh", sign, abs(timeShiftHours))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Your cat") {
                    LabeledContent("Name", value: model.save.profile.name)
                    LabeledContent("Breed", value: model.save.profile.appearance.breed.displayName)
                    LabeledContent("Personality", value: model.save.profile.archetype.displayName)
                    LabeledContent("Together for", value: "\(model.save.profile.ageDays) days")
                    LabeledContent("Bond", value: String(format: "%.0f%%", vm.bond * 100))
                    Button("Edit appearance & personality") {
                        dismiss()
                        model.editCat()
                    }
                }
                Section("Notifications") {
                    Toggle("Tell me what \(model.save.profile.name) is up to",
                           isOn: Binding(get: { model.save.notificationsEnabled },
                                         set: { model.setNotifications($0) }))
                    Text("Nudges when your cat is lonely, wants to play, or is eating.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Sound & touch") {
                    Toggle("Mute", isOn: $muted)
                        .onChange(of: muted) { _, value in CatVoice.shared.muted = value }
                    Toggle("Haptics", isOn: $haptics)
                        .onChange(of: haptics) { _, value in Haptics.enabled = value }
                }
#if DEBUG
                Section("Developer") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Preview time of day: \(timeShiftLabel)")
                            .font(.subheadline)
                        Slider(value: $timeShiftHours, in: -12...12, step: 0.25)
                            .onChange(of: timeShiftHours) { _, value in
                                WorldClock.debugTimeOffset = TimeInterval(value * 3600)
                            }
                        Text("Shifts the sun without waiting for it. Debug builds only.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
#endif
                Section {
                    Button("Start over with a new cat", role: .destructive) {
                        confirmReset = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Start over?", isPresented: $confirmReset) {
                Button("Cancel", role: .cancel) {}
                Button("Start over", role: .destructive) {
                    dismiss()
                    model.startOver()
                }
            } message: {
                Text("This deletes your current cat and everything you've built together.")
            }
        }
    }
}
