import '../auth.dart';
import 'page.dart';

// One-time consent-form CSRF tokens (AllisWell design reference only — no
// code copied; PolyForm NC). Issued when the authorize page renders,
// consumed exactly once on POST; a replay or a cold token fails closed.
// Process-local by design: a server restart invalidates in-flight forms and
// the user simply reloads the authorization URL.
class OneTimeFormTokens {
  OneTimeFormTokens({this.ttl = const Duration(minutes: 10)});

  final Duration ttl;
  final Map<String, DateTime> _tokens = <String, DateTime>{};

  String issue() {
    _prune();
    final token = newId(24);
    _tokens[token] = DateTime.now().toUtc().add(ttl);
    return token;
  }

  bool consume(String? token) {
    if (token == null || token.isEmpty) {
      return false;
    }
    final expiry = _tokens.remove(token);
    if (expiry == null) {
      return false;
    }
    return !expiry.isBefore(DateTime.now().toUtc());
  }

  void _prune() {
    final now = DateTime.now().toUtc();
    _tokens.removeWhere((_, expiry) => expiry.isBefore(now));
  }
}

String htmlEscape(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

// 24x24 stroke icons copied from the design master's `ico()` so the browser
// page needs no icon font, no JS and no asset route.
const Map<String, String> _iconPaths = {
  'calendar':
      '<rect x="3.5" y="5" width="17" height="15" rx="2"/>'
          '<path d="M3.5 10h17M8 3v4M16 3v4"/>',
  'plus': '<path d="M12 5v14M5 12h14"/>',
  'user':
      '<circle cx="12" cy="8" r="3.5"/><path d="M5 20a7 7 0 0 1 14 0"/>',
  'shield':
      '<path d="M12 3 19 6v6c0 4-3 7-7 9-4-2-7-5-7-9V6z"/>'
          '<path d="m9 12 2 2 4-4"/>',
  'alert': '<path d="M12 4 21 20H3z"/><path d="M12 10v4m0 3h.01"/>',
  'list': '<path d="M8 6h12M8 12h12M8 18h12"/>'
      '<circle cx="4" cy="6" r="1"/><circle cx="4" cy="12" r="1"/>'
      '<circle cx="4" cy="18" r="1"/>',
};

String _icon(String name) =>
    '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" '
    'stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round" '
    'aria-hidden="true">${_iconPaths[name] ?? _iconPaths['list']}</svg>';

class _ScopeRow {
  _ScopeRow(this.icon, this.text);

  final String icon;
  final String text;
}

List<_ScopeRow> _scopeRows(List<String> scopes, String email) {
  final rows = <_ScopeRow>[];
  // The master's card lists permissions in a fixed reading order, not in the
  // order the client happened to ask for them.
  if (scopes.contains('mcp:read')) {
    rows.add(_ScopeRow('calendar', '读取日历、待办和日程'));
  }
  if (scopes.contains('mcp:write')) {
    rows.add(_ScopeRow('plus', '创建和修改待办、日程'));
  }
  for (final scope in scopes) {
    if (scope != 'mcp:read' && scope != 'mcp:write') {
      // Unknown scopes never reach here (the authorize GET validates them),
      // but a hand-built POST must still be described honestly.
      rows.add(_ScopeRow('list', scope));
    }
  }
  rows.add(
    _ScopeRow(
      'user',
      email.isEmpty ? '读取账号邮箱' : '读取账号邮箱（${htmlEscape(email)}）',
    ),
  );
  rows.add(
    _ScopeRow('shield', '不会读取其他设备上的本地数据；不会访问附件内容'),
  );
  return rows;
}

String _scopeMarkup(List<String> scopes, String email) => _scopeRows(
  scopes,
  email,
).map((row) => '<div class="oauth-scope">${_icon(row.icon)}'
    '<span>${row.text}</span></div>').join('\n      ');

String _hiddenInputs(Map<String, String> hidden) => hidden.entries
    .map(
      (entry) =>
          '<input type="hidden" name="${htmlEscape(entry.key)}" '
          'value="${htmlEscape(entry.value)}">',
    )
    .join('\n      ');

// Consent screen from the frozen master's `server-oauth / normal` variant:
// 400px paper card, D-mark header, a human-readable scope list, and a footer
// pairing 拒绝 / 允许访问. The real flow still needs an authenticated user, so
// the email and password fields live in the body under a quiet sign-in label
// (the master shows a signed-in browser; this server has no browser session).
// Deny is a submit button with `formaction` so it carries the same hidden
// OAuth parameters and CSRF token without requiring the credentials.
String renderConsentPage({
  required String clientName,
  required List<String> scopes,
  required Map<String, String> hidden,
  String email = '',
  String? error,
}) {
  final body =
      '''
<form method="post" action="/oauth/authorize">
      ${_hiddenInputs(hidden)}
      <div class="oauth-head"><span class="mark">D</span>DaySpark</div>
      <div class="oauth-body">
        <h2>允许「${htmlEscape(clientName)}」访问你的 DaySpark？</h2>
        <p>这是一个 MCP 客户端，正在请求以你的账号读取和写入数据。授权后可以随时在设置里撤销。</p>
        ${_scopeMarkup(scopes, email)}
        <div class="oauth-auth">
          <div class="oauth-auth-label">登录以继续 · SIGN IN</div>
          ${error == null ? '' : '<div class="oauth-error">${htmlEscape(error)}</div>'}
          <label class="oauth-field"><span>邮箱 · Email</span>
            <input type="email" name="email" value="${htmlEscape(email)}"
              autocomplete="username" required>
          </label>
          <label class="oauth-field"><span>密码 · Password</span>
            <input type="password" name="password" autocomplete="current-password"
              required>
          </label>
        </div>
      </div>
      <div class="oauth-foot">
        <button type="submit" formaction="/oauth/deny" formnovalidate>拒绝</button>
        <button type="submit" class="primary">允许访问</button>
      </div>
    </form>''';
  return renderOauthCard(
    title: '允许访问 DaySpark · Authorize DaySpark',
    body: body,
  );
}

// `server-oauth / denied`: the same card, designed rather than a browser
// error. The client already receives the standard OAuth `access_denied`
// response when the user follows 返回客户端 — the link below is that exact
// redirect target, so the page can explain the outcome without losing it.
String renderOAuthDeniedPage({
  required String clientName,
  required String returnUrl,
}) {
  final body =
      '''
<div class="oauth-head"><span class="mark">D</span>DaySpark</div>
<div class="oauth-body">
  <h2>已拒绝授权</h2>
  <p>MCP 客户端「${htmlEscape(clientName)}」没有获得访问权限。你可以关闭这个页面，或在客户端里重新发起连接。</p>
  <div class="oauth-scope">${_icon('alert')}<span>没有共享任何日历、待办或账号信息。</span></div>
</div>
<div class="oauth-foot">
  <a class="primary" href="${htmlEscape(returnUrl)}">返回客户端</a>
</div>''';
  return renderOauthCard(title: '已拒绝授权 · Authorization denied', body: body);
}

// Shown only when a request can never be safely redirected (unknown client,
// unvalidated redirect_uri, dead form token) — deliberately carries no code
// and no Location header.
String renderOAuthErrorPage(String message) => renderOauthDocument(
  title: 'Authorization error',
  heading: 'Authorization error / 授权错误',
  body: '<div class="oauth-error">${htmlEscape(message)}</div>',
);
