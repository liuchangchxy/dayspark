import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dayspark/core/theme/spec_tokens.dart';

void main() {
  group('SpecTokens', () {
    test('color values match frozen spec', () {
      expect(SpecTokens.ink, const Color(0xFF191918));
      expect(SpecTokens.ink2, const Color(0xFF45453F));
      expect(SpecTokens.muted, const Color(0xFF6E6E66));
      expect(SpecTokens.faint, const Color(0xFF8B8B82));
      expect(SpecTokens.hair, const Color(0xFFECECE6));
      expect(SpecTokens.hair2, const Color(0xFFDEDED7));
      expect(SpecTokens.wash, const Color(0xFFF7F7F4));
      expect(SpecTokens.paper, const Color(0xFFFFFFFF));
      expect(SpecTokens.work, const Color(0xFF5F7183));
      expect(SpecTokens.workSoft, const Color(0xFFF1F3F4));
      expect(SpecTokens.amber, const Color(0xFF9A6A18));
      expect(SpecTokens.amberSoft, const Color(0xFFF7EEDB));
      expect(SpecTokens.red, const Color(0xFFC92A1E));
      expect(SpecTokens.redSoft, const Color(0xFFFDF3F1));
      expect(SpecTokens.scheduleBlue, const Color(0xFF4F7BBF));
      expect(SpecTokens.scheduleBlueSoft, const Color(0xFFDCE7F7));
    });

    test('type scale sizes match frozen spec', () {
      expect(SpecTokens.t26.fontSize, 26.0);
      expect(SpecTokens.t20.fontSize, 20.0);
      expect(SpecTokens.t15.fontSize, 15.0);
      expect(SpecTokens.t13.fontSize, 13.0);
      expect(SpecTokens.t11.fontSize, 11.0);
      expect(SpecTokens.t95.fontSize, 9.5);
    });

    test('radii and hairline match frozen spec', () {
      expect(SpecTokens.r6, 6.0);
      expect(SpecTokens.r8, 8.0);
      expect(SpecTokens.r12, 12.0);
      expect(SpecTokens.hairlineWidth, 1.0);
      expect(SpecTokens.shadow.first.blurRadius, 50.0);
      expect(SpecTokens.shadow.first.offset, const Offset(0, 18.0));
    });
  });
}
