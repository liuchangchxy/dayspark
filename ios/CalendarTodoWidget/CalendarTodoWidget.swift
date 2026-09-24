import AppIntents
import SwiftUI
import WidgetKit

// MARK: - v2 snapshot contract (mirrors lib/infrastructure/platform/home_widget_service.dart buildSnapshot)

struct WidgetEvent: Decodable {
    let summary: String
    let start: String
    let isAllDay: Bool
}

struct WidgetTodo: Decodable {
    // Optional because snapshots written before the id addition (and the
    // dual-write window) may lack it; taps are disabled when nil.
    let id: Int?
    let summary: String
    let dueDate: String
}

struct WidgetUpcomingEvent: Decodable {
    let summary: String
    let date: String
    let start: String
    let isAllDay: Bool
}

struct WidgetUpcoming: Decodable {
    let events: [WidgetUpcomingEvent]
    let todos: [WidgetTodo]
}

struct WidgetPendingTap: Decodable {
    let todoId: Int
    let action: String
    let at: String
}

// [[dayNumber, hasEvent]] — heterogeneous pair, decoded positionally.
struct WidgetMonthDot: Decodable {
    let day: Int
    let hasEvent: Bool

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        day = try container.decode(Int.self)
        hasEvent = try container.decode(Bool.self)
    }
}

struct WidgetUi: Decodable {
    let locale: String
    let title: String
    let today: String
    let events: String
    let todos: String
    let allDay: String
    let todayEventsHeader: String
    let noEvents: String
    let allDone: String
    let pendingCount: String
    let quickAdd: String
    let upcoming: String
}

struct WidgetThemeColors: Decodable {
    let background: String
    let surface: String
    let textPrimary: String
    let textSecondary: String
    let accent: String
    let border: String
}

struct WidgetTheme: Decodable {
    let dark: Bool
    let colors: WidgetThemeColors
}

struct WidgetSnapshot: Decodable {
    let version: Int
    let generatedAt: String?
    let todayEvents: [WidgetEvent]?
    let pendingTodos: [WidgetTodo]?
    let todoCount: Int?
    let upcoming: WidgetUpcoming?
    let pendingTaps: [WidgetPendingTap]?
    let monthDots: [WidgetMonthDot]?
    let ui: WidgetUi?
    let theme: WidgetTheme?

    var pendingTapIds: Set<Int> {
        Set((pendingTaps ?? []).map(\.todoId))
    }
}

// Reader/writer for the shared App Group snapshot. The reader side is the
// retarget that kills the legacy isAllDay-type mismatch (P1): typed JSON
// decode instead of casting [[String: String]] / [[String: Any]] blobs.
enum WidgetSnapshotStore {
    static let appGroupId = "group.com.dayspark.app"
    static let snapshotKey = "widget_snapshot"

    static func load() -> WidgetSnapshot? {
        guard let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: snapshotKey),
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        // A corrupt blob degrades to the empty placeholder, never a crash.
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    // WHY append-not-write (single-writer rule): the native checkbox never
    // touches the database and never rewrites other snapshot fields — it
    // read-modify-writes ONLY the pendingTaps array. The app consumes the
    // queue on its next foreground flush and clears it. Same-todoId taps
    // are last-wins: a re-tap replaces the queued entry, because the app's
    // consume path toggles and a duplicate would reopen the todo. Known
    // race (accepted in docs/CONSTRAINTS.md): a flush in flight may
    // overwrite a tap landing inside its read→write window.
    static func appendPendingTap(todoId: Int) {
        guard let defaults = UserDefaults(suiteName: appGroupId),
              let raw = defaults.string(forKey: snapshotKey),
              let data = raw.data(using: .utf8),
              var object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else {
            return
        }
        var taps = (object["pendingTaps"] as? [[String: Any]]) ?? []
        taps.removeAll { ($0["todoId"] as? Int) == todoId }
        let formatter = ISO8601DateFormatter()
        taps.append([
            "todoId": todoId,
            "action": "complete",
            "at": formatter.string(from: Date()),
        ])
        object["pendingTaps"] = taps
        guard let updated = try? JSONSerialization.data(withJSONObject: object),
              let string = String(data: updated, encoding: .utf8)
        else {
            return
        }
        defaults.set(string, forKey: snapshotKey)
    }
}

