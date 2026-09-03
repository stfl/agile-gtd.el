# `last<unit>s-N`: rolling, boundary-aligned clock ranges

## Problem Statement

I track time with org-clock and review it by period. Org can select a range by
calendar name (`thismonth`, `thisyear`) and can chop that range into steps
(`:step week`), but the two units are chosen independently. Whenever the range
boundary is not a multiple of the step, the periods at each edge are partial.

`:block thismonth :step week` is the case that bites. A month rarely begins or
ends on a week boundary, so the week that rolls over the month end is split in
two: part of it is reported in one month, the rest in the next. Neither figure
answers "how much did I work that week?", and no row in either table does
either.

There is no way to ask for a rolling window of whole periods — "the last eight
weeks" — at all. `:block thisweek-8` looks like it should mean that, but it is a
*shift*: it selects the single week that fell eight weeks ago. `:tstart "<-8w>"`
is not calendar-aware; it subtracts exactly 56 days from midnight today, so the
window edge lands on whatever weekday today happens to be and the first period is
a stub again. The only escape upstream offers is hand-writing week-aligned
`:tstart`/`:tend` dates and editing them every week.

## Solution

A family of range keywords, `last<unit>s-N`, usable anywhere Org accepts a
`:block` value. Each selects the last N whole periods of that unit, ending with —
and including — the period currently in progress. Because the window is measured
in the same unit as its boundaries, every period is whole by construction.

```org
#+BEGIN: clockmatrix :block lastweeks-8 :step week
#+BEGIN: clocktable  :block lastmonths-12 :step month :match "alpha"
```

The keywords are implemented at Org's range-resolution layer rather than inside
any one dynamic block, so plain clocktable, stepped clocktable, and clockmatrix
all accept them.

## User Stories

1. As a user reviewing recent work, I want to write `:block lastweeks-8`, so that I get the last eight weeks without hand-computing dates.
2. As a user, I want every period in that window to be a whole period, so that no row shows a fraction of a week.
3. As a user whose work week rolls over a month end, I want that week reported once and in full, so that I can see what I actually worked that week.
4. As a user, I want the window to include the period in progress, so that today's work is visible in the report.
5. As a user, I want the current period's row to grow as the period proceeds, so that the report stays live without my editing it.
6. As a user, I want `lastweeks-1` to mean just the current week, so that N counts periods rather than offsets.
7. As a user, I want the keyword family to cover days, so that I can write `lastdays-14`.
8. As a user, I want it to cover weeks, so that I can write `lastweeks-8`.
9. As a user, I want it to cover semimonths, so that the family matches every `:step` unit without exception.
10. As a user, I want it to cover months, so that I can write `lastmonths-12` for a rolling year.
11. As a user, I want it to cover quarters, so that I can write `lastquarters-4`.
12. As a user, I want it to cover years, so that I can write `lastyears-2`.
13. As a user, I want the same keyword to work in a plain clocktable, so that I am not forced into clockmatrix to get a rolling window.
14. As a user, I want it to work in a stepped clocktable, so that `:block lastweeks-8 :step week` produces eight weekly sub-tables.
15. As a user, I want it to work in clockmatrix, so that a rolling window renders as a period-by-project matrix.
16. As a user, I want the plural to distinguish it from Org's `lastweek`, so that a span is never confused with a shift.
17. As a user, I want `:step` to remain something I write explicitly, so that no parameter silently sets another.
18. As a user, I want a finer step that divides the window cleanly to be allowed, so that `:block lastweeks-8 :step day` gives me 56 daily rows.
19. As a user, I want no warning when the step does not tile the window, so that the block stays simple and the choice stays mine.
20. As a user, I want `:block` to keep its existing precedence over `:tstart`/`:tend`, so that there is no new conflict rule to learn.
21. As a user, I want `S-<left>` and `S-<right>` on such a block to refuse rather than rewrite it, so that my parameter is never silently destroyed.
22. As a user, I want that refusal to read exactly like Org's refusal for `untilnow`, so that it is indistinguishable from any other unshiftable block.
23. As a user, I want a nonsensical count such as `lastweeks-0` to be reported, so that I am not handed an empty table with no explanation.
24. As a user, I want an unrecognised unit to keep producing Org's own "No such time block" error, so that typos fail the way they always have.
25. As a user, I want week boundaries to follow `:wstart`, so that the window aligns with every other clock report I have.
26. As a user, I want `:wstart` to keep defaulting to Monday, so that existing reports are unaffected.
27. As a user, I want month boundaries to follow `:mstart`, so that a shifted accounting month is respected.
28. As a user, I want clockmatrix's `:stepskip0` to default to nil like clocktable's, so that the two blocks agree on defaults they share.
29. As a user, I want to keep dropping empty rows by writing `:stepskip0 t`, so that the behaviour I relied on remains available.
30. As a user, I want a rolling window with `:stepskip0 nil` to show empty periods, so that a week I did not work is visible as a gap rather than absent.
31. As a user, I want the keyword documented in the README with the rest of the range vocabulary, so that I can find it without reading source.
32. As a user, I want the singular-versus-plural distinction called out in the documentation, so that the trap is named before I fall into it.
33. As a maintainer, I want the keyword implemented in one place rather than per dynamic block, so that a new block type gets it for free.
34. As a maintainer, I want the internal decomposition free to change, so that tests do not break when I refactor.

