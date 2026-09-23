import '../auth.dart';

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

String _scopeDescription(String scope) => switch (scope) {
  'mcp:read' => 'Read your calendar events and tasks / 读取日历与任务',
  'mcp:write' =>
    'Create, update and trash your calendar events and tasks / '
        '创建、更新并移入回收站日历与任务',
  _ => scope,
};

const String _pageStyle = '''
body { font-family: system-ui, sans-serif; max-width: 28rem;
  margin: 4rem auto; padding: 0 1rem; color: #111; }
h1 { font-size: 1.25rem; }
ul { padding-left: 1.25rem; }
label { display: block; margin: 0.75rem 0; }
input { width: 100%; padding: 0.5rem; box-sizing: border-box; }
button { margin-top: 1rem; padding: 0.6rem 1.2rem; }
.error { color: #b00020; }
.muted { color: #555; font-size: 0.9rem; }
''';

String renderConsentPage({
  required String clientName,
  required List<String> scopes,
  required Map<String, String> hidden,
  String email = '',
  String? error,
}) {
  final scopeItems = scopes
      .map(
        (scope) =>
            '<li><code>${htmlEscape(scope)}</code> — '
            '${htmlEscape(_scopeDescription(scope))}</li>',
      )
      .join('\n      ');
  final hiddenInputs = hidden.entries
      .map(
        (entry) =>
            '<input type="hidden" name="${htmlEscape(entry.key)}" '
            'value="${htmlEscape(entry.value)}">',
      )
      .join('\n    ');
  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Authorize DaySpark / 授权 DaySpark</title>
<style>$_pageStyle</style>
</head>
<body>
<h1>Authorize DaySpark / 授权 DaySpark</h1>
<p><strong>${htmlEscape(clientName)}</strong> wants access to your DaySpark
data. Sign in to grant the requested scopes.</p>
<ul>
      $scopeItems
</ul>
${error == null ? '' : '<p class="error">${htmlEscape(error)}</p>'}
<form method="post" action="/oauth/authorize">
    $hiddenInputs
    <label>Email 邮箱
      <input type="email" name="email" value="${htmlEscape(email)}"
        autocomplete="username" required>
    </label>
    <label>Password 密码
      <input type="password" name="password" autocomplete="current-password"
        required>
    </label>
    <button type="submit">Authorize / 授权</button>
</form>
<p class="muted">Scopes requested: ${htmlEscape(scopes.join(' '))}</p>
</body>
</html>
''';
}

// Shown only when a request can never be safely redirected (unknown client,
// unvalidated redirect_uri, dead form token) — deliberately carries no code
// and no Location header.
String renderOAuthErrorPage(String message) => '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>Authorization error</title>
<style>$_pageStyle</style>
</head>
<body>
<h1>Authorization error / 授权错误</h1>
<p class="error">${htmlEscape(message)}</p>
</body>
</html>
''';
