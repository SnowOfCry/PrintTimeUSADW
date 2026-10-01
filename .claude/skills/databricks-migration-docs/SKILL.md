---
name: databricks-migration-docs
description: >
  Maintain the PrintTimeUSA Postgres→Azure Databricks migration's two living
  documents — docs/migration/MIGRATION_TO_DATABRICKS_GUIDE.md (teaching guide)
  and docs/migration/ERROR_AND_FIX_LOG.md (troubleshooting log). Invoke this
  whenever a migration step is advanced, a model/macro/contract is ported, a
  command is run against Databricks, an error is hit and fixed, or the user asks
  to update the guide/log. The docs must be specific and replicable enough that
  someone new to dbt and Databricks can reproduce the whole process by reading
  the markdown alone — never summarize away exact commands, file paths, code, or
  error text.
---

# Databricks Migration Docs — maintenance skill

This project is being migrated from local **Postgres** to **Azure Databricks**
(proven first on **Databricks Free Edition**). Two markdown files are the record
of that work and MUST be kept current:

- `docs/migration/MIGRATION_TO_DATABRICKS_GUIDE.md` — the step-by-step teaching
  guide (**what / why / how** for every advance).
- `docs/migration/ERROR_AND_FIX_LOG.md` — every problem hit
  (**symptom / cause / fix / lesson**) plus the dialect cheat-sheet.

The repo owner is **new to dbt and Databricks** and reviews these to learn and to
replicate the process. Optimize for that reader.

## The prime directive: replicable, not summarized

Someone must be able to **reproduce every step by reading the markdown alone**.
Therefore, for every advance you MUST record:

- The **exact command(s)** run, in a fenced code block, copy-pasteable, with all
  flags (e.g. `--target databricks --project-dir dbt/printtime_dw --profiles-dir dbt/printtime_dw --vars "{silver_batch_id: 1}"`).
- The **exact file paths** touched (repo-relative), and **what changed in them**
  — show the before→after for non-obvious edits (real code, not a paraphrase).
- Any **UI steps** in Databricks as a numbered click-path (e.g. "SQL → SQL
  Warehouses → *warehouse* → Connection details → HTTP path").
- The **verbatim error text** for failures (the message and SQLSTATE), not a
  description of it.
- **Why** the step was needed and **why** the fix works — the transferable reason.

Never write "we cleaned up the SQL" or "fixed some types." Write which types, in
which file, from what to what, and why.

## When to update (triggers)

Update the docs when ANY of these happen — do it in the SAME session, right after
the work, while details are exact:

1. A migration milestone advances (connect dbt, port a model/layer, load data,
   add grants, build a workflow, etc.).
2. A dbt model, macro, YAML contract, or seed is ported/created.
3. A command is run against Databricks (record it even if it succeeded first try).
4. An error is encountered and resolved (however small — env, shell, dbt, SQL).
5. The user asks to "update the guide/log" or says a step is done.
6. A decision is made (e.g. keep dbt, Free Edition vs paid, orchestration choice).

## How to update the GUIDE (MIGRATION_TO_DATABRICKS_GUIDE.md)

Append a new numbered step under the right Part (or add a new Part). Keep the
existing structure. Each step uses this exact template:

```
### Step X.Y — <short imperative title>
- **What:** <the concrete thing done, one or two sentences>
- **Why:** <the reason it was needed; plain language for a beginner>
- **How:**
  <exact commands in a fenced block, and/or numbered UI click-path, and/or the
   real before→after code for edited files>
```

Also, after the step:
- Update the **"Where we are"** checklist (tick boxes, add new unchecked items).
- If the step taught a reusable concept (e.g. a new dialect rule), add it to the
  relevant reference table so it's not lost.
- Keep Part 0 (the plain-language big picture) accurate if the plan changes.

Concept explanations are for a beginner: define jargon the first time it appears
(dbt, model, adapter, catalog, contract, Delta, warehouse, target, materialization).

## How to update the ERROR & FIX LOG (ERROR_AND_FIX_LOG.md)

Add one entry per distinct problem, in the correct section (*Environment / setup*,
*Databricks / dbt*, or a new section), numbered continuing the sequence. Template:

```
### N. <short title of the problem>
- **Symptom:** <verbatim error text / observable behavior, incl. SQLSTATE or code>
- **Cause:** <the actual root cause, precisely — not a guess>
- **Fix:** <exact commands / edits that resolved it, copy-pasteable>
- **Lesson:** <the transferable takeaway for next time>
```

Also:
- Keep the **SQL dialect cheat-sheet** table current — add any new
  Postgres→Databricks translation discovered (SQL *and* YAML `data_type`).
- Keep the **milestones** and **security follow-ups** checklists in sync with the
  guide.

## House rules

- **Both files stay in lockstep.** An advance updates the guide; any error during
  it updates the log. Don't update one and forget the other.
- **Preserve, don't rewrite.** Append and tick checkboxes; only edit prior entries
  to correct something that turned out wrong (and say what changed).
- **Frontmatter tags** stay intact (Obsidian relies on them). Both files render in
  GitHub and Obsidian — use standard markdown + fenced code + tables only.
- **Never write secrets** into the docs (no real tokens, passwords, PATs). Refer to
  them by variable name (`DBRICKS_TOKEN`) only.
- After updating, if the user is committing, stage both docs with the related code
  change so history ties the doc to the work.

## Known project specifics to keep consistent

- Catalog: `printtime_dw`; schemas `bronze` / `silver` / `gold` / `audit`.
- dbt target name: `databricks` (in `dbt/printtime_dw/profiles.yml`).
- Run dbt from **cmd/PowerShell, not Git Bash** (Git Bash mangles the `/sql/...`
  http_path → 404). Load secrets with `dotenv run --` (dbt does not read `.env`).
- Incremental silver models need `--vars "{silver_batch_id: <n>}"` (the
  `require_batch_id` macro refuses to run without it).
- Dialect porting lives in TWO places: model **SQL** and YAML **contract**
  `data_type:` declarations (`text`/`varchar(n)`/`char(n)` → `string`).
- Sample bronze seeds for POC testing live in `sql/databricks_poc/`.
