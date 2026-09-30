import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Settings")
                    .font(.system(size: 26, design: .serif))
                Spacer()
                Button("Done") { dismiss() }
            }
            Stepper(value: Binding(
                get: { store.data.timerSettings.workMinutes },
                set: { store.setWorkMinutes($0) }
            ), in: 5...120, step: 5) {
                HStack {
                    Text("Focus session")
                    Spacer()
                    Text("\(store.data.timerSettings.workMinutes) min")
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Focus session length")
            Stepper(value: Binding(
                get: { store.data.timerSettings.breakMinutes },
                set: { store.setBreakMinutes($0) }
            ), in: 1...30) {
                HStack {
                    Text("Break")
                    Spacer()
                    Text("\(store.data.timerSettings.breakMinutes) min")
                        .foregroundStyle(Theme.muted)
                        .monospacedDigit()
                }
            }
            .accessibilityLabel("Break length")
            Text("Changes apply to the next timer.\nA chime marks each timer's end.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Text("Planador saves tasks and focus time on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .padding(28)
        .frame(width: 440, height: 310)
    }
}
