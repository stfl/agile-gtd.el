# docs/

Human reference pages, one per question a user arrives with. Every file here is read by someone using agile-gtd, never by someone changing it: no internals, no private function names unless the user calls them, and no link into any `CLAUDE.md`.

| Page | Answers |
|---|---|
| `workflow.org` | states, hierarchy, tags, deferral, inbox and capture, metadata |
| `priorities-and-rank.org` | what each priority means; how parent priority, deadlines and scheduled dates make rank |
| `view-ranges.org` | the five ranges, which command opens where, rotating, pinned ranges for the query functions |
| `agenda-commands.org` | every agenda command and how a grouped block is ordered |
| `projects.org` | `agile-gtd-projects`, project records, the shared clocking registry, the startup tag check |
| `task-dependencies.org` | org-edna chains and how blocked tasks appear |
| `org-ql-predicates.org` | the public org-ql predicates |
| `org-records-mcp.org` | view keys, key grammar, what agile-gtd sets in org-records-mcp, setup |
| `configuration.org` | what `agile-gtd-enable` / `agile-gtd-refresh` change in Org |
| `org-settings.org` | each Org option agile-gtd applies, its value and its reason |

## Conventions

- Org format, `#+title:` first, then a two-sentence header saying what the page answers with a link back to `../README.org`. Sections start at `*`.
- Link between pages with `[[file:page.org][...]]` or `[[file:page.org::*Heading][...]]`. A heading used as a link target is load-bearing: renaming it means grepping `docs/` and `README.org` for `::*Old heading`.
- Present tense only. A removal or rename goes in `../CHANGELOG.org`, never on a page.
- Example project tags are `alpha`, `beta` and `gamma`. An example `:key` never uses a character already taken under the `w` prefix (`w`, `b`, `s`), or the generated command shadows a built-in one.
- The package installs no keybindings. Name commands, not keys; a key in a table is a claim the code does not back.

## Where a fact goes

- A fact earns a place in `../README.org` only when it changes what the project is or what it costs to run. Everything else lands on one of these pages and the README's "Where to go next" table links to it.
- A new page needs a row in that table and in the table above.
- The README's "What it looks like" output is a real capture. When a change alters agenda output (grouping, headers, range cutoffs), re-render it: load `agile-gtd` in `emacs -batch`, set `org-directory` to a directory holding the example `todo.org`, call `agile-gtd-enable`, then `(org-agenda nil "a")` and `agile-gtd-agenda-set-range`, and print `buffer-string`.

## Maintenance

A code change that alters user-visible behaviour updates the page that describes it in the same change. Grep the pages for the symbol or command name you touched; the README only needs a change when the admission test above says so.
