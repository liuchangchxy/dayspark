import AppIntents
import SwiftUI
import WidgetKit

// MARK: - v3 snapshot contract (mirrors lib/infrastructure/platform/home_widget_service.dart buildSnapshot)

struct WidgetTimelineItem: Decodable {
    let kind: String
    let summary: String
    let start: String
    var end: String? = nil
    var isAllDay: Bool? = nil
    var allocationId: String? = nil
    var todoId: Int? = nil
    var todoSyncId: String? = nil
    var occurrenceId: String? = nil
}

struct WidgetActionItem: Decodable {
    let kind: String
    let target: String
    let todoId: Int
    let todoSyncId: String?
    let occurrenceId: String?
    let summary: String
    let deadline: String?
    let displayTime: String?
}

struct WidgetStatus: Decodable {
    let overdueCount: Int?
    let missedCount: Int?
    let unplannedCount: Int?
}

struct WidgetToday: Decodable {
    let timeline: [WidgetTimelineItem]?
    let actions: [WidgetActionItem]?
    let status: WidgetStatus?
}

struct WidgetUpcomingItem: Decodable {
    let kind: String
    let summary: String
    let date: String
    let time: String
    let isAllDay: Bool
}

struct WidgetEvent: Decodable {
    let summary: String
    let start: String
    let isAllDay: Bool
}

struct WidgetTodo: Decodable {
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
    let items: [WidgetUpcomingItem]?
    let events: [WidgetUpcomingEvent]?
    let todos: [WidgetTodo]?
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
    var overdue: String? = nil
    var missed: String? = nil
    var unplanned: String? = nil
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
    let today: WidgetToday?
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

// Reader/writer for the shared App Group snapshot and command queue.
enum WidgetSnapshotStore {
    static let appGroupId = "group.com.dayspark.app"
    static let snapshotKey = "widget_snapshot"

    static func load() -> WidgetSnapshot? {
        guard let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: snapshotKey),
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    struct PendingCommandTargets {
        let todoIds: Set<Int>
        let instanceKeys: Set<String>
    }

    static func pendingCommandTargets() -> PendingCommandTargets {
        guard let defaults = UserDefaults(suiteName: appGroupId) else {
            return PendingCommandTargets(todoIds: [], instanceKeys: [])
        }
        var todoIds = Set<Int>()
        var instanceKeys = Set<String>()
        for (key, val) in defaults.dictionaryRepresentation() {
            if key.hasPrefix("widget_command_"),
               let str = val as? String,
               let data = str.data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let target = obj["target"] as? String,
               let todoId = obj["todoId"] as? Int {
                if target == "taskInstance" {
                    let occ = (obj["occurrenceId"] as? String) ?? ""
                    if !occ.isEmpty {
                        instanceKeys.insert("\(todoId):\(occ)")
                    }
                } else if target == "todo" {
                    todoIds.insert(todoId)
                }
            }
        }
        return PendingCommandTargets(todoIds: todoIds, instanceKeys: instanceKeys)
    }

