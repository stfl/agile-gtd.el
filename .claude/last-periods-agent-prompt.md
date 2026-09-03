# Agent prompt — implement `last<unit>s-N` rolling clock ranges

Copy everything below the line as the first message to a fresh agent.

---

Implement the `last<unit>s-N` Org range keywords and the `:stepskip0` default
change. The full spec is at `~/work/agile-gtd/.claude/last-periods-spec.md` —
**read it first and follow it**; it records not just what to build but what was
deliberately rejected and why. The design was settled in a long interview, so
treat its decisions as closed unless you find a fact that contradicts one.

Background reading, in this order: `.claude/last-periods-spec.md`, then
`.claude/clockmatrix-spec.md` (the feature this builds on), then
`docs/adr/0001-clockmatrix-default-scope.md`.

`~/work/agile-gtd/.claude/` is untracked and **must stay that way**. Never
`git add -A`; stage explicit paths.

## Starting state

- Repo `~/work/agile-gtd`, branch `main`, at `863ef5e feat(clock): add clockmatrix dynamic block`.
- The working tree has **one uncommitted change**: a note in `README.org`
  documenting where week start comes from. It describes already-shipped
  behaviour and is unrelated to this feature — commit it on its own first so
  your feature commit stays clean.
- `just test` → 76 passing. `just lint` → clean. `just build` → warnings exist
  but all pre-date this work (lines ~977–1076); nothing from the clockmatrix
  section warns. Keep it that way.
- System Emacs is **31.0.91**, Org **9.8.7**. CI already covers 30.2 and
  `release-snapshot` (= the emacs-31 branch); **no CI change is needed**.

## Scope

Two changes, one commit each is fine:

1. **`last<unit>s-N` range keywords** — six units matching `:step` exactly:
   `lastdays-N`, `lastweeks-N`, `lastsemimonths-N`, `lastmonths-N`,
   `lastquarters-N`, `lastyears-N`. Each selects the last N whole periods of
   that unit, **ending with and including the period in progress**.
   `lastweeks-1` therefore equals `thisweek`. N must be a positive integer;
   report anything else.
2. **`:stepskip0` default flips `t` → `nil`** in clockmatrix, to match the
   common dynamic-block API pattern. `org-clocktable-defaults` sets
   `:stepskip0 nil`, and a parameter that shares a name across blocks must not
   disagree on its default. This is the whole point of the change — **it is not
   negotiable, and it is not a bug to be fixed.** Nine existing tests break as a
   direct result (listed below); the correct response is to update those tests,
   never to restore the old default.

Deliverables: `agile-gtd.el` (new section, *not* under clockmatrix — the
keywords are generic), tests, `README.org`. No new ADR unless you think the
advice-on-core-Org decision warrants one.

### THE TRAP THAT WILL WASTE YOUR TIME

`just build` writes `agile-gtd.elc` next to the source, and `eask test` loads
the **`.elc` in preference to the `.el`**. Any edit you make after a build is
invisible to the tests, which then pass against dead code with no warning.

```sh
rm -f agile-gtd.elc     # before every test run where the source changed
```

This is not hypothetical: during the clockmatrix work it made a whole suite
appear to pass while every mutation survived. `*.elc` is gitignored, so
`git status` will not reveal it. Also note `rm -f agile-gtd.elc test/*.elc`
**aborts entirely under zsh** when the glob matches nothing — remove the one
file, or use `find`.

### Verified technical facts (do not re-derive these)

- **`org-clock-special-range` is the single integration point.** Signature
  `(key &optional time as-strings wstart mstart)`. It is called **8 times, all
  inside `org-clock.el`** — from the clocktable writer, `org-clocktable-steps`,
  and `org-clock-get-table-data`. `agile-gtd--clockmatrix-range` also calls it.
  Advising it therefore covers plain clocktable, stepped clocktable, and
  clockmatrix from one place. That is what "generic" means here.
