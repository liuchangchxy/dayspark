import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dayspark/domain/providers/ai_provider.dart';
import 'package:dayspark/domain/providers/ai_scheduler_provider.dart';
import 'package:dayspark/domain/providers/events_provider.dart';
import 'package:dayspark/domain/providers/todos_provider.dart';
import 'package:dayspark/domain/providers/reminders_provider.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/ui/widgets/ai_config_dialog.dart';

class AiChatPage extends ConsumerStatefulWidget {
  const AiChatPage({super.key});

  @override
  ConsumerState<AiChatPage> createState() => _AiChatPageState();
}

class _AiChatPageState extends ConsumerState<AiChatPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;

    _controller.clear();
    setState(() => _sending = true);

    await ref.read(aiChatProvider.notifier).sendMessage(text);

    setState(() => _sending = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context)!;
    final messages = ref.watch(aiChatProvider);
    final isConfigured = ref.watch(isAiConfiguredProvider).value ?? false;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(CupertinoIcons.back),
          onPressed: () => context.pop(),
        ),
        title: Text(l.aiAssistant),
        actions: [
          if (messages.isNotEmpty)
            IconButton(
              icon: const Icon(CupertinoIcons.delete),
              onPressed: () => ref.read(aiChatProvider.notifier).clear(),
              tooltip: l.clearChat,
            ),
        ],
      ),
      body: isConfigured
          ? Column(
              children: [
                Expanded(
                  child: messages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  CupertinoIcons.sparkles,
                                  size: 48,
                                  color: Theme.of(context).disabledColor,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  l.aiHint,
                                  style: Theme.of(context).textTheme.bodyLarge,
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  l.aiExample,
                                  style: Theme.of(context).textTheme.bodySmall,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(16),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final msg = messages[index];
                            final isUser = msg.role == 'user';
                            return Align(
                              alignment: isUser
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.75,
                                ),
                                decoration: BoxDecoration(
                                  color: isUser
                                      ? Theme.of(context).colorScheme.primary
                                            .withValues(alpha: 0.1)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    SelectableText(
                                      msg.content,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                    if (!isUser) ...[
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          _QuickActionChip(
                                            icon: CupertinoIcons
                                                .calendar_badge_plus,
                                            label: l.addEventShort,
                                            onTap: () => _tryCreateFromChat(
                                              ref,
                                              msg.content,
                                              'event',
                                            ),
                                          ),
                                          _QuickActionChip(
                                            icon: CupertinoIcons
                                                .checkmark_rectangle,
                                            label: l.addTodoShort,
                                            onTap: () => _tryCreateFromChat(
                                              ref,
                                              msg.content,
                                              'todo',
                                            ),
                                          ),
                                          _QuickActionChip(
                                            icon: CupertinoIcons.clock,
                                            label: l.schedule,
                                            onTap: () => _suggestSchedule(
                                              context,
                                              ref,
                                              msg.content,
                                            ),
                                          ),
                                          _QuickActionChip(
                                            icon: CupertinoIcons
                                                .checkmark_rectangle,
                                            label: l.breakDown,
                                            onTap: () => _breakDownTask(
                                              context,
                                              ref,
                                              msg.content,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
                SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _controller,
                            decoration: InputDecoration(
                              hintText: l.typeMessage,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(24),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                            ),
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          onPressed: _sending ? null : _send,
                          icon: _sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(CupertinoIcons.arrow_up_circle_fill),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.chat_bubble_2,
                      size: 48,
                      color: Theme.of(context).disabledColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      l.aiNotConfigured,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 16),
                    FilledButton.icon(
                      onPressed: () => showAiConfigDialog(context, ref),
                      icon: const Icon(CupertinoIcons.settings, size: 18),
                      label: Text(l.aiConfig),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _suggestSchedule(
    BuildContext context,
    WidgetRef ref,
    String content,
  ) async {
    final l = AppLocalizations.of(context)!;
    try {
      final now = DateTime.now();
      final suggestions = await ref.read(suggestTimeSlotsProvider)(
        taskDescription: content,
        rangeStart: now,
        rangeEnd: now.add(const Duration(days: 7)),
      );
      if (!context.mounted) return;
      if (suggestions.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.noTimeSlots)));
        return;
      }
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.suggestedTimeSlots),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: suggestions.map((s) {
                final startStr = s['start'] as String? ?? '';
                final endStr = s['end'] as String? ?? '';
                return ListTile(
                  title: Text('$startStr - $endStr'),
                  subtitle: s['reason'] != null
                      ? Text(s['reason'] as String)
                      : null,
                  onTap: () {
                    Navigator.of(ctx).pop();
                    // Navigate to event creation with the suggested time
                    final start = startStr.isNotEmpty
                        ? DateTime.tryParse(startStr)
                        : null;
                    final end = endStr.isNotEmpty
                        ? DateTime.tryParse(endStr)
                        : null;
                    context.push(
                      '/event/new'
                      '?start=${start?.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch}'
                      '&end=${end?.millisecondsSinceEpoch ?? DateTime.now().add(const Duration(hours: 1)).millisecondsSinceEpoch}',
                    );
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.schedulingFailed('$e'))));
      }
    }
  }

  Future<void> _breakDownTask(
    BuildContext context,
    WidgetRef ref,
    String content,
  ) async {
    final l = AppLocalizations.of(context)!;
    try {
      final subtasks = await ref.read(suggestTaskBreakdownProvider)(content);
      if (!context.mounted) return;
      if (subtasks.isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.noSubtasks)));
        return;
      }
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(l.taskBreakdown),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: subtasks.map((s) {
                return ListTile(
                  leading: const Icon(
                    CupertinoIcons.checkmark_circle,
                    size: 20,
                  ),
                  title: Text(s),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    // Create the todo directly
                    try {
                      final calendars = await ref.read(
                        calendarsProvider.future,
                      );
                      if (calendars.isEmpty) return;
                      final calId = calendars.first.id;
                      final todoId = await ref
                          .read(createTodoProvider)
                          .call(
                            calendarId: calId,
                            uid:
                                'ai-todo-${DateTime.now().millisecondsSinceEpoch}',
                            summary: s,
                            priority: 5,
                            status: 'NEEDS-ACTION',
                          );
                      try {
                        await ref.read(addDefaultTodoRemindersProvider)(
                          todoId: todoId,
                          dueDate: null,
                        );
                      } catch (_) {}
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.todoCreatedShort)),
                        );
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l.failedCreateTodo('$e'))),
                        );
                      }
                    }
                  },
                );
              }).toList(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(l.cancel),
            ),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.breakdownFailed('$e'))));
      }
    }
  }

  Future<void> _tryCreateFromChat(
    WidgetRef ref,
    String content,
    String type,
  ) async {
    final config = ref.read(aiConfigProvider).value;
    if (config == null) return;

    // Find the user message that prompted this response
    final messages = ref.read(aiChatProvider);
    var input = content;
    final idx = messages.indexWhere((m) => m.content == content);
    if (idx > 0) input = messages[idx - 1].content;

    try {
      final result = await parseNaturalLanguage(
        config: config,
        input: input,
        type: type,
      );

      final calendars = await ref.read(calendarsProvider.future);
      if (calendars.isEmpty) return;
      final calId = calendars.first.id;

      if (type == 'event') {
        final start = result['start'] != null
            ? DateTime.parse(result['start'] as String)
            : DateTime.now();
        final end = result['end'] != null
            ? DateTime.parse(result['end'] as String)
            : start.add(const Duration(hours: 1));
        final eventId = await ref.read(createEventProvider)(
          calendarId: calId,
          uid: 'ai-${DateTime.now().millisecondsSinceEpoch}',
          summary: result['summary'] as String? ?? 'New Event',
          startDt: start,
          endDt: end,
          isAllDay: result['is_all_day'] == true,
          description: result['description'] as String?,
          location: result['location'] as String?,
        );
        try {
          await ref.read(addDefaultEventRemindersProvider)(
            eventId: eventId,
            startDt: start,
          );
        } catch (_) {}
      } else {
        final dueDate = result['due_date'] != null
            ? DateTime.parse(result['due_date'] as String)
            : null;
        final todoId = await ref
            .read(createTodoProvider)
            .call(
              calendarId: calId,
              uid: 'ai-todo-${DateTime.now().millisecondsSinceEpoch}',
              summary: result['summary'] as String? ?? 'New Todo',
              priority: result['priority'] as int? ?? 5,
              status: 'NEEDS-ACTION',
              dueDate: dueDate,
              description: result['description'] as String?,
            );
        try {
          await ref.read(addDefaultTodoRemindersProvider)(
            todoId: todoId,
            dueDate: dueDate,
          );
        } catch (_) {}
      }

      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              type == 'event' ? l.eventCreatedShort : l.todoCreatedShort,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        final l = AppLocalizations.of(context)!;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l.failedAction('$e'))));
      }
    }
  }
}

class _QuickActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _QuickActionChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