    // Atomic single-writer command append: appends widget_command_<commandId> to UserDefaults.
    // Does NOT mutate widget_snapshot (Ruling E).
    static func appendCommand(
        target: String,
        todoId: Int,
        todoSyncId: String?,
        occurrenceId: String?,
        sourceAllocationId: String? = nil
    ) {
        guard let defaults = UserDefaults(suiteName: appGroupId) else { return }
        let commandId = UUID().uuidString
        let formatter = ISO8601DateFormatter()
        var dict: [String: Any] = [
            "version": 1,
            "commandId": commandId,
            "action": "complete",
            "target": target,
            "todoId": todoId,
            "at": formatter.string(from: Date()),
        ]
        if let todoSyncId = todoSyncId, !todoSyncId.isEmpty {
            dict["todoSyncId"] = todoSyncId
        }
        if let occurrenceId = occurrenceId, !occurrenceId.isEmpty {
            dict["occurrenceId"] = occurrenceId
        }
        if let sourceAllocationId = sourceAllocationId, !sourceAllocationId.isEmpty {
            dict["sourceAllocationId"] = sourceAllocationId
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let jsonString = String(data: data, encoding: .utf8) {
            defaults.set(jsonString, forKey: "widget_command_\(commandId)")
        }
    }

    // Legacy fallback append for pre-v3 snapshots
    static func appendPendingTap(todoId: Int) {
        appendCommand(target: "todo", todoId: todoId, todoSyncId: nil, occurrenceId: nil)
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CompleteActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete action"
    static var description =
        IntentDescription("Queues a widget action into command queue")

    @Parameter(title: "Target")
    var target: String

    @Parameter(title: "Todo ID")
    var todoId: Int

    @Parameter(title: "Todo Sync ID")
    var todoSyncId: String

    @Parameter(title: "Occurrence ID")
    var occurrenceId: String

    @Parameter(title: "Source Allocation ID")
    var sourceAllocationId: String

    init() {
        self.target = "todo"
        self.todoId = 0
        self.todoSyncId = ""
        self.occurrenceId = ""
        self.sourceAllocationId = ""
    }

    init(
        target: String,
        todoId: Int,
        todoSyncId: String = "",
        occurrenceId: String = "",
        sourceAllocationId: String = ""
    ) {
        self.target = target
        self.todoId = todoId
        self.todoSyncId = todoSyncId
        self.occurrenceId = occurrenceId
        self.sourceAllocationId = sourceAllocationId
    }

    func perform() async throws -> some IntentResult {
        WidgetSnapshotStore.appendCommand(
            target: target,
            todoId: todoId,
            todoSyncId: todoSyncId.isEmpty ? nil : todoSyncId,
            occurrenceId: occurrenceId.isEmpty ? nil : occurrenceId,
            sourceAllocationId: sourceAllocationId.isEmpty ? nil : sourceAllocationId
        )
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CompleteTodoIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete todo"
    static var description =
        IntentDescription("Queues a widget checkbox tap into widget_snapshot.pendingTaps")

    @Parameter(title: "Todo ID")
    var todoId: Int

    init() {
        self.todoId = 0
    }

    init(todoId: Int) {
        self.todoId = todoId
    }

    func perform() async throws -> some IntentResult {
        WidgetSnapshotStore.appendCommand(target: "todo", todoId: todoId, todoSyncId: nil, occurrenceId: nil)
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

                let pendingTargets = WidgetSnapshotStore.pendingCommandTargets()

                // Status compact indicator row (Overdue N, Missed N, Inbox N)
                let status = snapshot.today?.status
                let overdueCount = status?.overdueCount ?? 0
                let missedCount = status?.missedCount ?? 0
                let unplannedCount = status?.unplannedCount ?? 0
                if overdueCount > 0 || missedCount > 0 || unplannedCount > 0 {
                    HStack(spacing: 8) {
                        if overdueCount > 0 {
                            let label = ui.overdue ?? "Overdue"
                            Text("\(label) \(overdueCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.red)
                        }
                        if missedCount > 0 {
                            let label = ui.missed ?? "Missed"
                            Text("\(label) \(missedCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.orange)
                        }
                        if unplannedCount > 0 {
                            let label = ui.unplanned ?? "Inbox"
                            Text("\(label) \(unplannedCount)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(textSecondary)
                        }
                        Spacer()
                    }
                    .padding(.bottom, 2)
                }

                let timeline = snapshot.today?.timeline ?? (snapshot.todayEvents ?? []).map {
                    WidgetTimelineItem(
                        kind: "eventOccurrence",
                        summary: $0.summary,
                        start: $0.start,
                        end: nil,
                        isAllDay: $0.isAllDay
                    )
                }

                if timeline.isEmpty {
                    Text(ui.noEvents)
                        .font(.caption2)
                        .foregroundStyle(textSecondary)
                } else {
                    ForEach(timeline.prefix(isExpanded ? 3 : 2).indices, id: \.self) { i in
                        let item = timeline[i]
                        let isTaskAllocation = item.kind == "taskAllocation" && (item.todoId ?? -1) > 0
                        let isChecked: Bool = {
                            guard isTaskAllocation, let todoId = item.todoId else { return false }
                            if let occ = item.occurrenceId, !occ.isEmpty {
                                return pendingTargets.instanceKeys.contains("\(todoId):\(occ)")
                            } else {
                                return pendingTargets.todoIds.contains(todoId)
                            }
                        }()

                        HStack(spacing: 6) {
                            if isTaskAllocation, let todoId = item.todoId {
                                let target = (item.occurrenceId != nil && !item.occurrenceId!.isEmpty) ? "taskInstance" : "todo"
                                Button(intent: CompleteActionIntent(
                                    target: target,
                                    todoId: todoId,
                                    todoSyncId: item.todoSyncId ?? "",
                                    occurrenceId: item.occurrenceId ?? "",
                                    sourceAllocationId: item.allocationId ?? ""
                                )) {
                                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isChecked ? accent : textSecondary)
                                        .font(.footnote)
                                }
                                .buttonStyle(.plain)
                            } else {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(accent)
                                    .frame(width: 3, height: 16)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.summary)
                                    .font(.caption)
                                    .lineLimit(1)
                                    .strikethrough(isChecked)
                                    .foregroundStyle(isChecked ? textSecondary : textPrimary)
                                let timeStr: String = {
                                    if item.isAllDay == true { return ui.allDay }
                                    if let end = item.end, !end.isEmpty { return "\(item.start) - \(end)" }
                                    return item.start
                                }()
                                Text(timeStr)
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

                let actions: [WidgetActionItem] = snapshot.today?.actions ?? (snapshot.pendingTodos ?? []).map {
                    WidgetActionItem(
                        kind: "todoDeadline",
                        target: "todo",
                        todoId: $0.id ?? -1,
                        todoSyncId: nil,
                        occurrenceId: nil,
                        summary: $0.summary,
                        deadline: $0.dueDate,
                        displayTime: nil
                    )
                }

                if actions.isEmpty {
                    Text(ui.allDone)
                        .font(.caption2)
                        .foregroundStyle(.green)
                } else {
                    ForEach(actions.prefix(isExpanded ? 3 : 2).indices, id: \.self) { i in
                        actionRow(actions[i], pendingTargets: pendingTargets, legacyChecked: snapshot.pendingTapIds)
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
    private func actionRow(
        _ action: WidgetActionItem,
        pendingTargets: WidgetSnapshotStore.PendingCommandTargets,
        legacyChecked: Set<Int>
    ) -> some View {
        let isChecked: Bool = {
            if action.target == "taskInstance" {
                let occ = action.occurrenceId ?? ""
                return pendingTargets.instanceKeys.contains("\(action.todoId):\(occ)")
            } else {
                return pendingTargets.todoIds.contains(action.todoId) || legacyChecked.contains(action.todoId)
            }
        }()

        HStack(spacing: 6) {
            if action.todoId > 0 {
                Button(intent: CompleteActionIntent(
                    target: action.target,
                    todoId: action.todoId,
                    todoSyncId: action.todoSyncId ?? "",
                    occurrenceId: action.occurrenceId ?? ""
                )) {
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
            Text(action.summary)
                .font(.caption)
                .lineLimit(1)
                .strikethrough(isChecked)
                .foregroundStyle(isChecked ? textSecondary : textPrimary)
            Spacer()
            let secondaryText = action.deadline ?? action.displayTime ?? ""
            if !secondaryText.isEmpty {
                Text(secondaryText)
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

                let limit = family == .systemMedium ? 5 : 3

                if let items = snapshot.upcoming?.items {
                    if items.isEmpty {
                        Text(ui.noEvents)
                            .font(.caption2)
                            .foregroundStyle(textSecondary)
                    } else {
                        ForEach(items.prefix(limit).indices, id: \.self) { i in
                            let it = items[i]
                            let secondary = it.isAllDay ? it.date : (it.time.isEmpty ? it.date : "\(it.date) \(it.time)")
                            row(title: it.summary, secondary: secondary, marked: it.kind == "eventOccurrence")
                        }
                    }
                } else {
                    let events = snapshot.upcoming?.events ?? []
                    let todos = snapshot.upcoming?.todos ?? []

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
