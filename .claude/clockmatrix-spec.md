# `clockmatrix`: clocked time as a period × project matrix

## Problem Statement

I track time with org-clock across several projects, each identified by a tag. I can
produce a clocktable *per project*, or a clocktable *stepped by period* — but never both
at once.

Org's `:step` parameter writes one separate table per period, each with its own header.
And `:match` accepts a single tag matcher, so one clocktable can only ever describe one
project. Answering "how many hours did each project get, month by month?" therefore means
generating N×M disconnected tables and transcribing them into a spreadsheet by hand.

There is no single view of where my time went.

## Solution

A new Org dynamic block, `clockmatrix`, that renders clocked time as one table: calendar
periods down the rows, projects across the columns, totals on both axes.

```org
#+BEGIN: clockmatrix :block thisyear :step month
| Month   | alpha | beta   | gamma |  Total |
|---------+-------+--------+-------+--------|
| 2026-05 | 57:00 |  49:45 |  1:45 | 108:30 |
| 2026-06 | 13:00 |  79:00 |       |  92:00 |
|---------+-------+--------+-------+--------|
| Total   | 70:00 | 128:45 |  1:45 | 200:30 |
#+END:
```

Columns default to the projects registered in `agile-gtd-projects`, so in the common case
the block needs no configuration at all. It reuses clocktable's parameter vocabulary
(`:block`, `:tstart`/`:tend`, `:step`, `:scope`, `:stepskip0`) so there is nothing new to
learn, and refreshes with `C-c C-c` like any dynamic block.

## User Stories

1. As a user tracking several projects, I want one table showing clocked hours per project per period, so that I can see where my time went without collating separate clocktables.
2. As a user, I want periods as rows and projects as columns, so that I can read a project's trend down a column and a period's split across a row.
3. As a user, I want to write `:step month` and get one row per month, so that I can review a year at a glance.
4. As a user, I want to write `:step week` and get one row per week, so that I can review a month in finer granularity.
5. As a user, I want `:step` to also accept `day`, `semimonth`, `quarter`, and `year`, so that the same block serves daily review and annual summary.
6. As a user, I want week rows labelled by the date the week starts, so that the label matches what Org's stepped clocktable already prints and I can cross-reference them.
7. As a user, I want month rows labelled `YYYY-MM`, so that rows sort correctly and are unambiguous across year boundaries.
8. As a user, I want to select the reporting range with `:block thisyear` / `thismonth` / `2026-Q2`, so that the block uses the same range vocabulary as clocktable.
9. As a user, I want to select the range with explicit `:tstart` and `:tend`, so that I can report on an arbitrary window.
10. As a user, I want columns to default to my registered projects, so that a bare block with no parameters already does the right thing.
11. As a user, I want to override the columns with `:tags`, so that I can produce a single-project or hand-picked report from the same block.
12. As a user, I want column headers to be the raw project tags, so that I can paste a header straight into a `:match` when reconciling against an existing clocktable.
13. As a user, I want projects with zero time in the range omitted entirely, so that the table stays narrow and shows only what I actually worked on.
14. As a user, I want cells with zero time left blank rather than showing `0:00`, so that the non-zero numbers stand out.
15. As a user, I want periods with no time at all omitted, so that gaps in my history do not pad the table with empty rows.
16. As a user, I want to keep all-zero rows by setting `:stepskip0 nil`, so that I can see an unbroken calendar when that matters.
17. As a user, I want a Total column summing each period across projects, so that I can see how much I worked in a given month.
18. As a user, I want a Total row summing each project across the range, so that I get the same number a single unstepped clocktable would give me.
19. As a user, I want to suppress totals with `:total nil`, so that I can build my own aggregation on top.
20. As a user, I want durations rendered with my configured `org-duration-format`, so that they match every other clock report I have.
21. As a user, I want durations past 24 hours shown as hours and minutes rather than days, so that monthly totals stay readable.
22. As a user, I want the numbers to agree exactly with an equivalent clocktable, so that I can trust the matrix for reporting.
23. As a user, I want a clock that spans a period boundary split between the two periods, so that rows partition my time exactly and always sum to the range total.
24. As a user, I want the block to read each project's own file and its archive by default, so that refreshing is fast enough to be interactive.
25. As a user, I want archived entries included by default, so that historical periods are not silently understated.
26. As a user, I want to set `:scope agenda-with-archives`, so that I can audit whether any tagged time is hiding outside its project's file.
27. As a user, I want a warning when a registered project's file does not exist, so that a misconfigured project is not silently reported as zero hours.
28. As a user, I want that warning to name the project and the path that was tried, so that I can fix it without guessing.
29. As a user, I want no warning for a missing archive file, so that projects that have never been archived do not nag me.
30. As a user, I want a project whose time lives in a differently-named file to work by setting `:file` on its registration, so that a project does not need a file named after its tag.
31. As a user, I want a finished project to drop out of reports automatically once the range no longer covers its clocked time, so that I do not have to deregister it.
32. As a user, I want a finished project to still appear in historical ranges, so that past reports remain complete.
33. As a user, I want the block listed in Org's dynamic-block insertion menu, so that I can insert it without memorising the syntax.
34. As a user, I want the block documented in the package README with its full parameter list, so that I can discover options without reading source.
35. As a user, I want the reasoning behind the default scope recorded as an ADR, so that a future reader understands the trade-off and its known failure mode.
36. As a maintainer, I want the internal decomposition free to change, so that tests do not break when I refactor.

