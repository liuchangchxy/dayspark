import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Snapshot v4 contract
// Mirrors lib/infrastructure/platform/home_widget_service.dart. Every field
// the host may omit is optional so a v3 blob still decodes.

struct WidgetTimelineItem: Decodable {
    let kind: String
    let summary: String
    let start: String
    let end: String?
    let isAllDay: Bool?
    let eventId: Int?
    let calendarId: Int?
    let color: String?
    let allocationId: String?
    let todoId: Int?
    let todoSyncId: String?
    let occurrenceId: String?
}

struct WidgetActionItem: Decodable {
    let kind: String?
    let target: String?
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
    let date: String?
    let timeline: [WidgetTimelineItem]?
    let actions: [WidgetActionItem]?
    let status: WidgetStatus?
}

struct WidgetUpcomingItem: Decodable {
    let kind: String?
    let summary: String
    let date: String?
    let time: String?
    let isAllDay: Bool?
    let eventId: Int?
    let todoId: Int?
    let allocationId: String?
    let occurrenceId: String?
    let todoSyncId: String?
    let color: String?
}

struct WidgetUpcomingDay: Decodable {
    let date: String
    let items: [WidgetUpcomingItem]
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
    let days: [WidgetUpcomingDay]?
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

struct WidgetMonthDay: Decodable {
    let day: Int
    let hasEvent: Bool?
    let hasTodo: Bool?
    let hasAllocation: Bool?
    let colors: [String]?
}

struct WidgetMonth: Decodable {
    let year: Int?
    let month: Int?
    let firstWeekday: Int?
    let today: Int?
    let days: [WidgetMonthDay]?
}

struct WidgetUi: Decodable {
    let locale: String?
    let title: String?
    let today: String?
    let tomorrow: String?
    let events: String?
    let todos: String?
    let allDay: String?
    let todayEventsHeader: String?
    let noEvents: String?
    let allDone: String?
    let pendingCount: String?
    let quickAdd: String?
    let upcoming: String?
    let openApp: String?
    let noPlans: String?
    let noUpcoming: String?
    let quickActions: String?
    let newTodo: String?
    let newEvent: String?
    let overdue: String?
    let missed: String?
    let unplanned: String?
}

struct WidgetThemeColors: Decodable {
    let background: String?
    let surface: String?
    let textPrimary: String?
    let textSecondary: String?
    let accent: String?
    let border: String?
}

struct WidgetTheme: Decodable {
    let dark: Bool?
    let colors: WidgetThemeColors?
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
    let month: WidgetMonth?
    let ui: WidgetUi?
    let theme: WidgetTheme?

    var todayIso: String {
        if let date = today?.date, !date.isEmpty { return date }
        return WidgetDates.iso(Date())
    }

    var timeline: [WidgetTimelineItem] {
        if let rows = today?.timeline, !rows.isEmpty { return rows }
        return (todayEvents ?? []).map { event in
            WidgetTimelineItem(
                kind: "eventOccurrence",
                summary: event.summary,
                start: event.start,
                end: nil,
                isAllDay: event.isAllDay,
                eventId: nil,
                calendarId: nil,
                color: nil,
                allocationId: nil,
                todoId: nil,
                todoSyncId: nil,
                occurrenceId: nil
            )
        }
    }

    var actions: [WidgetActionItem] {
        if let rows = today?.actions, !rows.isEmpty { return rows }
        return (pendingTodos ?? []).map { todo in
            WidgetActionItem(
                kind: "todoDeadline",
                target: "todo",
                todoId: todo.id ?? -1,
                todoSyncId: nil,
                occurrenceId: nil,
                summary: todo.summary,
                deadline: todo.dueDate,
                displayTime: nil
            )
        }
    }
}

// MARK: - Shared store

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