- It **hard-errors on unrecognised keys**: `(_ (user-error "No such time block %s" key))`.
  So new keywords must be intercepted *before* it, delegating everything else
  through untouched so existing behaviour and error messages are byte-identical.
- **`org-clocktable-defaults`** carries `:wstart 1` and `:stepskip0 nil`. The
  clocktable writer merges it with `(org-combine-plists org-clocktable-defaults params)`,
  which is why an omitted `:wstart` is Monday.
- **`org-clocktable-shift` silently corrupts these keywords.** Measured:
  ```
  :block thisweek-8      ->  :block thisweek-7     correct
  :block lastweeks-8     ->  :block 9              CORRUPTED
  :block lastmonths-12   ->  :block 13             CORRUPTED
  ```
  Its second regex branch is unanchored and matches the *digits*, reading them
  as a bare year. Its fallback branch already refuses unshiftable blocks with
  `(t (user-error "Cannot shift clocktable block"))` — it refuses `untilnow`,
  `interactive` and garbage that way. **Reuse that exact message** so the
  refusal is indistinguishable from Org's own. A `:before` advice checking the
  `:block` value on the current line is enough (~6 lines).
- The shift command is gated to the **literal block name `clocktable`**
  (`#\+BEGIN:[ \t]+clocktable\>`), so it never touched clockmatrix blocks. The
  corruption exposure exists *only* because these keywords are generic.
- **`calendar-week-start-day` is irrelevant** — zero references across
  `org-clock.el`, `org.el`, `org-agenda.el`. Week start comes from `:wstart`.
  Do not wire it in; this was decided and documented deliberately.
- **`:wstart` is a `decode-time` day number, 0–6** (Sunday is 0). Value `7`
  makes the week step land on its own start date and loop forever; clockmatrix
  already guards this — reuse that guard's behaviour, do not reintroduce a hang.
- `org-matcher-time` supports `<±Nh/d/w/m/y>` but is **not** calendar-aware
  (`<-8w>` is exactly 56 days from midnight, `<-1m>` is a flat 31 days). It is
  not a substitute for these keywords; that was checked.

### Design decisions that are closed

- **No `:step` inference.** `:block lastweeks-8` does not set `:step`. Org's
  dynamic blocks use flat defaults plus precedence and never derive one
  parameter from a sibling; inference would be novel and surprising.
- **No divergence warning** when `:step` fails to tile the window. Deliberately
  the caller's responsibility. Note a finer step that divides cleanly is
  *legitimate*: `lastweeks-8 :step day` is a sound 56-row view.
- **No new precedence rule.** These are `:block` values, so `:block` over
  `:tstart`/`:tend` applies unchanged.
- **Install at load time**, alongside the existing `org-dynamic-block-define`
  call — not inside `agile-gtd-enable`.
- **`:stepskip0` defaults to nil**, matching the common dynamic-block API
  pattern. Where clockmatrix shares a parameter name with clocktable, it shares
  the default too. Divergent defaults on a shared name were the defect being
  corrected.
- Rejected alternatives, do not resurrect: a `:last` parameter, a `:since`
  parameter, an `:align` modifier, upstreaming as part of this change.

## Testing — two seams, both confirmed with the author

**Seam 1, existing — the dynamic block.** Insert `#+BEGIN: … #+END:`, refresh
with `org-update-dblock`, assert on the resulting buffer text. Reuse the helpers
already in `test/agile-gtd-clockmatrix-test.el`. Apply it to **both clockmatrix
and plain clocktable** — exercising a real clocktable is the only thing that
proves the keyword is generic, which is the entire point of the feature.

**Seam 2, new — the shift command.** Invoke it on a buffer holding such a block;
assert it refuses and leaves the `:block` value intact.

Do **not** assert on `org-clock-special-range`'s return value. That was
considered and rejected: it couples tests to a 3-element return shape that is
Org's, not ours, for no coverage the rendered output does not already give.

