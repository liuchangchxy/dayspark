import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dayspark/l10n/app_localizations.dart';
import 'package:dayspark/core/theme/app_spacing.dart';
import 'package:dayspark/core/theme/app_theme.dart';
import 'package:dayspark/core/theme/app_typography.dart';
import 'package:dayspark/ui/design/ds.dart';
import 'package:dayspark/ui/design/spec_pickers.dart';

/// Shows a bottom sheet with a Cupertino-style scroll wheel time picker
/// plus an optional text input field.
Future<TimeOfDay?> showWheelTimePicker(
  BuildContext context, {
  required TimeOfDay initialTime,
}) {
  if (defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS) {
    return showSpecTimePicker(context, initialTime: initialTime);
  }
  return showModalBottomSheet<TimeOfDay>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: context.ds.scrim,
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
    final ds = context.ds;
    final l = AppLocalizations.of(context)!;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        decoration: BoxDecoration(
          color: ds.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          border: Border(top: BorderSide(color: ds.line)),
          boxShadow: AppShadows.sheet(ds.brightness),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DsSheetChrome(title: l.dueTime),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4,
                  0,
                  AppSpacing.s4,
                  AppSpacing.s3,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
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
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.s2,
                      ),
                      child: Row(
                        children: [
                          Text(
                            l.keyboardInput,
                            style: AppTypography.body.copyWith(color: ds.ink3),
                          ),
                          const Spacer(),
                          DsIconButton(
                            icon: _showTextInput
                                ? CupertinoIcons
                                      .keyboard_chevron_compact_down
                                : CupertinoIcons.keyboard,
                            selected: _showTextInput,
                            onPressed: () => setState(
                              () => _showTextInput = !_showTextInput,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_showTextInput)
                      DsTextField(
                        controller: _textController,
                        hint: l.timeHint,
                        keyboardType: TextInputType.datetime,
                        onSubmitted: (_) => _applyTextInput(),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4,
                  AppSpacing.s2,
                  AppSpacing.s4,
                  AppSpacing.s2,
                ),
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: ds.lineSoft)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: DsButton(
                        label: l.cancel,
                        tone: DsButtonTone.secondary,
                        expand: true,
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Expanded(
                      child: DsButton(
                        label: l.ok,
                        expand: true,
                        onPressed: () =>
                            Navigator.of(context).pop(_selectedTime),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
