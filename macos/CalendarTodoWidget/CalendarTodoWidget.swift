import AppIntents
import SwiftUI
import WidgetKit

// MARK: - Snapshot v5 contract
// Mirrors lib/infrastructure/platform/home_widget_service.dart. Missing fields
// decode as nil so a partially-written blob can never crash the extension.

struct WidgetTimelineItem: Decodable {
    let kind: String
    let summary: String
    let start: String?
    let end: String?
    let startEpochMs: Int?
    let endEpochMs: Int?
    let isAllDay: Bool?
    let eventId: Int?
    let calendarId: Int?
    let color: String?
    let allocationId: String?
    let todoId: Int?
    let todoSyncId: String?
    let occurrenceId: String?
}

struct WidgetTaskItem: Decodable {
    let kind: String?
    let target: String?
    let todoId: Int
    let todoSyncId: String?
    let occurrenceId: String?
    let summary: String
    let displayTime: String?
    let priority: Int?
    let dueEpochMs: Int?
    let dueDate: String?
    let startEpochMs: Int?
}

struct WidgetActionCounts: Decodable {
    let dueToday: Int?
    let overdue: Int?
    let completedToday: Int?
}

struct WidgetActionBlock: Decodable {
    let timeline: [WidgetTimelineItem]?
    let dueToday: [WidgetTaskItem]?
    let overdue: [WidgetTaskItem]?
    let counts: WidgetActionCounts?
}

struct WidgetTodoItem: Decodable {
    let todoId: Int
    let todoSyncId: String?
    let summary: String
    let priority: Int?
    let dueDate: String?
    let dueEpochMs: Int?
    let hasTime: Bool?
    let recurring: Bool?
    let tagColors: [String]?
}

struct WidgetTodoMode: Decodable {
    let items: [WidgetTodoItem]?
    let overdue: [WidgetTodoItem]?
    let completedCount: Int?
    let total: Int?
    let sixThingsCap: Int?
}

struct WidgetTodosBlock: Decodable {
    let today: WidgetTodoMode?
    let inbox: WidgetTodoMode?
    let all: WidgetTodoMode?
}

struct WidgetMonthItem: Decodable {
    let kind: String
    let summary: String
    let start: String?
    let end: String?
    let startEpochMs: Int?
    let endEpochMs: Int?
    let isAllDay: Bool?
    let hasTime: Bool?
    let color: String?
    let eventId: Int?
    let todoId: Int?
    let todoSyncId: String?
    let allocationId: String?
    let occurrenceId: String?
}

struct WidgetMonthDay: Decodable {
    let day: Int
    let hasEvent: Bool?
    let hasTodo: Bool?
    let hasAllocation: Bool?
    let colors: [String]?
    let itemCount: Int?
    let items: [WidgetMonthItem]?
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
    let today: String?
    let inbox: String?
    let all: String?
    let noTodos: String?
    let allTodosDone: String?
    let noPlans: String?
    let allPlansDone: String?
    let now: String?
    let later: String?
    let dueToday: String?
    let overdue: String?
    let completedCount: String?
    let moreCount: String?
    let overdueCount: String?
    let selectedDayEmpty: String?
    let backToMonth: String?
    let openToUpdate: String?
    let stale: String?
    let addTodo: String?
    let addEvent: String?
    let quickAddHint: String?
    let quickAddToday: String?
    let quickAddInbox: String?
    let save: String?
    let saveFailed: String?
    let allDay: String?

    func withCount(_ template: String?, _ count: Int) -> String {
        (template ?? "{n}").replacingOccurrences(of: "{n}", with: "\(count)")
    }
}

struct WidgetThemeColors: Decodable {
    let background: String?
    let surface: String?
    let textPrimary: String?
    let textSecondary: String?
    let accent: String?
    let border: String?
    let error: String?
    let warning: String?
}

struct WidgetTheme: Decodable {
    let dark: Bool?
    let colors: WidgetThemeColors?
}

struct WidgetSnapshot: Decodable {
    let version: Int
    let generatedAt: String?
    let today: String?
    let action: WidgetActionBlock?
    let todos: WidgetTodosBlock?
    let month: WidgetMonth?
    let ui: WidgetUi?
    let theme: WidgetTheme?

    var todayIso: String {
        if let today, !today.isEmpty { return today }
        return WidgetDates.iso(Date())
    }

    func todoMode(_ filter: TodoFilter) -> WidgetTodoMode? {
        switch filter {
        case .today: return todos?.today
        case .inbox: return todos?.inbox
        case .all: return todos?.all
        }
    }
}

// MARK: - Shared store

enum WidgetSnapshotStore {
    static let appGroupId = "group.com.dayspark.app"
    static let snapshotKey = "widget_snapshot"