## Implementation Decisions

**Layer.** The keywords are resolved at Org's range-resolution layer, which every
clock consumer already funnels through — the clocktable writer, the stepped
clocktable, the table-data collector, and clockmatrix. Implementing there is what
makes the feature generic; implementing inside clockmatrix would satisfy only one
caller. Org's own resolver hard-errors on unrecognised keywords rather than
falling through, so the new keywords must be handled ahead of it, delegating
anything unrecognised so existing behaviour and existing error messages are
preserved exactly.

**Naming.** `last<unit>s-N`, pluralised, for all six units that `:step` accepts:
day, week, semimonth, month, quarter, year. Full symmetry with `:step` is
deliberate — a five-of-six family would make the missing one a special case to
remember, surfacing as a "No such time block" error at the moment a user
reasonably expects symmetry. The plural is load-bearing: Org's singular
`lastweek` means *the previous week* (a shift, excluding the current one), while
`lastweeks-N` means *the last N weeks* (a span, including the current one).

**Semantics.** N periods ending with, and including, the period currently in
progress. N counts periods, so `lastweeks-1` is the current week alone and is
equivalent to `thisweek`. N must be a positive integer; zero or negative is
reported rather than yielding an empty table. Boundaries derive from the same
`:wstart`/`:mstart` the caller already passes, so the window aligns with every
other clock report; week start continues to default to Monday.

**No inference.** `:step` is never derived from the block keyword. Org's dynamic
blocks use flat defaults plus documented precedence and never derive one
parameter from a sibling's value; introducing inference here would be novel in
Org and surprising. `:block lastweeks-8` written without `:step` therefore uses
whatever `:step` defaults to, and it is the caller's job to write the one they
want.

**No divergence checking.** A `:step` that does not tile the window evenly
produces partial periods, and that is permitted silently. The alternative —
warning when the units disagree — requires a rule subtler than "the names
differ", because a finer step that divides cleanly is perfectly legitimate:
`lastweeks-8 :step day` is a sound 56-row daily view, and `lastyears-2 :step
quarter` is a sound 8-row quarterly one. Encoding that tiling relation was judged
more complexity than the problem warrants. Choosing a sensible pair is the
caller's responsibility.

**Precedence.** No new rule. The keywords are `:block` values, so Org's existing
precedence of `:block` over `:tstart`/`:tend` applies unchanged.

**Shift guard.** Org's clocktable shift command rewrites a block's `:block` value
in place. Its fallback branch already refuses blocks it cannot shift —
`untilnow`, `interactive`, and anything unrecognised — with a single message. The
new keywords, however, slip past that guard: an unanchored numeric branch
intended for bare years matches the digits in `lastweeks-8`, reads them as a
year, and silently rewrites the block to the year 9. Measured:

```
:block thisweek-8      ->  :block thisweek-7     (correct)
:block lastweeks-8     ->  :block 9              (corrupted)
:block lastmonths-12   ->  :block 13             (corrupted)
```

The shift command therefore refuses these blocks, reusing Org's own message
verbatim so the experience is indistinguishable from any other unshiftable
block. This is restoring Org's evident intent, not new policy. The exposure
exists only because the keywords are generic: the shift command is gated to the
literal block name `clocktable`, so it never touches a clockmatrix block.

**Installation.** The range keywords and the shift guard install when the package
loads, alongside the existing dynamic-block registration, rather than inside the
package's enable entry point. Deferring them would make the keyword mysteriously
absent until enable ran. This does mean loading the package alters range parsing
for every clocktable in the user's Emacs; the keywords belong upstream in Org
eventually, and the local implementation is the interim.

**Module placement.** The keywords are not clockmatrix-specific and live in their
own section, not under clockmatrix.

**`:stepskip0` default.** Clockmatrix's default changes from `t` to `nil` to
match the common dynamic-block API pattern: clocktable's defaults set
`:stepskip0 nil`, and where a block borrows a parameter name it borrows the
default with it. A shared name carrying two different defaults is the defect
being corrected — a reader who knows one block should not have to check whether
the other silently disagrees. Blocks that relied on the old default gain empty
rows and restore their previous rendering by writing `:stepskip0 t` explicitly,
which is already the prevailing habit in the author's files.

**Week start, documented not changed.** Week start comes from `:wstart`,
defaulting to 1 (Monday) via clocktable's defaults. Org's clock code never reads
`calendar-week-start-day` — that variable governs only how the calendar grid is
drawn. This is documented because the opposite is a reasonable assumption, and
acting on it would silently shift every weekly report by a day.

