import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:xml/xml.dart';

/// A single calendar discovered from the CalDAV server.
class CalDavCalendarInfo {
  final String href;
  final String name;
  final String? color;
  final String? ctag;
  final String? syncToken;
  final bool supportsVEVENT;
  final bool supportsVTODO;

  CalDavCalendarInfo({
    required this.href,
    required this.name,
    this.color,
    this.ctag,
    this.syncToken,
    this.supportsVEVENT = true,
    this.supportsVTODO = true,
  });
}

/// A CalDAV object (event or todo) fetched from the server.
class CalDavObject {
  final String href;
  final String? etag;
  final String icalData;

  CalDavObject({
    required this.href,
    this.etag,
    required this.icalData,
  });
}

/// Raw CalDAV client using Dio for HTTP and xml package for XML parsing.
class CalDavClient {
  final Dio _dio;

  CalDavClient({
    required String baseUrl,
    required String username,
    required String password,
  }) : _dio = Dio(BaseOptions(
          baseUrl: baseUrl,
          headers: {
            'Authorization':
                'Basic ${_encodeBasicAuth(username, password)}',
            'Content-Type': 'application/xml; charset=utf-8',
          },
          responseType: ResponseType.plain,
        ));

  static String _encodeBasicAuth(String username, String password) {
    final credentials = '$username:$password';
    return base64Encode(credentials.codeUnits);
  }

  // ── Calendar Discovery ──────────────────────────────────────────

