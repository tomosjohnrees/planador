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
            Text("Focus session length")
                .font(.system(size: 14, weight: .medium))
            Picker("Focus session length", selection: Binding(
                get: { store.data.clock.durationMinutes },
                set: { store.setFocusDuration($0) }
            )) {
                ForEach([15, 25, 45, 60], id: \.self) { value in
                    Text("\(value) minutes").tag(value)
                }
            }
            .labelsHidden()
            Text("Changing the length resets the current timer. Time already focused stays in your daily total.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
            Spacer()
            Text("Planador saves tasks and focus time on this Mac.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
        }
        .padding(28)
        .frame(width: 420, height: 260)
    }
}
