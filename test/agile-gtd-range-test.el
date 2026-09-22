;;; agile-gtd-range-test.el --- View range cutoff and grouping tests -*- lexical-binding: t; -*-

;;; Commentary:

;; A view range makes one promise: the priority groups it shows are the
;; priority groups it lets in.  Every test here holds the filter and the
;; grouping against each other, because the two run on separate code paths —
;; an org-ql predicate decides what a range admits, `agile-gtd-rank-groups'
;; decides where each admitted entry lands — and nothing but a test keeps
;; them saying the same thing.

;;; Code:

(require 'ert)
(require 'org)
(require 'org-agenda)
(require 'org-capture)
(require 'org-modern)
(require 'org-ql)
(require 'org-edna)
(require 'agile-gtd)
(require 'agile-gtd-org-ql-predicates-test)
(require 'agile-gtd-agenda-test)


;;; Fixtures

(defun agile-gtd-range-test-data ()
  "Return Org data covering every way an entry can earn a rank.

The corpus is built around one distinction that the production bug turned
on: an entry with its own low cookie and an entry with no cookie under a
low-cookied parent rank the same, so a range must treat them the same.
Half the entries here exist only to be that pair."
  (let ((in (lambda (days)
              (format-time-string
               "%Y-%m-%d %a" (time-add (current-time) (days-to-time days))))))
    (concat
     ;; Inside `backlog' by their own cookie.
     "* NEXT [#B] Own cookie B\n\n"
     "* NEXT [#E] Own cookie E\n\n"
     ;; Inside `backlog' by carrying no cookie at all.
     "* NEXT Bare no cookie\n\n"
     ;; Outside `backlog' by their own cookie.  These were always correct.
     "* NEXT [#F] Own cookie F\n\n"
     "* NEXT [#G] Own cookie G\n\n"
     ;; Outside `backlog' by their parent's cookie, carrying none themselves.
     ;; These are the entries the `backlog' range used to show.
     "* PROJ [#F] Parent F project\n"
     "** NEXT Child of F parent\n\n"
     "* PROJ [#G] Parent G project\n"
     "** NEXT Child of G parent\n\n"
     ;; A deadline promotes: near enough and the entry joins a tighter range.
     "* NEXT Bare with near deadline\n"
     (format "DEADLINE: <%s>\n\n" (funcall in 3))
     ;; A deadline never demotes: far off, the entry stays where its (absent)
     ;; cookie puts it rather than sinking below the default band.
     "* NEXT Bare with far deadline\n"
     (format "DEADLINE: <%s>\n\n" (funcall in 17))
     "* NEXT Bare with very far deadline\n"
     (format "DEADLINE: <%s>\n\n" (funcall in 90))
     ;; Due today: inside every range, `today' included.
     "* NEXT Bare due today\n"
     (format "DEADLINE: <%s>\n\n" (funcall in 0))
     ;; Scheduled beyond today: not actionable until that day arrives.
     "* NEXT Bare scheduled future\n"
     (format "SCHEDULED: <%s>\n\n" (funcall in 11))
     "* NEXT [#C] Cookie C scheduled future\n"
     (format "SCHEDULED: <%s>\n\n" (funcall in 20))
     ;; Parked: someday, and the tickler that is someday plus a schedule.
     "* NEXT [#A] Parked someday :SOMEDAY:\n\n"
     "* NEXT [#A] Parked tickler :SOMEDAY:\n"
     (format "SCHEDULED: <%s>\n\n" (funcall in 7)))))

(defmacro agile-gtd-range-test-with-data (&rest body)
  "Run BODY over `agile-gtd-range-test-data' with `buffer' bound to it."
  (declare (indent 0) (debug t))
  `(agile-gtd-org-ql-test-with-sandbox
     (let* ((file (expand-file-name "range-fixtures.org" org-directory))
            (buffer nil))
       (unwind-protect
           (progn
             (with-temp-file file (insert (agile-gtd-range-test-data)))
             (setq buffer (find-file-noselect file))
             (with-current-buffer buffer
               (org-mode)
               (agile-gtd-enable)
               (org-set-regexps-and-options)
               ,@body))
         (when (buffer-live-p buffer) (kill-buffer buffer))))))

(defun agile-gtd-range-test-ranked (buffer query)
  "Return (HEADING . RANK) for every entry in BUFFER matching QUERY."
  (org-ql-select buffer query
    :action (lambda ()
              (cons (org-get-heading t t t t) (agile-gtd--item-rank)))))


;;; The band top — one number shared by the filter and the groups

(ert-deftest agile-gtd-rank-band-top-closes-each-priority-band ()
  "A band runs from a priority's rank to the top the next one starts above."
  (should (= (agile-gtd--rank-band-top ?A)  9))
  (should (= (agile-gtd--rank-band-top ?B) 19))
  (should (= (agile-gtd--rank-band-top ?E) 49))
  (should (= (agile-gtd--rank-band-top ?I) 89))
  (should (null (agile-gtd--rank-band-top nil))))

(ert-deftest agile-gtd-rank-band-top-is-where-an-uncookied-entry-lands ()
  "The default band's top is the rank an entry with no cookie is given.
`agile-gtd-rank-groups' closes the Default group at that number and the
view-range filter admits at it, so the two cannot drift apart."
  (should (= (agile-gtd--rank-default)
             (agile-gtd--rank-band-top agile-gtd-priority-default)))
  (should (= (agile-gtd--backlog-rank nil nil nil)
             (agile-gtd--rank-band-top agile-gtd-priority-default))))


