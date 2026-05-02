import WidgetKit
import SwiftUI

struct CalendarTodoEntry: TimelineEntry {
    let date: Date
    let events: [[String: String]]
    let todos: [[String: String]]
    let todoCount: Int
}

struct CalendarTodoProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarTodoEntry {
        CalendarTodoEntry(date: Date(), events: [], todos: [], todoCount: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarTodoEntry) -> Void) {
        let entry = loadEntry()
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarTodoEntry>) -> Void) {
        let entry = loadEntry()
        let timeline = Timeline(entries: [entry], policy: .atEnd)
        completion(timeline)
    }

    private func loadEntry() -> CalendarTodoEntry {
        let defaults = UserDefaults(suiteName: "group.com.calendarTodoApp")
        let eventsJson = defaults?.string(forKey: "today_events") ?? "[]"
        let todosJson = defaults?.string(forKey: "pending_todos") ?? "[]"
        let todoCount = Int(defaults?.string(forKey: "todo_count") ?? "0") ?? 0

        var events: [[String: String]] = []
        if let data = eventsJson.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            events = list
        }

        var todos: [[String: String]] = []
        if let data = todosJson.data(using: .utf8),
           let list = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            todos = list
        }

        return CalendarTodoEntry(date: Date(), events: events, todos: todos, todoCount: todoCount)
    }
}

struct CalendarTodoWidgetEntryView: View {
    var entry: CalendarTodoEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.date, style: .date)
                .font(.caption)
                .foregroundColor(.secondary)

            if entry.events.isEmpty {
                Text("No events today")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                ForEach(entry.events.prefix(3).indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.blue)
                            .frame(width: 3, height: 20)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(entry.events[i]["summary"] ?? "")
                                .font(.caption)
                                .lineLimit(1)
                            Text(entry.events[i]["isAllDay"] == "true" ? "All Day" : (entry.events[i]["start"] ?? ""))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }

            Divider()

            HStack {
                Text("To-Do")
                    .font(.caption)
                    .bold()
                Text("(\(entry.todoCount))")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if entry.todos.isEmpty {
                Text("All done!")
                    .font(.caption)
                    .foregroundColor(.green)
            } else {
                ForEach(entry.todos.prefix(3).indices, id: \.self) { i in
                    HStack(spacing: 6) {
                        Circle()
                            .stroke(Color.orange, lineWidth: 1.5)
                            .frame(width: 12, height: 12)
                        Text(entry.todos[i]["summary"] ?? "")
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        if let due = entry.todos[i]["dueDate"], !due.isEmpty {
                            Text(due)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
        .padding()
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

@main
struct CalendarTodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarTodoWidget()
    }
}