  /// PROPFIND to discover calendars for the current user.
  Future<List<CalDavCalendarInfo>> discoverCalendars({
    String path = '/',
  }) async {
    final body = _buildPropfindBody();
    final response = await _dio.request<String>(
      path,
      data: body,
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '1'},
      ),
    );

    return _parseMultistatusCalendars(response.data!);
  }

  /// Get calendar metadata (ctag, syncToken) for a specific calendar.
  Future<CalDavCalendarInfo> getCalendarMeta(String calendarHref) async {
    final body = _buildCalendarPropBody();
    final response = await _dio.request<String>(
      calendarHref,
      data: body,
      options: Options(
        method: 'PROPFIND',
        headers: {'Depth': '0'},
      ),
    );

    final calendars = _parseMultistatusCalendars(response.data!);
    if (calendars.isEmpty) {
      throw Exception('No calendar metadata returned for $calendarHref');
    }
    return calendars.first;
  }

  // ── Fetch Objects ───────────────────────────────────────────────

  /// REPORT: fetch all VEVENT objects in a calendar.
  Future<List<CalDavObject>> getEvents(String calendarHref) async {
    return _reportCalendarQuery(
      calendarHref: calendarHref,
      filterComponent: 'VEVENT',
    );
  }

  /// REPORT: fetch all VTODO objects in a calendar.
  Future<List<CalDavObject>> getTodos(String calendarHref) async {
    return _reportCalendarQuery(
      calendarHref: calendarHref,
      filterComponent: 'VTODO',
    );
  }

  /// REPORT: fetch objects that changed since a sync-token.
  Future<List<CalDavObject>> getChanges(
    String calendarHref,
    String syncToken,
  ) async {
    final body = _buildSyncCollectionBody(syncToken);
    final response = await _dio.request<String>(
      calendarHref,
      data: body,
      options: Options(
        method: 'REPORT',
        headers: {'Depth': '1'},
      ),
    );

    return _parseMultistatusObjects(response.data!);
  }

  /// REPORT: multiget — fetch specific objects by href.
  Future<List<CalDavObject>> multiget(
    String calendarHref,
    List<String> hrefs,
  ) async {
    final body = _buildMultigetBody(hrefs);
    final response = await _dio.request<String>(
      calendarHref,
      data: body,
      options: Options(
        method: 'REPORT',
        headers: {'Depth': '1'},
      ),
    );

    return _parseMultistatusObjects(response.data!);
  }

  // ── Create / Update / Delete ────────────────────────────────────

  /// PUT: create a new CalDAV object. Returns the new etag.
  Future<String?> createObject(
    String calendarHref,
    String uid,
    String icalData,
  ) async {
    final objectPath = '$calendarHref$uid.ics';
    final response = await _dio.request<String>(
      objectPath,
      data: icalData,
      options: Options(
        method: 'PUT',
        headers: {
          'Content-Type': 'text/calendar; charset=utf-8',
          'If-None-Match': '*',
        },
      ),
    );
    return response.headers.value('etag');
  }

  /// PUT: update an existing CalDAV object. Returns the new etag.
  Future<String?> updateObject(
    String href,
    String icalData,
    String etag,
  ) async {
    final response = await _dio.request<String>(
      href,
      data: icalData,
      options: Options(
        method: 'PUT',
        headers: {
          'Content-Type': 'text/calendar; charset=utf-8',
          'If-Match': etag,
        },
      ),
    );
    return response.headers.value('etag');
  }

  /// DELETE: remove a CalDAV object.
  Future<void> deleteObject(String href, String etag) async {
    await _dio.request<String>(
      href,
      options: Options(
        method: 'DELETE',
        headers: {'If-Match': etag},
      ),
    );
  }

  // ── XML Body Builders ───────────────────────────────────────────

  String _buildPropfindBody() {
    return '<?xml version="1.0" encoding="utf-8" ?>'
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '  <d:prop>'
        '    <d:displayname />'
        '    <d:resourcetype />'
        '    <c:supported-calendar-component-set />'
        '    <x1:calendar-color xmlns:x1="http://apple.com/ns/ical/" />'
        '  </d:prop>'
        '</d:propfind>';
  }

  String _buildCalendarPropBody() {
    return '<?xml version="1.0" encoding="utf-8" ?>'
        '<d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" '
        'xmlns:cs="http://calendarserver.org/ns/">'
        '  <d:prop>'
        '    <d:displayname />'
        '    <cs:getctag />'
        '    <d:sync-token />'
        '    <x1:calendar-color xmlns:x1="http://apple.com/ns/ical/" />'
        '  </d:prop>'
        '</d:propfind>';
  }

  String _buildCalendarQueryBody(String component) {
    return '<?xml version="1.0" encoding="utf-8" ?>'
        '<c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '  <d:prop>'
        '    <d:getetag />'
        '    <c:calendar-data />'
        '  </d:prop>'
        '  <c:filter>'
        '    <c:comp-filter name="VCALENDAR">'
        '      <c:comp-filter name="$component" />'
        '    </c:comp-filter>'
        '  </c:filter>'
        '</c:calendar-query>';
  }

  String _buildSyncCollectionBody(String syncToken) {
    return '<?xml version="1.0" encoding="utf-8" ?>'
        '<d:sync-collection xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '  <d:sync-token>$syncToken</d:sync-token>'
        '  <d:prop>'
        '    <d:getetag />'
        '    <c:calendar-data />'
        '  </d:prop>'
        '</d:sync-collection>';
  }

  String _buildMultigetBody(List<String> hrefs) {
    final hrefElements = hrefs.map((h) => '    <d:href>$h</d:href>').join('\n');
    return '<?xml version="1.0" encoding="utf-8" ?>'
        '<c:calendar-multiget xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">'
        '  <d:prop>'
        '    <d:getetag />'
        '    <c:calendar-data />'
        '  </d:prop>'
        '$hrefElements'
        '</c:calendar-multiget>';
  }

  // ── XML Response Parsers ────────────────────────────────────────

  Future<List<CalDavObject>> _reportCalendarQuery({
    required String calendarHref,
    required String filterComponent,
  }) async {
    final body = _buildCalendarQueryBody(filterComponent);
    final response = await _dio.request<String>(
      calendarHref,
      data: body,
      options: Options(
        method: 'REPORT',
        headers: {'Depth': '1'},
      ),
    );

    return _parseMultistatusObjects(response.data!);
  }

  List<CalDavCalendarInfo> _parseMultistatusCalendars(String xmlStr) {
    final doc = XmlDocument.parse(xmlStr);
    final responses = doc.findAllElements('response');

    return responses.map((resp) {
      final href = _findText(resp, 'href') ?? '';
      final displayName = _findText(resp, 'displayname') ?? '';
      final color = _findText(resp, 'calendar-color');
      final ctag = _findText(resp, 'getctag');
      final syncToken = _findText(resp, 'sync-token');

      bool supportsVEVENT = true;
      bool supportsVTODO = true;
      final compSets = resp.findAllElements('supported-calendar-component-set');
      if (compSets.isNotEmpty) {
        final comps = compSets.first.findAllElements('comp');
        if (comps.isNotEmpty) {
          final compNames = comps.map((e) => e.getAttribute('name')).toSet();
          supportsVEVENT = compNames.contains('VEVENT');
          supportsVTODO = compNames.contains('VTODO');
        }
      }

      // Only return actual calendar resources (those with calendar resourcetype)
      final rt = resp.findAllElements('resourcetype');
      if (rt.isNotEmpty) {
        final hasCalendar =
            rt.first.findAllElements('calendar').isNotEmpty;
        if (!hasCalendar) {
          return null;
        }
      }

      return CalDavCalendarInfo(
        href: href,
        name: displayName,
        color: color,
        ctag: ctag,
        syncToken: syncToken,
        supportsVEVENT: supportsVEVENT,
        supportsVTODO: supportsVTODO,
      );
    }).whereType<CalDavCalendarInfo>().toList();
  }

  List<CalDavObject> _parseMultistatusObjects(String xmlStr) {
    final doc = XmlDocument.parse(xmlStr);
    final responses = doc.findAllElements('response');

    return responses.map((resp) {
      final href = _findText(resp, 'href') ?? '';
      final etag = _findText(resp, 'getetag');
      final calendarData = _findText(resp, 'calendar-data') ?? '';

      final status = _findText(resp, 'status');
      if (status != null && status.contains('404')) {
        return null;
      }

      return CalDavObject(
        href: href,
        etag: etag,
        icalData: calendarData,
      );
    }).whereType<CalDavObject>().toList();
  }

  String? _findText(XmlElement parent, String localName) {
    try {
      final elements = parent.descendants
          .whereType<XmlElement>()
          .where((e) =>
              e.localName == localName ||
              e.localName.endsWith(':$localName'));
      if (elements.isEmpty) return null;
      return elements.first.innerText.trim();
    } catch (_) {
      return null;
    }
  }

  /// Dispose the underlying Dio client.
  void dispose() {
    _dio.close();
  }
}
