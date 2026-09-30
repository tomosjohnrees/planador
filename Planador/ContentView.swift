import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @State private var section: AppSection = .plan
    @State private var showingSettings = false

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Hairline().frame(width: 1)
            Group {
                switch section {
                case .plan:
                    PlanView(openFocus: { section = .focus })
                case .focus:
                    FocusView()
                case .review:
                    ReviewView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
        .background(Theme.sidebar)
        .foregroundStyle(Theme.ink)
        .sheet(isPresented: $showingSettings) { SettingsView() }
        .alert("Planador needs attention", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK") { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "An unknown error occurred.")
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(AppSection.allCases) { item in
                Button { section = item } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 39)
                        .background(section == item ? Theme.paleGreen : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(section == item ? .isSelected : [])
            }
            Spacer()
            Button { showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 39)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.top, 76)
        .padding(.bottom, 18)
        .frame(width: 140)
    }
}
