#!/usr/bin/env python3
"""Cross-platform Micro-Checkpoint & Instant Rollback Manager for Vibe Coding.

Allows developers and AI agents to create lightweight, non-intrusive snapshots
before risky refactors without polluting git commit history.
"""
import json
import os
import subprocess
import sys
import time
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    try:
        sys.stdout.reconfigure(encoding="utf-8", errors="replace")
        sys.stderr.reconfigure(encoding="utf-8", errors="replace")
    except Exception:
        pass


def get_git_root() -> Path:
    try:
        res = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=True
        )
        return Path(res.stdout.strip())
    except Exception:
        return Path(__file__).resolve().parent.parent


def get_checkpoint_store(root: Path) -> Path:
    store = root / ".git" / "vibe-checkpoints.json"
    return store


def load_checkpoints(store: Path) -> list[dict]:
    if not store.exists():
        return []
    try:
        return json.loads(store.read_text(encoding="utf-8"))
    except Exception:
        return []


def save_checkpoints(store: Path, checkpoints: list[dict]):
    store.parent.mkdir(parents=True, exist_ok=True)
    store.write_text(json.dumps(checkpoints, ensure_ascii=False, indent=2), encoding="utf-8")


def _stash_refs(root: Path) -> list[str]:
    """Return current stash refs (stash@{0}, ...) so we can detect a new one."""
    res = subprocess.run(
        ["git", "stash", "list", "--format=%gd"],
        cwd=str(root),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    return [line.strip() for line in res.stdout.splitlines() if line.strip()]


def cmd_save(message: str = ""):
    root = get_git_root()
    store = get_checkpoint_store(root)
    checkpoints = load_checkpoints(store)

    now_str = time.strftime("%Y-%m-%d %H:%M:%S")
    desc = message.strip() or f"Auto-checkpoint at {now_str}"

    # 1. Create a stash commit without modifying working tree
    res = subprocess.run(
        ["git", "stash", "create", desc],
        cwd=str(root),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace"
    )
    commit_sha = res.stdout.strip()

    # If working directory has no changes, stash create returns empty, use HEAD
    if not commit_sha:
        head_res = subprocess.run(
            ["git", "rev-parse", "HEAD"],
            cwd=str(root),
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace"
        )
        commit_sha = head_res.stdout.strip()
        state = "clean (HEAD)"
    else:
        state = "dirty snapshot"

    # 2. Pin reference so git garbage collection never sweeps it
    ref_name = f"refs/vibe-checkpoints/{int(time.time())}"
    subprocess.run(
        ["git", "update-ref", ref_name, commit_sha],
        cwd=str(root),
        capture_output=True,
        check=False
    )

    entry = {
        "id": len(checkpoints) + 1,
        "timestamp": now_str,
        "message": desc,
        "commit": commit_sha,
        "ref": ref_name,
        "state": state
    }
    checkpoints.append(entry)
    save_checkpoints(store, checkpoints)

    print(f"[CHECKPOINT SAVED] #{entry['id']} [{now_str}] '{desc}' (Commit: {commit_sha[:8]})")
    print("💡 To restore later, run: python tooling/checks/checkpoint.py restore")


def cmd_list():
    root = get_git_root()
    store = get_checkpoint_store(root)
    checkpoints = load_checkpoints(store)

    if not checkpoints:
        print("[INFO] No micro-checkpoints found. Create one with: python tooling/checks/checkpoint.py save")
        return

    print("============================================================")
    print(" 🕒 Available Micro-Checkpoints (Recent to Oldest)")
    print("============================================================")
    for cp in reversed(checkpoints):
        print(f" #{cp['id']:02d} | {cp['timestamp']} | [{cp['state']}]")
        print(f"      Message: {cp['message']}")
        print(f"      Ref:     {cp['commit'][:8]}")
        print("------------------------------------------------------------")


def cmd_restore(target_id: int | None = None):
    root = get_git_root()
    store = get_checkpoint_store(root)
    checkpoints = load_checkpoints(store)

    if not checkpoints:
        print("[ERROR] No checkpoints available to restore.")
        sys.exit(1)

    if target_id is None:
        target = checkpoints[-1]
    else:
        matched = [cp for cp in checkpoints if cp["id"] == target_id]
        if not matched:
            print(f"[ERROR] Checkpoint #{target_id} not found.")
            sys.exit(1)
        target = matched[0]

    commit_sha = target["commit"]
    print(f"Restoring checkpoint #{target['id']} ({commit_sha[:8]} - '{target['message']}')...")

    # Safety net: capture the current worktree (incl. untracked) so nothing is
    # silently destroyed by the rollback. Record which stash we created so it can
    # be named back to the user — a "safety" stash nobody can find is not a safety net.
    safety_stash_ref = None
    before_list = _stash_refs(root)
    stash_msg = f"vibe-checkpoint pre-restore safety ({time.strftime('%Y-%m-%d %H:%M:%S')})"
    subprocess.run(
        ["git", "stash", "push", "-u", "-m", stash_msg],
        cwd=str(root), capture_output=True,
        text=True, encoding="utf-8", errors="replace",
    )
    after_list = _stash_refs(root)
    new_refs = [r for r in after_list if r not in before_list]
    if new_refs:
        safety_stash_ref = safety_stash_ref or new_refs[0]

    # Roll the worktree back to the checkpoint.
    # `git checkout <sha> -- .` only overwrites/restores paths that exist in the
    # checkpoint; files added afterwards would survive as orphans, so the reset
    # has to be explicit about removals too.
    res = subprocess.run(
        ["git", "read-tree", "-u", "--reset", commit_sha],
        cwd=str(root),
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )

    if res.returncode == 0:
        print(f"[SUCCESS] Restored project state to checkpoint #{target['id']}: '{target['message']}'")
        print("[NOTE] Worktree content now matches the checkpoint exactly (added-after files removed).")
        if safety_stash_ref:
            print(f"[SAFETY] Your pre-restore worktree was saved first: {safety_stash_ref}")
            print(f"         Recover it with: git stash apply {safety_stash_ref}")
        else:
            print("[SAFETY] Worktree was clean before restore; nothing needed saving.")
    else:
        print(f"[ERROR] Restore failed: {res.stderr}")
        if safety_stash_ref:
            print(f"[SAFETY] Your pre-restore worktree is intact in: {safety_stash_ref}")
        sys.exit(1)


def main():
    args = sys.argv[1:]
    if not args or args[0] in ("-h", "--help", "help"):
        print("Usage:")
        print("  python tooling/checks/checkpoint.py save [message]   # Take a snapshot")
        print("  python tooling/checks/checkpoint.py list             # View snapshot history")
        print("  python tooling/checks/checkpoint.py restore [id]     # Restore latest or specific snapshot")
        return

    action = args[0].lower()
    if action == "save":
        msg = " ".join(args[1:]) if len(args) > 1 else ""
        cmd_save(msg)
    elif action == "list":
        cmd_list()
    elif action == "restore":
        tid = int(args[1]) if len(args) > 1 and args[1].isdigit() else None
        cmd_restore(tid)
    else:
        print(f"[ERROR] Unknown action '{action}'. Use save, list, or restore.")
        sys.exit(1)


if __name__ == "__main__":
    main()
