# Phase 3: CalDAV Sync Engine Implementation Plan
> ⚠️ **已过时（2026-09-27 标注，正文原样保留仅供考古）**：本文是 2026-04 项目早期的方案讨论，CalDAV 路线已被自研同步后端替代（v0.22.0 落地），内容不再维护。现行状态唯一源：`calendar_todo_app/docs/START_HERE.md`（接续入口）、`calendar_todo_app/docs/ROADMAP.md`（功能全景）。

**Goal:** 实现 CalDAV 同步引擎——连接 CalDAV 服务器，双向同步日历事件和待办。

**Architecture:** 自建 CalDAV 客户端基于 Dio，用 `enough_icalendar` 解析/生成 iCalendar 数据，`xml` 包处理 CalDAV XML 响应。离线优先：本地 Drift 为数据源，同步服务协调上下行。

**Tech Stack:** Dio / enough_icalendar / xml / Drift / Riverpod

---

## Task 1: Add Dependencies
- Add `enough_icalendar: ^0.17.0` and `xml: ^6.5.0` to pubspec.yaml
- Run `flutter pub get`

## Task 2: CalDAV Client
- Create `lib/data/remote/caldav/caldav_client.dart`
- HTTP methods: PROPFIND (calendar discovery), REPORT (query events/todos), PUT (create/update), DELETE
- Basic auth support via Dio headers
- Parse XML multistatus responses using `xml` package
- Methods: discoverCalendars, getEvents, getTodos, createObject, updateObject, deleteObject

## Task 3: iCalendar Converter
- Create `lib/data/remote/caldav/ical_converter.dart`
- Convert Drift Event → iCalendar VEVENT string
- Convert Drift Todo → iCalendar VTODO string
- Convert iCalendar VEVENT → Drift EventsCompanion
- Convert iCalendar VTODO → Drift TodosCompanion
- Handle RRULE, DTSTART, DTEND, DUE, PRIORITY, STATUS, etc.

## Task 4: Sync Service
- Create `lib/data/remote/caldav/sync_service.dart`
- Full sync: pull all events/todos from server, push local dirty ones
- Incremental sync: use sync-token / ctag to detect changes
- Conflict resolution: server wins (simplest)
- Track sync state in Calendars table (syncToken, lastSyncedAt)

## Task 5: Sync Providers
- Create `lib/domain/providers/sync_provider.dart`
- Providers: syncStatusProvider, syncServiceProvider
- Trigger sync manually or on app start
- Update events/todos providers after sync

## Task 6: CalDAV Settings UI
- Update `lib/ui/pages/settings/settings_page.dart`
- Add CalDAV account configuration: URL, username, password
- Use flutter_secure_storage for credentials
- Add sync status display (last sync time, sync button)

## Task 7: Router & Integration
- Update router if needed for new settings sub-pages
- Wire sync into app lifecycle (sync on app start)

## Task 8: Tests
- Test CalDavClient XML parsing
- Test IcalConverter (Drift ↔ iCalendar)
- Test SyncService (with mock CalDavClient)
- Test providers

## Task 9: Verification
- Run all tests
- Verify web build
