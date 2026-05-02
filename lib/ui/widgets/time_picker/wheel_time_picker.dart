import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:dayspark/l10n/app_localizations.dart';

/// Shows a bottom sheet with a Cupertino-style scroll wheel time picker
/// plus an optional text input field.
Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    builder: (ctx) => _WheelTimePickerSheet(initialTime: initialTime),
  );
}

class _WheelTimePickerSheet extends StatefulWidget {
  final TimeOfDay initialTime;
  const _WheelTimePickerSheet({required this.initialTime});

  @override
  State<_WheelTimePickerSheet> createState() => _WheelTimePickerSheetState();
}

class _WheelTimePickerSheetState extends State<_WheelTimePickerSheet> {
  late TimeOfDay _selectedTime;
  final _textController = TextEditingController();
  bool _showTextInput = false;

  @override
  void initState() {
    super.initState();
    _selectedTime = widget.initialTime;
    _textController.text =
        '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _onChanged(DateTime dateTime) {
    setState(() {
      _selectedTime = TimeOfDay(hour: dateTime.hour, minute: dateTime.minute);
      _textController.text =
          '${_selectedTime.hour.toString().padLeft(2, '0')}:${_selectedTime.minute.toString().padLeft(2, '0')}';
    });
  }

  void _applyTextInput() {
    final parts = _textController.text.split(':');
    if (parts.length == 2) {
      final h = int.tryParse(parts[0]);
      final m = int.tryParse(parts[1]);
      if (h != null && m != null && h >= 0 && h < 24 && m >= 0 && m < 60) {
        setState(() => _selectedTime = TimeOfDay(hour: h, minute: m));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l = AppLocalizations.of(context)!;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(l.cancel),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(_selectedTime),
                  child: Text(
                    l.ok,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Wheel picker
          SizedBox(
            height: 200,
            child: CupertinoDatePicker(
              mode: CupertinoDatePickerMode.time,
              initialDateTime: DateTime(
                DateTime.now().year,
                1,
                1,
                widget.initialTime.hour,
                widget.initialTime.minute,
              ),
              onDateTimeChanged: _onChanged,
              use24hFormat: true,
            ),
          ),
          // Keyboard input toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  l.keyboardInput,
                  style: TextStyle(fontSize: 14, color: theme.hintColor),
                ),
                const Spacer(),
                IconButton(
                  icon: Icon(
                    _showTextInput
                        ? CupertinoIcons.keyboard_chevron_compact_down
                        : CupertinoIcons.keyboard,
                    size: 20,
                  ),
                  onPressed: () =>
                      setState(() => _showTextInput = !_showTextInput),
                ),
              ],
            ),
          ),
          if (_showTextInput)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: TextField(
                controller: _textController,
                decoration: InputDecoration(
                  hintText: l.timeHint,
                  isDense: true,
                ),
                keyboardType: TextInputType.datetime,
                onSubmitted: (_) => _applyTextInput(),
              ),
            ),
        ],
      ),
    );
  }
}
