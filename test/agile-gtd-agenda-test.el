;;; agile-gtd-agenda-test.el --- Tests for agile-gtd agenda query functions -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'org-agenda)
(require 'org-capture)
(require 'org-modern)
(require 'org-ql)
(require 'org-edna)
(require 'agile-gtd)

;; Reuse the sandbox and helpers from predicates tests
(require 'agile-gtd-org-ql-predicates-test)

(defconst agile-gtd-agenda-test-data
  "* NEXT [#A] Work high-prio :#work:

* NEXT [#B] Private medium :#personal:

* NEXT Work with deadline :#work:
DEADLINE: <2026-04-06 Mon>

* NEXT No priority private

* PROJ [#C] Stuck work :#work:
** TODO Notes only

* PROJ Stuck private
** TODO Notes only

* TODO Inbox item one :#inbox:

* TODO Inbox item two :inbox:

* DONE Finished inbox :#inbox:

* Inbox :#inbox:

* NEXT [#A] Blocking action

* NEXT [#A] Blocked action
:PROPERTIES:
:BLOCKER:  previous-sibling
:END:
"
  "Org data for agenda query tests.")

(defmacro agile-gtd-agenda-test-with-data (&rest body)
  "Run BODY with agenda query fixtures in a temporary Org buffer."
  (declare (indent 0) (debug t))
  `(agile-gtd-org-ql-test-with-sandbox
    (let* ((file (expand-file-name "agenda-fixtures.org" org-directory))
           (buffer nil))
      (unwind-protect
          (progn
            (with-temp-file file
              (insert agile-gtd-agenda-test-data))
            (setq buffer (find-file-noselect file))
            (with-current-buffer buffer
              (org-mode)
              (agile-gtd-enable)
              (org-set-regexps-and-options)
              ,@body))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

;;; Structure tests — verify query functions return well-formed sexps

(ert-deftest agile-gtd-agenda-query-next-actions-returns-sexp ()
  "Next actions query returns a well-formed sexp with and without filter."
  (let ((query (agile-gtd-agenda-query-next-actions)))
    (should (listp query))
    (should (eq 'and (car query))))
  (let ((filtered (agile-gtd-agenda-query-next-actions '(agile-gtd-work))))
    (should (listp filtered))
    ;; Filtered query wraps with an outer `and'
    (should (eq 'and (car filtered)))))

(ert-deftest agile-gtd-view-ranges-run-narrowest-to-widest ()
  "The range vocabulary is ordered, so wider and narrower are unambiguous."
  (should (equal agile-gtd-view-ranges '(today sprint backlog all someday))))

(ert-deftest agile-gtd-view-range-cutoffs-are-ranks ()
  "Every range cuts off at a rank, `today' at 0 and the rest at a band top.
One number per range is what lets the filter and the rank groups agree:
`today' closes where the \"Today & Overdue\" group closes, and every other
range where its cutoff priority\='s group does."
  (should (= (agile-gtd-view-range-cutoff 'today) 0))
  (dolist (range '(sprint backlog all someday))
    (ert-info ((format "range=%s" range))
      (should (= (agile-gtd-view-range-cutoff range)
                 (agile-gtd--rank-band-top
                  (agile-gtd-view-range-priority range))))))
  (ert-info ("The cutoffs widen along the range list")
    (should (apply #'<= (mapcar #'agile-gtd-view-range-cutoff
                                agile-gtd-view-ranges))))
  (ert-info ("An unknown range is refused")
    (should-error (agile-gtd-view-range-cutoff 'nonsense) :type 'user-error)))

(ert-deftest agile-gtd-view-range-cutoffs-follow-the-priority-configuration ()
  "Each range takes its cutoff from a priority defcustom, never from a letter."
  (ert-info ("Stock priority configuration")
    (let ((agile-gtd-sprint-prio-threshold ?C)
          (agile-gtd-priority-default ?E)
          (agile-gtd-priority-lowest ?I))
      (should (= (agile-gtd-view-range-priority 'sprint)  ?C))
      (should (= (agile-gtd-view-range-priority 'backlog) ?E))
      (should (= (agile-gtd-view-range-priority 'all)     ?I))
      (should (= (agile-gtd-view-range-priority 'someday) ?I))))
  (ert-info ("A reconfigured priority scale moves every cutoff with it")
    (let ((agile-gtd-sprint-prio-threshold ?B)
          (agile-gtd-priority-default ?D)
          (agile-gtd-priority-lowest ?G))
      (should (= (agile-gtd-view-range-priority 'sprint)  ?B))
      (should (= (agile-gtd-view-range-priority 'backlog) ?D))
      (should (= (agile-gtd-view-range-priority 'all)     ?G))
      (should (= (agile-gtd-view-range-priority 'someday) ?G))))
  (ert-info ("An unknown range is refused")
    (should-error (agile-gtd-view-range-priority 'nonsense) :type 'user-error)))

(ert-deftest agile-gtd-view-range-parked-items-belong-to-someday-alone ()
  "Only the widest range takes in SOMEDAY entries and ticklers."
  (should (agile-gtd-view-range-parked-p 'someday))
  (should-not (agile-gtd-view-range-parked-p 'today))
  (should-not (agile-gtd-view-range-parked-p 'sprint))
  (should-not (agile-gtd-view-range-parked-p 'backlog))
  (should-not (agile-gtd-view-range-parked-p 'all)))

(ert-deftest agile-gtd-agenda-query-backlog-returns-sexp ()
  "Backlog query returns a well-formed sexp with and without filter."
  (let ((query (agile-gtd-agenda-query-backlog)))
    (should (listp query))
    (should (eq 'and (car query))))
  (let ((filtered (agile-gtd-agenda-query-backlog '(agile-gtd-work))))
    (should (listp filtered))
    (should (eq 'and (car filtered)))))

(ert-deftest agile-gtd-agenda-query-stuck-projects-with-and-without-filter ()
  "Stuck projects query supports optional tag-filter."
  (should (equal (agile-gtd-agenda-query-stuck-projects)
                 '(agile-gtd-stuck-proj)))
  (should (equal (agile-gtd-agenda-query-stuck-projects '(agile-gtd-work))
                 '(and (agile-gtd-stuck-proj) (agile-gtd-work))))
  (should (equal (agile-gtd-agenda-query-stuck-projects '(agile-gtd-private))
                 '(and (agile-gtd-stuck-proj) (agile-gtd-private)))))

;;; Area-filter tests — use simpler org-ql queries that work in batch

(ert-deftest agile-gtd-agenda-query-stuck-projects-area-filter ()
  "Work filter: only stuck work projects; private filter: only stuck private."
  (agile-gtd-agenda-test-with-data
   (let* ((work-query (agile-gtd-agenda-query-stuck-projects '(agile-gtd-work)))
          (work-headings (agile-gtd-org-ql-test-headings buffer work-query))
          (private-query (agile-gtd-agenda-query-stuck-projects '(agile-gtd-private)))
          (private-headings (agile-gtd-org-ql-test-headings buffer private-query)))
     (should (member "Stuck work" work-headings))
     (should-not (member "Stuck private" work-headings))
     (should (member "Stuck private" private-headings))
     (should-not (member "Stuck work" private-headings)))))

(ert-deftest agile-gtd-agenda-query-backlog-area-filter ()
  "Backlog query respects area filter."
  (agile-gtd-agenda-test-with-data
   (let* ((work-query (agile-gtd-agenda-query-backlog '(agile-gtd-work)))
          (work-headings (agile-gtd-org-ql-test-headings buffer work-query))
          (private-query (agile-gtd-agenda-query-backlog '(agile-gtd-private)))
          (private-headings (agile-gtd-org-ql-test-headings buffer private-query)))
     ;; Work backlog should include work projects
     (should (member "Stuck work" work-headings))
     (should-not (member "Stuck private" work-headings))
     ;; Private backlog should include private projects and standalone actions
     (should (member "Stuck private" private-headings))
     (should-not (member "Stuck work" private-headings)))))

(ert-deftest agile-gtd-agenda-query-next-actions-excludes-blocked ()
  "Next-actions query excludes entries whose BLOCKER is unsatisfied."
  (agile-gtd-agenda-test-with-data
   (let ((org-blocker-hook (list #'org-edna-blocker-function)))
     (let* ((query    (agile-gtd-agenda-query-next-actions))
            (headings (agile-gtd-org-ql-test-headings buffer query)))
       ;; Blocked action has BLOCKER: previous-sibling (Blocking action is NEXT)
       (should-not (member "Blocked action" headings))
       ;; The blocker itself has no BLOCKER property and must still appear
       (should (member "Blocking action" headings))))))

(ert-deftest agile-gtd-agenda-query-backlog-excludes-blocked ()
  "Backlog query excludes entries whose BLOCKER is unsatisfied."
  (agile-gtd-agenda-test-with-data
   (let ((org-blocker-hook (list #'org-edna-blocker-function)))
     (let* ((query    (agile-gtd-agenda-query-backlog))
            (headings (agile-gtd-org-ql-test-headings buffer query)))
       (should-not (member "Blocked action" headings))
       (should (member "Blocking action" headings))))))

(ert-deftest agile-gtd-agenda-actions-work-private-split ()
  "Action items split correctly between work and private via direct predicates."
  (agile-gtd-agenda-test-with-data
   (let* ((work-headings (agile-gtd-org-ql-test-headings
                          buffer
                          '(and (todo "NEXT" "WAIT") (agile-gtd-work))))
          (private-headings (agile-gtd-org-ql-test-headings
                             buffer
                             '(and (todo "NEXT" "WAIT") (agile-gtd-private)))))
     ;; Work actions
     (should (member "Work high-prio" work-headings))
     (should (member "Work with deadline" work-headings))
     (should-not (member "Private medium" work-headings))
     (should-not (member "No priority private" work-headings))
     ;; Private actions
     (should (member "Private medium" private-headings))
     (should (member "No priority private" private-headings))
     (should-not (member "Work high-prio" private-headings)))))

;;; Rank ordering test — uses agile-gtd--item-rank directly

(ert-deftest agile-gtd-agenda-rank-ordering ()
  "Items sorted by `agile-gtd--item-rank' come out in correct priority order."
  (agile-gtd-agenda-test-with-data
   (let* ((ranked (org-ql-select buffer '(todo "NEXT" "WAIT")
                    :action (lambda ()
                              (cons (org-get-heading t t t t)
                                    (agile-gtd--item-rank))))))
     ;; [#A] rank 1 should come before [#B] rank 11
     (should (< (cdr (assoc "Work high-prio" ranked))
                (cdr (assoc "Private medium" ranked))))
     ;; Deadline item should get a rank from deadline (3 days out = rank 10)
     (should (< (cdr (assoc "Work with deadline" ranked))
                (cdr (assoc "No priority private" ranked))))
     ;; No-priority default rank (agile-gtd--rank-default) should be highest
     (should (= (agile-gtd--rank-default) (cdr (assoc "No priority private" ranked)))))))

(ert-deftest agile-gtd-agenda-next-actions-sort-by-rank ()
  "org-ql-select :sort 'agile-gtd--item-rank< yields items in ascending rank order."
  (agile-gtd-agenda-test-with-data
   (let* ((sorted (org-ql-select buffer
                    (agile-gtd-agenda-query-next-actions)
                    :sort 'agile-gtd--item-rank<))
          (rank-map (org-ql-select buffer
                      (agile-gtd-agenda-query-next-actions)
                      :action (lambda ()
                                (cons (org-get-heading t t t t)
                                      (agile-gtd--item-rank)))))
          (sorted-headings
           (mapcar (lambda (el) (org-element-property :raw-value el)) sorted))
          (sorted-ranks
           (mapcar (lambda (h) (cdr (assoc h rank-map))) sorted-headings)))
     (should sorted-ranks)
     (cl-loop for (r1 r2) on sorted-ranks
              while r2
              do (should (<= r1 r2))))))

;;; Inbox query tests

(ert-deftest agile-gtd-agenda-query-inbox-returns-sexp ()
  "Inbox query returns a well-formed sexp."
  (let ((query (agile-gtd-agenda-query-inbox)))
    (should (listp query))
    (should (eq 'and (car query)))))

(ert-deftest agile-gtd-agenda-query-inbox-matches ()
  "Inbox query matches inbox-tagged items with a TODO keyword only.
Excludes done items and plain (stateless) section headings."
  (agile-gtd-agenda-test-with-data
   (let* ((query (agile-gtd-agenda-query-inbox))
          (headings (agile-gtd-org-ql-test-headings buffer query)))
     (should (member "Inbox item one" headings))
     (should (member "Inbox item two" headings))
     (should-not (member "Finished inbox" headings))
     (should-not (member "Inbox" headings))
     (should-not (member "Work high-prio" headings)))))

;;; Customer agenda command tests

(ert-deftest agile-gtd-project-agenda-commands-generated ()
  "Project agenda commands are generated for each configured project."
  (agile-gtd-agenda-test-with-data
   (let ((agile-gtd-projects '((:tag "acme" :name "ACME Corp" :key ?a)
                                (:tag "globex" :name "Globex" :key ?g))))
     (let ((cmds (agile-gtd--project-agenda-commands)))
       (should (= (length cmds) 2))
       (should (equal (caar cmds) "wa"))
       (should (equal (caadr cmds) "wg"))
       (should (string-match-p "ACME Corp" (cadar cmds)))
       (should (string-match-p "Globex" (car (cdar (cdr cmds)))))))))

(ert-deftest agile-gtd-project-tags-added-to-tag-alist ()
  "Project tags appear in org-tag-alist after refresh."
  (agile-gtd-agenda-test-with-data
   (let ((agile-gtd-projects '((:tag "acme" :name "ACME" :key ?a)
                                (:tag "globex" :name "Globex" :key ?g))))
     (agile-gtd-refresh)
     (should (assoc "acme" org-tag-alist))
     (should (equal (cdr (assoc "acme" org-tag-alist)) ?a))
     (should (assoc "globex" org-tag-alist))
     (should (equal (cdr (assoc "globex" org-tag-alist)) ?g)))))

(ert-deftest agile-gtd-project-tags-not-duplicated ()
  "Project tags are not duplicated across multiple refreshes."
  (agile-gtd-agenda-test-with-data
   (let ((agile-gtd-projects '((:tag "acme" :name "ACME" :key ?a))))
     (agile-gtd-refresh)
     (agile-gtd-refresh)
     (should (= 1 (cl-count "acme" org-tag-alist :key #'car-safe :test #'equal))))))

;;; Agenda custom command structure tests

(defun agile-gtd-test--collect-settings-values (tree key)
  "Walk agenda command TREE and collect all values bound to settings KEY."
  (let (results)
    (cl-labels ((walk (node)
                  (when (proper-list-p node)
                    (if (eq (car node) key)
                        (when (cdr node)
                          (push (cadr node) results))
                      (mapc #'walk node)))))
      (walk tree))
    results))

(ert-deftest agile-gtd-agenda-custom-commands-is-list ()
  "agile-gtd--agenda-custom-commands returns a non-empty list."
  (agile-gtd-agenda-test-with-data
   (let ((cmds (agile-gtd--agenda-custom-commands)))
     (should (listp cmds))
     (should (> (length cmds) 0)))))

(ert-deftest agile-gtd-agenda-super-groups-are-quoted ()
  "Every org-super-agenda-groups value in the agenda commands is a quoted
form so that org-agenda can eval it without triggering 'Invalid function'."
  (agile-gtd-agenda-test-with-data
   (let* ((cmds (agile-gtd--agenda-custom-commands))
          (vals (agile-gtd-test--collect-settings-values
                 cmds 'org-super-agenda-groups)))
     (should (> (length vals) 0))
     (dolist (val vals)
       ;; Each value must be either (quote ...) or a plain symbol —
       ;; never a bare list that would error when eval'd by org-agenda.
       (should (or (symbolp val)
                   (and (consp val) (eq 'quote (car val)))))))))

(ert-deftest agile-gtd-agenda-super-groups-eval-to-lists ()
  "Every org-super-agenda-groups value evaluates to a proper list."
  (agile-gtd-agenda-test-with-data
   (let* ((cmds (agile-gtd--agenda-custom-commands))
          (vals (agile-gtd-test--collect-settings-values
                 cmds 'org-super-agenda-groups)))
     (should (> (length vals) 0))
     (dolist (val vals)
       (should (listp (eval val t)))))))

(defun agile-gtd-test--collect-ql-block-queries (tree)
  "Walk agenda command TREE collecting org-ql-block query arguments."
  ;; Each org-ql-block form is (org-ql-block QUERY SETTINGS).
  ;; QUERY is (cadr form).
  (let (results)
    (cl-labels ((walk (node)
                  (when (proper-list-p node)
                    (if (memq (car node) '(org-ql-block agile-gtd-agenda-ql-block))
                        (when (cdr node)
                          (push (cadr node) results))
                      (mapc #'walk node)))))
      (walk tree))
    results))

(ert-deftest agile-gtd-agenda-ql-block-queries-are-quoted ()
  "Every org-ql-block query in the agenda commands is a quoted or
nested-backquote form — never a bare evaluated list that would call
org-ql predicates outside of any heading context."
  (agile-gtd-agenda-test-with-data
   (let* ((cmds (agile-gtd--agenda-custom-commands))
          (queries (agile-gtd-test--collect-ql-block-queries cmds)))
     (should (> (length queries) 0))
     (dolist (q queries)
       ;; Acceptable forms: (quote ...), (backquote ...), symbol, or a
       ;; bare function-call form like (agile-gtd-agenda-query-stuck-projects)
       ;; whose car is a known function (call-at-eval-time pattern).
       (should (or (symbolp q)
                   ;; (quote ...) — quoted at define-time
                   (and (consp q) (eq 'quote (car q)))
                   ;; nested backquote — expanded at agenda-build-time
                   (and (consp q) (eq '\` (car q)))
                   ;; bare function call like (func) — eval calls func
                   (and (consp q) (symbolp (car q)) (fboundp (car q)))))))))

(ert-deftest agile-gtd-agenda-ql-block-queries-eval-to-sexps ()
  "Every org-ql-block query evaluates to a proper list (org-ql sexp)
without signalling an error."
  (agile-gtd-agenda-test-with-data
   (let* ((cmds (agile-gtd--agenda-custom-commands))
          (queries (agile-gtd-test--collect-ql-block-queries cmds)))
     (should (> (length queries) 0))
     (dolist (q queries)
       (should (listp (eval q t)))))))

(ert-deftest agile-gtd-agenda-today-groups-has-time-grid ()
  "The today agenda groups include a :time-grid entry."
  (let* ((groups (agile-gtd--today-groups))
         (has-time-grid (cl-some (lambda (g) (plist-get g :time-grid)) groups)))
    (should has-time-grid)))

(ert-deftest agile-gtd-agenda-day-block-super-groups-evaluable ()
  "The agenda day block's org-super-agenda-groups value evaluates to a list."
  (let* ((block (agile-gtd--agenda-day))
         (settings (nth 2 block))
         (groups-pair (assq 'org-super-agenda-groups settings)))
    (should groups-pair)
    (should (listp (eval (cadr groups-pair) t)))))

;;; Agenda buffer integration tests

(defun agile-gtd-agenda-integration-test-org-data ()
  "Return org data for agenda integration tests.
Uses today's date so the scheduled items appear in the day block.

The band items carry one priority cookie each and nothing else — no
schedule, no deadline, no parent — so the only thing that can decide
whether one of them is on screen is the view range's priority cutoff.
With the stock configuration those cutoffs are C for `sprint', E for
`backlog' and I for `all', which makes D the first band outside
`sprint' and F the first band outside `backlog'."
  (let ((today (format-time-string "%Y-%m-%d %a"))
        (tomorrow (format-time-string "%Y-%m-%d %a"
                    (time-add (current-time) (days-to-time 1)))))
    (concat "* NEXT [#A] High priority action\n\n"
            "* NEXT [#C] Medium priority action\n\n"
            "* PROJ Stuck project\n"
            "** TODO Notes only\n\n"
            ;; Scheduled today: appears in day block but NOT in Next Actions
            ;; (excluded by `not (scheduled)').  No work tag → private only.
            "* NEXT [#B] Scheduled today\n"
            (format "SCHEDULED: <%s>\n" today)
            ;; A project due today.  Its step carries no date, so only the
            ;; project itself is inside `today'.
            "* PROJ Project due today\n"
            (format "DEADLINE: <%s>\n" today)
            "** NEXT Step of the project due today\n\n"
            ;; Work item scheduled today: appears in day block in work views only.
            "* NEXT [#A] Work item today :#work:\n"
            (format "SCHEDULED: <%s>\n" today)
            ;; Priority bands, one item per cutoff and one per first band beyond it.
            ;; Every heading here is unique as a substring of every other, so a
            ;; presence check cannot be satisfied by the wrong item.
            "* NEXT [#C] Band C item\n\n"
            "* NEXT [#D] Band D item\n\n"
            "* NEXT [#E] Band E item\n\n"
            "* NEXT [#F] Band F item\n\n"
            "* NEXT [#I] Band I item\n\n"
            ;; No cookie at all: Org reads it as the default priority, and so
            ;; must the filter — in from `backlog' onwards, out of `sprint'.
            "* NEXT Uncookied item\n\n"
            ;; A bare action under a low-cookied project.  It ranks where its
            ;; parent puts it, so it must leave `backlog' at the same cutoff a
            ;; [#G] cookie of its own would take it out at.  Reading a missing
            ;; cookie as the default and stopping there is the bug this pins.
            "* PROJ [#G] Band G parent project\n"
            "** NEXT Bare child of band G\n\n"
            ;; Scheduled past today, carrying [#A] so no priority cutoff can
            ;; account for its absence: only the date keeps it off screen
            ;; until `someday', where it is the Scheduled group's own item.
            "* NEXT [#A] Deferred by a later date\n"
            (format "SCHEDULED: <%s>\n\n" tomorrow)
            ;; Parked work.  Both carry [#A] so no priority cutoff can explain
            ;; their absence: only the parked gates keep them off screen.
            "* NEXT [#A] Parked someday item :SOMEDAY:\n\n"
            "* NEXT [#A] Parked future tickler :SOMEDAY:\n"
            (format "SCHEDULED: <%s>\n\n" tomorrow)
            ;; Being stuck is a process failure, so this one shows at every
            ;; range despite sitting in the lowest priority band.
            "* PROJ [#I] Band I stuck project\n"
            "** TODO Notes only\n\n"
            ;; Work-tagged counterparts for the work views.
            "* NEXT Work uncookied task :#work:\n\n"
            "* NEXT [#F] Work band F task :#work:\n\n"
            ;; Project-tagged counterparts for a generated per-project view.
            "* NEXT Acme uncookied job :acme:\n\n"
            "* NEXT [#F] Acme band F job :acme:\n\n")))

(defmacro agile-gtd-agenda-test-build-view-with (bindings cmd-key &rest body)
  "Build org agenda for CMD-KEY in a fresh sandbox under extra BINDINGS.
BINDINGS is a `let*' binding list that takes effect before
`agile-gtd-enable' runs, so configuration that shapes the generated
agenda commands is in place by the time they are built.
BODY executes with `agenda-text' bound to the resulting agenda buffer's text."
  (declare (indent 2) (debug t))
  `(agile-gtd-org-ql-test-with-sandbox
    (let* ((file (expand-file-name "agenda-integration.org" org-directory))
           (org-agenda-window-setup 'current-window)
           ,@bindings)
      (with-temp-file file
        (insert (agile-gtd-agenda-integration-test-org-data)))
      (agile-gtd-enable)
      ;; agile-gtd-enable adds inbox/todo/etc. files that don't exist in
      ;; the sandbox.  Override org-agenda-files to only our test fixture
      ;; so org-agenda doesn't prompt about missing files.
      (setq org-agenda-files (list file))
      (unwind-protect
          (save-window-excursion
            (org-agenda nil ,cmd-key)
            (let* ((buf (get-buffer org-agenda-buffer-name))
                   (agenda-text (with-current-buffer buf (buffer-string))))
              ,@body))
        (when-let ((buf (get-buffer org-agenda-buffer-name)))
          (kill-buffer buf))))))

(defmacro agile-gtd-agenda-test-build-view (cmd-key &rest body)
  "Build org agenda for CMD-KEY in a fresh sandbox.
BODY executes with `agenda-text' bound to the resulting agenda buffer's text."
  (declare (indent 1) (debug t))
  `(agile-gtd-agenda-test-build-view-with () ,cmd-key ,@body))

(defun agile-gtd-agenda-test-agenda-text ()
  "Return the current contents of the agenda buffer, without text properties.
Properties carry markers into the Org buffers behind the agenda, which two
renders never share, so they are dropped to leave the text comparable."
  (with-current-buffer (get-buffer org-agenda-buffer-name)
    (buffer-substring-no-properties (point-min) (point-max))))

(defun agile-gtd-agenda-test-current-range ()
  "Return the range the rendered agenda buffer is showing."
  (with-current-buffer (get-buffer org-agenda-buffer-name)
    (agile-gtd-agenda-current-range)))

(defun agile-gtd-agenda-test-rotate-to (range)
  "Rotate the rendered agenda until it shows RANGE; return the agenda text.
Steps one range at a time through the rotation commands, the way a user
reaches a range, and gives up after one pass over the vocabulary so that
a clamp cannot spin."
  (with-current-buffer (get-buffer org-agenda-buffer-name)
    (dotimes (_ (length agile-gtd-view-ranges))
      (let ((current (agile-gtd-agenda-current-range)))
        (cond
         ((eq current range) nil)
         ((< (cl-position current agile-gtd-view-ranges)
             (cl-position range agile-gtd-view-ranges))
          (agile-gtd-agenda-wider-range))
         (t (agile-gtd-agenda-narrower-range)))))
    ;; Refusing to return a view that is not at RANGE keeps every caller's
    ;; assertions about that range from passing on a view that never moved.
    (unless (eq (agile-gtd-agenda-current-range) range)
      (error "Rotation stopped at %s instead of reaching %s"
             (agile-gtd-agenda-current-range) range)))
  (agile-gtd-agenda-test-agenda-text))

(defun agile-gtd-agenda-test-block-onwards (text header)
  "Return the part of agenda TEXT from block HEADER onwards, or nil.
HEADER is matched as a prefix, so it finds a block header whether or not
the active range is appended to it."
  (when-let ((start (string-match (regexp-quote header) text)))
    (substring-no-properties text start)))

(defun agile-gtd-agenda-test-block-section (text header)
  "Return block HEADER\\='s own section of agenda TEXT, or nil.
The section runs from the header to the rule that starts the next block."
  (when-let ((rest (agile-gtd-agenda-test-block-onwards text header)))
    (substring rest 0 (string-match "^=+$" rest 1))))

(ert-deftest agile-gtd-agenda-main-view-all-sections-populated ()
  "Main Agenda ('a') builds with all three blocks populated by test items."
  (agile-gtd-agenda-test-build-view "a"
    ;; Day agenda block: today-scheduled item appears
    (ert-info ("Day block")
      (should (string-match-p "Scheduled today" agenda-text)))
    ;; Stuck Projects block: header present and stuck item present
    (ert-info ("Stuck Projects block")
      (should (string-match-p "Stuck Projects" agenda-text))
      (should (string-match-p "Stuck project" agenda-text)))
    ;; Next Actions block: header present and unscheduled priority items present
    (ert-info ("Next Actions block")
      (should (string-match-p "Next Actions" agenda-text))
      (should (string-match-p "High priority action" agenda-text))
      (should (string-match-p "Medium priority action" agenda-text)))))

(ert-deftest agile-gtd-agenda-main-view-section-order ()
  "In Main Agenda ('a'): Stuck Projects section precedes Next Actions."
  (agile-gtd-agenda-test-build-view "a"
    (let ((stuck-pos (string-match "Stuck Projects" agenda-text))
          (next-pos  (string-match "Next Actions"   agenda-text)))
      (should stuck-pos)
      (should next-pos)
      (should (< stuck-pos next-pos)))))

(ert-deftest agile-gtd-agenda-main-view-scheduled-excluded-from-next-actions ()
  "Scheduled items do not appear under the Next Actions section."
  (agile-gtd-agenda-test-build-view "a"
    (let ((next-pos (string-match "Next Actions" agenda-text)))
      (should next-pos)
      ;; The substring from the Next Actions header onward must not
      ;; contain the scheduled-today item.
      (should-not
       (string-match-p "Scheduled today"
                        (substring agenda-text next-pos))))))

(ert-deftest agile-gtd-agenda-stuck-projects-view-populated ()
  "Stuck Projects view ('rs') shows stuck items."
  (agile-gtd-agenda-test-build-view "rs"
    (should (string-match-p "Stuck Projects" agenda-text))
    (should (string-match-p "Stuck project" agenda-text))))

(ert-deftest agile-gtd-agenda-private-view-sections-populated ()
  "Private Agenda ('pp') contains private items in all its blocks."
  (agile-gtd-agenda-test-build-view "pp"
    (should (string-match-p "Next Actions" agenda-text))
    (should (string-match-p "High priority action" agenda-text))
    (should (string-match-p "Stuck Projects" agenda-text))
    (should (string-match-p "Stuck project" agenda-text))))

;;; Today-block tag-filter tests

(ert-deftest agile-gtd-agenda-day-block-tag-filter-uses-skip-function ()
  "Agenda day block with tag filter uses org-agenda-skip-function,
not the broken org-agenda-tag-filter-preset (which has no effect in
compound commands because org-agenda-prepare runs before lprops bind)."
  (let* ((block (agile-gtd--agenda-day '("+#work")))
         (settings (nth 2 block))
         (skip-pair (assq 'org-agenda-skip-function settings))
         (preset-pair (assq 'org-agenda-tag-filter-preset settings)))
    (should skip-pair)
    (should-not preset-pair)
    ;; Value must be a quoted form: (quote (when ...))
    (should (and (consp (cadr skip-pair))
                 (eq 'quote (car (cadr skip-pair)))))))

(ert-deftest agile-gtd-agenda-private-today-excludes-work-items ()
  "Private Agenda ('pp') today block excludes work-tagged items."
  (agile-gtd-agenda-test-build-view "pp"
    ;; Non-work item scheduled today must appear
    (should (string-match-p "Scheduled today" agenda-text))
    ;; Work-tagged item must not appear anywhere in the private view
    (should-not (string-match-p "Work item today" agenda-text))))

(ert-deftest agile-gtd-agenda-work-today-includes-only-work-items ()
  "Work Agenda ('ww') today block shows work items, excludes non-work ones."
  (agile-gtd-agenda-test-build-view "ww"
    ;; Work item scheduled today must appear
    (should (string-match-p "Work item today" agenda-text))
    ;; Non-work scheduled item must not appear in the work view
    (should-not (string-match-p "Scheduled today" agenda-text))))

;;; hide-today parameter tests

(defun agile-gtd-agenda-test-hide-today-data ()
  "Return org data for hide-today parameter tests.
Uses relative dates so scheduled/deadline items are testable."
  (let ((today (format-time-string "%Y-%m-%d %a"))
        (yesterday (format-time-string "%Y-%m-%d %a"
                     (time-subtract (current-time) (days-to-time 1))))
        (tomorrow (format-time-string "%Y-%m-%d %a"
                    (time-add (current-time) (days-to-time 1)))))
    (concat
     "* NEXT [#A] Plain next action\n\n"
     "* NEXT [#A] Scheduled today\n"
     (format "SCHEDULED: <%s>\n\n" today)
     "* NEXT [#A] Deadline today\n"
     (format "DEADLINE: <%s>\n\n" today)
     "* NEXT [#A] Scheduled yesterday (overdue)\n"
     (format "SCHEDULED: <%s>\n\n" yesterday)
     "* NEXT [#A] Deadline yesterday (overdue)\n"
     (format "DEADLINE: <%s>\n\n" yesterday)
     "* NEXT [#A] Scheduled tomorrow (future)\n"
     (format "SCHEDULED: <%s>\n\n" tomorrow)
     "* NEXT [#A] Someday item :SOMEDAY:\n\n"
     "* NEXT [#A] Tickler today :SOMEDAY:\n"
     (format "SCHEDULED: <%s>\n\n" today)
     "* NEXT [#A] Tickler future :SOMEDAY:\n"
     (format "SCHEDULED: <%s>\n\n" tomorrow)
     "* NEXT [#A] Habit item :HABIT:\n\n")))

(defmacro agile-gtd-agenda-test-hide-today-data-do (&rest body)
  "Run BODY with hide-today test fixtures in a temporary Org buffer."
  (declare (indent 0) (debug t))
  `(agile-gtd-org-ql-test-with-sandbox
    (let* ((file (expand-file-name "hide-today-fixtures.org" org-directory))
           (buffer nil))
      (unwind-protect
          (progn
            (with-temp-file file
              (insert (agile-gtd-agenda-test-hide-today-data)))
            (setq buffer (find-file-noselect file))
            (with-current-buffer buffer
              (org-mode)
              (agile-gtd-enable)
              (org-set-regexps-and-options)
              ,@body))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest agile-gtd-next-actions-default-includes-today-and-overdue ()
  "hide-today nil (default): scheduled/deadline today and overdue items appear."
  (agile-gtd-agenda-test-hide-today-data-do
    (let ((headings (agile-gtd-org-ql-test-headings
                     buffer (agile-gtd-agenda-query-next-actions))))
      (should (member "Plain next action" headings))
      (should (member "Scheduled today" headings))
      (should (member "Deadline today" headings))
      (should (member "Scheduled yesterday (overdue)" headings))
      (should (member "Deadline yesterday (overdue)" headings)))))

(ert-deftest agile-gtd-next-actions-default-excludes-future-scheduled ()
  "hide-today nil (default): future-scheduled items are excluded."
  (agile-gtd-agenda-test-hide-today-data-do
    (let ((headings (agile-gtd-org-ql-test-headings
                     buffer (agile-gtd-agenda-query-next-actions))))
      (should-not (member "Scheduled tomorrow (future)" headings)))))

(ert-deftest agile-gtd-next-actions-hide-today-excludes-all-scheduled-and-deadline ()
  "hide-today t: all scheduled and deadline items are excluded."
  (agile-gtd-agenda-test-hide-today-data-do
    (let ((headings (agile-gtd-org-ql-test-headings
                     buffer (agile-gtd-agenda-query-next-actions nil nil t))))
      (should (member "Plain next action" headings))
      (should-not (member "Scheduled today" headings))
      (should-not (member "Deadline today" headings))
      (should-not (member "Scheduled yesterday (overdue)" headings))
      (should-not (member "Deadline yesterday (overdue)" headings))
      (should-not (member "Scheduled tomorrow (future)" headings)))))

(ert-deftest agile-gtd-next-actions-excludes-someday ()
  "Someday items are excluded regardless of hide-today."
  (agile-gtd-agenda-test-hide-today-data-do
    (let ((default-headings (agile-gtd-org-ql-test-headings
                              buffer (agile-gtd-agenda-query-next-actions)))
          (hide-today-headings (agile-gtd-org-ql-test-headings
                                 buffer (agile-gtd-agenda-query-next-actions nil nil t))))
      (should-not (member "Someday item" default-headings))
      (should-not (member "Someday item" hide-today-headings)))))

(ert-deftest agile-gtd-next-actions-default-shows-tickler-today ()
  "hide-today nil (default): tickler items scheduled today appear (not someday)."
  (agile-gtd-agenda-test-hide-today-data-do
    (let ((headings (agile-gtd-org-ql-test-headings
                     buffer (agile-gtd-agenda-query-next-actions))))
      (should (member "Tickler today" headings))
      (should-not (member "Tickler future" headings)))))

(ert-deftest agile-gtd-next-actions-hide-today-excludes-tickler ()
  "hide-today t: tickler items are excluded (they are scheduled)."
  (agile-gtd-agenda-test-hide-today-data-do
    (let ((headings (agile-gtd-org-ql-test-headings
                     buffer (agile-gtd-agenda-query-next-actions nil nil t))))
      (should-not (member "Tickler today" headings))
      (should-not (member "Tickler future" headings)))))

(ert-deftest agile-gtd-next-actions-includes-habits ()
  "Habit items are included (filtered by priority like everything else)."
  (agile-gtd-agenda-test-hide-today-data-do
    (let ((headings (agile-gtd-org-ql-test-headings
                     buffer (agile-gtd-agenda-query-next-actions))))
      (should (member "Habit item" headings)))))

(ert-deftest agile-gtd-next-actions-default-matches-explicit-nil ()
  "Calling with no hide-today arg is equivalent to explicit nil."
  (agile-gtd-agenda-test-hide-today-data-do
    (let ((default-headings (agile-gtd-org-ql-test-headings
                             buffer (agile-gtd-agenda-query-next-actions)))
          (explicit-headings (agile-gtd-org-ql-test-headings
                              buffer (agile-gtd-agenda-query-next-actions nil nil nil))))
      (should (equal default-headings explicit-headings)))))

;;; Named view ranges — agenda buffer seam
;;
;; Every assertion below reads the rendered agenda: which headings are on
;; screen, what the block header says, and in what order the sections come.
;; The fixture puts one item in each priority band and nothing else on it, so
;; a heading's presence is decided by the view range and by nothing else.

(ert-deftest agile-gtd-agenda-main-view-opens-at-the-sprint-range ()
  "Main Agenda (\"a\") opens at `sprint', so the default screen is short."
  (agile-gtd-agenda-test-build-view "a"
    (should (eq (agile-gtd-agenda-test-current-range) 'sprint))
    (should (string-match-p "Next Actions \\[sprint\\]" agenda-text))))

(ert-deftest agile-gtd-agenda-private-view-opens-at-the-sprint-range ()
  "Private Agenda (\"pp\") opens at `sprint'."
  (agile-gtd-agenda-test-build-view "pp"
    (should (eq (agile-gtd-agenda-test-current-range) 'sprint))
    (should (string-match-p "Next Actions \\[sprint\\]" agenda-text))
    (should-not (string-match-p "Uncookied item" agenda-text))))

(ert-deftest agile-gtd-agenda-work-view-opens-at-the-backlog-range ()
  "Work Agenda (\"ww\") opens at `backlog', so unprioritised work is visible."
  (agile-gtd-agenda-test-build-view "ww"
    (should (eq (agile-gtd-agenda-test-current-range) 'backlog))
    (should (string-match-p "Next Actions \\[backlog\\]" agenda-text))
    (should (string-match-p "Work uncookied task" agenda-text))
    (should-not (string-match-p "Work band F task" agenda-text))))

(ert-deftest agile-gtd-agenda-project-view-opens-at-the-backlog-range ()
  "A generated per-project agenda opens at `backlog', like the work agenda."
  (agile-gtd-agenda-test-build-view-with
      ((agile-gtd-projects '((:tag "acme" :name "ACME Corp" :key ?a))))
      "wa"
    (should (eq (agile-gtd-agenda-test-current-range) 'backlog))
    (should (string-match-p "Next Actions \\[backlog\\]" agenda-text))
    (should (string-match-p "Acme uncookied job" agenda-text))
    (should-not (string-match-p "Acme band F job" agenda-text))))

(ert-deftest agile-gtd-agenda-private-backlog-opens-at-the-all-range ()
  "Private Backlog (\"pb\") opens at `all', so a backlog shows the long tail."
  (agile-gtd-agenda-test-build-view "pb"
    (should (eq (agile-gtd-agenda-test-current-range) 'all))
    (should (string-match-p "Backlog \\[all\\]" agenda-text))))

(ert-deftest agile-gtd-agenda-work-backlog-opens-at-the-all-range ()
  "Work Backlog (\"wb\") opens at `all': being a backlog beats the work prefix."
  (agile-gtd-agenda-test-build-view "wb"
    (should (eq (agile-gtd-agenda-test-current-range) 'all))
    (should (string-match-p "Backlog \\[all\\]" agenda-text))
    (should (string-match-p "Work band F task" agenda-text))))

(ert-deftest agile-gtd-agenda-item-without-a-cookie-joins-at-the-backlog-range ()
  "An item carrying no priority cookie is out of `sprint' and in from `backlog'.
Org reads a missing cookie as exactly the default priority, and so does the
rank code; this is the filter agreeing with both."
  (agile-gtd-agenda-test-build-view "a"
    (ert-info ("sprint leaves it out")
      (should-not (string-match-p "Uncookied item" agenda-text)))
    (ert-info ("backlog takes it in")
      (should (string-match-p "Uncookied item"
                              (agile-gtd-agenda-test-rotate-to 'backlog))))))

(ert-deftest agile-gtd-agenda-sprint-range-boundary ()
  "At `sprint' the cutoff band is on screen and the band past it is not."
  (agile-gtd-agenda-test-build-view "a"
    (should (eq (agile-gtd-agenda-test-current-range) 'sprint))
    (should (string-match-p "Band C item" agenda-text))
    (should-not (string-match-p "Band D item" agenda-text))))

(ert-deftest agile-gtd-agenda-backlog-range-boundary ()
  "At `backlog' the default band is on screen and the band past it is not."
  (agile-gtd-agenda-test-build-view "a"
    (let ((text (agile-gtd-agenda-test-rotate-to 'backlog)))
      (should (eq (agile-gtd-agenda-test-current-range) 'backlog))
      (should (string-match-p "Band D item" text))
      (should (string-match-p "Band E item" text))
      (should-not (string-match-p "Band F item" text)))))

(ert-deftest agile-gtd-agenda-all-range-takes-in-every-priority-band ()
  "At `all' every priority band is on screen and only parked work is missing."
  (agile-gtd-agenda-test-build-view "a"
    (let ((text (agile-gtd-agenda-test-rotate-to 'all)))
      (should (eq (agile-gtd-agenda-test-current-range) 'all))
      (should (string-match-p "Band F item" text))
      (should (string-match-p "Band I item" text))
      (should-not (string-match-p "Parked someday item" text))
      (should-not (string-match-p "Parked future tickler" text)))))

(ert-deftest agile-gtd-agenda-parked-items-appear-only-at-the-someday-range ()
  "Parked work stays off screen until the widest range.
The parked items carry [#A], so no priority cutoff can account for their
absence — only the someday and schedule gates can."
  (agile-gtd-agenda-test-build-view "a"
    (dolist (range '(today sprint backlog all))
      (ert-info ((format "range=%s" range))
        (let ((text (agile-gtd-agenda-test-rotate-to range)))
          (should-not (string-match-p "Parked someday item" text))
          (should-not (string-match-p "Parked future tickler" text)))))
    (ert-info ("range=someday")
      (let ((text (agile-gtd-agenda-test-rotate-to 'someday)))
        (should (string-match-p "Next Actions \\[someday\\]" text))
        (should (string-match-p "Parked someday item" text))))))

(ert-deftest agile-gtd-agenda-future-tickler-appears-at-the-someday-range ()
  "A tickler scheduled in the future survives the schedule gate at `someday'.
Lifting only the someday tag would leave the Tickler group permanently empty
in an agenda view, which filters future schedules as a second, invisible gate."
  (agile-gtd-agenda-test-build-view "a"
    (should-not (string-match-p "Parked future tickler" agenda-text))
    (should (string-match-p "Parked future tickler"
                            (agile-gtd-agenda-test-rotate-to 'someday)))))

(ert-deftest agile-gtd-agenda-backlog-view-shows-parked-items-at-the-someday-range ()
  "`someday' means the same thing in a backlog view as in an agenda view."
  (agile-gtd-agenda-test-build-view "pb"
    (ert-info ("all, the declared range, leaves parked work out")
      (should-not (string-match-p "Parked someday item" agenda-text))
      (should-not (string-match-p "Parked future tickler" agenda-text)))
    (ert-info ("someday brings both back")
      (let ((text (agile-gtd-agenda-test-rotate-to 'someday)))
        (should (string-match-p "Backlog \\[someday\\]" text))
        (should (string-match-p "Parked someday item" text))
        (should (string-match-p "Parked future tickler" text))))))

(ert-deftest agile-gtd-agenda-backlog-view-is-filtered-by-range ()
  "A backlog view narrows with the range, which an unfiltered backlog cannot."
  (agile-gtd-agenda-test-build-view "pb"
    (ert-info ("all admits every band")
      (should (string-match-p "Band I item" agenda-text))
      (should (string-match-p "Uncookied item" agenda-text))
      (should (string-match-p "Band I stuck project" agenda-text)))
    (ert-info ("sprint drops everything below the sprint cutoff")
      (let ((text (agile-gtd-agenda-test-rotate-to 'sprint)))
        (should (string-match-p "Backlog \\[sprint\\]" text))
        (should (string-match-p "Band C item" text))
        (should-not (string-match-p "Band I item" text))
        (should-not (string-match-p "Uncookied item" text))
        (should-not (string-match-p "Band I stuck project" text))))))

(ert-deftest agile-gtd-agenda-rotation-changes-the-items-and-the-header ()
  "Widening and narrowing redraw the view and restate the range in the header."
  (agile-gtd-agenda-test-build-view "a"
    (ert-info ("one step wider")
      (with-current-buffer (get-buffer org-agenda-buffer-name)
        (agile-gtd-agenda-wider-range))
      (let ((text (agile-gtd-agenda-test-agenda-text)))
        (should (eq (agile-gtd-agenda-test-current-range) 'backlog))
        (should (string-match-p "Next Actions \\[backlog\\]" text))
        (should (string-match-p "Uncookied item" text))))
    (ert-info ("one step back")
      (with-current-buffer (get-buffer org-agenda-buffer-name)
        (agile-gtd-agenda-narrower-range))
      (let ((text (agile-gtd-agenda-test-agenda-text)))
        (should (eq (agile-gtd-agenda-test-current-range) 'sprint))
        (should (string-match-p "Next Actions \\[sprint\\]" text))
        (should-not (string-match-p "Uncookied item" text))))))

(ert-deftest agile-gtd-agenda-set-range-jumps-straight-to-a-range ()
  "Picking a range reaches it in one action rather than by stepping."
  (agile-gtd-agenda-test-build-view "a"
    (with-current-buffer (get-buffer org-agenda-buffer-name)
      (agile-gtd-agenda-set-range 'someday))
    (should (eq (agile-gtd-agenda-test-current-range) 'someday))
    (let ((text (agile-gtd-agenda-test-agenda-text)))
      (should (string-match-p "Next Actions \\[someday\\]" text))
      (should (string-match-p "Parked someday item" text)))
    (ert-info ("An unknown range is refused")
      (with-current-buffer (get-buffer org-agenda-buffer-name)
        (should-error (agile-gtd-agenda-set-range 'nonsense) :type 'user-error)))))

(ert-deftest agile-gtd-agenda-widening-clamps-at-the-widest-range ()
  "Widening past `someday' leaves the view exactly as it was."
  (agile-gtd-agenda-test-build-view "a"
    (let ((widest (agile-gtd-agenda-test-rotate-to 'someday)))
      (with-current-buffer (get-buffer org-agenda-buffer-name)
        (agile-gtd-agenda-wider-range))
      (should (eq (agile-gtd-agenda-test-current-range) 'someday))
      (should (equal (agile-gtd-agenda-test-agenda-text) widest)))))

(ert-deftest agile-gtd-agenda-narrowing-clamps-at-the-narrowest-range ()
  "Narrowing past `today' leaves the view exactly as it was."
  (agile-gtd-agenda-test-build-view "a"
    (let ((narrowest (agile-gtd-agenda-test-rotate-to 'today)))
      (with-current-buffer (get-buffer org-agenda-buffer-name)
        (agile-gtd-agenda-narrower-range))
      (should (eq (agile-gtd-agenda-test-current-range) 'today))
      (should (equal (agile-gtd-agenda-test-agenda-text) narrowest)))))

(ert-deftest agile-gtd-agenda-today-sits-below-sprint-in-the-rotation ()
  "Narrowing from `sprint' reaches `today', and widening returns to `sprint'."
  (agile-gtd-agenda-test-build-view "a"
    (should (eq (agile-gtd-agenda-test-current-range) 'sprint))
    (with-current-buffer (get-buffer org-agenda-buffer-name)
      (agile-gtd-agenda-narrower-range))
    (should (eq (agile-gtd-agenda-test-current-range) 'today))
    (should (string-match-p "Next Actions \\[today\\]"
                            (agile-gtd-agenda-test-agenda-text)))
    (with-current-buffer (get-buffer org-agenda-buffer-name)
      (agile-gtd-agenda-wider-range))
    (should (eq (agile-gtd-agenda-test-current-range) 'sprint))))

(ert-deftest agile-gtd-agenda-set-range-accepts-today ()
  "`today' is picked by name like every other range."
  (agile-gtd-agenda-test-build-view "pb"
    (with-current-buffer (get-buffer org-agenda-buffer-name)
      (agile-gtd-agenda-set-range 'today))
    (should (eq (agile-gtd-agenda-test-current-range) 'today))
    (should (string-match-p "Backlog \\[today\\]"
                            (agile-gtd-agenda-test-agenda-text)))))

(ert-deftest agile-gtd-agenda-reset-returns-to-the-declared-range-from-today ()
  "Every command opens at its declared range, and reset returns there.
Adding `today' to the rotation changes nothing until someone switches to it,
and reset never lands on it."
  (dolist (case '(("a" sprint "Next Actions")
                  ("pp" sprint "Next Actions")
                  ("ww" backlog "Next Actions")
                  ("pb" all "Backlog")
                  ("wb" all "Backlog")
                  ("wa" backlog "Next Actions")))
    (pcase-let ((`(,key ,declared ,block) case))
      (ert-info ((format "command %s" key))
        (agile-gtd-agenda-test-build-view-with
            ((agile-gtd-projects '((:tag "acme" :name "ACME Corp" :key ?a))))
            key
          (should (eq (agile-gtd-agenda-test-current-range) declared))
          (should (string-match-p (format "%s \\[%s\\]" block declared)
                                  agenda-text))
          (agile-gtd-agenda-test-rotate-to 'today)
          (with-current-buffer (get-buffer org-agenda-buffer-name)
            (agile-gtd-agenda-reset-range))
          (should (eq (agile-gtd-agenda-test-current-range) declared))
          (should (string-match-p (format "%s \\[%s\\]" block declared)
                                  (agile-gtd-agenda-test-agenda-text))))))))

(ert-deftest agile-gtd-agenda-today-leaves-the-next-actions-block-empty ()
  "At `today' the next-actions block is empty, headed, under a full day block.
Everything inside `today' is scheduled, due or overdue, which is exactly what
the day block above already carries, so the block below it holds nothing."
  (dolist (key '("a" "pp" "ww"))
    (ert-info ((format "command %s" key))
      (agile-gtd-agenda-test-build-view key
        (let* ((text (agile-gtd-agenda-test-rotate-to 'today))
               (section (agile-gtd-agenda-test-block-section
                         text "Next Actions [today]"))
               (day (agile-gtd-agenda-test-block-section text "Day-agenda")))
          (should section)
          (ert-info ("The block holds its header and nothing else")
            (should (string-empty-p
                     (string-trim
                      (string-remove-prefix "Next Actions [today]" section)))))
          (ert-info ("The day block still lists the day's work")
            (should day)
            (should (string-match-p (if (equal key "ww")
                                        "Work item today"
                                      "Scheduled today")
                                    day))))))))

(ert-deftest agile-gtd-agenda-backlog-at-today-lists-only-what-is-due-today ()
  "A backlog rotated to `today' holds the projects and actions due today.
Nothing without a date for today comes along, whatever its priority, and
the one project step without a date stays out while its project is in."
  (agile-gtd-agenda-test-build-view "pb"
    (let ((section (agile-gtd-agenda-test-block-section
                    (agile-gtd-agenda-test-rotate-to 'today) "Backlog [today]")))
      (should section)
      (should (string-match-p "Scheduled today" section))
      (should (string-match-p "Project due today" section))
      (should-not (string-match-p "Step of the project due today" section))
      (should-not (string-match-p "High priority action" section))
      (should-not (string-match-p "Band C item" section))
      (should-not (string-match-p "Work item today" section))
      (ert-info ("They land under Today & Overdue and under no priority")
        (should (string-match-p "Today & Overdue" section))
        (should-not (string-match-p "Priority [A-I]" section))))))

(ert-deftest agile-gtd-agenda-range-does-not-survive-a-rebuild ()
  "Reopening a command returns it to its declared range."
  (agile-gtd-agenda-test-build-view "a"
    (agile-gtd-agenda-test-rotate-to 'someday)
    (should (eq (agile-gtd-agenda-test-current-range) 'someday))
    (kill-buffer (get-buffer org-agenda-buffer-name))
    (org-agenda nil "a")
    (should (eq (agile-gtd-agenda-test-current-range) 'sprint))
    (let ((text (agile-gtd-agenda-test-agenda-text)))
      (should (string-match-p "Next Actions \\[sprint\\]" text))
      (should-not (string-match-p "Parked someday item" text)))))

(ert-deftest agile-gtd-agenda-rotation-does-not-reach-another-command ()
  "Widening one view leaves the next view built at its own declared range."
  (agile-gtd-agenda-test-build-view "a"
    (agile-gtd-agenda-test-rotate-to 'someday)
    (should (eq (agile-gtd-agenda-test-current-range) 'someday))
    (org-agenda nil "pb")
    (should (eq (agile-gtd-agenda-test-current-range) 'all))
    (let ((text (agile-gtd-agenda-test-agenda-text)))
      (should (string-match-p "Backlog \\[all\\]" text))
      (should-not (string-match-p "Parked someday item" text)))))

(ert-deftest agile-gtd-agenda-stuck-projects-are-not-filtered-by-range ()
  "Stuck Projects shows the same entries at every range, and names no range.
Being stuck is a process failure whose priority is beside the point, so a
stuck project in the lowest band shows even in the narrowest view."
  (agile-gtd-agenda-test-build-view "a"
    (let ((section (agile-gtd-agenda-test-block-section
                    (agile-gtd-agenda-test-agenda-text) "Stuck Projects")))
      (should section)
      (ert-info ("A lowest-band stuck project shows in the narrowest range")
        (should (string-match-p "Band I stuck project" section)))
      (ert-info ("The header takes no range")
        (should-not (string-match-p "Stuck Projects \\[" section)))
      (dolist (range '(today backlog all someday))
        (ert-info ((format "range=%s" range))
          (should (equal (agile-gtd-agenda-test-block-section
                          (agile-gtd-agenda-test-rotate-to range)
                          "Stuck Projects")
                         section)))))))

(ert-deftest agile-gtd-agenda-stuck-projects-stay-above-next-actions ()
  "Stuck Projects keeps its place above Next Actions at every range."
  (agile-gtd-agenda-test-build-view "a"
    (dolist (range agile-gtd-view-ranges)
      (ert-info ((format "range=%s" range))
        (let* ((text (agile-gtd-agenda-test-rotate-to range))
               (stuck (string-match "Stuck Projects" text))
               (next (string-match "Next Actions" text)))
          (should stuck)
          (should next)
          (should (< stuck next)))))))

(ert-deftest agile-gtd-agenda-day-block-is-unaffected-by-range ()
  "The day block renders identically at every range, and is never duplicated.
A deadline must not go missing because the item carrying it is low priority,
and the Next Actions block must not name a task the day block already has."
  (agile-gtd-agenda-test-build-view "a"
    (let ((day (agile-gtd-agenda-test-block-section
                (agile-gtd-agenda-test-agenda-text) "Day-agenda")))
      (should day)
      (should (string-match-p "Scheduled today" day))
      (dolist (range '(today backlog all someday))
        (ert-info ((format "range=%s" range))
          (let ((text (agile-gtd-agenda-test-rotate-to range)))
            (should (equal (agile-gtd-agenda-test-block-section text "Day-agenda")
                           day))
            (let ((next-actions (agile-gtd-agenda-test-block-onwards
                                 text "Next Actions")))
              (should next-actions)
              (should-not (string-match-p "Scheduled today" next-actions)))))))))

(ert-deftest agile-gtd-agenda-rotation-refuses-an-agenda-with-no-ranged-block ()
  "Rotating a view that declares no range says so rather than doing nothing."
  (agile-gtd-agenda-test-build-view "rs"
    (should-not (agile-gtd-agenda-test-current-range))
    (with-current-buffer (get-buffer org-agenda-buffer-name)
      (should-error (agile-gtd-agenda-wider-range) :type 'user-error)
      (should-error (agile-gtd-agenda-narrower-range) :type 'user-error))))

(ert-deftest agile-gtd-agenda-rotation-refuses-outside-an-agenda-buffer ()
  "Outside an agenda there is no range to rotate, and the commands say so."
  (with-temp-buffer
    (should-not (agile-gtd-agenda-current-range))
    (should-error (agile-gtd-agenda-wider-range) :type 'user-error)
    (should-error (agile-gtd-agenda-narrower-range) :type 'user-error)))

;;; Named view ranges — corpus query seam
;;
;; The one thing the rendered agenda cannot show: what the public query
;; functions do when an external caller runs them outside any agenda buffer.

(defmacro agile-gtd-agenda-test-with-range-data (&rest body)
  "Run BODY over the range fixtures in a temporary Org buffer bound to `buffer'."
  (declare (indent 0) (debug t))
  `(agile-gtd-org-ql-test-with-sandbox
    (let* ((file (expand-file-name "range-fixtures.org" org-directory))
           (buffer nil))
      (unwind-protect
          (progn
            (with-temp-file file
              (insert (agile-gtd-agenda-integration-test-org-data)))
            (setq buffer (find-file-noselect file))
            (with-current-buffer buffer
              (org-mode)
              (agile-gtd-enable)
              (org-set-regexps-and-options)
              ,@body))
        (when (buffer-live-p buffer)
          (kill-buffer buffer))))))

(ert-deftest agile-gtd-query-next-actions-pins-its-range-to-sprint ()
  "Called with only a tag filter, the next-actions query is a `sprint' query.
It stays one whatever range an agenda was left showing, so asking an
assistant what the next actions are gives a reproducible answer."
  (agile-gtd-agenda-test-with-range-data
    (let ((pinned (agile-gtd-org-ql-test-headings
                   buffer (agile-gtd-agenda-query-next-actions))))
      (ert-info ("The pinned range is sprint")
        (should (member "Band C item" pinned))
        (should-not (member "Band D item" pinned))
        (should-not (member "Uncookied item" pinned))
        (should-not (member "Parked someday item" pinned))
        (should (equal pinned
                       (agile-gtd-org-ql-test-headings
                        buffer (agile-gtd-agenda-query-next-actions nil 'sprint)))))
      (ert-info ("Rotation state does not reach it")
        (setq-local agile-gtd--agenda-range 'someday)
        (dolist (range agile-gtd-view-ranges)
          (ert-info ((format "override=%s" range))
            (let ((agile-gtd--agenda-range-override range))
              (should (equal (agile-gtd-org-ql-test-headings
                              buffer (agile-gtd-agenda-query-next-actions))
                             pinned)))))))))

(ert-deftest agile-gtd-query-backlog-pins-its-range-to-all ()
  "Called with only a tag filter, the backlog query is an `all' query.
A backlog answers with the long tail, and parked work stays parked."
  (agile-gtd-agenda-test-with-range-data
    (let ((pinned (agile-gtd-org-ql-test-headings
                   buffer (agile-gtd-agenda-query-backlog))))
      (ert-info ("The pinned range is all")
        (should (member "Band I item" pinned))
        (should (member "Uncookied item" pinned))
        (should-not (member "Parked someday item" pinned))
        (should-not (member "Parked future tickler" pinned))
        (should (equal pinned
                       (agile-gtd-org-ql-test-headings
                        buffer (agile-gtd-agenda-query-backlog nil 'all)))))
      (ert-info ("Rotation state does not reach it")
        (setq-local agile-gtd--agenda-range 'sprint)
        (dolist (range agile-gtd-view-ranges)
          (ert-info ((format "override=%s" range))
            (let ((agile-gtd--agenda-range-override range))
              (should (equal (agile-gtd-org-ql-test-headings
                              buffer (agile-gtd-agenda-query-backlog))
                             pinned)))))))))

(ert-deftest agile-gtd-agenda-rotation-does-not-reach-the-public-queries ()
  "A rotated agenda leaves the pinned public queries where they were.
Rotation really happens here — the agenda is widened to `someday' and left
there — and the query still answers at `sprint'."
  (agile-gtd-agenda-test-build-view "a"
    (agile-gtd-agenda-test-rotate-to 'someday)
    (should (eq (agile-gtd-agenda-test-current-range) 'someday))
    (cl-flet ((next-actions-in (query)
                (org-ql-select file query :action '(org-get-heading t t t t))))
      (ert-info ("Called from outside the agenda")
        (let ((headings (next-actions-in
                         (with-temp-buffer (agile-gtd-agenda-query-next-actions)))))
          (should (member "Band C item" headings))
          (should-not (member "Uncookied item" headings))
          (should-not (member "Parked someday item" headings))))
      (ert-info ("Called from inside the rotated agenda buffer")
        (let ((headings (next-actions-in
                         (with-current-buffer (get-buffer org-agenda-buffer-name)
                           (agile-gtd-agenda-query-next-actions)))))
          (should-not (member "Uncookied item" headings))
          (should-not (member "Parked someday item" headings)))))))

(provide 'agile-gtd-agenda-test)

;;; agile-gtd-agenda-test.el ends here