**Relationship to existing decisions.** This feature changes range resolution
only. It does not touch file scope, so the default-scope ADR is unaffected, and
it adds no notion of money, invoicing, drill-down, or non-project time.

## Testing Decisions

**What makes a good test here.** Tests assert only on what a user can observe:
the text a dynamic block renders, and whether an interactive command refuses.
They must not reach into range arithmetic, keyword parsing, or period stepping,
so the internal decomposition stays free to change. A test that breaks when a
helper is renamed, split, or inlined — without any rendered output changing — is
a bad test.

**Seams.** Two, both user-observable, confirmed with the author before writing:

1. **Dynamic block render** — the existing seam, unchanged. Insert a
   `#+BEGIN: … #+END:` block, refresh it, assert against the resulting buffer
   text. It is applied to **both** clockmatrix and plain clocktable. Exercising a
   real clocktable is what proves the keyword is generic; testing only through
   clockmatrix would leave the feature's entire reason for existing unverified.
2. **The shift command** — new, and new only because the guard is not reachable
   through block rendering. Invoke the command on a buffer holding such a block
   and assert it refuses and leaves the block's parameter intact. This is a
   user-facing interactive command, so the seam is still at the highest available
   point.

Asserting directly on the range resolver's return value was considered and
rejected: it would couple tests to a return shape that is Org's rather than
ours, for no coverage the rendered output does not already give.

**Fixtures.** Reuse the package's existing test sandbox, which binds the org
directory to a temporary location and isolates Org's global state, together with
the fixture macro that writes synthetic files with known clock entries and binds
the project registry to point at them. Fixtures are synthetic and
self-contained — never the author's real files, whose contents change and whose
numbers would make the suite non-deterministic.

**Determinism.** These keywords are relative to the current date, so fixtures
must derive their clock entries from the current date at run time rather than
hard-coding dates, or assert on relationships between rows rather than on
absolute labels. This is a departure from the existing clockmatrix tests, which
use fixed 2026 dates with explicit ranges, and is the main new hazard in this
suite.

**Prior art.** The clockmatrix suite already drives everything through the
dynamic block and captures a warning while rendering; the shift-refusal test
follows the same shape, capturing an error instead.

**Coverage.** At minimum: one row per period for a rolling window; the window
including the current period; N counting periods, with `lastweeks-1` equalling
`thisweek`; each of the six units resolving, with semimonth covered across a
month boundary because it is the newest step keyword and the likeliest
cross-version wrinkle; the keyword working in a plain clocktable as well as
clockmatrix; a finer step that tiles cleanly producing whole sub-periods; a
non-positive N reported; an unrecognised unit still producing Org's own error;
`:wstart` shifting the window's boundaries; the shift command refusing and
leaving the block unmodified; and clockmatrix's `:stepskip0` defaulting to nil
with `t` still dropping empty rows.

## Out of Scope

- **A `:last` or `:since` parameter.** Both were designed and rejected in favour
  of extending `:block`, which adds no parameter and keeps range selection in one
  place.
- **Inferring `:step` from the block keyword.** Rejected as novel in Org and
  surprising.
- **Warning when step and window units diverge.** Rejected as more complexity
  than the problem warrants.
- **An `:align` modifier** that snaps a named range such as `thismonth` outward
  to whole steps. It solves an adjacent problem and would change what a total
  means, so it needs its own decision.
- **Upstreaming the keywords to Org.** The right long-term home, but not this
  change.
- **Editing the author's existing org files.** Blocks already committed there
  keep their current parameters and gain rows when next refreshed.
- **Fixing Org's unrelated shift bug**, where shifting a block holding a specific
  date errors on a type mismatch.
- **Changing `calendar-week-start-day` handling.** Documented, deliberately not
  acted upon.
- **Any change to file scope, money, invoicing, drill-down, or non-project
  time**, all of which remain as the clockmatrix spec and the default-scope ADR
  settled them.

## Further Notes

**The plural is the whole distinction.** `lastweek` and `lastweeks-1` differ by
one character and by a week: the first is the *previous* week, the second is the
*current* one. This is the part of the design most likely to trip someone later
and is called out in the documentation for that reason. It was accepted because
the alternative — inventing an unrelated word for the span form — costs more
familiarity than the ambiguity costs.

**Advice on core Org is an interim arrangement.** Making the keywords generic
means the package alters range parsing globally for the user's whole Emacs, which
is a heavier footprint than a package would normally take and is worth revisiting
before publication.

**The shift corruption is silent and destructive.** The original parameter is
gone from the buffer once rewritten, and in files under an auto-committing sync
daemon the corrupted value can be committed and pushed before anyone notices. The
likely first symptom is a clocktable inexplicably reporting no time, long after
the cause is recoverable. This is why the guard is in scope rather than left to
the caller, unlike the divergence warning.
