import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:dayspark/data/local/database/app_database.dart';
import 'package:dayspark/domain/providers/database_provider.dart';

/// Watch all tags.
final tagsProvider = StreamProvider<List<Tag>>((ref) {
  final db = ref.watch(databaseProvider);
  return (db.select(db.tags)..orderBy([(t) => OrderingTerm.asc(t.name)])).watch();
});

/// Tags for a specific event.
final eventTagsProvider =
    StreamProvider.family<List<Tag>, int>((ref, eventId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.tags).join([
    innerJoin(db.eventTags, db.eventTags.tagId.equalsExp(db.tags.id)),
  ])..where(db.eventTags.eventId.equals(eventId));

  return query.watch().map((rows) => rows.map((r) => r.readTable(db.tags)).toList());
});

/// Tags for a specific todo.
final todoTagsProvider =
    StreamProvider.family<List<Tag>, int>((ref, todoId) {
  final db = ref.watch(databaseProvider);
  final query = db.select(db.tags).join([
    innerJoin(db.todoTags, db.todoTags.tagId.equalsExp(db.tags.id)),
  ])..where(db.todoTags.todoId.equals(todoId));

  return query.watch().map((rows) => rows.map((r) => r.readTable(db.tags)).toList());
});

/// Create a new tag.
final createTagProvider =
    Provider<Future<int> Function({required String name, String? color})>(
        (ref) {
  final db = ref.watch(databaseProvider);
  return ({required name, color}) async {
    return db.into(db.tags).insert(TagsCompanion.insert(
          name: name,
          color: Value(color ?? '#6B7280'),
        ));
  };
});

/// Delete a tag.
final deleteTagProvider = Provider<Future<void> Function(int)>((ref) {
  final db = ref.watch(databaseProvider);
  return (int tagId) async {
    await (db.delete(db.eventTags)..where((t) => t.tagId.equals(tagId))).go();
    await (db.delete(db.todoTags)..where((t) => t.tagId.equals(tagId))).go();
    await (db.delete(db.tags)..where((t) => t.id.equals(tagId))).go();
  };
});

/// Assign a tag to an event.
final addTagToEventProvider =
    Provider<Future<void> Function({required int eventId, required int tagId})>(
        (ref) {
  final db = ref.watch(databaseProvider);
  return ({required eventId, required tagId}) async {
    await db.into(db.eventTags).insert(EventTagsCompanion.insert(
          eventId: eventId,
          tagId: tagId,
        ));
  };
});

/// Remove a tag from an event.
final removeTagFromEventProvider =
    Provider<Future<void> Function({required int eventId, required int tagId})>(
        (ref) {
  final db = ref.watch(databaseProvider);
  return ({required eventId, required tagId}) async {
    await (db.delete(db.eventTags)
          ..where((t) => t.eventId.equals(eventId) & t.tagId.equals(tagId)))
        .go();
  };
});

/// Assign a tag to a todo.
final addTagToTodoProvider =
    Provider<Future<void> Function({required int todoId, required int tagId})>(
        (ref) {
  final db = ref.watch(databaseProvider);
  return ({required todoId, required tagId}) async {
    await db.into(db.todoTags).insert(TodoTagsCompanion.insert(
          todoId: todoId,
          tagId: tagId,
        ));
  };
});

/// Remove a tag from a todo.
final removeTagFromTodoProvider =
    Provider<Future<void> Function({required int todoId, required int tagId})>(
        (ref) {
  final db = ref.watch(databaseProvider);
  return ({required todoId, required tagId}) async {
    await (db.delete(db.todoTags)
          ..where((t) => t.todoId.equals(todoId) & t.tagId.equals(tagId)))
        .go();
  };
});