;;; A date may promote an entry, never demote it

(ert-deftest agile-gtd-rank-a-far-deadline-does-not-demote-an-uncookied-entry ()
  "A deadline is a reason to act sooner, never a reason to act later.
An entry with no cookie sits in the default band; a deadline beyond that
band\\='s reach leaves it there instead of sinking it past every priority."
  (let ((default (agile-gtd--rank-default)))
    (should (= (agile-gtd--backlog-rank nil nil 17) default))
    (should (= (agile-gtd--backlog-rank nil nil 30) default))
    (should (= (agile-gtd--backlog-rank nil nil 90) default))
    (ert-info ("A near deadline still promotes")
      (should (< (agile-gtd--backlog-rank nil nil 3) default)))))

(ert-deftest agile-gtd-rank-a-far-deadline-does-not-demote-a-cookied-entry ()
  "A cookie fixes the floor; a distant deadline cannot push an entry below it."
  (should (= (agile-gtd--backlog-rank ?C nil 90) (agile-gtd--prio-rank ?C)))
  (should (= (agile-gtd--backlog-rank nil ?C 90) (agile-gtd--prio-rank ?C))))

(ert-deftest agile-gtd-rank-a-parent-cookie-still-beats-the-default ()
  "Inheriting a low cookie is the point: it must outrank the bare default.
Were a parent's cookie replaced by the default, every entry under a low
project would be pulled into `backlog' — the opposite of the bug."
  (should (= (agile-gtd--backlog-rank nil ?G nil) (agile-gtd--prio-rank ?G)))
  (should (> (agile-gtd--backlog-rank nil ?G nil) (agile-gtd--rank-default))))


;;; The cutoff and the grouping agree

(ert-deftest agile-gtd-range-admits-only-what-its-groups-can-hold ()
  "Every entry a range admits ranks at or above that range's cutoff band.
This is the whole contract.  When it breaks, the agenda grows headings for
priorities the range never claimed to show — the reported symptom."
  (agile-gtd-range-test-with-data
    (dolist (range agile-gtd-view-ranges)
      (let ((top (agile-gtd-view-range-cutoff range)))
        (dolist (entry (agile-gtd-range-test-ranked
                        buffer (agile-gtd-agenda-query-next-actions nil range)))
          (ert-info ((format "range=%s entry=%S top=%d" range entry top))
            (should (<= (cdr entry) top))))
        (dolist (entry (agile-gtd-range-test-ranked
                        buffer (agile-gtd-agenda-query-backlog nil range)))
          (ert-info ((format "range=%s backlog entry=%S top=%d" range entry top))
            (should (<= (cdr entry) top))))))))

(ert-deftest agile-gtd-range-within-range-can-be-asked-for-any-range ()
  "The predicate takes a range name, `today' included, and cuts at its rank.
A priority character is still accepted and cuts at that priority\='s band."
  (agile-gtd-range-test-with-data
    (dolist (range agile-gtd-view-ranges)
      (let ((cutoff (agile-gtd-view-range-cutoff range))
            (ranked (agile-gtd-range-test-ranked buffer '(todo))))
        (ert-info ((format "range=%s" range))
          (should (equal (agile-gtd-range-test-ranked
                          buffer `(and (todo) (agile-gtd-within-range ,range)))
                         (cl-remove-if-not (lambda (entry) (<= (cdr entry) cutoff))
                                           ranked))))))
    (ert-info ("today admits the overdue and due-today entries only")
      (should (equal (mapcar #'car (agile-gtd-range-test-ranked
                                    buffer '(and (todo) (agile-gtd-within-range today))))
                     '("Bare due today"))))
    (ert-info ("a priority character cuts at its band")
      (should (equal (agile-gtd-range-test-ranked
                      buffer '(and (todo) (agile-gtd-within-range ?E)))
                     (agile-gtd-range-test-ranked
                      buffer '(and (todo) (agile-gtd-within-range backlog))))))))

(ert-deftest agile-gtd-range-backlog-excludes-an-uncookied-child-of-a-low-project ()
  "A bare entry under a [#F] or [#G] project is outside `backlog'.
It ranks where its parent's cookie puts it, so the range that stops at the
default priority must stop before it — exactly as it already does for an
entry carrying that cookie itself."
  (agile-gtd-range-test-with-data
    (let ((backlog (mapcar #'car (agile-gtd-range-test-ranked
                                  buffer (agile-gtd-agenda-query-next-actions
                                          nil 'backlog))))
          (all (mapcar #'car (agile-gtd-range-test-ranked
                              buffer (agile-gtd-agenda-query-next-actions
                                      nil 'all)))))
      (ert-info ("Out of backlog, whether the cookie is its own or its parent's")
        (should-not (member "Child of F parent" backlog))
        (should-not (member "Child of G parent" backlog))
        (should-not (member "Own cookie F" backlog))
        (should-not (member "Own cookie G" backlog)))
      (ert-info ("All four come back once the range reaches the lowest priority")
        (should (member "Child of F parent" all))
        (should (member "Child of G parent" all))
        (should (member "Own cookie F" all))
        (should (member "Own cookie G" all))))))

(ert-deftest agile-gtd-range-backlog-keeps-the-entries-it-should ()
  "Narrowing the cutoff must not take the default band down with it."
  (agile-gtd-range-test-with-data
    (let ((backlog (mapcar #'car (agile-gtd-range-test-ranked
                                  buffer (agile-gtd-agenda-query-next-actions
                                          nil 'backlog)))))
      (should (member "Own cookie B" backlog))
      (should (member "Own cookie E" backlog))
      (should (member "Bare no cookie" backlog))
      (ert-info ("A far deadline leaves an entry in the default band, not below it")
        (should (member "Bare with far deadline" backlog))
        (should (member "Bare with very far deadline" backlog)))
      (ert-info ("A near deadline pulls an entry up into `sprint'")
        (should (member "Bare with near deadline"
                        (mapcar #'car (agile-gtd-range-test-ranked
                                       buffer (agile-gtd-agenda-query-next-actions
                                               nil 'sprint)))))))))


;;; Scheduled beyond today

(ert-deftest agile-gtd-range-backlog-query-excludes-future-scheduled ()
  "An entry scheduled beyond today is not backlog work.
It is spoken for until that day arrives, so every range short of `someday'
leaves it out — the backlog query no less than the next-actions one."
  (agile-gtd-range-test-with-data
    (dolist (range '(sprint backlog all))
      (let ((headings (mapcar #'car (agile-gtd-range-test-ranked
                                     buffer (agile-gtd-agenda-query-backlog
                                             nil range)))))
        (ert-info ((format "range=%s" range))
          (should-not (member "Bare scheduled future" headings))
          (should-not (member "Cookie C scheduled future" headings)))))))

(ert-deftest agile-gtd-range-someday-query-restores-future-scheduled ()
  "The widest range is where work set aside for a date comes back."
  (agile-gtd-range-test-with-data
    (let ((headings (mapcar #'car (agile-gtd-range-test-ranked
                                   buffer (agile-gtd-agenda-query-backlog
                                           nil 'someday)))))
      (should (member "Bare scheduled future" headings))
      (should (member "Cookie C scheduled future" headings))
      (ert-info ("And the tickler it exists to show")
        (should (member "Parked tickler" headings))))))


;;; The Scheduled group

(ert-deftest agile-gtd-rank-groups-carry-a-scheduled-group ()
  "A Scheduled group collects work waiting on a date beyond today."
  (let ((group (cl-find-if (lambda (g) (equal (plist-get g :name) "Scheduled"))
                           (agile-gtd-rank-groups))))
    (should group)
    (should (equal (plist-get group :scheduled) 'future))))

(ert-deftest agile-gtd-rank-groups-place-scheduled-below-the-priorities ()
  "Scheduled sits under every priority heading and over the parked ones.
Order is what the reader sees: priorities first because they are the work
on offer, then what is waiting on a date, then what was set aside."
  (let* ((groups (agile-gtd-rank-groups))
         (order (lambda (name)
                  (plist-get (cl-find-if
                              (lambda (g) (equal (plist-get g :name) name))
                              groups)
                             :order)))
         (scheduled (funcall order "Scheduled")))
    (should (< (funcall order "Today & Overdue") scheduled))
    (dolist (prio (agile-gtd--priority-range))
      (let ((name (format "[#%c] Priority %c" prio prio)))
        (ert-info ((format "priority group %s" name))
          (should (< (funcall order name) scheduled)))))
    (should (< (funcall order "Default Priority") scheduled))
    (should (< scheduled (funcall order "Tickler")))
    (should (< (funcall order "Tickler") (funcall order "Someday")))))

(ert-deftest agile-gtd-rank-groups-let-tickler-claim-a-scheduled-someday ()
  "A tickler is a schedule and a SOMEDAY tag; the tickler group takes it.
org-super-agenda hands an item to the first group that matches, so Tickler
must be listed before Scheduled or every tickler would be swallowed."
  (let* ((groups (agile-gtd-rank-groups))
         (position (lambda (name)
                     (cl-position-if
                      (lambda (g) (equal (plist-get g :name) name)) groups))))
    (should (< (funcall position "Tickler") (funcall position "Scheduled")))
    (should (< (funcall position "Someday") (funcall position "Scheduled")))
    (ert-info ("And Scheduled is listed before any priority group could claim it")
      (should (< (funcall position "Scheduled")
                 (funcall position
                          (format "[#%c] Priority %c"
                                  agile-gtd-priority-highest
                                  agile-gtd-priority-highest)))))))


;;; Rendered agenda

(ert-deftest agile-gtd-range-someday-view-groups-future-scheduled-under-scheduled ()
  "At `someday' a future-scheduled entry renders under Scheduled.
The fixture's tickler is scheduled too, so this also pins that the two
groups do not take each other's items."
  (agile-gtd-agenda-test-build-view "a"
    (let* ((text (agile-gtd-agenda-test-rotate-to 'someday))
           (section (agile-gtd-agenda-test-block-section text "Next Actions")))
      (should section)
      (should (string-match-p "Scheduled" section))
      (let ((scheduled-at (string-match "^ *Scheduled$" section))
            (tickler-at (string-match "^ *Tickler$" section)))
        (should scheduled-at)
        (should tickler-at)
        (ert-info ("Scheduled is printed above Tickler")
          (should (< scheduled-at tickler-at)))
        (ert-info ("The future tickler is under Tickler, not under Scheduled")
          (should (string-match-p
                   "Parked future tickler"
                   (substring section tickler-at))))))))

(ert-deftest agile-gtd-range-backlog-view-has-no-heading-past-its-cutoff ()
  "The rendered `backlog' shows no priority heading below the default.
This is the screenshot the bug was reported from: a `backlog' agenda with
[#F] and [#G] headings on it."
  (agile-gtd-agenda-test-build-view "a"
    (let* ((text (agile-gtd-agenda-test-rotate-to 'backlog))
           (section (agile-gtd-agenda-test-block-section text "Next Actions")))
      (should section)
      (cl-loop for prio from (1+ agile-gtd-priority-default)
               to agile-gtd-priority-lowest
               do (ert-info ((format "priority %c heading" prio))
                    (should-not
                     (string-match-p (format "\\[#%c\\] Priority %c" prio prio)
                                     section)))))))

(provide 'agile-gtd-range-test)
;;; agile-gtd-range-test.el ends here
