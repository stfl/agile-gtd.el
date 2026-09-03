# Agent prompt — implement `clockmatrix` and wire it in

Copy everything below the line as the first message to a fresh agent.

---

Implement the `clockmatrix` Org dynamic block and wire it into my running config. The full
spec is at `~/work/agile-gtd/.claude/clockmatrix-spec.md` — **read it first and follow it**;
it records not just what to build but what was deliberately rejected and why.

Work in three phases, in order. Do not start a phase until the previous one verifies.
`~/work/agile-gtd/.claude/` is untracked and must stay that way.

Commit policy differs per repo, deliberately:

| Repo | Commit? |
|---|---|
| `~/work/agile-gtd` | **No** — leave as working-tree changes |
| `~/.config/doom` | **No** — leave as working-tree changes |
| `~/.org` | **Yes** — one meaningful commit (see Phase 3; a sync daemon requires it) |

Never push in any of them.

## Phase 1 — build it (`~/work/agile-gtd`)

A dynamic block rendering clocked time as a matrix: calendar periods down the rows,
projects across the columns, totals on both axes.

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

Deliverables:

- `agile-gtd.el` — the feature, ~90 lines, as one clearly delimited section before
  `(provide 'agile-gtd)`. Add `org-clock` and `org-duration` to the requires block; neither
  is currently pulled in.
- `test/agile-gtd-clockmatrix-test.el` — new.
- `Eask` — the `(script "test" …)` line enumerates test files explicitly; add the new one
  or it will not run in CI.
- `.github/workflows/ci.yml` — **add Emacs 31 to the test matrix** (see below).
- `README.org` — a section documenting the block and its full parameter list.
- `docs/adr/0001-clockmatrix-default-scope.md` — the directory does not exist yet.

### Emacs 31 in CI

My system Emacs is **31.0.91**, but `matrix.emacs-version` in the CI workflow lists only
`"30.2"`. So `just test` locally has been exercising 31 while CI has only ever checked 30.2.
Add a 31 entry: use the highest released 31.x that `purcell/setup-emacs` offers, and if 31
is not yet available there, use `"snapshot"` with `continue-on-error: true` on that matrix
entry so upstream churn doesn't red the build. `fail-fast: false` is already set.

This matters for this feature specifically: it ports period-stepping logic out of
`org-clock.el`, and the Org version resolved under each Emacs may differ. Locally I cannot
prove the two agree — both Doom straight builds share a single Org checkout, so comparing
them proves nothing about CI. Adding 31 to the matrix is what actually establishes it.

**Do not bump the version floor.** `Eask` and `Package-Requires` must stay at
`emacs "30.2"` — the point is to support 30 *and* 31, not to drop 30.

### Naming (fixed — do not improvise)

Org dispatches on the block name, so the writer **must** be `org-dblock-write:clockmatrix`
and cannot carry a package prefix. Everything else does: `agile-gtd-clockmatrix` for the
public entry point, `agile-gtd--clockmatrix-*` for helpers, matching the package's existing
`agile-gtd--` convention.

Do not name it `columnview-matrix` or anything `columnview`-flavoured — `columnview` is an
unrelated built-in Org dynamic block and the collision was explicitly rejected.

### Verified technical facts (don't re-derive these)

- **The aggregation primitive is `org-clock-get-table-data`**, which returns
  `(FILE TOTAL-MINUTES ENTRIES)`. With `:maxlevel 0` and `:match "<tag>"` plus
  `:tstart`/`:tend`, element 1 is the number you want. Call it with the file's buffer
  current, inside `save-excursion` + `save-restriction` + `widen`.
- Using Org's own summing (rather than parsing CLOCK lines) is what guarantees the matrix
  agrees with equivalent clocktables, and it **clips clocks at range boundaries** for free,
  so a clock spanning a boundary is split, not double-counted or dropped. Verified: a
  22:15→00:00 clock yields 1:45 / 0:00 / 1:45 for the two days and their union.
