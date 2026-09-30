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
            Text("Changes apply to the next focus session or break. A sound plays when each timer ends.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text("Planador saves tasks and focus time on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .padding(28)
        .frame(width: 440, height: 280)
    }
}