**Determinism hazard, new to this suite.** These keywords are relative to *today*,
so you cannot hard-code 2026 dates the way the existing clockmatrix tests do.
Derive fixture clock entries from the run date, or assert on relationships
between rows rather than absolute labels. Get this wrong and the suite goes
flaky months later.

Note `org-update-all-dblocks` swallows errors via `condition-case-unless-debug`
— use `org-update-dblock` with point on the `#+BEGIN:` line when a test needs to
observe an error.

**Prove the tests actually bite.** Mutation-test them: break the implementation
deliberately and confirm the suite goes red. During the clockmatrix work this
caught a coverage hole no amount of reading would have. Verify at minimum that
reversing the include-current-period rule, and breaking the N-counts-periods
rule, both fail.

### The `:stepskip0` flip breaks exactly 9 existing tests

Measured, so you can plan rather than discover:

```
agile-gtd-clockmatrix-clips-the-last-period-to-the-range-end
agile-gtd-clockmatrix-honours-a-non-default-wstart
agile-gtd-clockmatrix-honours-tags-override
agile-gtd-clockmatrix-keeps-a-project-in-historical-ranges
agile-gtd-clockmatrix-reads-a-project-from-a-renamed-file
agile-gtd-clockmatrix-renders-periods-against-projects
agile-gtd-clockmatrix-steps-semimonths-twice-in-a-month
agile-gtd-clockmatrix-steps-weeks-from-the-range-start
agile-gtd-clockmatrix-suppresses-totals
```

Each relied on the old default dropping all-zero rows. **Preserve each test's
original intent** by adding `:stepskip0 t` to its block parameters — do not
weaken assertions to make them pass. Then add a test asserting the *new* default
renders empty rows, and check whether
`agile-gtd-clockmatrix-keeps-all-zero-rows-with-stepskip0-nil` still tests
anything meaningful now that nil is the default; it likely needs inverting to
cover `:stepskip0 t`.

## Verification

```sh
cd ~/work/agile-gtd
rm -f agile-gtd.elc
just test && just lint && just build
```

Then confirm the thing the suite cannot: that the keyword works in a **plain
clocktable** under the user's real configuration.

```sh
emacs -q --batch -l ~/.config/doom/test/bootstrap.el \
      -l ~/work/agile-gtd/agile-gtd.el -l /tmp/check.el
```

Do **not** set `DOOMPROFILE` when running that bootstrap; it repoints
`doom-data-dir` and the generated init is not found. Note the doom config
currently points agile-gtd at this local repo via `:local-repo`, so the loaded
package is already your working copy.

Assert there that `#+BEGIN: clocktable :block lastweeks-2 :step week` renders two
weekly sub-tables with Monday start dates, and that `lastweeks-1` covers the same
range as `thisweek`.

## Do not

- Touch `~/.org`. Its clockmatrix blocks keep their current parameters and will
  gain rows when next refreshed — that was decided deliberately.
- Commit in `~/.config/doom`. It carries two intentional uncommitted changes: a
  temporary `:local-repo` recipe, and a calendar week-start setting.
- Push anywhere.
- Create GitHub issues, labels, or PRs. The repo is **public**; be careful not
  to put real client tags (the author's project tags) into anything that could
  become public — use the README's `alpha`/`beta`/`gamma` placeholders.
- Add `.claude/` to git.
- Change the Emacs version floor. `Eask` and `Package-Requires` stay at
  `emacs "30.2"`.
- Wire in `calendar-week-start-day`, add `:step` inference, add a divergence
  warning, or add `:last`/`:since`/`:align`. All explicitly rejected.
- Edit `.claude/*-spec.md`. They are the author's design records.

## Report back

What changed and the commits you made; `just test`, `just lint`, `just build`
output; which mutations you used to prove the tests bite and that each failed;
the plain-clocktable verification result; how you handled the 9 broken tests; and
anything in the verified-facts list above that turned out to be wrong.