    static func load() -> WidgetSnapshot? {
        guard let raw = UserDefaults(suiteName: appGroupId)?.string(forKey: snapshotKey),
              let data = raw.data(using: .utf8),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version >= 5
        else {
            return nil
        }
        return snapshot
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
                    if !occ.isEmpty { instanceKeys.insert("\(todoId):\(occ)") }
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

enum WidgetCalendarState {
    static let dateKey = "widget_calendar_selected_date"
    static let modeKey = "widget_calendar_mode"

    static var defaults: UserDefaults? { UserDefaults(suiteName: WidgetSnapshotStore.appGroupId) }

    static func selectedIso() -> String {
        let today = WidgetDates.iso(Date())
        guard let raw = defaults?.string(forKey: dateKey), WidgetDates.parse(raw) != nil else {
            return today
        }
        let calendar = Calendar.current
        guard let selected = WidgetDates.parse(raw),
              let now = WidgetDates.parse(today) else { return today }
        let sameMonth = calendar.component(.year, from: selected) == calendar.component(.year, from: now)
            && calendar.component(.month, from: selected) == calendar.component(.month, from: now)
        return sameMonth ? raw : today
    }

    static func mode() -> String {
        defaults?.string(forKey: modeKey) == "day" ? "day" : "month"
    }

    static func set(dateIso: String, enterDay: Bool) {
        defaults?.set(dateIso, forKey: dateKey)
        if enterDay { defaults?.set("day", forKey: modeKey) }
    }

    static func backToMonth() {
        defaults?.set("month", forKey: modeKey)
    }

    static func today() {
        defaults?.set(WidgetDates.iso(Date()), forKey: dateKey)
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CompleteActionIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete action"
    static var description = IntentDescription("Queues a widget completion command")

    @Parameter(title: "Target") var target: String
    @Parameter(title: "Todo ID") var todoId: Int
    @Parameter(title: "Todo Sync ID") var todoSyncId: String
    @Parameter(title: "Occurrence ID") var occurrenceId: String
    @Parameter(title: "Source Allocation ID") var sourceAllocationId: String

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

@available(iOS 17.0, macOS 14.0, *)
struct SelectCalendarDateIntent: AppIntent {
    static var title: LocalizedStringResource = "Select date"

    @Parameter(title: "Date") var dateIso: String
    @Parameter(title: "Enter day") var enterDay: Bool

    init() {
        dateIso = WidgetDates.iso(Date())
        enterDay = false
    }

    init(dateIso: String, enterDay: Bool) {
        self.dateIso = dateIso
        self.enterDay = enterDay
    }

    func perform() async throws -> some IntentResult {
        WidgetCalendarState.set(dateIso: dateIso, enterDay: enterDay)
        WidgetCenter.shared.reloadTimelines(ofKind: "CalendarMonthWidget")
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CalendarTodayIntent: AppIntent {
    static var title: LocalizedStringResource = "Today"

    func perform() async throws -> some IntentResult {
        WidgetCalendarState.today()
        WidgetCenter.shared.reloadTimelines(ofKind: "CalendarMonthWidget")
        return .result()
    }
}

@available(iOS 17.0, macOS 14.0, *)
struct CalendarBackToMonthIntent: AppIntent {
    static var title: LocalizedStringResource = "Back to month"

    func perform() async throws -> some IntentResult {
        WidgetCalendarState.backToMonth()
        WidgetCenter.shared.reloadTimelines(ofKind: "CalendarMonthWidget")
        return .result()
    }
}

// MARK: - Todo filter configuration

enum TodoFilter: String, AppEnum {
    case today
    case inbox
    case all

    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Task list"
    static var caseDisplayRepresentations: [TodoFilter: DisplayRepresentation] = [
        .today: "Today",
        .inbox: "Inbox",
        .all: "All",
    ]
}

@available(iOS 17.0, macOS 14.0, *)
struct TodosConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "Tasks"
    static var description = IntentDescription("Choose which task list this widget shows")

    @Parameter(title: "List") var filter: TodoFilter

    init() {
        filter = .today
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

    static func short(_ iso: String) -> String {
        guard let date = parse(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMd")
        return formatter.string(from: date)
    }

    static func dayTitle(_ iso: String) -> String {
        guard let date = parse(iso) else { return iso }
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMdEEE")
        return formatter.string(from: date)
    }

    static func monthTitle(year: Int, month: Int) -> String {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1
        guard let date = Calendar.current.date(from: components) else { return "\(year)-\(month)" }
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

    static func nextBoundary(_ snapshot: WidgetSnapshot?) -> Date? {
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        var candidates: [Int] = []
        for item in snapshot?.action?.timeline ?? [] {
            if let start = item.startEpochMs, start > nowMs { candidates.append(start) }
            if let end = item.endEpochMs, end > nowMs { candidates.append(end) }
        }
        guard let next = candidates.min() else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(next) / 1000.0)
    }
}

enum WidgetLinks {
    static let action = URL(string: "dayspark://open/action")!
    static let calendar = URL(string: "dayspark://open/calendar")!

    static func todos(_ filter: TodoFilter) -> URL {
        URL(string: "dayspark://open/todos?view=\(filter.rawValue)")!
    }

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

    static func quickAdd(_ dateIso: String?) -> URL {
        guard let dateIso, !dateIso.isEmpty else {
            return URL(string: "dayspark://quick-add")!
        }
        return URL(string: "dayspark://quick-add?date=\(dateIso)")!
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
        case "CalendarTodoWidget": return chinese ? "今日行动" : "Action"
        case "CalendarMonthWidget": return chinese ? "月历" : "Calendar"
        case "CalendarTodosWidget": return chinese ? "待办" : "Tasks"
        default: return "DaySpark"
        }
    }

    static func galleryDescription(_ kind: String) -> String {
        switch kind {
        case "CalendarTodoWidget":
            return chinese ? "查看并完成今天正在发生的事" : "See and complete what is happening today."
        case "CalendarMonthWidget":
            return chinese ? "查看本月任意一天的安排" : "See any day in this month at a glance."
        case "CalendarTodosWidget":
            return chinese ? "你的任务清单，直接在桌面完成" : "Your task list, ready to check off."
        default:
            return ""
        }
    }

    static let openApp = chinese ? "打开 DaySpark 以显示你的安排" : "Open DaySpark to show your schedule"
    static let noPlans = chinese ? "今天没有安排" : "No plans for today"
    static let noTodos = chinese ? "没有待办" : "No tasks"
    static let openToUpdate = chinese ? "打开 DaySpark 以更新" : "Open DaySpark to update"
    static let selectedDayEmpty = chinese ? "这一天没有安排" : "Nothing on this day"
    static let newTodo = chinese ? "+ 待办" : "+ Task"
    static let newEvent = chinese ? "+ 日程" : "+ Event"
    static let today = chinese ? "今天" : "Today"
    static let inbox = chinese ? "收件箱" : "Inbox"
    static let all = chinese ? "全部" : "All"
    static let backToMonth = chinese ? "月" : "Month"
    static let allDay = chinese ? "全天" : "All day"
}

// MARK: - Theme

struct WidgetPalette {
    let background: Color
    let surface: Color
    let textPrimary: Color
    let textSecondary: Color
    let accent: Color
    let border: Color
    let error: Color
    let warning: Color

    init(_ snapshot: WidgetSnapshot?) {
        let colors = snapshot?.theme?.colors
        #if os(iOS)
        let fallbackBackground = Color(.systemBackground)
        let fallbackSurface = Color(.secondarySystemBackground)
        let fallbackError = Color.red
        let fallbackWarning = Color.orange
        #else
        let fallbackBackground = Color(nsColor: .windowBackgroundColor)
        let fallbackSurface = Color(nsColor: .controlBackgroundColor)
        let fallbackError = Color.red
        let fallbackWarning = Color.orange
        #endif
        background = Color(hex: colors?.background) ?? fallbackBackground
        surface = Color(hex: colors?.surface) ?? fallbackSurface
        textPrimary = Color(hex: colors?.textPrimary) ?? Color.primary
        textSecondary = Color(hex: colors?.textSecondary) ?? Color.secondary
        accent = Color(hex: colors?.accent) ?? Color.blue
        border = Color(hex: colors?.border) ?? Color.gray.opacity(0.35)
        error = Color(hex: colors?.error) ?? fallbackError
        warning = Color(hex: colors?.warning) ?? fallbackWarning
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

// MARK: - Timeline providers

struct WidgetEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct TodosEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let filter: TodoFilter
}

struct SnapshotTimelineProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetEntry {
        WidgetEntry(date: Date(), snapshot: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetEntry) -> Void) {
        completion(WidgetEntry(date: Date(), snapshot: WidgetSnapshotStore.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.load()
        var entries = [WidgetEntry(date: now, snapshot: snapshot)]
        let calendar = Calendar.current
        let nextMidnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: now) ?? now
        )
        if let boundary = WidgetDates.nextBoundary(snapshot), boundary > now, boundary < nextMidnight {
            entries.append(WidgetEntry(date: boundary, snapshot: snapshot))
        }
        entries.append(WidgetEntry(date: nextMidnight, snapshot: snapshot))
        completion(Timeline(entries: entries, policy: .after(nextMidnight)))
    }
}

struct TodosTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> TodosEntry {
        TodosEntry(date: Date(), snapshot: nil, filter: .today)
    }

    func snapshot(for configuration: TodosConfigurationIntent, in context: Context) async -> TodosEntry {
        TodosEntry(date: Date(), snapshot: WidgetSnapshotStore.load(), filter: configuration.filter)
    }

    func timeline(for configuration: TodosConfigurationIntent, in context: Context) async -> Timeline<TodosEntry> {
        let now = Date()
        let calendar = Calendar.current
        let nextMidnight = calendar.startOfDay(
            for: calendar.date(byAdding: .day, value: 1, to: now) ?? now
        )
        let entry = TodosEntry(date: now, snapshot: WidgetSnapshotStore.load(), filter: configuration.filter)
        return Timeline(entries: [entry], policy: .after(nextMidnight))
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

private struct SectionLabel: View {
    let text: String
    let palette: WidgetPalette
    var color: Color?

    var body: some View {
        Text(text)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(color ?? palette.textSecondary)
            .lineLimit(1)
    }
}

private enum WidgetCommandState {
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

private func actionTime(_ item: WidgetTimelineItem, allDay: String) -> String {
    if item.isAllDay == true { return allDay }
    let start = item.start ?? ""
    if let end = item.end, !end.isEmpty { return "\(start) - \(end)" }
    return start
}

private func priorityColor(_ priority: Int?, palette: WidgetPalette) -> Color? {
    guard let priority else { return nil }
    if priority == 1 { return palette.error }
    if priority >= 2 && priority <= 4 { return palette.warning }
    return nil
}

// MARK: - Action

struct ActionWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var ui: WidgetUi? { snapshot?.ui }
    private var palette: WidgetPalette { WidgetPalette(snapshot) }
    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }

    private enum Line {
        case section(String)
        case timeline(WidgetTimelineItem)
        case task(WidgetTaskItem)
        case overdueSummary(Int)
    }

    var body: some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else {
                emptyState
            }
        }
        .padding(small ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { palette.background }
        .widgetURL(WidgetLinks.action)
    }

    private var stale: Bool {
        guard let snapshot else { return true }
        return snapshot.todayIso != WidgetDates.iso(Date())
    }

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let pending = WidgetSnapshotStore.pendingCommandTargets()
        let block = snapshot.action
        let counts = block?.counts
        let nowMs = Int(Date().timeIntervalSince1970 * 1000)
        let timeline = block?.timeline ?? []
        let current = timeline
            .filter { ($0.startEpochMs ?? 0) <= nowMs && nowMs < ($0.endEpochMs ?? 0) }
            .sorted { ($0.startEpochMs ?? 0) < ($1.startEpochMs ?? 0) }
        let later = timeline
            .filter { ($0.startEpochMs ?? 0) > nowMs }
            .sorted { ($0.startEpochMs ?? 0) < ($1.startEpochMs ?? 0) }
        let due = block?.dueToday ?? []
        let overdue = block?.overdue ?? []
        let completed = counts?.completedToday ?? 0
        let overdueCount = counts?.overdue ?? overdue.count

        return VStack(alignment: .leading, spacing: 2) {
            header(snapshot: snapshot, overdueCount: stale ? 0 : overdueCount)

            if stale {
                EmptyMessage(
                    text: ui?.openToUpdate ?? WidgetCopy.openToUpdate,
                    palette: palette
                )
                Spacer(minLength: 0)
            } else if small {
                if let line = smallLine(current: current, later: later, due: due) {
                    row(line, pending: pending)
                } else {
                    EmptyMessage(
                        text: completed > 0
                            ? (ui?.allPlansDone ?? WidgetCopy.noPlans)
                            : (ui?.noPlans ?? WidgetCopy.noPlans),
                        palette: palette
                    )
                }
                Spacer(minLength: 0)
            } else {
                let lines = sectionLines(current: current, later: later, due: due, overdue: overdue, overdueCount: overdueCount, large: large)
                ForEach(lines.indices, id: \.self) { index in
                    row(lines[index], pending: pending)
                }
                Spacer(minLength: 0)
                if lines.isEmpty {
                    EmptyMessage(
                        text: completed > 0
                            ? (ui?.allPlansDone ?? WidgetCopy.noPlans)
                            : (ui?.noPlans ?? WidgetCopy.noPlans),
                        palette: palette
                    )
                }
                footer(snapshot: snapshot, completed: completed)
            }
        }
    }

    private func header(snapshot: WidgetSnapshot, overdueCount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(WidgetDates.short(snapshot.todayIso))
                .font(small ? .title3.weight(.semibold) : .title2.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
            Text(WidgetDates.dayTitle(snapshot.todayIso))
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 2)
            if small && overdueCount > 0 {
                Text(ui?.withCount(ui?.overdueCount, overdueCount) ?? "\(overdueCount)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(palette.error)
                    .lineLimit(1)
            }
            if !small {
                Link(destination: WidgetLinks.quickAdd(snapshot.todayIso)) {
                    Text(ui?.addTodo ?? WidgetCopy.newTodo)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
                if large || family == .systemMedium {
                    Link(destination: WidgetLinks.newEvent(snapshot.todayIso)) {
                        Text(ui?.addEvent ?? WidgetCopy.newEvent)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(palette.accent)
                    }
                }
            }
        }
    }

    private func smallLine(
        current: [WidgetTimelineItem],
        later: [WidgetTimelineItem],
        due: [WidgetTaskItem]
    ) -> Line? {
        if let first = current.first { return .timeline(first) }
        if let first = later.first { return .timeline(first) }
        if let first = due.first { return .task(first) }
        return nil
    }

    private func sectionLines(
        current: [WidgetTimelineItem],
        later: [WidgetTimelineItem],
        due: [WidgetTaskItem],
        overdue: [WidgetTaskItem],
        overdueCount: Int,
        large: Bool
    ) -> [Line] {
        let budget = large ? 12 : 5
        var lines: [Line] = []
        func append(_ title: String?, _ items: [Line]) {
            guard !items.isEmpty, lines.count < budget else { return }
            if let title, !title.isEmpty { lines.append(.section(title)) }
            for item in items {
                if lines.count >= budget { break }
                lines.append(item)
            }
        }
        append(ui?.now, current.map { .timeline($0) })
        append(ui?.later, later.map { .timeline($0) })
        append(ui?.dueToday, due.map { .task($0) })
        append(ui?.overdue, overdue.map { .task($0) })
        if overdueCount > 0, !lines.contains(where: { if case .task = $0 { return true }; return false }), lines.count < budget {
            lines.append(.overdueSummary(overdueCount))
        }
        return lines
    }

    @ViewBuilder
    private func row(_ line: Line, pending: WidgetSnapshotStore.PendingCommandTargets) -> some View {
        switch line {
        case let .section(title):
            SectionLabel(text: title, palette: palette)
                .padding(.top, 3)
        case let .timeline(item):
            timelineRow(item, pending: pending)
        case let .task(item):
            taskRow(item, pending: pending)
        case let .overdueSummary(count):
            if small {
                Text(ui?.withCount(ui?.overdueCount, count) ?? "\(count)")
                    .font(.caption2)
                    .foregroundStyle(palette.error)
            } else {
                Link(destination: WidgetLinks.action) {
                    Text(ui?.withCount(ui?.overdueCount, count) ?? "\(count)")
                        .font(.caption2)
                        .foregroundStyle(palette.error)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
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
                    .frame(width: 3, height: 20)
            }

            let body = VStack(alignment: .leading, spacing: 1) {
                Text(item.summary)
                    .font(.caption)
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                Text(actionTime(item, allDay: ui?.allDay ?? WidgetCopy.allDay))
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if small {
                body
            } else if let url = WidgetLinks.detail(eventId: item.eventId, todoId: item.todoId) {
                Link(destination: url) { body }
            } else {
                body
            }
        }
        .frame(minHeight: small ? 38 : 30)
    }

    @ViewBuilder
    private func taskRow(
        _ item: WidgetTaskItem,
        pending: WidgetSnapshotStore.PendingCommandTargets
    ) -> some View {
        let target = item.target ?? (item.kind == "taskInstance" ? "taskInstance" : "todo")
        let checked = WidgetCommandState.isPending(
            pending,
            target: target,
            todoId: item.todoId,
            occurrenceId: item.occurrenceId
        )
        HStack(spacing: 6) {
            if item.todoId > 0 {
                Button(intent: CompleteActionIntent(
                    target: target,
                    todoId: item.todoId,
                    todoSyncId: item.todoSyncId ?? "",
                    occurrenceId: item.occurrenceId ?? ""
                )) {
                    WidgetCheck(checked: checked, palette: palette)
                }
                .buttonStyle(.plain)
            }
            let body = VStack(alignment: .leading, spacing: 1) {
                Text(item.summary)
                    .font(.caption)
                    .strikethrough(checked)
                    .foregroundStyle(checked ? palette.textSecondary : palette.textPrimary)
                    .lineLimit(1)
                let meta = (item.displayTime?.isEmpty == false ? item.displayTime : nil)
                    ?? (item.dueDate.map { WidgetDates.short($0) })
                if let meta, !meta.isEmpty {
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if small {
                body
            } else if item.todoId > 0 {
                Link(destination: WidgetLinks.todo(item.todoId)) { body }
            } else {
                body
            }
        }
        .frame(minHeight: small ? 38 : 30)
    }

    @ViewBuilder
    private func footer(snapshot: WidgetSnapshot, completed: Int) -> some View {
        if completed > 0 {
            Link(destination: WidgetLinks.action) {
                HStack {
                    Text(ui?.withCount(ui?.completedCount, completed) ?? "\(completed)")
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9))
                        .foregroundStyle(palette.textSecondary)
                }
                .frame(minHeight: 20)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Spacer(minLength: 0)
            Text(ui?.openToUpdate ?? WidgetCopy.openToUpdate)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 0)
        }
    }
}

// MARK: - Todos

struct TodosWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: TodosEntry

    private var snapshot: WidgetSnapshot? { entry.snapshot }
    private var ui: WidgetUi? { snapshot?.ui }
    private var palette: WidgetPalette { WidgetPalette(snapshot) }
    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }

    private var mode: WidgetTodoMode? { snapshot?.todoMode(entry.filter) }

    private enum Line {
        case section(String)
        case item(WidgetTodoItem, overdue: Bool)
        case more(Int)
    }

    var body: some View {
        Group {
            if let snapshot {
                content(snapshot)
            } else {
                VStack(alignment: .leading) {
                    Spacer(minLength: 0)
                    Text(ui?.openToUpdate ?? WidgetCopy.openToUpdate)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(small ? 8 : 10)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { palette.background }
        .widgetURL(WidgetLinks.todos(entry.filter))
    }

    private func content(_ snapshot: WidgetSnapshot) -> some View {
        let pending = WidgetSnapshotStore.pendingCommandTargets()
        let modeBlock = mode
        let items = modeBlock?.items ?? []
        let overdue = modeBlock?.overdue ?? []
        let total = (modeBlock?.total ?? 0) + (entry.filter == .today ? overdue.count : 0)
        let completed = modeBlock?.completedCount ?? 0
        let snapshotStale = snapshot.todayIso != WidgetDates.iso(Date())
        let todayStale = snapshotStale && entry.filter == .today

        return VStack(alignment: .leading, spacing: 2) {
            header(count: total)
            if todayStale {
                EmptyMessage(
                    text: ui?.openToUpdate ?? WidgetCopy.openToUpdate,
                    palette: palette
                )
                Spacer(minLength: 0)
            } else {
                if snapshotStale {
                    Text(ui?.stale ?? WidgetCopy.openToUpdate)
                        .font(.system(size: 10))
                        .foregroundStyle(palette.error)
                        .lineLimit(1)
                }
                let lines = buildLines(items: items, overdue: overdue, large: large)
                ForEach(lines.indices, id: \.self) { index in
                    lineRow(lines[index], pending: pending)
                }
                Spacer(minLength: 0)
                if lines.isEmpty {
                    EmptyMessage(
                        text: entry.filter == .today && completed > 0
                            ? (ui?.allTodosDone ?? WidgetCopy.noTodos)
                            : (ui?.noTodos ?? WidgetCopy.noTodos),
                        palette: palette
                    )
                }
            }
        }
    }

    private func header(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(modeTitle)
                .font(small ? .headline : .title3.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Text("\(count)")
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
            Spacer(minLength: 2)
            if !small {
                Link(destination: WidgetLinks.quickAdd(entry.filter == .today ? WidgetDates.iso(Date()) : nil)) {
                    Text(ui?.addTodo ?? WidgetCopy.newTodo)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.accent)
                }
            }
        }
    }

    private var modeTitle: String {
        switch entry.filter {
        case .today: return ui?.today ?? WidgetCopy.today
        case .inbox: return ui?.inbox ?? WidgetCopy.inbox
        case .all: return ui?.all ?? WidgetCopy.all
        }
    }

    private func buildLines(
        items: [WidgetTodoItem],
        overdue: [WidgetTodoItem],
        large: Bool
    ) -> [Line] {
        let budget = large ? 8 : (small ? 2 : 4)
        var lines: [Line] = []
        if entry.filter == .today && !overdue.isEmpty {
            if large { lines.append(.section(ui?.overdue ?? "")) }
            for item in overdue {
                if lines.count >= budget { break }
                lines.append(.item(item, overdue: true))
            }
            if large && lines.count < budget && !items.isEmpty {
                lines.append(.section(ui?.today ?? ""))
            }
        }
        var emitted = 0
        for item in items {
            if lines.count >= budget { break }
            lines.append(.item(item, overdue: false))
            emitted += 1
        }
        let total = mode?.total ?? items.count
        let more = total - emitted
        if more > 0 && lines.count < budget {
            lines.append(.more(more))
        }
        return lines
    }

    @ViewBuilder
    private func lineRow(_ line: Line, pending: WidgetSnapshotStore.PendingCommandTargets) -> some View {
        switch line {
        case let .section(title):
            SectionLabel(text: title, palette: palette)
                .padding(.top, 3)
        case let .item(item, overdue):
            itemRow(item, overdue: overdue, pending: pending)
        case let .more(count):
            if small {
                Text(ui?.withCount(ui?.moreCount, count) ?? "\(count)")
                    .font(.caption2)
                    .foregroundStyle(palette.accent)
            } else {
                Link(destination: WidgetLinks.todos(entry.filter)) {
                    Text(ui?.withCount(ui?.moreCount, count) ?? "\(count)")
                        .font(.caption2)
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func itemRow(
        _ item: WidgetTodoItem,
        overdue: Bool,
        pending: WidgetSnapshotStore.PendingCommandTargets
    ) -> some View {
        let checked = WidgetCommandState.isPending(
            pending,
            target: "todo",
            todoId: item.todoId,
            occurrenceId: nil
        )
        HStack(spacing: 6) {
            if let color = priorityColor(item.priority, palette: palette), large {
                RoundedRectangle(cornerRadius: 1)
                    .fill(color)
                    .frame(width: 2, height: 22)
            }
            if item.recurring == true {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 12))
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 32, height: 32)
            } else {
                Button(intent: CompleteActionIntent(
                    target: "todo",
                    todoId: item.todoId,
                    todoSyncId: item.todoSyncId ?? ""
                )) {
                    WidgetCheck(checked: checked, palette: palette)
                }
                .buttonStyle(.plain)
            }

            let body = VStack(alignment: .leading, spacing: 1) {
                Text(item.summary)
                    .font(.caption)
                    .strikethrough(checked)
                    .foregroundStyle(checked ? palette.textSecondary : palette.textPrimary)
                    .lineLimit(large ? 2 : 1)
                if let meta = metaText(item, overdue: overdue, large: large), !meta.isEmpty {
                    Text(meta)
                        .font(.caption2)
                        .foregroundStyle(overdue ? palette.error : palette.textSecondary)
                        .lineLimit(1)
                }
                if large, let colors = item.tagColors, !colors.isEmpty {
                    HStack(spacing: 3) {
                        ForEach(Array(colors.prefix(3).enumerated()), id: \.offset) { _, hex in
                            Circle()
                                .fill(Color(hex: hex) ?? palette.textSecondary)
                                .frame(width: 5, height: 5)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if small {
                body
            } else {
                Link(destination: WidgetLinks.todo(item.todoId)) { body }
            }
        }
        .frame(minHeight: small ? 38 : 38)
    }

    private func metaText(_ item: WidgetTodoItem, overdue: Bool, large: Bool) -> String? {
        guard entry.filter != .inbox else { return nil }
        guard large || entry.filter == .all || overdue else { return nil }
        guard let dueDate = item.dueDate else { return nil }
        return WidgetDates.short(dueDate)
    }
}

// MARK: - Calendar

struct CalendarWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WidgetEntry

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
        let isCurrent: Bool
    }

    private var month: MonthModel {
        let calendar = Calendar.current
        let now = Date()
        let snapshotMonth = snapshot?.month
        let snapshotIsCurrent = (snapshotMonth?.year ?? 0) == calendar.component(.year, from: now)
            && (snapshotMonth?.month ?? 0) == calendar.component(.month, from: now)
        let year = snapshotIsCurrent ? (snapshotMonth?.year ?? 0) : calendar.component(.year, from: now)
        let month = snapshotIsCurrent ? (snapshotMonth?.month ?? 0) : calendar.component(.month, from: now)
        var first = DateComponents()
        first.year = year
        first.month = month
        first.day = 1
        let firstDate = calendar.date(from: first) ?? now
        let weekday = calendar.component(.weekday, from: firstDate)
        let firstWeekday = ((weekday + 5) % 7) + 1
        let range = calendar.range(of: .day, in: .month, for: firstDate)
        let daysInMonth = range?.count ?? 30
        let marks = Dictionary(
            uniqueKeysWithValues: (snapshotMonth?.days ?? []).map { ($0.day, $0) }
        )
        return MonthModel(
            year: year,
            month: month,
            firstWeekday: firstWeekday,
            todayDay: snapshotIsCurrent ? calendar.component(.day, from: now) : -1,
            daysInMonth: daysInMonth,
            marks: marks,
            isCurrent: snapshotIsCurrent
        )
    }

    private var selectedIso: String { WidgetCalendarState.selectedIso() }

    private var dayMode: Bool {
        !large && WidgetCalendarState.mode() == "day"
    }

    var body: some View {
        let model = month
        VStack(alignment: .leading, spacing: 4) {
            header(model: model)
            if !dayMode {
                weekdayHeader
                grid(model)
            }
            if large {
                Divider().overlay(palette.border)
                selectedDayList(model: model)
            } else if dayMode {
                dayHeader
                selectedDayList(model: model)
            }
        }
        .padding(large ? 10 : 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(for: .widget) { palette.background }
        .widgetURL(WidgetLinks.calendar(selectedIso))
    }

    private func header(model: MonthModel) -> some View {
        HStack(spacing: 4) {
            let staleSuffix: String = {
                guard model.isCurrent,
                      let snapshot,
                      snapshot.todayIso != WidgetDates.iso(Date())
                else { return "" }
                return " · \(ui?.stale ?? WidgetCopy.openToUpdate)"
            }()
            Link(destination: WidgetLinks.calendar(selectedIso)) {
                Text(WidgetDates.monthTitle(year: model.year, month: model.month) + staleSuffix)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.accent)
                    .lineLimit(1)
            }
            Spacer(minLength: 2)
            if selectedIso != WidgetDates.iso(Date()) {
                Button(intent: CalendarTodayIntent()) {
                    Text(ui?.today ?? WidgetCopy.today)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.accent)
                        .frame(minWidth: 32, minHeight: 28)
                }
                .buttonStyle(.plain)
            }
            Link(destination: WidgetLinks.newEvent(selectedIso)) {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(palette.accent)
                    .frame(width: 32, height: 28)
            }
        }
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
        let iso = isoFor(day: day, model: model)
        let isSelected = iso == selectedIso
        let dotColor: Color? = {
            if mark?.hasEvent == true || mark?.hasAllocation == true {
                return Color(hex: mark?.colors?.first) ?? palette.accent
            }
            if mark?.hasTodo == true { return palette.textSecondary }
            return nil
        }()
        return Button(intent: SelectCalendarDateIntent(dateIso: iso, enterDay: !large)) {
            VStack(spacing: 1) {
                Text("\(day)")
                    .font(.system(size: large ? 12 : 10, weight: isSelected || isToday ? .bold : .regular))
                    .foregroundStyle(isSelected || isToday ? palette.accent : palette.textPrimary)
                Circle()
                    .fill(dotColor ?? .clear)
                    .frame(width: large ? 4 : 3, height: large ? 4 : 3)
            }
            .frame(maxWidth: .infinity, minHeight: large ? 25 : 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(isSelected ? palette.accent.opacity(0.16) : .clear)
            )
        }
        .buttonStyle(.plain)
    }

    private func isoFor(day: Int, model: MonthModel) -> String {
        var components = DateComponents()
        components.year = model.year
        components.month = model.month
        components.day = day
        guard let date = Calendar.current.date(from: components) else {
            return WidgetDates.iso(Date())
        }
        return WidgetDates.iso(date)
    }

    private var dayHeader: some View {
        HStack(spacing: 8) {
            Button(intent: CalendarBackToMonthIntent()) {
                Text("‹ \(ui?.backToMonth ?? WidgetCopy.backToMonth)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(palette.accent)
                    .frame(minHeight: 28)
            }
            .buttonStyle(.plain)
            Text(WidgetDates.dayTitle(selectedIso))
                .font(.caption.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
        }
    }

    private func selectedDayList(model: MonthModel) -> some View {
        let day = Calendar.current.component(.day, from: WidgetDates.parse(selectedIso) ?? Date())
        let mark = model.marks[day]
        let items = mark?.items ?? []
        let limit = large ? 6 : 4
        return VStack(alignment: .leading, spacing: 2) {
            if !large && !dayMode {
                Text(WidgetDates.dayTitle(selectedIso))
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(palette.textSecondary)
            }
            if items.isEmpty {
                EmptyMessage(
                    text: model.isCurrent
                        ? (ui?.selectedDayEmpty ?? WidgetCopy.selectedDayEmpty)
                        : (ui?.openToUpdate ?? WidgetCopy.openToUpdate),
                    palette: palette
                )
            }
            ForEach(Array(items.prefix(limit).enumerated()), id: \.offset) { _, item in
                summaryRow(item)
            }
            if let itemCount = mark?.itemCount, itemCount > limit {
                Link(destination: WidgetLinks.calendar(selectedIso)) {
                    Text(ui?.withCount(ui?.moreCount, itemCount - limit) ?? "\(itemCount - limit)")
                        .font(.caption2)
                        .foregroundStyle(palette.accent)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder
    private func summaryRow(_ item: WidgetMonthItem) -> some View {
        let isDeadline = item.kind == "todoDeadline"
        let time: String = {
            if item.isAllDay == true { return ui?.allDay ?? WidgetCopy.allDay }
            if isDeadline && item.hasTime != true { return "□" }
            return item.start ?? ""
        }()
        let body = HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1)
                .fill(isDeadline ? palette.textSecondary : (Color(hex: item.color) ?? palette.accent))
                .frame(width: 3, height: 18)
            Text(time)
                .font(.system(size: 10))
                .foregroundStyle(palette.textSecondary)
                .frame(width: 48, alignment: .leading)
                .lineLimit(1)
            Text(item.summary)
                .font(.caption2)
                .foregroundStyle(palette.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .frame(minHeight: 24)

        if let url = WidgetLinks.detail(eventId: item.eventId, todoId: item.todoId) {
            Link(destination: url) { body }
        } else {
            body
        }
    }
}

// MARK: - Widget bundle

struct CalendarTodoWidget: Widget {
    let kind = "CalendarTodoWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
            ActionWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetCopy.galleryName(kind))
        .description(WidgetCopy.galleryDescription(kind))
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
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

struct CalendarTodosWidget: Widget {
    let kind = "CalendarTodosWidget"

    var body: some WidgetConfiguration {
        if #available(iOS 17.0, macOS 14.0, *) {
            return AppIntentConfiguration(
                kind: kind,
                intent: TodosConfigurationIntent.self,
                provider: TodosTimelineProvider()
            ) { entry in
                TodosWidgetView(entry: entry)
            }
            .configurationDisplayName(WidgetCopy.galleryName(kind))
            .description(WidgetCopy.galleryDescription(kind))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        } else {
            return StaticConfiguration(kind: kind, provider: SnapshotTimelineProvider()) { entry in
                TodosWidgetView(entry: TodosEntry(date: entry.date, snapshot: entry.snapshot, filter: .today))
            }
            .configurationDisplayName(WidgetCopy.galleryName(kind))
            .description(WidgetCopy.galleryDescription(kind))
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        }
    }
}

@main
struct CalendarTodoWidgetBundle: WidgetBundle {
    var body: some Widget {
        CalendarTodoWidget()
        CalendarMonthWidget()
        CalendarTodosWidget()
    }
}