## Implementation Decisions

**Module.** The feature ships inside the `agile-gtd` package rather than user config,
because it depends on the project registry (`agile-gtd-projects`) that the package already
owns. The package gains `org-clock` and `org-duration` as requires; neither is currently
pulled in.

**Naming.** The dynamic block is `clockmatrix`. Org dispatches on the block name, so the
writer must be `org-dblock-write:clockmatrix` and cannot carry a package prefix; every
other symbol does (`agile-gtd-clockmatrix`, `agile-gtd--clockmatrix-*`). The name
deliberately avoids `columnview`, which is an unrelated existing Org dynamic block that
renders `#+COLUMNS` properties.

**Domain vocabulary.** Columns are **projects**, not clients — the package models projects,
and anything that deserves a column gets registered as one. The report covers **clocked**
time only; it is not invoice-aware and deliberately avoids the word "booked", which in
practice means *invoiced*.

**Column derivation.** Candidate columns come from `agile-gtd-projects` in registration
order, overridable per block with `:tags`. A candidate with zero clocked time across the
whole range is dropped. Column selection is *not* keyed off the `:key` field — that
controls agenda keybindings and would silently change the report the day a key is bound.

**Default scope.** For each project, the block reads that project's own file plus its
archive, resolved through the existing `agile-gtd--project-file` accessor and the
package's org-path expansion. `:scope agenda-with-archives` selects clocktable's wider
file set as an audit path. Files that do not exist are filtered out.

**Missing-file handling.** A project whose *main* file is absent is a misconfiguration,
not an absence of time, and emits a warning naming the project, the path tried, and the
two remedies (set `:file`, or use the wider scope). Archive files are exempt — they are
routinely absent by design.

**Aggregation primitive.** Each cell is one call to Org's `org-clock-get-table-data` with
`:maxlevel 0` and a `:match` of the project tag, summed across the project's files. Using
Org's own summing function rather than parsing CLOCK lines guarantees the matrix agrees
with equivalent clocktables, and inherits Org's boundary clipping so a clock spanning a
period boundary is split rather than double-counted or dropped.

**Period stepping.** Range resolution and the `:step` advance follow the same logic Org
uses for stepped clocktables, including `:wstart` / `:mstart` handling, so periods align
with the user's existing reports. Row labels: `%Y-%m` for month; `%Y-%m-%d` for day, week,
and semimonth, with a week labelled by its start date; `%Y-Q%d` for quarter; `%Y` for year.

**Performance.** Scoping to project files is what makes refresh interactive. A naive
implementation that scans every agenda file for every cell costs roughly an order of
magnitude more: a 12-period × 4-project grid over ~27 files took ~14s, versus under a
second when each project reads only its own two files. An intermediate design — wide scope
plus a per-tag prefilter — lands in between, but spends most of its budget rediscovering
the project-to-file mapping the package already holds.

**Parameter contract.**

| Param | Default | Meaning |
|---|---|---|
| `:block` | — | Range keyword, as clocktable |
| `:tstart` / `:tend` | — | Explicit range; `:block` takes precedence |
| `:step` | `month` | `day` \| `week` \| `semimonth` \| `month` \| `quarter` \| `year` |
| `:tags` | from `agile-gtd-projects` | Column tags, in order |
| `:scope` | project files | or `agenda-with-archives` |
| `:stepskip0` | `t` | Drop all-zero rows |
| `:total` | `t` | Total column and Total row |
| `:wstart` / `:mstart` | `1` / `1` | Week / month start, as clocktable |

**Registration in Org.** The block registers with Org's dynamic-block registry so it
appears in the insertion menu.