    // Atomic single-writer command append; never mutates the snapshot blob.
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
        if let todoSyncId, !todoSyncId.isEmpty { dict["todoSyncId"] = todoSyncId }
        if let occurrenceId, !occurrenceId.isEmpty { dict["occurrenceId"] = occurrenceId }
        if let sourceAllocationId, !sourceAllocationId.isEmpty {
            dict["sourceAllocationId"] = sourceAllocationId
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict),
           let jsonString = String(data: data, encoding: .utf8) {
            defaults.set(jsonString, forKey: "widget_command_\(commandId)")
        }
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CompleteActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete action"
    static var description = IntentDescription("Queues a widget completion command")

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
        target = "todo"
        todoId = 0
        todoSyncId = ""
        occurrenceId = ""
        sourceAllocationId = ""
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

// MARK: - Dates + links + copy

enum WidgetDates {
    static func iso(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func parse(_ iso: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: iso)
    }

    static func tomorrowIso() -> String {
        let calendar = Calendar.current
        let date = calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        return iso(date)
    }

    static func short(_ iso: String) -> String {
        guard let date = parse(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    static func monthTitle(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        let calendar = Calendar.current
        guard let date = calendar.date(from: components) else { return "\(year)-\(month)" }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMMyyyy")
        return formatter.string(from: date)
    }

    static func weekdaySymbolsMondayFirst() -> [String] {
        let symbols = DateFormatter().shortWeekdaySymbols ?? []
        guard symbols.count == 7 else { return [] }
        let order = [1, 2, 3, 4, 5, 6, 0]
        return order.map { symbols[$0] }
    }
}

enum WidgetLinks {
    static let today = URL(string: "dayspark://open/today")!
    static let calendar = URL(string: "dayspark://open/calendar")!
    static let quickAdd = URL(string: "dayspark://quick-add")!

    static func todo(_ id: Int) -> URL {
        URL(string: "dayspark://open/todo?id=\(id)")!
    }

    static func event(_ id: Int) -> URL {
        URL(string: "dayspark://open/event?id=\(id)")!
    }

    static func calendar(_ dateIso: String) -> URL {
        URL(string: "dayspark://open/calendar?date=\(dateIso)")!
    }

    static func newEvent(_ dateIso: String) -> URL {
        URL(string: "dayspark://open/new-event?date=\(dateIso)")!
    }

    static func detail(eventId: Int?, todoId: Int?) -> URL? {
        if let eventId, eventId > 0 { return event(eventId) }
        if let todoId, todoId > 0 { return todo(todoId) }
        return nil
    }
}

enum WidgetCopy {
    private static var chinese: Bool {
        Locale.preferredLanguages.first?.hasPrefix("zh") == true
    }

    static func galleryName(_ kind: String) -> String {
        switch kind {
        case "CalendarTodoWidget": return chinese ? "今日行动" : "Today"
        case "CalendarUpcomingWidget": return chinese ? "近期安排" : "Upcoming"
        case "CalendarMonthWidget": return chinese ? "月历" : "Calendar"
        case "CalendarQuickActionsWidget": return chinese ? "快速操作" : "Quick actions"
        default: return "DaySpark"
        }
    }

    static func galleryDescription(_ kind: String) -> String {
        switch kind {
        case "CalendarTodoWidget":
            return chinese ? "查看并完成今天的日程与待办" : "View and complete today's schedule and tasks."
        case "CalendarUpcomingWidget":
            return chinese ? "查看未来几天的日程与任务" : "See the next few days' schedule and tasks."
        case "CalendarMonthWidget":
            return chinese ? "查看本月日程分布" : "See this month's schedule at a glance."
        case "CalendarQuickActionsWidget":
            return chinese ? "快速创建待办和日程" : "Create a task or event, or open Today and Calendar."
        default:
            return ""
        }
    }

    static let openApp = chinese ? "打开 DaySpark 以显示你的安排" : "Open DaySpark to show your schedule"
    static let noPlans = chinese ? "今天没有安排" : "No plans for today"
    static let noUpcoming = chinese ? "未来几天没有安排" : "Nothing scheduled for the next few days"
    static let newTodo = chinese ? "+ 待办" : "+ Task"
    static let newEvent = chinese ? "+ 日程" : "+ Event"
    static let today = chinese ? "今天" : "Today"
    static let calendar = chinese ? "日历" : "Calendar"
}

// MARK: - Theme

struct WidgetPalette {
    let background: Color
    let surface: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let border: Color

    init(_ snapshot: WidgetSnapshot?) {
        let colors = snapshot?.theme?.colors
        #if os(iOS)
        let fallbackBackground = Color(.systemBackground)
        let fallbackSurface = Color(.secondarySystemBackground)
        #else
        let fallbackBackground = Color(nsColor: .windowBackgroundColor)
        let fallbackSurface = Color(nsColor: .controlBackgroundColor)
        #endif
        background = Color(hex: colors?.background) ?? fallbackBackground
        surface = Color(hex: colors?.surface) ?? fallbackSurface
        textPrimary = Color(hex: colors?.textPrimary) ?? Color.primary
        textSecondary = Color(hex: colors?.textSecondary) ?? Color.secondary
        accent = Color(hex: colors?.accent) ?? Color.blue
        border = Color(hex: colors?.border) ?? Color.gray.opacity(0.35)
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        guard cleaned.count == 6 || cleaned.count == 8 else { return nil }
        var value: UInt64 = 0
        guard Scanner(string: cleaned).scanHexInt64(&value) else { return nil }
        let red: Double
        let green: Double
        let blue: Double
        let alpha: Double
        if cleaned.count == 8 {
            red = Double((value >> 24) & 0xFF) / 255.0
            green = Double((value >> 16) & 0xFF) / 255.0
            blue = Double((value >> 8) & 0xFF) / 255.0
            alpha = Double(value & 0xFF) / 255.0
        } else {
            red = Double((value >> 16) & 0xFF) / 255.0
            green = Double((value >> 8) & 0xFF) / 255.0
            blue = Double(value & 0xFF) / 255.0
            alpha = 1
        }
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - Timeline provider

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
        let calendar = Calendar.current
        let nextMidnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: Date()) ?? Date()
        )
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }
}

// MARK: - Shared row views

private struct WidgetCheck: View {
    let checked: Bool
    let palette: WidgetPalette

