import SwiftUI

struct ReviewView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PageHeader(title: "Review", date: store.now)
                HStack(spacing: 0) {
                    metric("\(store.completedToday.count)", caption: "Completed today")
                    Hairline().frame(width: 1, height: 60)
                    metric("\(store.todayTasks.count)", caption: "Unfinished today")
                    Hairline().frame(width: 1, height: 60)
                    metric(DurationLabel.summary(store.focusedToday), caption: "Total focused time")
                }
                .padding(.bottom, 40)
                Hairline()
                sectionTitle("Completed today")
                if store.completedToday.isEmpty {
                    empty("Completed tasks will appear here.")
                } else {
                    ForEach(store.completedToday) { task in
                        taskRow(task, complete: true)
                    }
                }
                Hairline().padding(.top, 30)
                sectionTitle("Unfinished today")
                if store.todayTasks.isEmpty {
                    empty("You’re all caught up for today.")
                } else {
                    ForEach(store.todayTasks) { task in
                        taskRow(task, complete: false)
                    }
                }
            }
            .frame(maxWidth: 680)
            .padding(.horizontal, 44)
            .padding(.top, 49)
            .padding(.bottom, 44)
            .frame(maxWidth: .infinity)
        }
    }

    private func metric(_ value: String, caption: String) -> some View {
        VStack(spacing: 5) {
            Text(value)
                .font(.system(size: 28, weight: .regular, design: .serif))
                .monospacedDigit()
            Text(caption)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .padding(.top, 25)
            .padding(.bottom, 10)
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundStyle(Theme.muted)
            .padding(.vertical, 18)
    }

    private func taskRow(_ task: PlanTask, complete: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button {
                    if complete { store.reopen(task.id) }
                    else { store.complete(task.id) }
                } label: {
                    Image(systemName: complete ? "checkmark.square.fill" : "square")
                        .font(.system(size: 21, weight: complete ? .regular : .ultraLight))
                        .foregroundStyle(complete ? Theme.green : Theme.muted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(complete ? "Reopen \(task.title)" : "Complete \(task.title)")
                Text(task.title)
                    .font(.system(size: 14))
                    .lineLimit(1)
                Spacer()
                Text(DurationLabel.short(task.estimatedMinutes))
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
            }
            .frame(height: 46)
            Hairline()
            if !complete {
                HStack {
                    Spacer()
                    Button {
                        store.move(task.id, to: store.tomorrow)
                    } label: {
                        Label("Tomorrow", systemImage: "calendar")
                    }
                    Button {
                        store.move(task.id, to: nil)
                    } label: {
                        Label("Backlog", systemImage: "square.stack")
                    }
                }
                .buttonStyle(.bordered)
                .font(.system(size: 12))
                .padding(.top, 10)
                .padding(.bottom, 16)
            }
        }
    }
}