**Deliberately rejected parameters.** `:formula` (emitting a trailing `#+TBLFM:`) is not
offered: because empty columns are dropped, column indices are not stable between
refreshes, so a formula written against `$3` silently retargets a different project in a
period where some project has no time. A `:match` parameter for ANDing an extra matcher
into every column was measured against real data and dropped as unjustified API surface.

## Testing Decisions

**What makes a good test here.** Tests assert only on what a user can observe: the
rendered Org table. They must not reach into range resolution, period stepping, file
resolution, summing, or column selection, so that the internal decomposition stays free
to change. A test that breaks when a helper is renamed, split, or inlined — without any
rendered output changing — is a bad test.

**One seam.** All behaviour is driven through the dynamic block itself: insert a
`#+BEGIN: clockmatrix … #+END:` block into a buffer, refresh it via Org's dynamic-block
update, and assert against the resulting buffer text. This is the highest available seam
and the only one the suite touches. Everything in scope is reachable through it — row
labels for every `:step` value, blank zero cells, dropped columns, dropped rows, Total row
and column, boundary splitting, `:tags` override, `:scope` override, and the missing-file
warning (captured while rendering).

**Fixtures.** Tests reuse the package's existing test sandbox, which binds `org-directory`
to a temporary directory and isolates Org's global state. Synthetic project files with
known CLOCK entries are written into that sandbox and `agile-gtd-projects` is bound to
point at them. This exercises the real file-resolution path rather than stubbing it,
which is what makes the missing-file warning testable at the same seam.

Fixtures are synthetic and self-contained — never the author's real org files, whose
contents change and whose numbers would make the suite non-deterministic.

**Prior art.** The package already tests Org-dependent behaviour this way: a sandbox macro
providing isolated Org state, wrapped by a fixture macro that writes an Org file into it
and opens it before running the body. The new fixture macro follows that shape.

**Coverage.** At minimum: one row per period for each `:step` value; correct row-label
format per `:step`; correct per-cell attribution; blank cell for zero; column dropped when
a project has no time in range; row dropped when all projects have no time, and kept under
`:stepskip0 nil`; Total column equals the sum of its row; Total row equals the range total
per project; a clock spanning a period boundary appearing split across two rows and summing
to its full duration; `:tags` overriding the derived column set; and a project with an
unresolvable file producing a warning rather than a silent zero.

**Verification beyond the suite.** Separately from ERT, a one-off parity check against a
real dataset confirms every rendered cell equals what an equivalent clocktable reports for
the same range and matcher, and that the two scopes agree. This is a confidence check run
during development, not a committed test — it depends on data that changes.

## Out of Scope

- **Money.** No rates, no currency columns, no `:formula` passthrough. Rates change over
  time and a single scalar would misprice historical periods.
- **Invoice awareness.** Billing periods are per-client and arbitrary; they cannot share
  rows in one matrix. Existing per-invoice clocktables keep that job. The block has no
  notion of invoiced-versus-open time.
- **Non-project time.** Time not carrying a registered project tag is not represented, and
  there is no residual "Other" column. Totals mean *sum of the project columns shown*, and
  never *all time clocked*.
- **A lifecycle field on projects.** No active/finished/abandoned status is added to the
  project registry. Nothing in this feature needs it: the empty-column rule already drops
  a finished project from ranges after its last clock, and a registration without an
  agenda key is already inert.
- **Drill-down.** No per-headline breakdown, no `:maxlevel`, no properties columns, no
  links. Cells are project totals. Existing clocktables cover drill-down.
- **Sorting and custom column order.** Columns follow registration order.
- **Export targets.** Org table output only; no CSV or spreadsheet export.

## Further Notes

**Known failure mode of the default scope.** Because each project is read from its own
file, clocked time carrying a project's tag that lives in *another* file — an item captured
to an inbox, clocked, and not yet refiled — is invisible until refiled, with no error. On
the dataset this was designed against, the two scopes currently agree exactly, so the
divergence is zero today; but it is a property of that data, not an invariant. This
trade-off and its remedy (`:scope agenda-with-archives`) is the subject of an ADR shipped
with the change.

**Registering a project costs nothing when keyless.** Verified against the package: capture
templates do not enumerate projects, tag-alist entries and agenda commands are created only
for projects carrying a key, and agenda files are unioned so an already-present file is not
duplicated. A project can therefore be registered purely so its history appears in reports.

**A project does not need a file named after its tag.** The registry's `:file` key points a
project at any existing file; the tag matcher isolates that project's entries within it.
Omitting `:file` for a project whose file is named differently is the single most likely
misconfiguration, which is what the missing-file warning exists to catch.

**Documentation.** The change ships with a README section covering the block and its full
parameter list, and an ADR recording the default-scope decision.
