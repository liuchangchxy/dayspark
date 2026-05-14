import 'package:flutter/material.dart';

class CalendarScrollablePage extends StatefulWidget {
  final double targetOffset;
  final double totalHeight;
  final Widget child;

  const CalendarScrollablePage({
    super.key,
    required this.targetOffset,
    required this.totalHeight,
    required this.child,
  });

  @override
  State<CalendarScrollablePage> createState() => _CalendarScrollablePageState();
}

class _CalendarScrollablePageState extends State<CalendarScrollablePage> {
  final _controller = ScrollController(keepScrollOffset: false);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_controller.hasClients) {
        final max = _controller.position.maxScrollExtent;
        _controller.jumpTo(widget.targetOffset.clamp(0, max));
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      child: SizedBox(
        height: widget.totalHeight,
        child: widget.child,
      ),
    );
  }
}