    var body: some View {
        Image(systemName: checked ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 16))
            .foregroundStyle(checked ? palette.accent : palette.textSecondary)
            .frame(width: 32, height: 32)
    }
}

private struct TimeText: View {
    let start: String
    let end: String?
    let isAllDay: Bool
    let allDay: String
    let palette: WidgetPalette

    var body: some View {
        let text: String = {
            if isAllDay { return allDay }
            if let end, !end.isEmpty { return "\(start) - \(end)" }
            return start
        }()
        Text(text)
            .font(.caption2)
            .foregroundStyle(palette.textSecondary)
            .lineLimit(1)
    }
}

private struct EmptyMessage: View {
    let text: String
    let palette: WidgetPalette

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Today

struct TodayWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarTodoEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var ui: WidgetUi? { snapshot?.ui }
    private var palette: WidgetPalette { WidgetPalette(snapshot) }
    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }

    var body: some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else {
                emptyState
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { palette.background }
        .widgetURL(WidgetLinks.today)
    }

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let pending = WidgetSnapshotStore.pendingCommandTargets()
        let timeline = Array(snapshot.timeline.prefix(small ? 1 : (large ? 3 : 2)))
        let actions = Array(snapshot.actions.prefix(small ? 1 : (large ? 5 : 3)))
        return VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(WidgetDates.short(snapshot.todayIso))
                    .font(small ? .title3.weight(.semibold) : .title2.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                Spacer(minLength: 4)
                Text(entry.date, format: .dateTime.weekday(.abbreviated))
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
            }

            if timeline.isEmpty && actions.isEmpty {
                EmptyMessage(
                    text: (ui?.noPlans).flatMap { $0.isEmpty ? nil : $0 } ?? WidgetCopy.noPlans,
                    palette: palette
                )
                .padding(.top, 4)
            } else if small {
                ForEach(timeline.indices, id: \.self) { index in
                    timelineRow(timeline[index], pending: pending)
                }
                ForEach(actions.indices, id: \.self) { index in
                    actionRow(actions[index], pending: pending)
                }
            } else if large {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(timeline.indices, id: \.self) { index in
                        timelineRow(timeline[index], pending: pending)
                    }
                }
                if !timeline.isEmpty && !actions.isEmpty {
                    Rectangle().fill(palette.border).frame(height: 1)
                }
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(actions.indices, id: \.self) { index in
                        actionRow(actions[index], pending: pending)
                    }
                }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(timeline.indices, id: \.self) { index in
                            timelineRow(timeline[index], pending: pending)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(palette.border).frame(width: 1)
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(actions.indices, id: \.self) { index in
                            actionRow(actions[index], pending: pending)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            Spacer(minLength: 0)

            if !small {
                HStack(spacing: 6) {
                    if large {
                        Link(destination: WidgetLinks.newEvent(snapshot.todayIso)) {
                            footerLabel(ui?.newEvent ?? WidgetCopy.newEvent)
                        }
                    }
                    Link(destination: WidgetLinks.quickAdd) {
                        footerLabel(ui?.newTodo ?? WidgetCopy.newTodo)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text((ui?.openApp).flatMap { $0.isEmpty ? nil : $0 } ?? WidgetCopy.openApp)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private func footerLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.accent)
            .frame(maxWidth: .infinity, minHeight: 24)
            .background(palette.accent.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func timelineRow(
        _ item: WidgetTimelineItem,
        pending: WidgetSnapshotStore.PendingCommandTargets
    ) -> some View {
        let todoId = item.todoId ?? -1
        let isAllocation = item.kind == "taskAllocation" && todoId > 0
        HStack(spacing: 6) {
            if isAllocation {
                let target = (item.occurrenceId?.isEmpty == false) ? "taskInstance" : "todo"
                let checked = WidgetCommandState.isPending(
                    pending,
                    target: target,
                    todoId: todoId,
                    occurrenceId: item.occurrenceId
                )
                Button(intent: CompleteActionIntent(
                    target: target,
                    todoId: todoId,
                    todoSyncId: item.todoSyncId ?? "",
                    occurrenceId: item.occurrenceId ?? "",
                    sourceAllocationId: item.allocationId ?? ""
                )) {
                    WidgetCheck(checked: checked, palette: palette)
                }
                .buttonStyle(.plain)
            } else {
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color(hex: item.color) ?? palette.accent)
                    .frame(width: 4, height: 20)
                    .padding(.leading, 2)
            }

            if let url = WidgetLinks.detail(eventId: item.eventId, todoId: item.todoId) {
                if small {
                    rowBody(item)
                } else {
                    Link(destination: url) { rowBody(item) }
                }
            } else {
                rowBody(item)
            }
        }
        .frame(minHeight: small ? 40 : 32)
    }

    private func rowBody(_ item: WidgetTimelineItem) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(item.summary)
                .font(.caption)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            TimeText(
                start: item.start,
                end: item.end,
                isAllDay: item.isAllDay ?? false,
                allDay: ui?.allDay ?? "",
                palette: palette
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func actionRow(
        _ action: WidgetActionItem,
        pending: WidgetSnapshotStore.PendingCommandTargets
    ) -> some View {
        let target = action.target ?? "todo"
        let checked = WidgetCommandState.isPending(
            pending,
            target: target,
            todoId: action.todoId,
            occurrenceId: action.occurrenceId
        )
        HStack(spacing: 6) {
            if action.todoId > 0 {
                Button(intent: CompleteActionIntent(
                    target: target,
                    todoId: action.todoId,
                    todoSyncId: action.todoSyncId ?? "",
                    occurrenceId: action.occurrenceId ?? ""
                )) {
                    WidgetCheck(checked: checked, palette: palette)
                }
                .buttonStyle(.plain)
            }
            if action.todoId > 0 && !small {
                Link(destination: WidgetLinks.todo(action.todoId)) {
                    actionBody(action, checked: checked)
                }
            } else {
                actionBody(action, checked: checked)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: small ? 40 : 32)
    }

    private func actionBody(_ action: WidgetActionItem, checked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(action.summary)
                .font(.caption)
                .strikethrough(checked)
                .foregroundStyle(checked ? palette.textSecondary : palette.textPrimary)
                .lineLimit(1)
            let meta = (action.deadline?.isEmpty == false ? action.deadline : nil)
                ?? (action.displayTime?.isEmpty == false ? action.displayTime : nil)
            if let meta {
                Text(meta)
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

enum WidgetCommandState {
    static func isPending(
        _ targets: WidgetSnapshotStore.PendingCommandTargets,
        target: String,
        todoId: Int,
        occurrenceId: String?
    ) -> Bool {
        if target == "taskInstance" {
            return targets.instanceKeys.contains("\(todoId):\(occurrenceId ?? "")")
        }
        return targets.todoIds.contains(todoId)
    }
}

// MARK: - Upcoming

struct UpcomingWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarTodoEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var ui: WidgetUi? { snapshot?.ui }
    private var palette: WidgetPalette { WidgetPalette(snapshot) }
    private var large: Bool { family == .systemLarge }

    private var groups: [(String, [WidgetUpcomingItem])] {
        guard let snapshot else { return [] }
        if let days = snapshot.upcoming?.days, !days.isEmpty {
            return days.map { ($0.date, $0.items) }
        }
        let items = snapshot.upcoming?.items ?? []
        let grouped = Dictionary(grouping: items) { $0.date ?? "" }
        return grouped.keys.sorted().map { ($0, grouped[$0] ?? []) }
    }

    var body: some View {
        Group {
            if snapshot != nil {
                content
            } else {
                VStack(alignment: .leading) {
                    Spacer()
                    Text((ui?.openApp).flatMap { $0.isEmpty ? nil : $0 } ?? WidgetCopy.openApp)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer()
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { palette.background }
        .widgetURL(WidgetLinks.calendar)
    }

    private var content: some View {
        let todayIso = snapshot?.todayIso ?? WidgetDates.iso(Date())
        let limit = large ? 10 : 4
        let rows = flatten(groups: groups, limit: limit)
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Link(destination: WidgetLinks.calendar) {
                    Text(ui?.upcoming ?? WidgetCopy.today)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
                Spacer()
                Text(WidgetDates.short(todayIso))
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
            }
            if rows.isEmpty {
                EmptyMessage(
                    text: (ui?.noUpcoming).flatMap { $0.isEmpty ? nil : $0 } ?? WidgetCopy.noUpcoming,
                    palette: palette
                )
            }
            ForEach(rows.indices, id: \.self) { index in
                switch rows[index] {
                case let .header(label):
                    Text(label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 3)
                case let .item(item):
                    rowView(item)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private enum Row {
        case header(String)
        case item(WidgetUpcomingItem)
    }

    private func flatten(groups: [(String, [WidgetUpcomingItem])], limit: Int) -> [Row] {
        let todayIso = snapshot?.todayIso ?? WidgetDates.iso(Date())
        let tomorrowIso = WidgetDates.tomorrowIso()
        var rows: [Row] = []
        for group in groups {
            if rows.count >= limit { break }
            rows.append(.header(dayLabel(group.0, todayIso: todayIso, tomorrowIso: tomorrowIso)))
            for item in group.1 {
                if rows.count >= limit { break }
                rows.append(.item(item))
            }
        }
        return rows
    }

    private func dayLabel(_ iso: String, todayIso: String, tomorrowIso: String) -> String {
        if iso == todayIso { return (ui?.today).flatMap { $0.isEmpty ? nil : $0 } ?? WidgetCopy.today }
        if iso == tomorrowIso { return (ui?.tomorrow).flatMap { $0.isEmpty ? nil : $0 } ?? "Tomorrow" }
        return WidgetDates.short(iso)
    }

    private func rowView(_ item: WidgetUpcomingItem) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(markerColor(item))
                .frame(width: 4, height: 16)
            Text(item.time ?? "")
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 54, alignment: .leading)
                .lineLimit(1)
            if let url = WidgetLinks.detail(eventId: item.eventId, todoId: item.todoId) {
                Link(destination: url) {
                    Text(item.summary)
                        .font(.caption)
                        .foregroundStyle(palette.textPrimary)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(minHeight: 28)
    }

    private func markerColor(_ item: WidgetUpcomingItem) -> Color {
        if item.kind == "todoDeadline" { return palette.textSecondary }
        return Color(hex: item.color) ?? palette.accent
    }
}

// MARK: - Calendar

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarTodoEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var ui: WidgetUi? { snapshot?.ui }
    private var palette: WidgetPalette { WidgetPalette(snapshot) }
    private var large: Bool { family == .systemLarge }

    private struct MonthModel {
        let year: Int
        let month: Int
        let firstWeekday: Int
        let todayDay: Int
        let daysInMonth: Int
        let marks: [Int: WidgetMonthDay]
    }

    private var month: MonthModel {
        let calendar = Calendar.current
        let now = Date()
        let snapshotMonth = snapshot?.month
        let year = (snapshotMonth?.year ?? 0) > 0
            ? snapshotMonth!.year!
            : calendar.component(.year, from: now)
        let month = (snapshotMonth?.month ?? 0) > 0
            ? snapshotMonth!.month!
            : calendar.component(.month, from: now)
        var first = DateComponents()
        first.year = year
        first.month = month
        first.day = 1
        let firstDate = calendar.date(from: first) ?? now
        let weekday = calendar.component(.weekday, from: firstDate)
        let firstWeekday = (snapshotMonth?.firstWeekday).flatMap { $0 >= 1 && $0 <= 7 ? $0 : nil }
            ?? (((weekday + 5) % 7) + 1)
        let range = calendar.range(of: .day, in: .month, for: firstDate)
        let daysInMonth = range?.count ?? 30
        let isCurrent = year == calendar.component(.year, from: now)
            && month == calendar.component(.month, from: now)
        let marks = Dictionary(
            uniqueKeysWithValues: (snapshotMonth?.days ?? []).map { ($0.day, $0) }
        )
        return MonthModel(
            year: year,
            month: month,
            firstWeekday: firstWeekday,
            todayDay: isCurrent ? calendar.component(.day, from: now) : -1,
            daysInMonth: daysInMonth,
            marks: marks
        )
    }

    var body: some View {
        let model = month
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(WidgetDates.monthTitle(year: model.year, month: model.month))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                Spacer()
                Link(destination: WidgetLinks.newEvent(WidgetDates.iso(Date()))) {
                    Image(systemName: "plus")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(palette.accent)
                        .frame(width: 32, height: 32)
                }
            }
            weekdayHeader
            grid(model)
            if large {
                Divider().overlay(palette.border)
                todaySummary
            }
        }
        .padding(large ? 10 : 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { palette.background }
        .widgetURL(WidgetLinks.calendar)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(WidgetDates.weekdaySymbolsMondayFirst(), id: \.self) { symbol in
                Text(symbol)
                    .font(.system(size: 9))
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func grid(_ model: MonthModel) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)
        let leading = model.firstWeekday - 1
        let total = leading + model.daysInMonth
        let cells = Int(ceil(Double(total) / 7.0)) * 7
        return LazyVGrid(columns: columns, spacing: large ? 3 : 0) {
            ForEach(0..<cells, id: \.self) { index in
                let day = index - leading + 1
                if day >= 1 && day <= model.daysInMonth {
                    dayCell(day, model: model)
                } else {
                    Color.clear.frame(height: large ? 30 : 22)
                }
            }
        }
    }

    private func dayCell(_ day: Int, model: MonthModel) -> some View {
        let mark = model.marks[day]
        let isToday = day == model.todayDay
        var iso = WidgetDates.iso(Date())
        var components = DateComponents()
        components.year = model.year
        components.month = model.month
        components.day = day
        if let date = Calendar.current.date(from: components) {
            iso = WidgetDates.iso(date)
        }
        let dotColor: Color? = {
            if mark?.hasEvent == true || mark?.hasAllocation == true {
                return Color(hex: mark?.colors?.first) ?? palette.accent
            }
            if mark?.hasTodo == true { return palette.textSecondary }
            return nil
        }()
        return Link(destination: WidgetLinks.calendar(iso)) {
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.system(size: large ? 12 : 10, weight: isToday ? .bold : .regular))
                    .foregroundStyle(isToday ? palette.accent : palette.textPrimary)
                Circle()
                    .fill(dotColor ?? .clear)
                    .frame(width: large ? 4 : 3, height: large ? 4 : 3)
            }
            .frame(maxWidth: .infinity, minHeight: large ? 25 : 18)
        }
    }

    private var todaySummary: some View {
        let timeline = Array((snapshot?.timeline ?? []).prefix(2))
        let actions = Array((snapshot?.actions ?? []).prefix(2))
        return VStack(alignment: .leading, spacing: 2) {
            Text((ui?.today).flatMap { $0.isEmpty ? nil : $0 } ?? WidgetCopy.today)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(palette.textSecondary)
            if timeline.isEmpty && actions.isEmpty {
                EmptyMessage(
                    text: (ui?.noPlans).flatMap { $0.isEmpty ? nil : $0 } ?? WidgetCopy.noPlans,
                    palette: palette
                )
            }
            ForEach(timeline.indices, id: \.self) { index in
                let item = timeline[index]
                summaryRow(
                    time: timeLabel(start: item.start, end: item.end, isAllDay: item.isAllDay ?? false),
                    title: item.summary,
                    url: WidgetLinks.detail(eventId: item.eventId, todoId: item.todoId)
                )
            }
            ForEach(actions.indices, id: \.self) { index in
                let action = actions[index]
                summaryRow(
                    time: (action.deadline?.isEmpty == false ? action.deadline : nil)
                        ?? (action.displayTime ?? ""),
                    title: action.summary,
                    url: action.todoId > 0 ? WidgetLinks.todo(action.todoId) : nil
                )
            }
        }
    }

    private func timeLabel(start: String, end: String?, isAllDay: Bool) -> String {
        if isAllDay { return ui?.allDay ?? "" }
        if let end, !end.isEmpty { return "\(start)-\(end)" }
        return start
    }

    @ViewBuilder
    private func summaryRow(time: String, title: String, url: URL?) -> some View {
        let body = HStack(spacing: 6) {
            Text(time)
                .font(.system(size: 9))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 48, alignment: .leading)
                .lineLimit(1)
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 22)
        if let url {
            Link(destination: url) { body }
        } else {
            body
        }
    }
}

// MARK: - Quick actions

struct QuickActionsWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CalendarTodoEntry

    private var palette: WidgetPalette { WidgetPalette(entry.snapshot) }
    private var small: Bool { family == .systemSmall }

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                action(WidgetLinks.quickAdd, title: WidgetCopy.newTodo)
                action(WidgetLinks.newEvent(WidgetDates.iso(Date())), title: WidgetCopy.newEvent)
            }
            if !small {
                HStack(spacing: 8) {
                    action(WidgetLinks.today, title: WidgetCopy.today)
                    action(WidgetLinks.calendar, title: WidgetCopy.calendar)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(for: .widget) { palette.background }
    }

    private func action(_ url: URL, title: String) -> some View {
        Link(destination: url) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(palette.accent)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(palette.accent.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .frame(minHeight: 44)
        }
    }
}

// MARK: - Widget bundle

struct CalendarTodoWidget: Widget {
    let kind = "CalendarTodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            TodayWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetCopy.galleryName(kind))
        .description(WidgetCopy.galleryDescription(kind))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct CalendarUpcomingWidget: Widget {
    let kind = "CalendarUpcomingWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            UpcomingWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetCopy.galleryName(kind))
        .description(WidgetCopy.galleryDescription(kind))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CalendarMonthWidget: Widget {
    let kind = "CalendarMonthWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetCopy.galleryName(kind))
        .description(WidgetCopy.galleryDescription(kind))
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct CalendarQuickActionsWidget: Widget {
    let kind = "CalendarQuickActionsWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            QuickActionsWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetCopy.galleryName(kind))
        .description(WidgetCopy.galleryDescription(kind))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct CalendarTodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarTodoWidget()
        CalendarUpcomingWidget()
        CalendarMonthWidget()
        CalendarQuickActionsWidget()
    }
}
