# CLAUDE.md

This file provides guidance to coding agents like Claude Code when working with code in this repository.

## Commands

```sh
# Byte-compile the package
eask recompile

# Run the full ERT test suite
eask run script test

# Run both via just
just build
just test

# Run a subset of tests by name prefix
eask exec emacs -batch -Q -L . \
  -l agile-gtd.el \
  -l test/agile-gtd-test.el \
  --eval '(ert-run-tests-batch "agile-gtd-enable")'
```

## Architecture

This is a single-file Emacs Lisp package (`agile-gtd.el`) with ten companion test files under `test/`. It depends on org-records-mcp, which is not on MELPA (MELPA's `org-mcp` is a different package with no views); Eask fetches `stfl/org-records-mcp` from GitHub's `main` branch.

### Main entry points

- `agile-gtd-enable` — call once after customising variables; delegates to `agile-gtd-refresh`
- `agile-gtd-refresh` — validates config, then applies all derived settings (Org settings, loop-tag inheritance, priorities, keywords, tags, agenda files, refile targets, capture templates, agenda commands, org-records-mcp views)

### Key subsystems

**Priority system** (`agile-gtd-priority-highest/default/lowest`, A–I range)
- `agile-gtd--priority-range` derives the active character range
- `agile-gtd--prio-rank` / `agile-gtd--backlog-rank` map priorities to numeric ranks used for sorting
- `agile-gtd--rank-band-top` closes a priority's ten-rank band; it is the single boundary both the view-range filter and the rank groups read, so the two cannot disagree
- Rank functions are derived from the configured range and must not hard-code character values

**TODO keywords**
- Sequence: `TODO → NEXT → WAIT → PROJ → EPIC | DONE, IDEA, KILL`
- Logging lives in the selectors of `agile-gtd-todo-keywords` (`NEXT(n!)`, `WAIT(w@/!)`, `PROJ(p!)`, `EPIC(e!)`, `DONE(d@)`, `KILL(k@)`); nothing parses those strings, Org strips the suffixes into `org-todo-keywords-1`
- Public accessors: `agile-gtd-project-keyword`, `agile-gtd-action-keywords`

**View ranges** (`agile-gtd-view-ranges`: today -> sprint -> upcoming -> all -> someday)
- `agile-gtd-view-range-cutoff` is each range's rank cutoff: 0 for `today`, the cutoff priority's `agile-gtd--rank-band-top` for the rest. `today` has no priority (`agile-gtd-view-range-priority` returns nil for it)
- `agile-gtd-within-range` is the org-ql predicate every ranged query filters on; it takes a range name (quoted by its normalizer) or a priority character, and tests `agile-gtd--item-rank` against the cutoff
- `today` holds rank ≤ 0: any deadline within two days (the [#A] deadline window), due today, overdue, or scheduled today or earlier. A deadline within two days ranks 0 whatever the cookie; it lines up with the "Today & Overdue" rank group. The day block's `org-deadline-warning-days` is that same window, so an item `hide-today` removes is always in the day block
- No agenda command declares `today`; reset returns to the declared range. Ranged blocks use `agile-gtd-agenda-ql-block`, which keeps the header when the result is empty (`org-ql-block` drops the whole block)
- Grouping and filtering must stay derived from rank. Re-deriving a cutoff from cookies, parents or deadlines separately is what produced headings for priorities a range had excluded
- Work scheduled beyond today is excluded from every range but `someday`

**Agenda queries** (org-ql based)
- `agile-gtd-agenda-query-next-actions` — unblocked NEXT/WAIT, or any open task inside `today` regardless of blocking, cut at the range. `hide-today` (passed by the agenda blocks under the day block) removes everything inside `today` by rank, from both halves, at every range, so the `[today]` block is always empty
- `agile-gtd-agenda-query-backlog` — PROJ and standalone NEXT/WAIT, blocked included
- `agile-gtd-agenda-query-inbox` — unprocessed inbox items
- `agile-gtd-agenda-query-stuck-projects` — PROJ or EPIC (`agile-gtd--container-keywords`) with no open PROJ/EPIC/NEXT/WAIT child
- Project-specific agenda commands generated from `agile-gtd-projects`

**Area table** (`agile-gtd-areas`)
- One row per area: everything (`:name` nil), `private`, `work`, and one per `agile-gtd-project-records` entry, keyed or not. Each carries `:filter`, `:next-range`, `:day-filter` and `:command` (nil for a project without a character `:key`)
- `agile-gtd--area-agenda-command` builds `a`, `pp`, `ww` and `w<key>` from it; the org-records-mcp views are built from the same rows. A change to what an area filters or defaults to goes in the table, never in one consumer

**org-records-mcp views** (`agile-gtd--apply-org-records-mcp`, behind `agile-gtd-enable-org-records-mcp`)
- `agile-gtd-org-records-mcp-views` generates keys `[<area>-]<view>[-<range>]`: 13 per area plus `inbox`, `tangling`, `human-turn`, `agent-turn` and `agent-wait`. Each carries a literal `:query` and no `:filter`/`:range`, so org-records-mcp refuses parameters. Every key searches `org-agenda-files` alone: never add `agile-gtd-loop-files` to a view
- The apply step merges views and the `rank`/`parent-priority` computed fields by name (dropping keys recorded in `agile-gtd--org-records-mcp-view-names` from the previous refresh), adds `rank` to `org-records-mcp-list-computed-fields` (what a match list carries unasked; `all` and the user's names are kept), sets `org-records-mcp-query-sort-fn`, `org-records-mcp-view-catalogue-function`, `org-records-mcp-allowed-files` (nil) and `org-records-mcp-file-scope-override` (t). It never starts the MCP server
- `blocked` and `breadcrumbs` are org-records-mcp node fields, not agile-gtd computed fields. `blocked` answers `org-blocker-hook`, so it sees org-edna's blockers only while `agile-gtd--apply-org-settings` keeps `org-edna-mode` on
- `agile-gtd-org-records-mcp-view-catalogue` writes the `org-view` description from the area table and range list; keep its words in step with the queries
- org-records-mcp's schema lists every key as the `enum` of `org-view`'s `view`, and the computed fields as that of `computed`, read when it registers the tools; `agile-gtd-org-records-mcp-schema-lists-every-key` reads them over tools/list

**Rank / sort key** (`agile-gtd--item-rank`, `agile-gtd--item-rank<`)
- Composite score from item priority, parent-project priority, deadline proximity, and scheduled date
- Cookies set the floor: the stronger of the item's own and its parent's, or `agile-gtd--rank-default` when neither states one
- Dates only ever lift that floor; a deadline further out than the floor already sits is ignored rather than demoting the item
- Scheduled only affects rank when `sc-delta <= 0` (today or overdue); future scheduled dates are ignored
- `agile-gtd--backlog-rank` accepts an optional `sc-delta` arg with the same convention as `dl-delta`
- `agile-gtd-rank` / `agile-gtd-agenda-rank` display a breakdown including both Deadline and Scheduled
- Used as the org-ql `:sort` comparator

**Tag management**
- Workflow tags (SOMEDAY, HABIT, LASTMILE, #work, #personal) managed in `agile-gtd--workflow-tag-alist`
- Customer tags injected alongside workflow tags on `agile-gtd-enable`

**Org settings** (`agile-gtd--apply-org-settings`, behind `agile-gtd-enable-org-settings`, default t)
- Runs first in `agile-gtd-refresh`: turns on `org-edna-mode`, adds `org-habit` to `org-modules`, removes Org's own enforce blockers from `org-blocker-hook`, and `set-default`s every pair in `agile-gtd--org-settings`
- `set-default`, not `setq`: a refresh run from an Org buffer whose startup options made a variable local must not change that buffer alone
- Next to `org-edna-mode` it adds `agile-gtd--org-edna-todo-keep-log-a` around `org-edna-action/todo!` (removed when the flag is off). A TRIGGER's `org-todo` runs inside the change that fired it, and Org keeps one pending log entry: without the advice `NEXT(n!)` on the triggered sibling replaces the pending `DONE(d@)` note, so the prompt never comes and org-records-mcp writes the closing note on the sibling. The advice binds fresh `org-log-note-*` state (fresh markers: `org-add-log-setup` moves them), writes the triggered entry at once without prose (`agile-gtd--store-log-note-now`), and leaves `post-command-hook` alone when `org-add-log-note` was on it already. `agile-gtd-chain-test.el` covers both paths
- `org-archive-location` derives from `org-directory` through `agile-gtd--expand-org-path`; values that follow from agile-gtd's own configuration are derived, never hard-coded
- Blocked tasks are hidden globally (`org-agenda-dim-blocked-tasks` `invisible`); the area commands (`agile-gtd--area-agenda-command`) and the `pb`/`wb` backlogs dim them with a command-level setting, because `org-agenda-finalize` sees only command settings, never a block's
- A setting added here goes into both test sandboxes and into [docs/org-settings.org](docs/org-settings.org), with its reason

**Link storing** (`agile-gtd--apply-link-storing`, behind `agile-gtd-enable-link-ids` and `agile-gtd-enable-link-kill-ring`)
- Two `:around` advices on `org-store-link`, added or removed on every refresh. `agile-gtd--org-store-link-ids-a` links a heading by `:ID:` in files under `org-directory`/`org-roam-directory` and by a created `:CUSTOM_ID:` slug elsewhere; `agile-gtd--org-store-link-kill-ring-a` copies the link to the kill ring as a bare link with an absolute `file:` path, preferring the heading's `id:` link when Org stores two
- Both act only when `org-store-link`'s INTERACTIVE? argument is non-nil. org-records-mcp mints every link it returns with a non-interactive `org-store-link` and refuses advice that changes the buffer or the link's form (`org-records-mcp--link-at-point`); a change that acts on non-interactive calls breaks it, and `agile-gtd-links-org-records-mcp-mints-its-own-links` guards that
- The kill-ring advice runs at depth -50, outermost, so it reads `org-stored-links` after the ID advice; it never writes `org-stored-links`, whose form `org-insert-last-stored-link` relies on
- org-roam is not a dependency: `org-roam-directory` is read with `bound-and-true-p`
- [docs/storing-links.org](docs/storing-links.org) describes the behaviour and the org-records-mcp contract for users

**Agent/human loop** (`agile-gtd-agent-tag`, `agile-gtd-human-tag`, `agile-gtd-loop-tags`, `agile-gtd-loop-files`)
- The two tags (`%agent` and `%human` by default) say whose move an item is; states stay the human's. `agile-gtd--apply-loop-tags` runs on every refresh in its own step, whatever `agile-gtd-enable-org-settings` says: it merges the two tag defcustoms' values plus `agile-gtd-loop-tags` (extra tags only, default nil) into `org-tags-exclude-from-inheritance` rather than setting it, takes out only what the previous refresh added (`agile-gtd--loop-tags-excluded`, as the org-records-mcp view names are tracked), and never records a tag the user had excluded first. Never list the agent or human name as a literal: a rename must move the exclusion with it. A tag name holds `%`, so it is never part of a format string: pass it as an argument, and write `%%` in a test fixture built with `format`
- `agile-gtd-hand-over` refuses a closed item, changes the state first — `org-todo` WAIT for an open task (`agile-gtd--hand-over-waits-p`, derived from `agile-gtd--wait-keyword` and `agile-gtd--container-keywords`), read back because a Lisp `org-todo` reports a block only in the echo area — or `org-add-note`, and only then swaps the local human tag for the agent tag, so a refused change leaves nothing half done. Both region-loop variables are bound nil. In an agenda it uses the `org-agenda-*` equivalents, so the lines update. The note is Org's own deferred prompt (`post-command-hook`), and exactly one: a second `org-add-log-setup` would overwrite the WAIT note. WAIT stays WAIT with a plain note, because `org-todo` logs a WAIT-to-WAIT change. There is no hand-back command: the agent hands back through org-records-mcp
- Turns (`agile-gtd-agent-claim-property`): `agile-gtd--turn` is the one classifier, a `cond` whose order is the precedence, so exactly one turn holds for a heading with a local loop tag or the claim: `withdrawn` first, then `agent-wait`/`delegated` (agent tag), `answered` (done), `replied` (WAIT or TODO), else `human-turn`. The predicates `human-turn`, `agent-turn` (optional KIND, one of `agile-gtd--agent-turn-kinds`) and `agent-wait` are aliases of `agile-gtd-human-turn` etc. and only ask the classifier; a change of meaning goes into `agile-gtd--turn` and `agile-gtd--turn-marks`, never into a view or the agenda. LOGBOOK notes move no turn (decided: state, local tags and claim only). `agile-gtd-turns-exactly-one-holds-for-every-looped-item` checks every combination against an independent transcription of the definitions; extend its combinations and oracle with any new input
- Tags are read with `org-get-tags nil t` and the claim with `org-entry-get` without inheritance. Never use org-ql's `tags-local` for a loop tag: its preamble matches the tag text anywhere in the heading line with `:query t`, so a title containing `:%agent:` counts as tagged. `agile-gtd--turn-preamble` only narrows (tags at the end of the heading line, or the claim's property line, case folded) and always keeps the predicate as the query; `agile-gtd--turn-candidate-p` is the cheap per-heading guard for when another predicate holds the preamble. `agile-gtd--turn-marks` signals on an unknown turn, because a preamble from no marks is an empty regexp and org-ql's preamble loop would never advance
- The `h` command has three `agile-gtd-agenda-ql-block`s (one per turn) and binds `org-agenda-files` at command level to `agile-gtd--loop-agenda-files` (agenda files plus `agile-gtd-loop-files`), evaluated at render and redo time; it dims blocked items (command-level `org-agenda-dim-blocked-tasks`, as the backlogs do). WAIT `%agent` items stay in the next-actions queries: no existing filter reads the loop tags

**org-edna integration**
- `agile-gtd-trigger-next-sibling` / `agile-gtd-blocker-previous-sibling` wire up task-chaining via org-edna triggers/blockers
- `agile-gtd-chain-task` sets both properties on the current heading

### Documentation

Human-facing docs are Org files. `README.org` is a primer: the concept, a real agenda capture, quickstart, install, limits, and a "Where to go next" table. Reference lives in `docs/*.org`, one page per question; `docs/CLAUDE.md` lists the pages and their conventions. Releases are described in `CHANGELOG.org`.

- A fact earns a place in `README.org` only by changing what the project is or what it costs to run. Everything else goes to a `docs/` page and is linked from the README's table.
- A code change that alters user-visible behaviour updates the `docs/` page describing it in the same change.
- Human-facing files never link into a `CLAUDE.md`.

### Per-directory notes

`test/CLAUDE.md` (suites, sandbox macros, adding a test file) and `docs/CLAUDE.md` (page index and doc conventions) load when a file in that directory is read. Changing the code in a directory obliges reconciling its `CLAUDE.md` before finishing.
