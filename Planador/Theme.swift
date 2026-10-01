import SwiftUI

enum Theme {
    static let canvas = Color(red: 0.987, green: 0.984, blue: 0.976)
    static let sidebar = Color(red: 0.976, green: 0.977, blue: 0.967)
    static let ink = Color(red: 0.12, green: 0.15, blue: 0.14)
    static let muted = Color(red: 0.43, green: 0.47, blue: 0.45)
    static let line = Color(red: 0.89, green: 0.90, blue: 0.88)
    static let green = Color(red: 0.45, green: 0.59, blue: 0.46)
    static let paleGreen = Color(red: 0.90, green: 0.94, blue: 0.89)
}

struct PageHeader: View {
    let title: String
    let date: Date

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 40, weight: .regular, design: .serif))
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(date, format: .dateTime.weekday(.abbreviated).month(.abbreviated).day())
                .font(.system(size: 13))
                .foregroundStyle(Theme.muted)
        }
        .padding(.bottom, 30)
    }
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.line).frame(height: 1) }
}

struct RoundAction: View {
    let symbol: String
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .frame(width: 46, height: 46)
                .background(Theme.sidebar, in: Circle())
                .overlay(Circle().stroke(Theme.line, lineWidth: 0.7))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct TaskDeletionAlert: ViewModifier {
    @EnvironmentObject private var store: AppStore
    @Binding var task: PlanTask?

    func body(content: Content) -> some View {
        content.alert("Delete task?", isPresented: Binding(
            get: { task != nil },
            set: { if !$0 { task = nil } }
        )) {
            Button("Cancel", role: .cancel) { task = nil }
            Button("Delete task", role: .destructive) {
                guard let id = task?.id else { return }
                task = nil
                store.delete(id)
            }
        } message: {
            Text("This deletes “\(task?.title ?? "this task")” and its notes. You can undo this during the current app session. Logged focus time is kept.")
        }
    }
}

extension View {
    func taskDeletionAlert(task: Binding<PlanTask?>) -> some View {
        modifier(TaskDeletionAlert(task: task))
    }
}
