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

This is a single-file Emacs Lisp package (`agile-gtd.el`) with four companion test files under `test/`.

### Main entry points

- `agile-gtd-enable` — call once after customising variables; delegates to `agile-gtd-refresh`
- `agile-gtd-refresh` — validates config, then applies all derived settings (priorities, keywords, tags, agenda files, refile targets, capture templates, agenda commands)

### Key subsystems

**Priority system** (`agile-gtd-priority-highest/default/lowest`, A–I range)
- `agile-gtd--priority-range` derives the active character range
- `agile-gtd--prio-rank` / `agile-gtd--backlog-rank` map priorities to numeric ranks used for sorting
- Rank functions are derived from the configured range and must not hard-code character values

**TODO keywords**
- Sequence: `TODO → NEXT → WAIT → PROJ → EPIC | DONE, IDEA, KILL`
- Public accessors: `agile-gtd-project-keyword`, `agile-gtd-action-keywords`

**Agenda queries** (org-ql based)
- `agile-gtd-agenda-query-next-actions` — sprint / next-actions view
- `agile-gtd-agenda-query-backlog` — backlog with priority grouping
- `agile-gtd-agenda-query-inbox` — unprocessed inbox items
- `agile-gtd-agenda-query-stuck-projects` — projects with no NEXT action
- Customer-specific agenda commands generated from `agile-gtd-customers`

**Rank / sort key** (`agile-gtd--item-rank`, `agile-gtd--item-rank<`)
- Composite score from item priority, parent-project priority, deadline proximity, and scheduled date
- Scheduled only affects rank when `sc-delta <= 0` (today or overdue); future scheduled dates are ignored
- `agile-gtd--backlog-rank` accepts an optional `sc-delta` arg with the same convention as `dl-delta`
- `agile-gtd-rank` / `agile-gtd-agenda-rank` display a breakdown including both Deadline and Scheduled
- Used as the org-ql `:sort` comparator

**Tag management**
- Workflow tags (SOMEDAY, HABIT, LASTMILE, #work, #personal) managed in `agile-gtd--workflow-tag-alist`
- Customer tags injected alongside workflow tags on `agile-gtd-enable`

**org-edna integration**
- `agile-gtd-trigger-next-sibling` / `agile-gtd-blocker-previous-sibling` wire up task-chaining via org-edna triggers/blockers
- `agile-gtd-chain-task` sets both properties on the current heading

### Documentation

When making any code changes, update `README.org` to reflect them.

### Test conventions

Tests live in `test/` and are split by concern:

| File | Coverage |
|---|---|
| `agile-gtd-test.el` | `agile-gtd-enable`, configuration application, capture templates, agenda commands |
| `agile-gtd-rank-test.el` | rank and sort functions |
| `agile-gtd-org-ql-predicates-test.el` | custom org-ql predicates |
| `agile-gtd-agenda-test.el` | agenda query helpers |

The `agile-gtd-test-with-sandbox` macro isolates each test by binding all relevant org/agile-gtd variables to clean defaults and using a temporary `org-directory`.  Always use this macro (or the sandbox it provides) rather than mutating global state directly.
