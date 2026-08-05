# 1. Clockmatrix default scope: per-project files, not a full agenda scan

## Status

Accepted

## Context

The `clockmatrix` dynamic block renders a table of clocked time with calendar periods
down the rows and projects across the columns. Each cell is one clock-sum over a
(period, project) pair, so the number of file scans the block performs is periods ×
projects × files scanned per cell. That multiplier makes file scope the dominant cost
of a refresh.

A 12-period × 4-project grid (48 cells) scanning the full agenda file set — around 27
files — measures roughly 14 seconds to render. Scoping each project's cells to only
that project's own two files (its main file and its archive) brings the same grid
under a second. `clockmatrix` refreshes with `C-c C-c` like any Org dynamic block, and
a multi-second wait on every refresh defeats the point of an interactive report.

## Decision

The default scope, per project, is that project's own file plus `archive/<file>`,
resolved through the package's existing `agile-gtd--project-file` accessor and its
org-path expansion. Files that do not exist are filtered out with `file-exists-p`
before scanning.

`:scope agenda-with-archives` selects `(org-add-archive-files (org-agenda-files t))`
as an explicit, opt-in audit path that scans the full agenda file set instead.

A related decision governs missing files: a project whose *main* file is absent is
a misconfiguration, not an absence of clocked time, and the block warns, naming the
project, the path it tried, and both remedies — set `:file` in `agile-gtd-projects`,
or use `:scope agenda-with-archives`. A missing *archive* file produces no warning,
because archives are routinely absent by design; most projects never accumulate one.

## Consequences

Refresh is fast enough to run interactively at the file scope that makes the report
useful in the first place.

The default scope has a known failure mode: clocked time that carries a project's tag
but lives in a file other than that project's own — for example, an item captured to
an inbox, clocked there, and not yet refiled — is invisible under the default scope,
and produces no error. On the dataset this was designed against, the two scopes agree
exactly, so divergence is zero today, but that agreement is a property of that data,
not an invariant the default scope guarantees. The remedy is `:scope
agenda-with-archives`, which trades the speed of the default for a scan wide enough to
catch tagged-but-unrefiled entries anywhere in the agenda.

A missing main file surfaces as a named warning rather than a silent zero-hours
report, so a misregistered project (most commonly, a project whose file is not named
after its tag and needs an explicit `:file`) is caught rather than misreported.

## Alternatives considered

**Wide scope for every cell.** Scanning the full agenda file set for every
(period, project) cell is correct — it cannot miss unrefiled entries — but costs
roughly an order of magnitude more time, matching the ~14s measurement above against
the same grid.

**Wide scope plus a per-tag prefilter.** Narrowing the wide file set by tag before
summing lands in between the two extremes on speed, but spends most of its budget
rediscovering the project-to-file mapping that `agile-gtd-projects` already holds,
making it a worse trade than either scoping directly to project files or scanning
everything.
