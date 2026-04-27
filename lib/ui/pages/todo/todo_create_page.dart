import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:rrule_generator/rrule_generator.dart';
import 'package:dayspark/core/utils/color_utils.dart';
import 'package:dayspark/core/utils/date_formatters.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/tags_provider.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';

class TodoCreatePage extends ConsumerStatefulWidget {
  const TodoCreatePage({super.key});

  @override
  ConsumerState<TodoCreatePage> createState() => _TodoCreatePageState();
}

class _TodoCreatePageState extends ConsumerState<TodoCreatePage> {
  final _summaryController = TextEditingController();
  final _descriptionController = TextEditingController();
  DateTime? _dueDate;
  DateTime? _startDate;
  int _priority = 5;
  bool _saving = false;
  bool _aiLoading = false;
  String? _rrule;
  int? _selectedCalendarId;
  final Set<int> _selectedTagIds = {};

  static const _priorityValues = [0, 9, 5, 1];

  @override
  void dispose() {
    _summaryController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    // Pre-select first calendar
    Future.microtask(() async {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isNotEmpty && mounted) {
        setState(() => _selectedCalendarId = calendars.first.id);
      }
    });
  }

  Future<void> _save() async {
    final l = AppLocalizations.of(context)!;
    if (_summaryController.text.trim().isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l.enterTitle)));
      return;
    }

    setState(() => _saving = true);
    try {
      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(l.noCalendar)));
        }
        return;
      }

      final calendarId = _selectedCalendarId ?? calendars.first.id;
      final todoId = await ref
          .read(createTodoProvider)
          .call(
            calendarId: calendarId,
            uid: 'local-todo-${DateTime.now().millisecondsSinceEpoch}',
            summary: _summaryController.text.trim(),
            priority: _priority,
            status: 'NEEDS-ACTION',
            dueDate: _dueDate,
            startDate: _startDate,
            description: _descriptionController.text.trim().isNotEmpty
                ? _descriptionController.text.trim()
                : null,
            rrule: _rrule,
          );

      // Assign selected tags
      for (final tagId in _selectedTagIds) {
        try {
          await ref.read(addTagToTodoProvider)(todoId: todoId, tagId: tagId);
        } catch (_) {}
      }

      // Add default reminders
      try {
        await ref.read(addDefaultTodoRemindersProvider)(
          todoId: todoId,
          dueDate: _dueDate,
        );
      } catch (_) {}

      if (mounted) context.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.error('$e'))));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _setQuickDate(DateTime date) {
    setState(() => _dueDate = DateTime(date.year, date.month, date.day));
  }

  Future<void> _pickCustomDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _dueDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => _dueDate = date);
    }
  }

  Future<void> _pickStartDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _startDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date != null && mounted) {
      setState(() => _startDate = date);
    }
  }

  Future<void> _aiParse() async {
    final l = AppLocalizations.of(context)!;
    final text = _summaryController.text.trim();
    if (text.isEmpty) return;

    final config = ref.read(aiConfigProvider).value;
    if (config == null) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.notConfigured)));
      }
      return;
    }

    setState(() => _aiLoading = true);
    try {
      final result = await parseNaturalLanguage(
        config: config,
        input: text,
        type: 'todo',
      );
      if (mounted) {
        setState(() {
          if (result['summary'] != null) {
            _summaryController.text = result['summary'] as String;
          }
          if (result['due_date'] != null) {
            _dueDate = DateTime.parse(result['due_date'] as String);
          }
          if (result['priority'] != null) {
            _priority = result['priority'] as int;
          }
          if (result['description'] != null) {
            _descriptionController.text = result['description'] as String;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.aiError('$e'))));
      }
    } finally {
      if (mounted) setState(() => _aiLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final priorityLabels = {
      0: l.priorityNone,
      9: l.priorityLow,
      5: l.priorityMedium,
      1: l.priorityHigh,
    };
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.xmark),
          onPressed: () => context.pop(),
        ),
        title: Text(l.newTodo),
        actions: [
          IconButton(
            onPressed: _aiLoading ? null : _aiParse,
            icon: _aiLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(CupertinoIcons.sparkles),
            tooltip: 'AI parse',
          ),
          TextButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l.save),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Title
          TextField(
            controller: _summaryController,
            decoration: InputDecoration(
              labelText: l.title,
              border: const OutlineInputBorder(),
            ),
            textCapitalization: TextCapitalization.sentences,
            autofocus: true,
          ),
          const SizedBox(height: 16),

          // Calendar picker
          _buildCalendarPicker(l),
          const SizedBox(height: 16),

          // Start date
          ListTile(
            leading: const Icon(CupertinoIcons.play),
            title: Text(l.startDate),
            subtitle: _startDate != null
                ? Text(DateFormatters.formatDate(_startDate!))
                : Text(l.notSet),
            onTap: _pickStartDate,
            trailing: _startDate != null
                ? IconButton(
                    icon: const Icon(CupertinoIcons.clear, size: 18),
                    onPressed: () => setState(() => _startDate = null),
                  )
                : null,
            contentPadding: EdgeInsets.zero,
          ),

          // Due date with quick options
          const SizedBox(height: 8),
          ListTile(
            leading: const Icon(CupertinoIcons.calendar),
            title: Text(l.dueDate),
            subtitle: _dueDate != null
                ? Text(DateFormatters.formatDate(_dueDate!))
                : Text(l.notSet),
            onTap: _pickCustomDate,
            trailing: _dueDate != null
                ? IconButton(
                    icon: const Icon(CupertinoIcons.clear, size: 18),
                    onPressed: () => setState(() => _dueDate = null),
                  )
                : null,
            contentPadding: EdgeInsets.zero,
          ),
          const SizedBox(height: 8),

          // Quick date chips
          _buildQuickDateChips(l, now),
          const SizedBox(height: 16),

          // Priority
          Text(
            l.priority,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 4),
          SegmentedButton<int>(
            showSelectedIcon: false,
            segments: _priorityValues
                .map(
                  (v) =>
                      ButtonSegment(value: v, label: Text(priorityLabels[v]!)),
                )
                .toList(),
            selected: {_priority},
            onSelectionChanged: (s) => setState(() => _priority = s.first),
            style: ButtonStyle(
              visualDensity: VisualDensity.compact,
              textStyle: WidgetStatePropertyAll(
                Theme.of(context).textTheme.labelSmall,
              ),
            ),
          ),
          const SizedBox(height: 16),

          // Description
          TextField(
            controller: _descriptionController,
            decoration: InputDecoration(
              labelText: l.description,
              border: const OutlineInputBorder(),
            ),
            maxLines: 3,
            textCapitalization: TextCapitalization.sentences,
          ),
          const SizedBox(height: 16),

          // Tags
          _buildTagSelector(l),
          const SizedBox(height: 16),

          // Recurrence rule
          RRuleGenerator(
            locale: RRuleLocale.zh_CN,
            config: RRuleGeneratorConfig(),
            initialRRule: _rrule ?? '',
            withExcludeDates: false,
            onChange: (String rrule) {
              setState(() {
                _rrule = rrule.isEmpty ? null : rrule;
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarPicker(AppLocalizations l) {
    final calendarsAsync = ref.watch(calendarsProvider);
    return calendarsAsync.when(
      data: (calendars) {
        if (calendars.length <= 1) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l.calendar,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            DropdownButtonFormField<int>(
              initialValue: _selectedCalendarId ?? calendars.first.id,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                isDense: true,
                contentPadding: EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
              ),
              items: calendars.map((c) {
                final color = ColorUtils.parseHex(c.color);
                return DropdownMenuItem(
                  value: c.id,
                  child: Row(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(c.name),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (id) {
                if (id != null) setState(() => _selectedCalendarId = id);
              },
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildQuickDateChips(AppLocalizations l, DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final tomorrow = today.add(const Duration(days: 1));
    final dayAfter = today.add(const Duration(days: 2));
    final nextWeek = today.add(const Duration(days: 7));

    return Wrap(
      spacing: 8,
      runSpacing: 6,
      children: [
        _quickChip(l.today, today),
        _quickChip(l.tomorrow, tomorrow),
        _quickChip(l.dayAfterTomorrow, dayAfter),
        _quickChip(l.nextWeek, nextWeek),
        ActionChip(
          label: Text(l.custom),
          avatar: const Icon(CupertinoIcons.calendar, size: 14),
          onPressed: _pickCustomDate,
        ),
      ],
    );
  }

  Widget _quickChip(String label, DateTime date) {
    final isToday =
        _dueDate != null &&
        _dueDate!.year == date.year &&
        _dueDate!.month == date.month &&
        _dueDate!.day == date.day;

    return ChoiceChip(
      label: Text(label),
      selected: isToday,
      onSelected: (_) => _setQuickDate(date),
    );
  }

  Widget _buildTagSelector(AppLocalizations l) {
    final tagsAsync = ref.watch(tagsProvider);
    return tagsAsync.when(
      data: (allTags) {
        if (allTags.isEmpty) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                const Icon(CupertinoIcons.tag, size: 16, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  l.noTags,
                  style: const TextStyle(color: Colors.grey, fontSize: 13),
                ),
                TextButton(
                  onPressed: () => context.push('/tags'),
                  child: Text(l.createTag),
                ),
              ],
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  l.tags,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => context.push('/tags'),
                  child: Text(
                    l.manageTags,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: allTags.map((tag) {
                final isSelected = _selectedTagIds.contains(tag.id);
                return FilterChip(
                  label: Text(tag.name),
                  selected: isSelected,
                  selectedColor: ColorUtils.parseHex(
                    tag.color,
                  ).withValues(alpha: 0.3),
                  checkmarkColor: ColorUtils.parseHex(tag.color),
                  onSelected: (selected) {
                    setState(() {
                      if (selected) {
                        _selectedTagIds.add(tag.id);
                      } else {
                        _selectedTagIds.remove(tag.id);
                      }
                    });
                  },
                );
              }).toList(),
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
