#!/usr/bin/env bash
# Re-run the round-4 real-UI evidence. Requires: python3, websockets, Google Chrome (macOS path).
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
OUT="${1:-/tmp/r4-evidence-out}"
mkdir -p "$OUT" /tmp/r4-final
cp "$ROOT/dayspark-prototype.html" /tmp/r4-final/dayspark-prototype.html
cd "$HERE/scripts"
for f in \
  plan_draft_probe plan_edit_probe plan_cancel_all plan_status_probe plain_done_probe \
  repeat_plan_draft_final legacy_ui qa_force rem_probe2 new_rem_save3 event_edit_rem \
  mobile_repeat_final mobile_probe backup_probe backup_retry_final backup_single_plan_merge merge_probe2 ai_probe \
  backup_roundtrip rem_plan_not_anchor repeat_detail_done drag_delta drag_second_keeps_first \
  resize_second plan_dupe_same_time repeat_anchor_not_plan repeat_next_pending \
  quickadd_removed menu_plan_append; do
  echo "===== $f"
  timeout 120 python3 "$f.py" 2>&1 | tee "$OUT/$f.txt" | tail -3
done
echo "results: $OUT"