- **Port the period stepping from Org's `org-clocktable-steps`** — the `pcase` on `:step`
  with `org-encode-time`, including `:wstart` / `:mstart`. Do not hand-roll calendar math.
  Watch `semimonth`, the newest step keyword, as the most likely cross-version wrinkle.
- Range resolution mirrors `org-dblock-write:clocktable`: `:block` through
  `org-clock-special-range` with `as-strings` t, otherwise `:tstart`/`:tend`, both fed
  through `org-matcher-time`.
- Render cells with `org-duration-from-minutes` so they honour the user's
  `org-duration-format`, then `org-table-align`.
- Register with `org-dynamic-block-define` so it appears under `C-c C-x x`.
- Default scope resolves each project's own file plus `archive/<file>` via the existing
  `agile-gtd--project-file` accessor and the package's org-path expansion. Filter through
  `file-exists-p`. `:scope agenda-with-archives` selects
  `(org-add-archive-files (org-agenda-files t))` instead.
- **Warn** (don't silently report zero) when a project's *main* file is missing. Name the
  project, the path tried, and both remedies: set `:file` in `agile-gtd-projects`, or use
  `:scope agenda-with-archives`. Archive files are exempt — routinely absent by design.

### Testing — exactly one seam

All assertions go through the dynamic block: insert `#+BEGIN: clockmatrix … #+END:` into a
buffer, refresh it, assert on the resulting buffer text. **Do not write tests against
`--range`, `--steps`, `--files`, `--sum`, or `--columns`** — the internal decomposition must
stay free to change.

Reuse the existing sandbox macro `agile-gtd-org-ql-test-with-sandbox` (defined in
`test/agile-gtd-org-ql-predicates-test.el`), which binds `org-directory` to a temp dir and
isolates Org state. Follow the shape of `agile-gtd-agenda-test-with-data`: write synthetic
project files with known CLOCK entries into the sandbox, bind `agile-gtd-projects` to point
at them, then run the body. Exercising the real file-resolution path is what makes the
missing-file warning testable at the same seam.

Fixtures must be synthetic. Never depend on my real org files — their contents change.

Cover: one row per period for each `:step` value; row-label format per `:step`; per-cell
attribution; blank cell for zero; column dropped when a project has no time in range; row
dropped when all are zero and kept under `:stepskip0 nil`; Total column equals the sum of
its row; Total row equals the per-project range total; a boundary-spanning clock split
across two rows and summing to its full duration; `:tags` overriding derived columns; and a
project with an unresolvable file warning instead of silently reporting zero.

### Phase 1 verification

```bash
cd ~/work/agile-gtd
just test
just lint
```

Then a parity check against real data — a development confidence check, **not** a committed
test:

```bash
emacs -q --batch -l ~/.config/doom/test/bootstrap.el \
      -l ~/work/agile-gtd/agile-gtd.el -l /tmp/parity.el
```

Assert each rendered cell equals a plain
`clocktable :scope agenda-with-archives :maxlevel 0 :match "<tag>" :tstart … :tend …` over
the same range, and that both scopes agree. **Anchor: project `oebb`, 2026-07-01 →
2026-08-01, must be `66:15`.** Also assert the two scopes agree across all projects (they
do today — measured `DIFF=0:00`), so future divergence shows up as a signal.

Do **not** set `DOOMPROFILE` when running that bootstrap; it repoints `doom-data-dir` and
the generated init is not found.

## Phase 2 — wire it into Doom (`~/.config/doom`)

Two edits, both in `config.org`. **`config.el` is generated — never edit it by hand.**

1. **Switch the agile-gtd recipe to the local repo** so the new code actually loads. In the
   `** agile-gtd` section, uncomment the `:local-repo` line and comment out the GitHub one:

   ```elisp
   (package! agile-gtd
     :recipe (:local-repo "~/work/agile-gtd" :build (:not compile)))
     ;; :recipe (:host github :repo "stfl/agile-gtd.el"))
   ```

   **This is temporary.** Call it out prominently in your final report so I remember to
   revert it when I publish the package.

2. **Register the `glas` project** in the `agile-gtd-projects` list. `:file` is mandatory —
   without it the file resolves to a non-existent `glas.org` and the column silently
   reports zero. Keyless, so it stays inert in the agenda:

   ```elisp
   (:tag "glas" :name "Café Glas" :file "cafe-glas.org")
   ```

Then:

```bash
~/.config/emacs/bin/doom +org tangle config.org
~/.config/emacs/bin/doom sync -u
```

`-u` also updates other packages — report anything unexpected that moved. Verify `config.el`
was regenerated by the tangle (not hand-edited), and that agile-gtd now resolves to the
local repo.

## Phase 3 — update the org files (`~/.org`)

**`~/.org` is watched by a running sync daemon that auto-commits and pushes.** Stop it
before touching anything, or it will commit your half-finished edits under a generated
message:

```bash
systemctl --user stop git-sync-org.service
systemctl --user is-active git-sync-org.service   # expect: inactive
```

The repo is on `master`, tracking `origin/master`, currently clean and fully pushed. Make
surgical edits only — no reformatting, no touching surrounding content.

1. **`freelance.org`** — under `* Time Tracking all`, **replace** the existing
   `#+BEGIN: clocktable … :block thisyear :step month` block (it has no `:match`) and its
   generated body through `#+END:` with:

   ```org
   #+BEGIN: clockmatrix :block thisyear :step month
   #+END:
   ```

   Note this deliberately narrows the report: the old block counted all clocked time, the
   new one counts registered projects only.

2. **`oebb.org`** — under `** Clock Report - weekly`, **insert above** the existing weekly
   clocktable, leaving that clocktable completely untouched:

   ```org
   #+BEGIN: clockmatrix :block thismonth :step week :tags ("oebb")
   #+END:
   ```

3. **`momentedge.org`** — same, under its `** Clock Report - weekly`, above the existing
   weekly clocktable:

   ```org
   #+BEGIN: clockmatrix :block thismonth :step week :tags ("momentedge")
   #+END:
   ```

The two weekly clocktables are `:maxlevel 2 :link t` and give per-headline detail that
`clockmatrix` does not — that is why they stay. Do not remove them.

Then **refresh each inserted block** so it renders, and confirm the output is sane:
projects as columns, `H:MM` durations, blank cells for zero, totals that add up.
Cross-check: the `freelance.org` matrix row for a given month must equal what a
`:match "<tag>"` clocktable reports for that project and month.

Review `git diff` and confirm it contains nothing but the intended block changes. Then
commit — one commit, with a message that says what changed and why (not "update org
files"). Finally restart the daemon:

```bash
systemctl --user start git-sync-org.service
systemctl --user is-active git-sync-org.service   # expect: active
```

Restarting it will push that commit to `origin/master`, so make sure the diff is right
before you commit.

## Do not

- Add money: no rates, no currency columns, no `:formula`. Rejected — dropped columns make
  `$N` indices unstable between refreshes, so a formula silently retargets another project.
- Add a `:match` parameter for ANDing an extra matcher. Measured and rejected.
- Add an `Other` / residual column, or make Total mean "all clocked time". Total means
  *sum of the project columns shown*.
- Add an active/finished lifecycle field to `agile-gtd-projects`. The empty-column rule
  already handles finished projects.
- Add drill-down: no `:maxlevel`, no properties columns, no per-headline rows.
- Raise the `emacs "30.2"` floor in `Eask` or `Package-Requires`.
- Edit `config.el` by hand, or any org file beyond the three blocks above.
- Use `emacsclient` for anything mutating — read-only queries only; I have a live session.
- Commit in `~/work/agile-gtd` or `~/.config/doom`. Push anywhere.
- Create GitHub issues, labels, or PRs.

## Report back

What changed in each of the three repos; `just test` and `just lint` output; the CI matrix
entry you chose for Emacs 31 and why; the parity-check result including the `66:15` anchor;
the `~/.org` diff and commit message; anything `doom sync -u` moved unexpectedly;
confirmation that `git-sync-org.service` is active again — and a reminder that the
agile-gtd recipe is temporarily pointed at the local repo.
