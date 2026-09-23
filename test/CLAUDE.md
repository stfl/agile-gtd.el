# test/

ERT suites, split by concern:

| File | Coverage |
|---|---|
| `agile-gtd-test.el` | `agile-gtd-enable`, configuration application, capture templates, agenda commands |
| `agile-gtd-rank-test.el` | rank and sort functions |
| `agile-gtd-org-ql-predicates-test.el` | custom org-ql predicates |
| `agile-gtd-agenda-test.el` | agenda query helpers |
| `agile-gtd-range-test.el` | view-range cutoffs, the rank/grouping contract, and the Scheduled group |
| `agile-gtd-startup-test.el` | the project registry, its normalisation and skip-and-warn, and the project-tag startup check |
| `agile-gtd-org-records-mcp-test.el` | the org-records-mcp view keys, called through `org-records-mcp--tool-view` over fixture files; computed fields, refusals, the apply step and its flag |

## Isolation

The `agile-gtd-test-with-sandbox` macro (`agile-gtd-test.el`) isolates each test by binding all relevant org/agile-gtd/org-records-mcp variables to clean defaults and using a temporary `org-directory`. It and `agile-gtd-org-ql-test-with-sandbox` (`agile-gtd-org-ql-predicates-test.el`) both bind every variable `agile-gtd--apply-org-settings` sets, plus `org-edna-mode`, `org-blocker-hook`, `org-trigger-hook` and `org-modules`; keep both in step with `agile-gtd--org-settings`. Always use one of these macros rather than mutating global state directly: a leaked `org-agenda-files` or `org-todo-keywords` makes a later test pass or fail for reasons unrelated to it.

`agile-gtd-org-records-mcp-test.el` requires `agile-gtd-test` for the sandbox. The Eask script loads `agile-gtd-test.el` first, which provides it; running the file alone needs `-L test` or an explicit `-l test/agile-gtd-test.el` before it.

## Adding a test file

The Eask `test` script names every suite explicitly. A new file under `test/` runs only once it is appended to that list in `Eask`; `eask test ert` does not glob.

## Stale bytecode

`eask run script test` deletes `*.elc` before running, because Emacs loads a stale `agile-gtd.elc` in preference to newer source. Running ERT by hand after `just build` exercises the last compile, not the working tree: delete `agile-gtd.elc` first.

## CI

CI runs the suite on Emacs 30.2 and 31.1. The two differ in whether `warnings.el` is preloaded, so a test that captures warnings (the startup suite) can pass on one and fail on the other; `(require 'warnings)` at the top of such a file is what keeps them equal.

## Maintenance

A change to a test file's scope updates the table above in the same change.
