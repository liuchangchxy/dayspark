import 'package:flutter/material.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';

const double kDesktopDrawerBreakpoint = 1000.0;
const double kWideDesktopBreakpoint = 1180.0;
const double kDrawerWidthWide = 380.0;
const double kDrawerWidthNarrow = 360.0;

bool canShowDesktopDrawer(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= kDesktopDrawerBreakpoint;

double specDrawerWidth(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return width >= kWideDesktopBreakpoint ? kDrawerWidthWide : kDrawerWidthNarrow;
}

/// A reusable overlay drawer shell (.drawer.overlay).
///
/// Features:
/// - Absolute positioning at `right: 0, top: 0, bottom: 0`
/// - Width: 380 on wide desktop (>= 1180), 360 on narrow desktop (1000-1179)
/// - Left hairline border and box-shadow `-16px 0 46px rgba(25,25,24,.10)`
/// - Background #ffffff
/// - Overlays list without squeezing it
class SpecDrawerOverlay extends StatelessWidget {
  const SpecDrawerOverlay({
    super.key,
    required this.child,
    this.width,
    this.onClose,
  });

  final Widget child;
  final double? width;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final resolvedWidth = width ?? specDrawerWidth(context);

    return Positioned(
      key: const ValueKey('spec-drawer-overlay-positioned'),
      top: 0,
      right: 0,
      bottom: 0,
      width: resolvedWidth,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {}, // Prevent taps inside drawer from bubbling to blank-area dismisser
        child: Material(
          color: SpecTokens.paper,
          child: Container(
            key: const ValueKey('spec-drawer-overlay'),
            decoration: const BoxDecoration(
              color: SpecTokens.paper,
              border: Border(
                left: BorderSide(color: SpecTokens.hair, width: 1.0),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(25, 25, 24, 0.10),
                  offset: Offset(-16, 0),
                  blurRadius: 46,
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
