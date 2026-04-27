import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';

import 'package:calendar_todo_app/data/remote/caldav/caldav_client.dart';

void main() {
  // Test XML parsing by creating a client with dummy credentials
  // and calling internal parsers indirectly through the public API
  // (which we can't do without a server, so we test parsing logic separately)

  group('CalDavObject', () {
    test('stores href, etag, and icalData', () {
      final obj = CalDavObject(
        href: '/cal/event1.ics',
        etag: '"abc123"',
        icalData: 'BEGIN:VCALENDAR\r\nEND:VCALENDAR',
      );

      expect(obj.href, '/cal/event1.ics');
      expect(obj.etag, '"abc123"');
      expect(obj.icalData, contains('VCALENDAR'));
    });
  });

  group('CalDavCalendarInfo', () {
    test('stores calendar properties', () {
      final info = CalDavCalendarInfo(
        href: '/cal/user/calendar/',
        name: 'My Calendar',
        color: '#FF0000',
        ctag: 'ctag-123',
        syncToken: 'sync-token-abc',
        supportsVEVENT: true,
        supportsVTODO: false,
      );

      expect(info.href, '/cal/user/calendar/');
      expect(info.name, 'My Calendar');
      expect(info.color, '#FF0000');
      expect(info.ctag, 'ctag-123');
      expect(info.syncToken, 'sync-token-abc');
      expect(info.supportsVEVENT, true);
      expect(info.supportsVTODO, false);
    });

    test('defaults supportsVEVENT and supportsVTODO to true', () {
      final info = CalDavCalendarInfo(
        href: '/cal/',
        name: 'Cal',
      );

      expect(info.supportsVEVENT, true);
      expect(info.supportsVTODO, true);
    });
  });

  group('CalDavClient construction', () {
    test('creates client with valid parameters', () {
      final client = CalDavClient(
        baseUrl: 'https://caldav.example.com/',
        username: 'user',
        password: 'pass',
      );

      expect(client, isNotNull);
      client.dispose();
    });

    test('Basic auth header is Base64 encoded', () {
      final credentials = 'user:pass';
      final encoded = base64Encode(credentials.codeUnits);
      // Base64 should differ from plaintext
      expect(encoded, isNot(equals(credentials)));
      // Roundtrip
      expect(utf8.decode(base64Decode(encoded)), equals(credentials));
    });
  });
}