// Checkbox tap: queue the append, then ask WidgetKit to rebuild — the next
// entry reads pendingTaps back and paints the row checked (optimistic
// round-trip through storage, no second state store to desync).
@available(iOS 17.0, macOS 14.0, *)
struct CompleteTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete todo"
    static var description =
        IntentDescription("Queues a widget checkbox tap into widget_snapshot.pendingTaps")

    @Parameter(title: "Todo ID")
    var todoId: Int

    init() {}

    init(todoId: Int) {
        self.todoId = todoId
    }

    func perform() async throws -> some IntentResult {
        WidgetSnapshotStore.appendPendingTap(todoId: todoId)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

// MARK: - Timeline provider (shared by all three variants)

struct CalendarTodoEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> CalendarTodoEntry {
        CalendarTodoEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (CalendarTodoEntry) -> Void) {
        completion(CalendarTodoEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CalendarTodoEntry>) -> Void) {
        // Data is app-driven (flush after every mutation reloads all kinds);
        // .atEnd matches the legacy provider so WidgetKit re-asks cheaply.
        let entry = CalendarTodoEntry(date: Date(), snapshot: WidgetSnapshotStore.load())
        completion(Timeline(entries: [entry], policy: .atEnd))
    }
}

// MARK: - Color + shared bits

extension Color {
    init(hex: String) {
        var value: UInt64 = 0
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        Scanner(string: cleaned).scanHexInt64(&value)
        switch cleaned.count {
        case 6:
            self.init(
                .sRGB,
                red: Double((value >> 16) & 0xFF) / 255.0,
                green: Double((value >> 8) & 0xFF) / 255.0,
                blue: Double(value & 0xFF) / 255.0
            )
        default:
            self.init(.sRGB, red: 0.5, green: 0.5, blue: 0.5)
        }
    }
}

private let quickAddURL = URL(string: "dayspark://quick-add")

