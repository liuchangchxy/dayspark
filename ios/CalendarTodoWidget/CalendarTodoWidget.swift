import WidgetKit
import SwiftUI

struct CalendarTodoEntry: TimelineEntry {
    let date: Date
    let events: [[String: Any]]
    let todos: [[String: Any]]
    let todoCount: String
}

struct CalendarTodoProvider: TimelineProvider {
    let appGroupId = "group.com.calendarTodoApp"

    func placeholder(in context: Context) -> CalendarTodoEntry {
        CalendarTodoEntry(date: Date(), events: [], todos: [], todoCount: "0")
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarTodoEntry) -> Void) {
        let entry = loadEntry(date: Date())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarTodoEntry>) -> Void) {
        let entry = loadEntry(date: Date())
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }

    private func loadEntry(date: Date) -> CalendarTodoEntry {
        let defaults = UserDefaults(suiteName: appGroupId)
        var events: [[String: Any]] = []
        var todos: [[String: Any]] = []
        var todoCount = "0"

        if let eventsData = defaults?.string(forKey: "today_events"),
           let data = eventsData.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            events = decoded
        }

        if let todosData = defaults?.string(forKey: "pending_todos"),
           let data = todosData.data(using: .utf8),
           let decoded = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            todos = decoded
        }

        if let count = defaults?.string(forKey: "todo_count") {
            todoCount = count
        }

        return CalendarTodoEntry(date: date, events: events, todos: todos, todoCount: todoCount)
    }
}

struct CalendarTodoWidgetEntryView: View {
    var entry: CalendarTodoProvider.Entry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack {
                Image(systemName: "calendar")
                    .font(.caption)
                    .foregroundColor(.blue)
                Text("Today's Events")
                    .font(.caption)
                    .fontWeight(.semibold)
                Spacer()
                Text(entry.date, style: .date)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            // Events section
            if entry.events.isEmpty {
                Text("No events today")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                ForEach(0..<entry.events.count, id: \.self) { i in
                    let event = entry.events[i]
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: 3, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(event["summary"] as? String ?? "")
                                .font(.caption2)
                                .lineLimit(1)
                            if let isAllDay = event["isAllDay"] as? Bool, !isAllDay,
                               let start = event["start"] as? String {
                                Text(start)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            } else {
                                Text("All Day")
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }

            Divider()

            // Todos section
            HStack {
                Image(systemName: "checklist")
                    .font(.caption)
                    .foregroundColor(.orange)
                Text("To-Do (\(entry.todoCount))")
                    .font(.caption)
                    .fontWeight(.semibold)
            }

            if entry.todos.isEmpty {
                Text("All done!")
                    .font(.caption2)
                    .foregroundColor(.green)
            } else {
                ForEach(0..<entry.todos.count, id: \.self) { i in
                    let todo = entry.todos[i]
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.system(size: 10))
                            .foregroundColor(.orange)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(todo["summary"] as? String ?? "")
                                .font(.caption2)
                                .lineLimit(1)
                            if let due = todo["dueDate"] as? String {
                                Text(due)
                                    .font(.system(size: 9))
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding()
    }
}

@main
struct CalendarTodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarTodoWidget()
    }
}

struct CalendarTodoWidget: Widget {
    let kind: String = "CalendarTodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: CalendarTodoProvider()) { entry in
            CalendarTodoWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("Calendar & Todo")
        .description("View today's events and pending to-dos.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
