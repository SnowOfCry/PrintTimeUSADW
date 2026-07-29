# ADR-017: Power BI as the BI Tool, on a Tool-Agnostic Serving Layer (Tableau Version to Follow)

- **Status:** Accepted
- **Date:** 2026-07-29
- **Decision-makers:** Erick Palma (Data Engineer)
- **Consulted:** Freddy Vazquez (Manager)
- **Informed:** Jaime Chavez Jr (CEO)

## Context

The gold star schema is built, tested, and served by an orchestrated pipeline. What is missing
is the layer the business actually looks at: dashboards. ADR-001 already fixed two constraints —
**BI consumers only ever see gold** (never silver/bronze), and the intended consumers are
**"Power BI / Tableau"** (the gold dimensions were deliberately denormalized to make their models
simpler). No ADR had yet chosen *which* tool, or *how* the tool connects to gold. This record
closes that gap.

Two facts shape the decision:

1. **The metric logic must not live inside a dashboard file.** Refund netting (refunds are stored
   negative, ADR/​backlog #5), current-vs-historical dimension versions, gross margin, and
   "at-risk" definitions are business rules. If they are re-derived inside each `.pbix`/`.twbx`,
   they drift between tools and reports and cannot be tested. They belong in version-controlled
   SQL.
2. **Desktop BI tools sit outside the Docker stack (ADR-002).** Power BI and Tableau are Windows
   desktop applications; their output is a binary workbook, not a container. This is an accepted
   tension: the *serving layer* is reproducible (dbt views in gold), the *dashboard file* is not.

## Decision

**Adopt Power BI as the primary BI tool, sitting on a tool-agnostic BI serving layer built in
gold. Build a Tableau version of the same dashboards afterward, so the managers can compare the
two front-ends on identical data and decide which to standardize on.**

1. **BI serving layer (the real engineering).** A small set of report-ready views in the gold
   schema, built as dbt models materialized as views (`gold.bi_sales`, `gold.bi_payments`,
   `gold.bi_customer_snapshot`). Each pre-joins the star one hop per dimension, exposes
   business-friendly column names, and encodes the metric logic **once** (margin, refund
   direction, day counts, at-risk). Both front-ends consume these views, so the semantics are
   shared and only the presentation differs. The views read gold only — ADR-001 upheld.

2. **Power BI first.** Chosen over Tableau as the primary because Power BI Desktop is **free and
   stays free** (a portfolio/stakeholder artifact must remain openable indefinitely; Tableau
   Desktop is a 14-day trial then paid), it aligns with the Microsoft/Azure data ecosystem that
   data-engineering roles increasingly touch (DAX/Power Query are the transferable skills), it is
   Windows-native on the work machines, and it is the tool ADR-001 names first. Deliverables: the
   serving views, a DAX measures reference, and a connect-and-build guide.

3. **Tableau version to follow — for the managers to decide.** After the Power BI version ships,
   build the equivalent dashboards in Tableau on the *same* serving views. Because the semantic
   layer is shared, the second front-end is cheap — only the visuals are rebuilt, not the logic.
   The point is to give Jaime (CEO) and Freddy (Manager) a genuine side-by-side on identical
   numbers so the choice of a house BI tool is theirs, made on evidence rather than asserted by
   engineering. Whichever they pick, the serving layer does not change.

## Alternatives considered

1. **Dashboards directly on the raw star, no serving views.** Power BI is designed to import a
   star and build the model in-tool, so this is viable. Rejected as the *foundation* because the
   business rules (refund netting, margin, at-risk, version selection) would then be re-authored
   in DAX inside Power BI and again in Tableau's calculated fields — two copies that drift and
   neither testable in dbt. The serving views keep one tested definition; the star is still
   importable for ad-hoc modeling on top.
2. **Metabase or Superset (containerized).** Genuinely appealing: either drops into
   `docker-compose` and makes the dashboards reproducible with `docker compose up`, fully honoring
   ADR-002 — and unlike the desktop tools, could be built and verified in-repo. Rejected as the
   *primary* because ADR-001 names Power BI/Tableau, those are what the stakeholders and the job
   market expect, and the managers asked to evaluate the mainstream tools. Kept on the table as a
   future reproducibility option (a `docker compose up`-able demo of the same serving views).
3. **Tableau first / Tableau only.** Rejected: the trial-then-paid model makes it a poor default
   for an artifact that must stay openable, and choosing one tool outright removes the comparison
   the managers want.
4. **dbt semantic layer / MetricFlow.** Overkill for three fact tables at this volume, and it
   would add a dependency and a second place metrics are defined. The SQL serving views are
   simpler and directly consumable by both tools.

## Consequences

**Positive**

- One tested definition of every BI metric, in dbt-managed SQL under version control — not
  trapped inside a workbook. A metric change is a reviewed dbt change, and both front-ends inherit
  it.
- Building the Tableau version is cheap because it reuses the serving views; the managers get a
  real, like-for-like comparison rather than a rebuild.
- The serving views read gold only, so ADR-001's "BI sees only gold" holds, and upstream refactors
  do not reach the dashboards.
- Power BI Desktop is free, so the artifact stays openable and extensible indefinitely.

**Negative / accepted costs**

- The dashboard workbooks themselves are not containerized or diffable (binary files, outside
  `docker compose`). Accepted: this is inherent to desktop BI, and the *logic* is reproducible in
  dbt even though the *layout* is not. A future Metabase demo (alternative 2) could close this if
  reproducible dashboards become a requirement.
- Two front-ends to maintain once both exist. Mitigated by the shared serving layer: only visuals
  are duplicated, never metric logic.
- "At-risk customer" and similar BI-layer definitions are introduced here (no prior spec). They
  are documented in the view SQL and the gold data dictionary and are explicitly open for the
  managers to adjust — a definition choice surfaced, not buried.

## Related

- ADR-001 (medallion — BI sees only gold; names Power BI/Tableau), ADR-002 (local Docker stack —
  the reproducibility tension), ADR-007/009/010/011 (gold modeling the views sit on)
- `docs/architecture/gold_star_schema.md` — the star the serving views consume
- The serving views: `dbt/printtime_dw/models/gold/bi_sales.sql`, `bi_payments.sql`,
  `bi_customer_snapshot.sql`
