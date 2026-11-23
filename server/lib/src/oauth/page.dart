// Shared frame for every browser-visible OAuth page. Plain CSS with no build
// step: shelf serves these documents directly, and the palette mirrors
// lib/core/theme/spec_tokens.dart so the browser surface reads as the app's
// light paper theme rather than a third UI family.
const String oauthPageStyle = '''
:root {
  color-scheme: light;
  --paper: #FFFFFF;
  --ink: #191918;
  --ink2: #45453F;
  --muted: #6E6E66;
  --hair: #ECECE6;
  --accent: #C92A1E;
  --accent-strong: #B3261B;
  --red-soft: #FDF3F1;
  --red-line: #F3D4CF;
  --wash: #F7F7F4;
}
* { box-sizing: border-box; }
html { background: var(--paper); }
body {
  margin: 0;
  min-height: 100vh;
  display: flex;
  align-items: flex-start;
  justify-content: center;
  padding: 4rem 1rem;
  background: var(--paper);
  color: var(--ink);
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  font-size: 15px;
  line-height: 1.5;
}
.card {
  width: 100%;
  max-width: 28rem;
  padding: 28px;
  background: var(--paper);
  border: 1px solid var(--hair);
  border-radius: 12px;
  box-shadow: 0 18px 50px rgba(24, 24, 22, 0.10);
}
h1 {
  margin: 0 0 12px;
  font-size: 20px;
  font-weight: 600;
  line-height: 1.35;
  letter-spacing: -0.005em;
  color: var(--ink);
}
p { margin: 0 0 16px; color: var(--ink2); }
strong { color: var(--ink); font-weight: 600; }
ul {
  margin: 0 0 20px;
  padding: 0;
  list-style: none;
  border: 1px solid var(--hair);
  border-radius: 8px;
}
li {
  padding: 10px 12px;
  color: var(--ink2);
  border-top: 1px solid var(--hair);
}
li:first-child { border-top: 0; }
code {
  padding: 1px 6px;
  font-family: ui-monospace, "SFMono-Regular", Menlo, monospace;
  font-size: 13px;
  color: var(--ink);
  background: var(--wash);
  border-radius: 6px;
}
label {
  display: block;
  margin: 0 0 14px;
  font-size: 13px;
  font-weight: 500;
  color: var(--ink);
}
input {
  display: block;
  width: 100%;
  margin-top: 6px;
  padding: 10px 12px;
  font: inherit;
  color: var(--ink);
  background: var(--paper);
  border: 1px solid var(--hair);
  border-radius: 8px;
}
input:focus {
  outline: none;
  border-color: var(--ink2);
  box-shadow: 0 0 0 3px rgba(69, 69, 63, 0.10);
}
.btn {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 40px;
  margin-top: 4px;
  padding: 0.6rem 1.2rem;
  font: inherit;
  font-weight: 500;
  color: var(--paper);
  background: var(--accent);
  border: 1px solid var(--accent);
  border-radius: 8px;
  cursor: pointer;
}
.btn:hover { background: var(--accent-strong); border-color: var(--accent-strong); }
.btn:focus-visible { outline: 2px solid var(--ink); outline-offset: 2px; }
.btn-secondary {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  min-height: 40px;
  padding: 0.6rem 1.2rem;
  font: inherit;
  font-weight: 500;
  color: var(--ink);
  background: var(--paper);
  border: 1px solid var(--hair);
  border-radius: 8px;
  cursor: pointer;
}
.btn-secondary:hover { border-color: var(--ink2); }
.error {
  margin: 0 0 16px;
  padding: 10px 12px;
  color: var(--accent);
  background: var(--red-soft);
  border: 1px solid var(--red-line);
  border-radius: 8px;
}
.muted { margin: 16px 0 0; color: var(--muted); font-size: 13px; }
@media (max-width: 30rem) {
  body { padding: 1.5rem 16px; }
  .card { padding: 20px 16px; border-radius: 8px; }
}
''';

String renderOauthDocument({
  required String title,
  required String heading,
  required String body,
}) => '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>$title</title>
<style>$oauthPageStyle</style>
</head>
<body>
<main class="card">
<h1>$heading</h1>
$body
</main>
</body>
</html>
''';