// MARK: - Today variant

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: CalendarTodoEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var ui: WidgetUi? { snapshot?.ui }
    private var theme: WidgetTheme? { snapshot?.theme }

    private var background: Color {
        guard let hex = theme?.colors.background else { return .white }
        return Color(hex: hex)
    }

    private var textPrimary: Color {
        guard let hex = theme?.colors.textPrimary else { return .primary }
        return Color(hex: hex)
    }

    private var textSecondary: Color {
        guard let hex = theme?.colors.textSecondary else { return .secondary }
        return Color(hex: hex)
    }

    private var accent: Color {
        guard let hex = theme?.colors.accent else { return .blue }
        return Color(hex: hex)
    }

    private var isExpanded: Bool {
        if case .systemMedium = family { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let snapshot, let ui {
                HStack {
                    Text(ui.todayEventsHeader)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(accent)
                    Spacer()
                    Text(entry.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(textSecondary)
                }

                let events = snapshot.todayEvents ?? []
                if events.isEmpty {
                    Text(ui.noEvents)
                        .font(.caption2)
                        .foregroundStyle(textSecondary)
                } else {
                    ForEach(events.prefix(isExpanded ? 3 : 2).indices, id: \.self) { i in
                        HStack(spacing: 6) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(accent)
                                .frame(width: 3, height: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(events[i].summary)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .foregroundStyle(textPrimary)
                                Text(events[i].isAllDay ? ui.allDay : events[i].start)
                                    .font(.caption2)
                                    .foregroundStyle(textSecondary)
                            }
                        }
                    }
                }

                Divider()

                HStack {
                    Text(ui.todos)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(accent)
                    Spacer()
                    Text(ui.pendingCount)
                        .font(.caption2)
                        .foregroundStyle(textSecondary)
                }

                let todos = snapshot.pendingTodos ?? []
                let checked = snapshot.pendingTapIds
                if todos.isEmpty {
                    Text(ui.allDone)
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    ForEach(todos.prefix(isExpanded ? 3 : 2).indices, id: \.self) { i in
                        todoRow(todos[i], checked: checked)
                    }
                }

                Spacer(minLength: 0)
                Link(destination: quickAddURL ?? URL(string: "dayspark://")!) {
                    HStack {
                        Spacer()
                        Text(ui.quickAdd)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    .padding(.vertical, 4)
                    .background(accent.opacity(0.12))
                    .foregroundStyle(accent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
            } else {
                // Snapshot missing (app never flushed / corrupt): quiet
                // placeholder, no hardcoded copy.
                Spacer()
                Image(systemName: "calendar")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
        .background(background)
        .widgetURL(quickAddURL)
    }

    @ViewBuilder
    private func todoRow(_ todo: WidgetTodo, checked: Set<Int>) -> some View {
        let isChecked = todo.id.map { checked.contains($0) } ?? false
        HStack(spacing: 6) {
            if let todoId = todo.id {
                Button(intent: CompleteTodoIntent(todoId: todoId)) {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(isChecked ? accent : textSecondary)
                        .font(.footnote)
                }
                .buttonStyle(.plain)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(textSecondary)
                    .font(.footnote)
            }
            Text(todo.summary)
                .font(.caption)
                .lineLimit(1)
                .strikethrough(isChecked)
                .foregroundStyle(isChecked ? textSecondary : textPrimary)
            Spacer()
            if !todo.dueDate.isEmpty {
                Text(todo.dueDate)
                    .font(.caption2)
                    .foregroundStyle(textSecondary)
            }
        }
    }
}

// MARK: - Upcoming variant (7-day bucket)

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: CalendarTodoEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var ui: WidgetUi? { snapshot?.ui }
    private var theme: WidgetTheme? { snapshot?.theme }

    private var background: Color {
        guard let hex = theme?.colors.background else { return .white }
        return Color(hex: hex)
    }

    private var textPrimary: Color {
        guard let hex = theme?.colors.textPrimary else { return .primary }
        return Color(hex: hex)
    }

    private var textSecondary: Color {
        guard let hex = theme?.colors.textSecondary else { return .secondary }
        return Color(hex: hex)
    }

    private var accent: Color {
        guard let hex = theme?.colors.accent else { return .blue }
        return Color(hex: hex)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if let snapshot, let ui {
                HStack {
                    Text(ui.upcoming)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundStyle(accent)
                    Spacer()
                    Text(entry.date, style: .date)
                        .font(.caption2)
                        .foregroundStyle(textSecondary)
                }

                let events = snapshot.upcoming?.events ?? []
                let todos = snapshot.upcoming?.todos ?? []
                let limit = family == .systemMedium ? 5 : 3

                if events.isEmpty && todos.isEmpty {
                    Text(ui.noEvents)
                        .font(.caption2)
                        .foregroundStyle(textSecondary)
                } else {
                    ForEach(events.prefix(limit).indices, id: \.self) { i in
                        row(
                            title: events[i].summary,
                            secondary: events[i].isAllDay ? events[i].date : "\(events[i].date) \(events[i].start)",
                            marked: true
                        )
                    }
                    let remaining = max(limit - min(events.count, limit), 0)
                    ForEach(todos.prefix(remaining).indices, id: \.self) { i in
                        row(
                            title: todos[i].summary,
                            secondary: todos[i].dueDate,
                            marked: false
                        )
                    }
                }
            } else {
                Spacer()
                Image(systemName: "calendar.badge.clock")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Spacer()
            }
        }
        .padding(8)
        .background(background)
        .widgetURL(quickAddURL)
    }

    @ViewBuilder
    private func row(title: String, secondary: String, marked: Bool) -> some View {
        HStack(spacing: 6) {
            if marked {
                RoundedRectangle(cornerRadius: 2)
                    .fill(accent)
                    .frame(width: 3, height: 14)
            } else {
                Circle()
                    .stroke(accent, lineWidth: 1.5)
                    .frame(width: 8, height: 8)
            }
            Text(title)
                .font(.caption)
                .lineLimit(1)
                .foregroundStyle(textPrimary)
            Spacer()
            Text(secondary)
                .font(.caption2)
                .foregroundStyle(textSecondary)
        }
    }
}

// MARK: - Month-dots variant

struct MonthDotsWidgetView: View {
    var entry: CalendarTodoEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var theme: WidgetTheme? { snapshot?.theme }

    private var background: Color {
        guard let hex = theme?.colors.background else { return .white }
        return Color(hex: hex)
    }

    private var accent: Color {
        guard let hex = theme?.colors.accent else { return .blue }
        return Color(hex: hex)
    }

    private var dotIdle: Color {
        guard let hex = theme?.colors.border else { return .gray.opacity(0.4) }
        return Color(hex: hex).opacity(0.55)
    }

    private var todayColor: Color {
        guard let hex = theme?.colors.textPrimary else { return .primary }
        return Color(hex: hex)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter.string(from: entry.date)
    }

    private var daysInMonth: Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: entry.date)
        guard let startOfMonth = cal.date(from: comps),
              let range = cal.range(of: .day, in: .month, for: startOfMonth)
        else {
            return 30
        }
        return range.count
    }

    private var leadingBlanks: Int {
        let cal = Calendar.current
        let comps = cal.dateComponents([.year, .month], from: entry.date)
        guard let startOfMonth = cal.date(from: comps) else { return 0 }
        let weekday = cal.component(.weekday, from: startOfMonth)  // Sunday=1
        return (weekday + 5) % 7  // Monday-first offset
    }

    private var eventDays: Set<Int> {
        Set((snapshot?.monthDots ?? []).filter(\.hasEvent).map(\.day))
    }

    private var todayDay: Int {
        Calendar.current.component(.day, from: entry.date)
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 6) {
            Text(monthTitle)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundStyle(accent)

            let total = daysInMonth + leadingBlanks
            LazyVGrid(columns: columns, spacing: 5) {
                ForEach(0..<total, id: \.self) { index in
                    let day = index - leadingBlanks + 1
                    if day >= 1 && day <= daysInMonth {
                        dot(for: day)
                    } else {
                        Color.clear
                            .frame(width: 10, height: 10)
                    }
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(background)
        .widgetURL(quickAddURL)
    }

    @ViewBuilder
    private func dot(for day: Int) -> some View {
        let isToday = day == todayDay
        let hasEvent = eventDays.contains(day)
        Circle()
            .fill(hasEvent ? accent : (isToday ? todayColor : dotIdle))
            .frame(width: 9, height: 9)
            .overlay {
                if isToday {
                    Circle()
                        .stroke(accent, lineWidth: 1.5)
                        .frame(width: 13, height: 13)
                }
            }
    }
}

// MARK: - Widgets

struct CalendarTodoWidget: Widget {
    let kind = "CalendarTodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        // Display metadata can't wait for a snapshot (WidgetKit shows it in
        // the gallery before any data exists); runtime copy all comes from
        // the pre-localized ui block.
        .configurationDisplayName("Calendar & Todo")
        .description("View today's events and pending to-dos.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CalendarUpcomingWidget: Widget {
    let kind = "CalendarUpcomingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName("Upcoming")
        .description("Events and to-dos for the next 7 days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct CalendarMonthWidget: Widget {
    let kind = "CalendarMonthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            MonthDotsWidgetView(entry: entry)
        }
        .configurationDisplayName("Month Dots")
        .description("Days with events in the current month.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CalendarTodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarTodoWidget()
        CalendarUpcomingWidget()
        CalendarMonthWidget()
    }
}
