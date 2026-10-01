import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.undoManager) private var undoManager
    @State private var showingSettings = false
    @FocusState private var focusedSection: AppSection?

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Hairline().frame(width: 1)
            Group {
                switch store.section {
                case .plan:
                    PlanView()
                case .focus:
                    FocusView()
                case .review:
                    ReviewView()
                case .search:
                    SearchView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.canvas)
        }
        .background(Theme.sidebar)
        .foregroundStyle(Theme.ink)
        .onAppear {
            store.undoManager = undoManager
            if store.data.clock.phase == .breakReady { store.section = .focus }
        }
        .onChange(of: store.data.clock.phase) { _, phase in
            if phase == .breakReady || phase == .ready { store.section = .focus }
        }
        .onChange(of: undoManager) { _, manager in store.undoManager = manager }
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
                Button { store.section = item } label: {
                    Label(item.rawValue, systemImage: item.symbol)
                        .font(.system(size: 13))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .frame(height: 39)
                        .background(store.section == item ? Theme.paleGreen : .clear,
                                    in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .focused($focusedSection, equals: item)
                .accessibilityAddTraits(store.section == item ? .isSelected : [])
            }
            Spacer()
            Button { showingSettings = true } label: {
                Label("Settings", systemImage: "gearshape")
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .frame(height: 39)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 10)
        .padding(.top, 76)
        .padding(.bottom, 18)
        .frame(width: 140)
    }
}
