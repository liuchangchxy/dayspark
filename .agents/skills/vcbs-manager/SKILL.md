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

### Verifying Revision and Dependencies
Before running the workflow, verify that your VCBS checkout is clean and matches the trusted revision, and that all runtime dependencies are available:

1. **Verify VCBS Revision**:
   ```bash
   VCBS_DIR="${VCBS_ROOT:-../vibe-coding-Bootstrap}"
   git -C "${VCBS_DIR}" rev-parse HEAD
   git -C "${VCBS_DIR}" status --porcelain
   ```
   *Expected trusted revision:* `6a8a3ef8ee1d33d320f0325da8edc35e6eebf5f1` (upstream `main`). If the revision does not match or the working tree is dirty, halt and verify your checkout before proceeding.

2. **Verify Python Dependencies**:
   ```bash
   python3 -c "import jsonschema, yaml; print('VCBS dependencies: OK')"
   ```
   If dependencies are missing, fail clearly and install them:
   ```bash
   pip install -r "${VCBS_DIR}/requirements.txt"
   ```

3. **Verify Unmodified CLI Accessibility**:
   ```bash
   PYTHONPATH="${VCBS_DIR}" python3 -m bootstrap --help
   ```

### Execution Methods
You can invoke VCBS either via the bundled launcher or directly via Python:

- **Via bundled launcher**:
  ```bash
  .agents/skills/vcbs-manager/scripts/vcbs <command> [arguments]
  ```
- **Via direct Python invocation**:
  ```bash
  PYTHONPATH="${VCBS_ROOT:-../vibe-coding-Bootstrap}" python3 -m bootstrap <command> [arguments]
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

**Derive Inspection Facts dynamically**:
Do not assume fixed inspection results. Read `/tmp/vcbs/inspect.json` and extract:
- `target_repository` from `.target.repository`
- `commit_sha` from `.target.commit_sha`
- `route` from `.route` (`adoption` when existing project assets are found)
- `semantic_package` from `.semantic_package` (includes `discovered_assets`, `capability_catalog`, `baseline_coverage`, and `profile_constraints`)

### Step 2: Evidence-Based Semantic Review
Analyze the dynamically extracted `semantic_package` from Step 1. In adoption mode, VCBS requires a semantic review result before building a plan (`HOST_SEMANTIC_REVIEW_REQUIRED`).

Inspect the discovered assets and baseline coverage in `semantic_package`. For each capability in `capability_catalog`, evaluate DaySpark's actual coverage:
- Cite discovered relative paths and explain their meaning.
- Judge satisfied by substantive coverage, not file count.
- Judge missing only when applicability is established and core purpose is not covered; otherwise use `unknown`.
- *Historical baseline reference (for commit `b3b4efd595`)*:
  - `code-review`: Satisfied (covered by `CLAUDE.md`, code review checklists).
  - `documentation`: Satisfied (covered by `SPEC.md`, `CLAUDE.md`, `README.md`, `docs/`).
  - `engineering-baseline`: Satisfied (covered by `AGENTS.md`, `CLAUDE.md`, `docs/process/EXECUTION.md`).
  - `planning`: Satisfied (covered by `DECISIONS.md`, `docs/CONSTRAINTS.md`, `docs/ROADMAP.md`, `docs/START_HERE.md`).
  - `testing`: Satisfied (covered by `AGENTS.md`, `CLAUDE.md`, `docs/process/TESTING.md`, unit/widget/integration tests).
  - `agent-development` / `debugging` / `research-workflow`: Marked `unknown` with `no_action` recommended (DaySpark is an end-user client app, not an agent runtime or research project).

Construct the review result adhering to `schemas/semantic-review-result.schema.json` and write it to `/tmp/vcbs/semantic_review.json`.

### Step 3: Build and Summarize Adoption Plan
Generate the adoption plan:

```bash
.agents/skills/vcbs-manager/scripts/vcbs plan \
  --project-root . \
  --host none \
  --semantic-result /tmp/vcbs/semantic_review.json \
  --output /tmp/vcbs/plan.json
```

**Extract and Display Dynamic Plan Summary**:
Read `/tmp/vcbs/plan.json` and extract all summary fields directly from the artifact:
- `route` from `.route`
- `target_revision` from `.target_revision`
- `covered_capabilities` from `.capabilities`
- `actual_changes` from `.actual_changes`
- `requires_confirmation` from `.requires_confirmation`
- `project_changes` from `.project_changes`
- `global_changes` from `.global_changes`

Display the actual derived values to the developer:
```text
Route: <extracted route>
Target revision: <extracted target_revision>
Covered capabilities: <count of covered capabilities>
Actual changes: <extracted actual_changes count>
Confirmation required: <extracted requires_confirmation boolean>
```
*(When existing capabilities satisfy requirements, `actual_changes` will be 0, representing a legitimate NO-OP plan).*

### Step 4: Authorization Gate (Never Auto-Approve)

> [!CAUTION]
> **Strict Rule: Never Auto-Approve**:
> If the derived `actual_changes > 0` or `requires_confirmation == true`, the host agent MUST NEVER automatically approve the plan. It must present the exact diff / change list to the human developer and wait for explicit confirmation.

- **If `actual_changes > 0` (Mutating Plan)**:
  Only after explicit human confirmation:
  ```bash
  .agents/skills/vcbs-manager/scripts/vcbs decide /tmp/vcbs/plan.json \
    --decision approve \
    --output /tmp/vcbs/decision.json
  ```

- **If `actual_changes == 0` (Legitimate No-Op Plan)**:
  No decision is required by VCBS (`decide` is skipped; a no-op needs no decision and creates no snapshot or deployment record).

### Step 5: Apply
Apply the plan:

- **For No-Op (`actual_changes == 0`)**:
  ```bash
  .agents/skills/vcbs-manager/scripts/vcbs apply \
    --plan /tmp/vcbs/plan.json \
    --project-root .
  ```
  Verify that the command returns `status: "no_changes"` and that git status confirms the working tree is untouched.

- **For Mutating Plan (`actual_changes > 0`)**:
  ```bash
  .agents/skills/vcbs-manager/scripts/vcbs apply \
    --plan /tmp/vcbs/plan.json \
    --decision /tmp/vcbs/decision.json \
    --project-root .
  ```
  Apply creates a pre-apply Git snapshot under `refs/vibe-coding-bootstrap/snapshots/<deployment-id>` before materializing changes.

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
