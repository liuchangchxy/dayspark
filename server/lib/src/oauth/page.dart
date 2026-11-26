// Shared frame for every browser-visible OAuth page. Plain CSS with no build
// step: shelf serves these documents directly. The palette and type scale are
// copied from the frozen design master's `server-oauth` screen (paper, ink,
// ink2, muted, hair, red, amber) so the browser surface reads as DaySpark's
// paper theme rather than a third UI family.
const String oauthPageStyle = '''
:root {
  color-scheme: light;
  --paper: #FFFFFF;
  --ink: #191918;
  --ink2: #45453F;
  --muted: #6E6E66;
  --faint: #8B8B82;
  --hair: #ECECE6;
  --hair2: #DEDED7;
  --red: #C92A1E;
  --red-soft: #FDF3F1;
  --red-line: #F3D4CF;
  --wash: #F7F7F4;
  --host: #F3F3EE;
  --foot: #FBFBF8;
}
* { box-sizing: border-box; }
html, body { height: 100%; }
body {
  margin: 0;
  min-height: 100%;
  display: grid;
  place-items: center;
  padding: 24px;
  background: var(--host);
  color: var(--ink);
  font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "PingFang SC",
    "Hiragino Sans GB", "Helvetica Neue", Arial, sans-serif;
  font-size: 13px;
  line-height: 1.45;
  -webkit-font-smoothing: antialiased;
  text-rendering: optimizeLegibility;
}
.card {
  width: 400px;
  max-width: 100%;
  background: var(--paper);
  border: 1px solid var(--hair2);
  border-radius: 10px;
  overflow: hidden;
  box-shadow: 0 18px 50px rgba(20, 20, 18, 0.10);
}
.oauth-head {
  display: flex;
  align-items: center;
  gap: 9px;
  padding: 16px 18px;
  border-bottom: 1px solid var(--hair);
  font-size: 13px;
  font-weight: 650;
  color: var(--ink);
}
.mark {
  width: 22px;
  height: 22px;
  border-radius: 6px;
  background: var(--ink);
  color: #fff;
  display: grid;
  place-items: center;
  font-size: 11px;
  font-weight: 700;
  flex: none;
}
.oauth-body { padding: 16px 18px; }
.oauth-body h1, .oauth-body h2 {
  margin: 0 0 5px;
  font-size: 15px;
  font-weight: 650;
  line-height: 1.4;
  letter-spacing: 0;
  color: var(--ink);
}
.oauth-body p {
  margin: 0 0 10px;
  font-size: 11px;
  line-height: 1.6;
  color: var(--muted);
}
.oauth-scope {
  display: flex;
  align-items: flex-start;
  gap: 8px;
  padding: 7px 0;
  border-top: 1px solid var(--hair);
  font-size: 10.5px;
  color: var(--ink2);
  line-height: 1.5;
}
.oauth-scope svg {
  width: 12px;
  height: 12px;
  color: var(--faint);
  margin-top: 1px;
  flex: none;
}
.oauth-auth {
  margin-top: 12px;
  padding-top: 12px;
  border-top: 1px solid var(--hair);
}
.oauth-auth-label {
  margin-bottom: 8px;
  font-size: 9.5px;
  letter-spacing: 0.08em;
  color: var(--faint);
  font-weight: 650;
}
.oauth-field {
  display: block;
  margin: 0 0 8px;
  font-size: 10.5px;
  color: var(--ink2);
}
.oauth-field span { display: block; margin-bottom: 4px; }
.oauth-field input {
  display: block;
  width: 100%;
  height: 32px;
  padding: 0 9px;
  font: inherit;
  font-size: 11px;
  color: var(--ink);
  background: var(--paper);
  border: 1px solid var(--hair2);
  border-radius: 6px;
}
.oauth-field input:focus {
  outline: none;
  border-color: var(--ink2);
  box-shadow: 0 0 0 3px rgba(69, 69, 63, 0.10);
}
.oauth-error {
  margin: 2px 0 8px;
  padding: 7px 9px;
  font-size: 10.5px;
  line-height: 1.5;
  color: var(--red);
  background: var(--red-soft);
  border: 1px solid var(--red-line);
  border-radius: 6px;
}
.oauth-foot {
  display: flex;
  gap: 8px;
  padding: 12px 18px;
  border-top: 1px solid var(--hair);
  background: var(--foot);
}
.oauth-foot button, .oauth-foot a {
  flex: 1;
  height: 32px;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  padding: 0 10px;
  border: 1px solid var(--hair2);
  border-radius: 6px;
  background: #fff;
  font: inherit;
  font-size: 11px;
  color: var(--ink2);
  text-decoration: none;
  white-space: nowrap;
  cursor: pointer;
}
.oauth-foot button.primary, .oauth-foot a.primary {
  background: var(--ink);
  border-color: var(--ink);
  color: #fff;
  font-weight: 600;
}
.oauth-foot button:hover, .oauth-foot a:hover { border-color: var(--ink2); }
.oauth-foot button.primary:hover, .oauth-foot a.primary:hover {
  background: #000;
  border-color: #000;
}
.oauth-foot button:focus-visible, .oauth-foot a:focus-visible {
  outline: 2px solid var(--ink);
  outline-offset: 2px;
}
.oauth-note {
  margin: 0;
  padding: 0 18px 14px;
  font-size: 9.5px;
  line-height: 1.5;
  color: var(--faint);
}
@media (max-width: 30rem) {
  body { padding: 16px; }
  .oauth-head, .oauth-body { padding-left: 16px; padding-right: 16px; }
  .oauth-foot { padding-left: 16px; padding-right: 16px; }
  .oauth-note { padding-left: 16px; padding-right: 16px; }
}
''';

// The card shell every OAuth document renders into. `body` carries the
// header, body and footer so the consent and denied states can share the
// frame exactly while owning their own anatomy.
String renderOauthCard({
  required String title,
  required String body,
  String lang = 'zh-CN',
}) => '''<!doctype html>
<html lang="$lang">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>$title</title>
<style>$oauthPageStyle</style>
</head>
<body>
<main class="card">
$body
</main>
</body>
</html>
''';

String renderOauthDocument({
  required String title,
  required String heading,
  required String body,
}) => renderOauthCard(
  title: title,
  body: '''
<div class="oauth-head"><span class="mark">D</span>DaySpark</div>
<div class="oauth-body">
<h1>$heading</h1>
$body
</div>''',
);
