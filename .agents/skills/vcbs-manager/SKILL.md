---
name: vcbs-manager
description: Manage VCBS (Vibe-Coding-Bootstrap) adoption and capabilities for DaySpark — run real VCBS CLI inspect, perform evidence-based semantic review, generate and summarize adoption plans, and execute confirmed plan apply or rollback preview.
---

# VCBS Manager (DaySpark Integration)

This Skill provides a DaySpark-local integration with [vibe-coding-Bootstrap (VCBS)](https://github.com/liuchangchxy/vibe-coding-Bootstrap). It guides developers and host AI agents through inspecting capability assets, performing evidence-based semantic reviews, building adoption plans, and executing authorized plan applications or rollback previews using the real, unmodified VCBS CLI.

---

## 1. Scope and Integration Nature

- **DaySpark-Owned Consumer Integration (`DAYSPARK_VCBS_INTEGRATION`)**:
  These skill entrypoints (`.claude/skills/vcbs-manager` and `.agents/skills/vcbs-manager`) are DaySpark-owned integration files created to make VCBS accessible within DaySpark.
- **Distinct from Upstream Native Activation (`VCBS_NATIVE_ACTIVATION`)**:
  Generic native host activation for Claude Code or Antigravity is not implemented in upstream VCBS and is separately tracked in upstream issue [`liuchangchxy/vibe-coding-Bootstrap#1`](https://github.com/liuchangchxy/vibe-coding-Bootstrap/issues/1).
- **No Fabricated Artifacts**:
  Do not fabricate VCBS ownership manifests, fake Deployment IDs, or invented host adapters.
- **Host Flag Constraint**:
  Supported VCBS `--host` options are `codex` and `none`. Because existing-project host activation is not implemented in VCBS, **always use `--host none`** for DaySpark inspect and plan commands. Never invent `--host claude_code` or `--host antigravity`.

---

## 2. Core Boundary Distinctions

Always maintain a clear distinction between these three independent states:

1. **`VCBS CLI inspected a repo`**:
   The read-only execution of `bootstrap inspect` against a target repository. It identifies existing assets and packages capability signals. It does **not** modify files, install components, or imply that VCBS manages the repository.
2. **`VCBS installed/manages a component`**:
   Occurs **only** when an approved adoption or bootstrap plan with non-zero actions (`actual_changes > 0`) is applied, materializing files into `.vibe-coding-bootstrap/` or component paths with Git snapshots and rollback records. On a no-op adoption plan (`actual_changes: 0`), zero components are installed or managed.
3. **`Host actually used a Skill`**:
   The host agent (Claude Code or Antigravity) loaded and executed this `vcbs-manager` Skill from project configuration to perform development tasks.

---

## 3. Portability and Environment Setup

Execution requires access to a trusted local checkout of `liuchangchxy/vibe-coding-Bootstrap`. No machine-specific absolute paths, private credentials, or automatic network downloads are committed.

### Locating VCBS
1. Check the `VCBS_ROOT` environment variable if set by the user:
   ```bash
   export VCBS_ROOT=/path/to/vibe-coding-Bootstrap
   ```
2. If `VCBS_ROOT` is unset, default to the sibling checkout relative to DaySpark:
   `../vibe-coding-Bootstrap`
3. If neither location contains a valid `bootstrap/` package, fail clearly:
   ```text
   Error: VCBS repository not found.
   Please set VCBS_ROOT to the path of your trusted vibe-coding-Bootstrap checkout:
     export VCBS_ROOT=/path/to/vibe-coding-Bootstrap
   ```

### Prerequisites
- Python 3 with required dependencies (`pip install -r requirements.txt` in VCBS root, including `jsonschema` and `pyyaml`).
- Clean repository checkout with known revision (e.g. pinned commit).

### Execution Methods
You can invoke VCBS either via the bundled launcher or directly via Python:

- **Via bundled launcher**:
  ```bash
  .agents/skills/vcbs-manager/scripts/vcbs <command> [arguments]
  ```
- **Via direct Python invocation**:
  ```bash
  PYTHONPATH="${VCBS_ROOT}" python3 -m bootstrap <command> [arguments]
  ```

---

## 4. Product Loop Workflow

The unified workflow follows: `inspect → semantic review → plan → confirm once → apply`.

> [!IMPORTANT]
> **Artifacts Outside DaySpark**: All generated plan, inspect, decision, and review artifacts (`--output`) MUST be stored outside the DaySpark repository tree (for example, under `/tmp/vcbs/`), per VCBS contract.

### Step 1: Inspect (Read-Only)
Inspect DaySpark's existing capability assets and bind the repository revision.

```bash
mkdir -p /tmp/vcbs
.agents/skills/vcbs-manager/scripts/vcbs inspect \
  --project-root . \
  --host none \
  --output /tmp/vcbs/inspect.json
```

**Inspection Facts**:
- Target repository: `liuchangchxy/dayspark`
- Selected route: `adoption` (DaySpark has existing project-owned assets)
- Output contains `semantic_package` with `discovered_assets`, `capability_catalog`, `baseline_coverage`, and `profile_constraints`.

### Step 2: Evidence-Based Semantic Review
Analyze the `semantic_package` from Step 1. In adoption mode, VCBS requires a semantic review result before building a plan (`HOST_SEMANTIC_REVIEW_REQUIRED`).

Review DaySpark's existing assets against each catalog capability:
- **`code-review`**: Satisfied (evidence: `CLAUDE.md`, code review checklists, `dayspark-code-review` skill).
- **`documentation`**: Satisfied (evidence: `SPEC.md`, `CLAUDE.md`, `README.md`, `docs/`).
- **`engineering-baseline`**: Satisfied (evidence: `AGENTS.md`, `CLAUDE.md`, `docs/process/EXECUTION.md`).
- **`planning`**: Satisfied (evidence: `DECISIONS.md`, `docs/CONSTRAINTS.md`, `docs/ROADMAP.md`, `docs/START_HERE.md`).
- **`testing`**: Satisfied (evidence: `AGENTS.md`, `CLAUDE.md`, `docs/process/TESTING.md`, extensive unit/widget/integration tests).
- **`agent-development` / `debugging` / `research-workflow`**: Marked `unknown` with `no_action` recommended (DaySpark is an end-user client app, not an agent runtime or research project).

Write the review result to `/tmp/vcbs/semantic_review.json` following `schemas/semantic-review-result.schema.json`.

### Step 3: Build and Summarize Adoption Plan
Generate the adoption plan:

```bash
.agents/skills/vcbs-manager/scripts/vcbs plan \
  --project-root . \
  --host none \
  --semantic-result /tmp/vcbs/semantic_review.json \
  --output /tmp/vcbs/plan.json
```

Display a concise summary to the developer:
- Route: `adoption`
- Target commit: `<commit-sha>`
- Covered capabilities: 5 satisfied
- Gaps / changes: 0 (legitimate NO-OP)
- Confirmation required: `false`

### Step 4: Authorization Gate (Never Auto-Approve)

> [!CAUTION]
> **Strict Rule: Never Auto-Approve**:
> The host agent must NEVER automatically approve a plan that proposes material changes (`actual_changes > 0`). It must present the exact diff / plan summary and wait for explicit human authorization.

For plans requiring confirmation:
```bash
.agents/skills/vcbs-manager/scripts/vcbs decide /tmp/vcbs/plan.json \
  --decision approve \
  --output /tmp/vcbs/decision.json
```

For no-op plans (`actual_changes: 0`), VCBS requires no decision artifact and creates no snapshot.

### Step 5: Apply
Apply the plan:

```bash
.agents/skills/vcbs-manager/scripts/vcbs apply \
  --plan /tmp/vcbs/plan.json \
  --project-root .
```

- When `actual_changes == 0`, apply returns `status: "no_changes"`, creating no snapshot and leaving DaySpark's working tree completely untouched.
- When `actual_changes > 0`, apply creates a pre-apply Git snapshot under `refs/vibe-coding-bootstrap/snapshots/<deployment-id>` before materializing changes.

### Step 6: Rollback (Preview and Apply)
If a previous mutating deployment needs reversal:

1. **Preview rollback (dry-run)**:
   ```bash
   .agents/skills/vcbs-manager/scripts/vcbs rollback \
     --project-root . \
     --deployment <deployment-id>
   ```
2. **Apply rollback**:
   ```bash
   .agents/skills/vcbs-manager/scripts/vcbs rollback \
     --project-root . \
     --deployment <deployment-id> \
     --apply
   ```
   Rollback verifies that touched paths have not changed since deployment, then restores files from the pre-apply snapshot.
