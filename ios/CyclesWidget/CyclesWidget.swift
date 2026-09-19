import WidgetKit
import SwiftUI

private let appGroupId = "group.com.example.cycles"

struct WidgetTaskItem: Identifiable, Codable {
    let id: String
    let title: String
    let status: String
    let priority: Int
    let dueMillis: Int64?
}

struct TaskEntry: TimelineEntry {
    let date: Date
    let tasks: [WidgetTaskItem]
    let openCount: Int
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> TaskEntry {
        TaskEntry(
            date: Date(),
            tasks: [
                WidgetTaskItem(id: "1", title: "Review pull requests", status: "open", priority: 2, dueMillis: nil),
                WidgetTaskItem(id: "2", title: "Prepare release notes", status: "open", priority: 1, dueMillis: nil)
            ],
            openCount: 2
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (TaskEntry) -> Void) {
        completion(loadEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<TaskEntry>) -> Void) {
        let entry = loadEntry()
        // Refresh every 30 minutes or when reloaded by app
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date()
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func loadEntry() -> TaskEntry {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let jsonStr = defaults.string(forKey: "widget_tasks_json"),
              let data = jsonStr.data(using: .utf8) else {
            return TaskEntry(date: Date(), tasks: [], openCount: 0)
        }

        let tasks = (try? JSONDecoder().decode([WidgetTaskItem].self, from: data)) ?? []
        let count = defaults.integer(forKey: "widget_open_count")
        return TaskEntry(date: Date(), tasks: tasks, openCount: max(count, tasks.sizeFallback))
    }
}

private extension Array {
    var sizeFallback: Int { return count }
}

struct CyclesWidgetEntryView: View {
    var entry: Provider.Entry
    @Environment(\.widgetFamily) var family

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Label("CYCLES", systemImage: "arrow.triangle.2.circlepath")
                    .font(.caption2.bold())
                    .foregroundStyle(.secondary)

                Spacer()

                Text("\(entry.openCount) OPEN")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .foregroundStyle(Color.accentColor)
                    .clipShape(Capsule())
            }

            Divider()

            // Task content
            if entry.tasks.isEmpty {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.green)
                    Text("All caught up!")
                        .font(.subheadline.bold())
                    Text("No pending tasks")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                Spacer()
            } else {
                let maxItems = family == .systemSmall ? 2 : 4
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(entry.tasks.prefix(maxItems)) { task in
                        HStack(spacing: 6) {
                            Image(systemName: "circle")
                                .font(.system(size: 8))
                                .foregroundStyle(priorityColor(task.priority))

                            Text(task.title)
                                .font(.caption)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                    }
                }
                Spacer()
            }

            HStack {
                Spacer()
                Text("Tap to open")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .widgetURL(URL(string: "cycles://home"))
    }

    private func priorityColor(_ priority: Int) -> Color {
        switch priority {
        case 3: return .red
        case 2: return .orange
        case 1: return .blue
        default: return .secondary
        }
    }
}

@main
struct CyclesWidget: Widget {
    let kind: String = "CyclesWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: Provider()) { entry in
            CyclesWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Cycles Tasks")
        .description("View your active peer-to-peer tasks at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
