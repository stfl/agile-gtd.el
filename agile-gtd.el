;;; agile-gtd.el --- Agile GTD workflow for Org -*- lexical-binding: t; -*-

;; Version: 0.1.0
;; URL: https://github.com/stfl/agile-gtd
;; Package-Requires: ((emacs "30.2") (dash "2.19.1") (org-modern "1.6") (org-ql "0.8") (org-super-agenda "1.3") (ts "0.3") (org-edna "1.1.2"))
;; Keywords: outlines, calendar, tools

;;; Commentary:

;; Agile GTD workflow for Org-mode.  Provides priority-based ranking, sprint
;; planning, backlog management, and agenda views using org-ql.

;;; Code:

(require 'cl-lib)
(require 'dash)
(require 'org)
(require 'org-agenda)
(require 'org-capture)
(require 'org-clock)
(require 'org-duration)
(require 'org-element)
(require 'org-id)
(require 'org-ql)
(require 'org-ql-search)
(require 'org-super-agenda)
(require 'ts)

(defvar org-modern-priority)

(defgroup agile-gtd nil
  "Agile and GTD helpers for Org mode."
  :group 'org)

(defcustom agile-gtd-priority-highest ?A
  "Highest priority used by Agile GTD."
  :type 'character
  :group 'agile-gtd)

(defcustom agile-gtd-priority-default ?E
  "Default priority used by Agile GTD."
  :type 'character
  :group 'agile-gtd)

(defcustom agile-gtd-priority-lowest ?I
  "Lowest priority used by Agile GTD."
  :type 'character
  :group 'agile-gtd)

(defcustom agile-gtd-priority-symbol-alist
  '((?A . "⛔")
    (?B . "▲")
    (?C . "𐱄")
    (?D . "ᐱ")
    (?E . "Ⲷ")
    (?F . "ᐯ")
    (?G . "𐠠")
    (?H . "▼")
    (?I . "҉"))
  "Symbols shown by org-modern for GTD priorities."
  :type '(alist :key-type character :value-type string)
  :group 'agile-gtd)

(defcustom agile-gtd-priority-face-alist
  '((?A . (:foreground "red3" :weight bold :height 0.95))
    (?B . (:foreground "OrangeRed2" :weight bold))
    (?C . (:foreground "DarkOrange2" :weight bold))
    (?D . (:foreground "gold3" :weight bold))
    (?E . (:foreground "OliveDrab1" :weight bold))
    (?F . (:foreground "SpringGreen3" :weight bold))
    (?G . (:foreground "cyan4" :weight bold))
    (?H . (:foreground "DeepSkyBlue4" :weight bold))
    (?I . (:foreground "LightSteelBlue3" :weight bold)))
  "Faces used for GTD priorities."
  :type '(alist :key-type character :value-type plist)
  :group 'agile-gtd)

(defcustom agile-gtd-todo-keywords
  '((sequence
     "TODO(t)"
     "NEXT(n)"
     "WAIT(w)"
     "PROJ(p)"
     "EPIC(e)"
     "|"
     "DONE(d@)"
     "IDEA(i)"
     "KILL(k@)"))
  "TODO keyword sequence used by Agile GTD."
  :type 'sexp
  :group 'agile-gtd)

(defcustom agile-gtd-todo-repeat-to-state "NEXT"
  "State repeated tasks should move to."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-someday-tag "SOMEDAY"
  "Tag used for someday items."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-habit-tag "HABIT"
  "Tag used for habits."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-lastmile-tag "LASTMILE"
  "Tag used for nearly finished tasks."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-work-tag "#work"
  "Tag used for work items."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-personal-tag "#personal"
  "Tag used for personal items."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-projects nil
  "List of configured projects.
Each entry is a plist with:
  :tag  - org tag string identifying this project (required)
  :name - display name (defaults to value of :tag)
  :file - org file relative to `org-directory' (defaults to :tag \".org\")
  :key  - single character for agenda key binding and tag-alist (optional, nil means no binding)"
  :type '(repeat (plist :key-type keyword :value-type sexp))
  :group 'agile-gtd)

(defcustom agile-gtd-inbox-file "inbox.org"
  "Inbox file relative to `org-directory'."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-todo-file "todo.org"
  "Todo file relative to `org-directory'."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-diary-file "diary.org"
  "Diary file relative to `org-directory'."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-someday-files-glob "gtd/someday/*.org"
  "Glob relative to `org-directory' used for someday refile targets."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-inbox-heading "Inbox"
  "Heading used for inbox captures."
  :type 'string
  :group 'agile-gtd)

(defcustom agile-gtd-inbox-tags '("#inbox" "inbox")
  "Tags treated as inbox items in the agenda."
  :type '(repeat string)
  :group 'agile-gtd)

(defcustom agile-gtd-max-priority-group nil
  "Highest visible priority group in agenda commands.

When nil, derive it from `agile-gtd-priority-default'."
  :type '(choice (const :tag "Derived from default" nil)
          character)
  :group 'agile-gtd)

(defcustom agile-gtd-sprint-prio-threshold ?C
  "Default priority threshold for the next-actions (sprint) view.
Items at this priority or above (including via parent or deadline) appear
in the next-actions query.  `agile-gtd-max-priority-group' overrides this
interactively."
  :type 'character
  :group 'agile-gtd)

(defcustom agile-gtd-backlog-priority-threshold nil
  "Priority threshold after which backlog items count as someday.

When nil, derive it from `agile-gtd-priority-default'."
  :type '(choice (const :tag "Derived from default" nil)
          character)
  :group 'agile-gtd)

(defcustom agile-gtd-enable-agenda-files t
  "Whether `agile-gtd-enable' should manage `org-agenda-files'."
  :type 'boolean
  :group 'agile-gtd)

(defcustom agile-gtd-enable-refile-targets t
  "Whether `agile-gtd-enable' should manage `org-refile-targets'."
  :type 'boolean
  :group 'agile-gtd)

(defcustom agile-gtd-enable-org-modern-visuals t
  "Whether Agile GTD should configure org-modern priority visuals."
  :type 'boolean
  :group 'agile-gtd)

(defface agile-gtd-todo-active
  '((t (:inherit (bold font-lock-constant-face org-todo))))
  "Face for active TODO items."
  :group 'agile-gtd)

(defface agile-gtd-todo-idea
  '((t (:inherit (bold font-lock-constant-face org-todo))))
  "Face for idea items."
  :group 'agile-gtd)

(defface agile-gtd-todo-project
  '((t (:inherit (bold font-lock-doc-face org-todo))))
  "Face for projects."
  :group 'agile-gtd)

(defface agile-gtd-todo-epic
  '((t (:inherit (bold org-cite org-todo))))
  "Face for epics."
  :group 'agile-gtd)

(defface agile-gtd-todo-onhold
  '((t (:inherit (bold warning org-todo))))
  "Face for waiting items."
  :group 'agile-gtd)

(defface agile-gtd-todo-next
  '((t (:inherit (bold font-lock-keyword-face org-todo))))
  "Face for next actions."
  :group 'agile-gtd)

(defface agile-gtd-todo-cancel
  '((t (:inherit (bold org-done) :foreground "IndianRed3")))
  "Face for cancelled items."
  :group 'agile-gtd)

(defun agile-gtd--project-keyword ()
  "Return the GTD project keyword."
  "PROJ")

(defun agile-gtd--action-keywords ()
  "Return the GTD action keywords."
  '("NEXT" "WAIT"))

(defun agile-gtd-project-keyword ()
  "Return the public GTD project keyword."
  (agile-gtd--project-keyword))

(defun agile-gtd-action-keywords ()
  "Return the public GTD action keywords."
  (copy-sequence (agile-gtd--action-keywords)))

(defun agile-gtd--priority-range ()
  "Return the configured priority range."
  (number-sequence agile-gtd-priority-highest agile-gtd-priority-lowest))

(defun agile-gtd--priority-in-range-p (priority)
  "Return non-nil when PRIORITY is within the configured priority range."
  (and (characterp priority)
       (<= agile-gtd-priority-highest priority agile-gtd-priority-lowest)))

(defun agile-gtd--validate-configuration ()
  "Validate the current Agile GTD configuration."
  (unless (<= agile-gtd-priority-highest
              agile-gtd-priority-default
              agile-gtd-priority-lowest)
    (error "Agile GTD priorities must satisfy highest <= default <= lowest"))
  (dolist (priority (delq nil (list agile-gtd-max-priority-group
                                    agile-gtd-backlog-priority-threshold)))
    (unless (agile-gtd--priority-in-range-p priority)
      (error "Priority %s is outside the configured Agile GTD range"
             priority))))

(defun agile-gtd--project-tag (c)
  "Return the tag for project C."
  (plist-get c :tag))

(defun agile-gtd--project-name (c)
  "Return the display name for project C."
  (or (plist-get c :name) (plist-get c :tag)))

(defun agile-gtd--project-file (c)
  "Return the org file for project C."
  (or (plist-get c :file) (concat (plist-get c :tag) ".org")))

(defun agile-gtd--project-key (c)
  "Return the key character for project C, or nil if none."
  (plist-get c :key))

(defun agile-gtd--workflow-tag-alist ()
  "Return the workflow tag definitions managed by Agile GTD."
  `((:startgrouptag)
    ("Process" . nil)
    (:grouptags)
    (,agile-gtd-someday-tag . ?S)
    (,agile-gtd-habit-tag . ?H)
    (,agile-gtd-lastmile-tag . ?L)
    (:endgrouptag)
    (:startgrouptag)
    ("Areas" . nil)
    (:grouptags)
    (,agile-gtd-work-tag . ?$)
    (,agile-gtd-personal-tag . ?_)
    (:endgrouptag)))

(defun agile-gtd--merge-tag-alist (current additions)
  "Merge ADDITIONS into CURRENT without overwriting existing tag names."
  (let ((result (copy-tree current)))
    (dolist (entry additions result)
      (unless (assoc (car entry) result)
        (setq result (append result (list entry)))))))

(defun agile-gtd--workflow-tag-names ()
  "Return the workflow tag names managed by Agile GTD."
  (list "Process"
        agile-gtd-someday-tag
        agile-gtd-habit-tag
        agile-gtd-lastmile-tag
        "Areas"
        agile-gtd-work-tag
        agile-gtd-personal-tag))

(defun agile-gtd--list-prefix-p (prefix list)
  "Return non-nil when PREFIX matches the start of LIST."
  (and (<= (length prefix) (length list))
       (cl-every #'equal prefix (cl-subseq list 0 (length prefix)))))

(defun agile-gtd--delete-sublist (sublist list)
  "Delete all SUBLIST occurrences from LIST."
  (let ((result nil)
        (tail list)
        (sublist-length (length sublist)))
    (while tail
      (if (agile-gtd--list-prefix-p sublist tail)
          (setq tail (nthcdr sublist-length tail))
        (push (pop tail) result)))
    (nreverse result)))

(defun agile-gtd--replace-by-key (current additions)
  "Replace entries in CURRENT whose key matches an entry in ADDITIONS."
  (let ((keys (mapcar #'car additions)))
    (append
     (cl-remove-if (lambda (item)
                     (member (car-safe item) keys))
                   current)
     additions)))

(defun agile-gtd--priority-symbols ()
  "Return org-modern priority symbols for the configured range."
  (--keep (when-let ((symbol (alist-get it agile-gtd-priority-symbol-alist)))
            (cons it symbol))
          (agile-gtd--priority-range)))

(defun agile-gtd--priority-faces ()
  "Return `org-priority-faces' data for the configured range."
  (--keep (when-let ((face (alist-get it agile-gtd-priority-face-alist)))
            (append (list it) face))
          (agile-gtd--priority-range)))

(defun agile-gtd--priority-prompt-choices ()
  "Return the priority choices used in capture templates."
  (mapconcat (lambda (priority)
               (format "[#%c]" priority))
             (agile-gtd--priority-range)
             " |"))

(defun agile-gtd--expand-org-path (file)
  "Expand FILE relative to `org-directory'."
  (expand-file-name file org-directory))

(defun agile-gtd-project-files ()
  "Return the list of project files derived from `agile-gtd-projects'."
  (mapcar #'agile-gtd--project-file agile-gtd-projects))

(defun agile-gtd--managed-agenda-files ()
  "Return the agenda files directly managed by Agile GTD."
  (mapcar #'agile-gtd--expand-org-path
          (cl-remove-duplicates
           (append (list agile-gtd-inbox-file
                         agile-gtd-todo-file)
                   (agile-gtd-project-files))
           :test #'equal)))

(defun agile-gtd--someday-files ()
  "Return the someday files used for refiling."
  (file-expand-wildcards (agile-gtd--expand-org-path agile-gtd-someday-files-glob)))

(defun agile-gtd--current-max-priority-group ()
  "Return the currently active maximum priority group."
  (or agile-gtd-max-priority-group
      agile-gtd-sprint-prio-threshold))

(defun agile-gtd--current-backlog-priority-threshold ()
  "Return the currently active backlog threshold."
  (or agile-gtd-backlog-priority-threshold
      (min agile-gtd-priority-lowest (+ agile-gtd-priority-default 2))))

(defun agile-gtd--capture-template-project ()
  "Return the project capture template."
  (concat "* PROJ %^{PRIORITY||"
          (agile-gtd--priority-prompt-choices)
          " }%^{Title}\n"
          ":PROPERTIES:\n"
          ":ID:       %(org-id-new)\n"
          ":CREATED:  %U\n"
          ":END:\n\n"
          "~Goal:~ %^{Goal}\n\n"
          "** NEXT %^{Next Action}\n"
          ":PROPERTIES:\n"
          ":CREATED:  %U\n"
          ":END:\n\n"
          "%?\n"))

(defun agile-gtd--protocol-description (description)
  "Normalize DESCRIPTION for protocol capture links."
  (let ((text (or description "")))
    (setq text (replace-regexp-in-string "\\[" "(" text))
    (replace-regexp-in-string "\\]" ")" text)))

(defun agile-gtd--capture-templates ()
  "Return the Agile GTD capture templates."
  `(("n" "capture to inbox" entry
     (file+headline ,(agile-gtd--expand-org-path agile-gtd-inbox-file) ,agile-gtd-inbox-heading)
     "* TODO %^{Task}\n:PROPERTIES:\n:CREATED:  %U\n:ID:       %(org-id-uuid)\n:END:\n\n%?\n"
     :empty-lines-after 1)
    ("p" "Project" entry
     (file ,(agile-gtd--expand-org-path agile-gtd-inbox-file))
     ,(agile-gtd--capture-template-project)
     :empty-lines-after 1)
    ("s" "scheduled" entry
     (file ,(agile-gtd--expand-org-path agile-gtd-inbox-file))
     "* NEXT %^{Task}\nSCHEDULED: %^{Scheduled}t\n:PROPERTIES:\n:CREATED:  %U\n:END:\n\n%?\n"
     :empty-lines-after 1)
    ("S" "deadline" entry
     (file ,(agile-gtd--expand-org-path agile-gtd-inbox-file))
     "* NEXT %^{Task}\nDEADLINE: %^{Deadline}t\n:PROPERTIES:\n:CREATED:  %U\n:END:\n\n%?\n"
     :empty-lines-after 1)
    ("P" "Protocol" entry
     (file ,(agile-gtd--expand-org-path agile-gtd-inbox-file))
     ,(concat "* %^{Title}\n"
              "Source: [[%:link][%(agile-gtd--protocol-description \"%:description\")]]\n"
              ":PROPERTIES:\n"
              ":CREATED: %U\n"
              ":END:\n"
              "#+BEGIN_QUOTE\n%i\n#+END_QUOTE\n\n%?")
     :empty-lines-after 1)
    ("L" "Protocol Link" entry
     (file ,(agile-gtd--expand-org-path agile-gtd-inbox-file))
     "* [[%:link][%:description]]\n:PROPERTIES:\n:CREATED: %U\n:END:\n%?"
     :empty-lines-after 1)))

(defun agile-gtd--stuck-projects-setting ()
  "Return the `org-stuck-projects' setting for Agile GTD."
  (list (format "-%s/+%s" agile-gtd-someday-tag (agile-gtd--project-keyword))
        (agile-gtd--action-keywords)
        nil
        ""))

(defun agile-gtd--prio-rank (priority)
  "Return numeric rank for PRIORITY character, or nil if out of the configured range.
Rank starts at 1 for `agile-gtd-priority-highest' and increases by 10 per step,
so the effective maximum is determined by `agile-gtd-priority-lowest'."
  (when (agile-gtd--priority-in-range-p priority)
    (+ (* 10 (- priority agile-gtd-priority-highest)) 1)))

(defconst agile-gtd--priority-deadline-days
  '((?A . 2)
    (?B . 5)
    (?C . 7)
    (?D . 11)
    (?E . 14)
    (?F . 21)
    (?G . 30)
    (?H . 60))
  "Maximum days-until-deadline for each priority level.")

(defun agile-gtd--deadline-rank (days)
  "Return numeric rank for DAYS until deadline (integer).
Thresholds are derived from `agile-gtd--priority-deadline-days': each priority
maps to the floor of its rank band, `(* 10 (- prio agile-gtd-priority-highest))'.
Overdue (negative) returns DAYS itself; today returns -1; beyond all thresholds returns 1000."
  (cond
   ((< days 0) days)
   ((= days 0) -1)
   (t (or (cl-loop for (prio . threshold) in agile-gtd--priority-deadline-days
                   when (<= days threshold)
                   return (* 10 (- prio agile-gtd-priority-highest)))
          1000))))

(defconst agile-gtd--rank-inf 99999)

(defun agile-gtd--rank-default ()
  "Return the rank for items with no explicit priority, deadline, or parent.
Computed as the top of the 10-wide band for `agile-gtd-priority-default':
  floor(prio-rank(default) / 10) * 10 + 9.
With default ?E (rank 41) this yields 49, sitting between E (40..48) and F (50+)."
  (let ((r (agile-gtd--prio-rank agile-gtd-priority-default)))
    (+ (* 10 (/ r 10)) 9)))

(defun agile-gtd--backlog-rank (prio parent-prio dl-delta &optional sc-delta)
  "Return numeric backlog rank.
PRIO and PARENT-PRIO are priority characters or nil.
DL-DELTA and SC-DELTA are integer days until deadline/scheduled, or nil.
SC-DELTA only influences rank when <= 0 (today or overdue); future
scheduled dates are ignored."
  (let* ((own      (or (agile-gtd--prio-rank prio)        agile-gtd--rank-inf))
         (par      (or (agile-gtd--prio-rank parent-prio) agile-gtd--rank-inf))
         (dl       (if dl-delta (agile-gtd--deadline-rank dl-delta) agile-gtd--rank-inf))
         (sc       (if (and sc-delta (<= sc-delta 0))
                       (agile-gtd--deadline-rank sc-delta)
                     agile-gtd--rank-inf))
         (combined (min own par dl sc)))
    (if (>= combined agile-gtd--rank-inf) (agile-gtd--rank-default) combined)))

(defun agile-gtd--deadline-window (priority)
  "Return the deadline window in days for PRIORITY (hard-coded table)."
  (or (alist-get priority agile-gtd--priority-deadline-days) 0))

(defun agile-gtd--priority-or-default ()
  "Return the priority at point or the default fallback."
  (or (org-element-property :priority (org-element-at-point))
      (+ 0.5 org-priority-default)))

(defun agile-gtd--direct-parent-priority ()
  "Return the direct parent heading's priority character, or nil."
  (save-excursion
    (when (org-up-heading-safe)
      (org-element-property :priority (org-element-at-point)))))

(defun agile-gtd--parent-project-priority-or-default (marker)
  "Return the parent project priority for MARKER."
  (org-with-point-at marker
    (cl-loop minimize (when (equal (agile-gtd--project-keyword)
                                   (nth 2 (org-heading-components)))
                        (agile-gtd--priority-or-default))
             while (and (not (equal (agile-gtd--project-keyword)
                                    (nth 2 (org-heading-components))))
                        (org-up-heading-safe)))))

(defun agile-gtd--project-priority= (marker priority)
  "Return non-nil when MARKER belongs to a project with PRIORITY."
  (let ((project-priority (agile-gtd--parent-project-priority-or-default marker)))
    (and project-priority
         (= project-priority priority))))

(defun agile-gtd-priority-groups ()
  "Return priority-based org-super-agenda groups."
  (append
   `((:tag ,agile-gtd-someday-tag :order 90))
   (mapcar (lambda (priority)
             (let ((priority-string (char-to-string priority)))
               `(:name ,(format "[#%s] Priority %s" priority-string priority-string)
                 :priority ,priority-string
                 :order ,priority)))
           (agile-gtd--priority-range))
   `((:name "Default Priority"
      :anything t
      :order ,(+ 0.5 org-priority-default)))))

(defun agile-gtd--rank-for-item (item)
  "Return the effective backlog rank for agenda ITEM string, or nil."
  (when-let ((marker (org-find-text-property-in-string 'org-marker item)))
    (org-with-point-at marker
      (agile-gtd--item-rank))))

(defun agile-gtd-rank-groups ()
  "Return rank-mark org-super-agenda groups.
Groups use upper-bound rank checks; first-match semantics means no lower
bound is needed per group.

Sequence: Tickler | Someday | Today&Overdue(≤0) | A(≤9) | B(≤19) | C(≤29)
| D(≤39) | Default(=49) | E(≤49) | F(≤59) | G(≤69) | H(≤79) | I | Rest.

Default group precedes E so rank `(agile-gtd--rank-default)' (49 by default)
is consumed before E's (≤49) check; E then effectively captures 40..48.
hi per priority P: (+ (* 10 (/ (prio-rank P) 10)) 9) — uniform formula."
  (append
   `((:name "Tickler"
      :and (:scheduled t :tag ,agile-gtd-someday-tag)
      :order 1000)
     (:name "Someday"
      :tag ,agile-gtd-someday-tag
      :order 1100)
     (:name "Today & Overdue"
      :pred (lambda (item)
              (when-let ((rank (agile-gtd--rank-for-item item)))
                (<= rank 0)))
      :order 0))
   (cl-mapcan
    (lambda (prio)
      (let* ((r    (agile-gtd--prio-rank prio))
             (hi   (unless (= prio agile-gtd-priority-lowest)
                     (+ (* 10 (/ r 10)) 9)))
             (name (format "[#%c] Priority %c" prio prio))
             (prio-group
              `(:name ,name
                :pred (lambda (item)
                        (when-let ((rank (agile-gtd--rank-for-item item)))
                          ,(if hi `(<= rank ,hi) t)))
                :order ,r)))
        (if (= prio agile-gtd-priority-default)
            (list `(:name "Default Priority"
                    :pred (lambda (item)
                            (when-let ((rank (agile-gtd--rank-for-item item)))
                              (= rank ,(agile-gtd--rank-default))))
                    :order ,(agile-gtd--rank-default))
                  prio-group)
          (list prio-group))))
    (agile-gtd--priority-range))
   `((:name "Not Grouped" :anything t :order 9999))))

(defun agile-gtd--today-groups ()
  "Return the org-super-agenda groups used by the today agenda."
  `((:time-grid t :order 0)
    (:name "Tickler" :tag ,agile-gtd-someday-tag :order 20)
    (:name "Habits" :tag ,agile-gtd-habit-tag :habit t :order 90)
    (:name "Today" :anything t :order 10)))

(defun agile-gtd--agenda-skip-form (filter-preset)
  "Return a skip sexp implementing FILTER-PRESET tag filtering.
FILTER-PRESET is a list of strings like \\='(\"+#work\") or \\='(\"-#work\").
Each entry starts with + to require the tag or - to exclude it.
The returned sexp can be used as `org-agenda-skip-function'."
  (let* ((conditions
          (mapcar
           (lambda (entry)
             (let ((exclude (string-prefix-p "-" entry))
                   (tag (substring entry 1)))
               (if exclude
                   `(member ,tag (org-get-tags))
                 `(not (member ,tag (org-get-tags))))))
           filter-preset))
         (combined (if (cdr conditions)
                       `(or ,@conditions)
                     (car conditions))))
    `(when ,combined (org-entry-end-position))))

(defun agile-gtd--agenda-day (&optional tag-filter-preset)
  "Return the base agenda block used by the daily view.
TAG-FILTER-PRESET, when non-nil, is a list of strings like
\\='(\"+#work\") or \\='(\"-#work\") used to restrict which entries appear."
  `(agenda "Agenda" ;; FIXME rename to Today
    ((org-agenda-use-time-grid t)
     (org-deadline-warning-days 0)
     (org-agenda-span '1)
     (org-super-agenda-groups ',(agile-gtd--today-groups))
     (org-agenda-start-day (org-today))
     ,@(when tag-filter-preset
         `((org-agenda-skip-function
            ',(agile-gtd--agenda-skip-form tag-filter-preset)))))))


(defun agile-gtd-agenda-query-next-actions (&optional tag-filter priority hide-today)
  "Return org-ql sexp for next actions at or above PRIORITY.
TAG-FILTER, when non-nil, is `and'-ed in to narrow by tag.
PRIORITY defaults to `agile-gtd--current-max-priority-group'.
HIDE-TODAY, when non-nil, excludes items with any deadline or
schedule (the agenda-view behaviour where today items appear in a
separate section).  When nil (the default), items scheduled or due
today or overdue are included.  Future-scheduled items are always
excluded."
  (let* ((prio (or priority (agile-gtd--current-max-priority-group)))
         (base `(and (todo ,@(agile-gtd--action-keywords))
                     (agile-gtd-prio-deadline ,prio)
                     (not (agile-gtd-someday))
                     (not (agile-gtd-blocked))
                     ,@(if hide-today
                           '((not (deadline :to 0))
                             (not (scheduled)))
                         '((not (scheduled :from +1)))))))
    (if tag-filter `(and ,base ,tag-filter) base)))

(defun agile-gtd-agenda-query-inbox ()
  "Return org-ql sexp for inbox items."
  `(and (todo)
        (tags ,@agile-gtd-inbox-tags)))

(defun agile-gtd-agenda-query-backlog (&optional tag-filter)
  "Return org-ql sexp for backlog (projects and standalone next actions).
TAG-FILTER, when non-nil, is `and'-ed in to narrow by tag."
  (let ((base `(and (or (todo ,(agile-gtd--project-keyword))
                        (agile-gtd-standalone-next))
                    (not (agile-gtd-habit))
                    (not (agile-gtd-blocked)))))
    (if tag-filter `(and ,base ,tag-filter) base)))

(defun agile-gtd-agenda-query-stuck-projects (&optional tag-filter)
  "Return org-ql sexp for stuck projects.
TAG-FILTER, when non-nil, is `and'-ed in to narrow by tag."
  (if tag-filter
      `(and (agile-gtd-stuck-proj) ,tag-filter)
    '(agile-gtd-stuck-proj)))

(defun agile-gtd--project-agenda-commands ()
  "Return agenda commands for each project that has a :key defined."
  (mapcar
   (lambda (project)
     (let* ((tag  (agile-gtd--project-tag project))
            (name (agile-gtd--project-name project))
            (key  (char-to-string (agile-gtd--project-key project)))
            (filt `(tags ,tag)))
       `(,(concat "w" key) ,(format "%s Agenda" name)
         (,(agile-gtd--agenda-day (list (concat "+" tag)))
          (org-ql-block ',(agile-gtd-agenda-query-stuck-projects filt)
                        ((org-ql-block-header "Stuck Projects")
                         (org-super-agenda-header-separator "")))
          (org-ql-block ',(agile-gtd-agenda-query-next-actions filt nil t)
                        ((org-ql-block-header "Next Actions")
                         (org-super-agenda-groups ',(agile-gtd-rank-groups))))))))
   (cl-remove-if-not #'agile-gtd--project-key agile-gtd-projects)))

(defun agile-gtd--agenda-custom-commands ()
  "Return the Agile GTD agenda commands."
  `(("i" "Inbox"
     ((org-ql-block `(and (todo)
                          (tags ,@agile-gtd-inbox-tags))
                    ((org-ql-block-header "Inbox")
                     (org-super-agenda-groups '((:auto-property "CREATED")))))))
    ("a" "Main Agenda"
     (,(agile-gtd--agenda-day)
      (org-ql-block ',(agile-gtd-agenda-query-stuck-projects)
                    ((org-ql-block-header "Stuck Projects")
                     (org-super-agenda-header-separator "")))
      (org-ql-block ',(agile-gtd-agenda-query-next-actions nil nil t)
                    ((org-ql-block-header "Next Actions")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))))))
    ("A" "Agenda Weekly"
     ((agenda ""
              ((org-agenda-span 'week)
               (org-agenda-start-on-weekday 1)))))
    ("l" "Agenda Weekly with Log"
     ((agenda ""
              ((org-agenda-span 'week)
               (org-agenda-start-on-weekday 1)
               (org-agenda-archives-mode t)
               (org-agenda-use-time-grid nil)
               (org-agenda-show-log 'only)
               (org-agenda-log-mode-items '(state))))))
    ("c" "Agenda Weekly | clock entries"
     ((agenda ""
              ((org-agenda-span 'week)
               (org-agenda-start-on-weekday 1)
               (org-agenda-archives-mode t)
               (org-agenda-use-time-grid nil)
               (org-agenda-show-log 'clockcheck)
               (org-agenda-log-mode-items '(clock))))))
    ("r" . "Review")
    ("rc" "Close open NEXT Actions and WAIT"
     ((org-ql-block `(and (todo ,@(agile-gtd--action-keywords))
                          (not (tags ,agile-gtd-someday-tag ,agile-gtd-habit-tag))
                          (not (agile-gtd-habit))
                          (or (not (deadline))
                              (deadline :to "+30")
                              (ancestors (deadline :to "+30")))
                          (or (not (scheduled))
                              (scheduled :to "+30")))
                    ((org-super-agenda-header-separator "")
                     (org-deadline-warning-days 30)
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))
                     (org-ql-block-header "Something to do")))
      (org-ql-block (agile-gtd-agenda-query-stuck-projects)
                    ((org-ql-block-header "Stuck Projects")
                     (org-super-agenda-header-separator "")
                     (org-super-agenda-groups ',(agile-gtd-priority-groups))))))
    ("rs" "Stuck Projects"
     ((org-ql-block '(agile-gtd-stuck-proj)
                    ((org-ql-block-header "Stuck Projects")
                     (org-super-agenda-header-separator "")
                     (org-super-agenda-groups ',(agile-gtd-priority-groups))))))
    ("rt" "Tangling TODOs"
     ((org-ql-block '(agile-gtd-tangling)
                    ((org-ql-block-header "Tangling TODOs")
                     (org-super-agenda-header-separator "")
                     (org-super-agenda-groups ',(agile-gtd-priority-groups))))))
    ("rS" "SOMEDAY"
     ((org-ql-block `(and (todo ,(agile-gtd--project-keyword))
                          (or (and (priority <= (char-to-string ,(agile-gtd--current-backlog-priority-threshold)))
                                   (not (ancestors (priority > (char-to-string ,(agile-gtd--current-backlog-priority-threshold)))))
                                   (not (children (priority > (char-to-string ,(agile-gtd--current-backlog-priority-threshold))))))
                              (tags ,agile-gtd-someday-tag)
                              (children (and (todo ,@(agile-gtd--action-keywords))
                                             (tags ,agile-gtd-someday-tag))))
                          (not (scheduled))
                          (not (habit))
                          (not (deadline)))
                    ((org-ql-block-header "Projects")
                     (org-super-agenda-header-separator "")
                     (org-super-agenda-groups ',(list (list :tag agile-gtd-someday-tag :order 10)
                                                      '(:auto-priority)))))))
    ("p" . "Private")
    ("pp" "Private Agenda Today"
     (,(agile-gtd--agenda-day (list (concat "-" agile-gtd-work-tag)))
      (org-ql-block ',(agile-gtd-agenda-query-stuck-projects '(agile-gtd-private))
                    ((org-ql-block-header "Stuck Projects")
                     (org-super-agenda-header-separator "")))
      (org-ql-block ',(agile-gtd-agenda-query-next-actions '(agile-gtd-private) nil t)
                    ((org-ql-block-header "Next Actions")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))))))
    ("pb" "Private Backlog"
     ((org-ql-block ',(agile-gtd-agenda-query-backlog '(agile-gtd-private))
                    ((org-ql-block-header "Backlog")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))
                     (org-dim-blocked-tasks t)))))
    ("ps" "Private Stuck Projects"
     ((org-ql-block ',(agile-gtd-agenda-query-stuck-projects '(agile-gtd-private))
                    ((org-ql-block-header "Stuck Projects")
                     (org-super-agenda-header-separator "")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))))))
    ("w" . "Work")
    ("ww" "Work Agenda Today"
     (,(agile-gtd--agenda-day (list (concat "+" agile-gtd-work-tag)))
      (org-ql-block ',(agile-gtd-agenda-query-stuck-projects '(agile-gtd-work))
                    ((org-ql-block-header "Stuck Projects")
                     (org-super-agenda-header-separator "")))
      (org-ql-block ',(agile-gtd-agenda-query-next-actions '(agile-gtd-work) nil t)
                    ((org-ql-block-header "Next Actions")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))))))
    ("wb" "Work Backlog"
     ((org-ql-block ',(agile-gtd-agenda-query-backlog '(agile-gtd-work))
                    ((org-ql-block-header "Backlog")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))
                     (org-dim-blocked-tasks t)))))
    ("ws" "Work Stuck Projects"
     ((org-ql-block ',(agile-gtd-agenda-query-stuck-projects '(agile-gtd-work))
                    ((org-ql-block-header "Stuck Projects")
                     (org-super-agenda-header-separator "")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))))))
    ,@(agile-gtd--project-agenda-commands)))

(defun agile-gtd--agenda-someday-p ()
  "Return non-nil when the current agenda item is tagged as someday."
  (-find (-partial #'string= agile-gtd-someday-tag)
         (org-get-at-bol 'tags)))

(defun agile-gtd-agenda-set-someday (&optional do-schedule)
  "Mark the current agenda entry as SOMEDAY.

With prefix argument DO-SCHEDULE, schedule it as a tickler."
  (interactive "P")
  (org-agenda-set-tags agile-gtd-someday-tag 'on)
  (ignore-error user-error
    (org-agenda-priority 'remove))
  (org-agenda-deadline '(4))
  (org-agenda-schedule (unless do-schedule '(4))))

(defun agile-gtd-agenda-set-tickler ()
  "Mark the current agenda entry as a tickler."
  (interactive)
  (agile-gtd-agenda-set-someday '(4)))

(defun agile-gtd-agenda-remove-someday ()
  "Remove SOMEDAY and scheduling from the current agenda item."
  (interactive)
  (unless (agile-gtd--agenda-someday-p)
    (error "Element has no %s tag" agile-gtd-someday-tag))
  (org-agenda-set-tags agile-gtd-someday-tag 'off)
  (ignore-error user-error
    (org-agenda-priority 'remove))
  (org-agenda-deadline '(4))
  (org-agenda-schedule '(4)))

(defun agile-gtd-agenda-toggle-someday (&optional do-schedule)
  "Toggle SOMEDAY status for the current agenda item.

With prefix argument DO-SCHEDULE, create a tickler."
  (interactive "P")
  (if (agile-gtd--agenda-someday-p)
      (agile-gtd-agenda-remove-someday)
    (agile-gtd-agenda-set-someday (when do-schedule '(4)))))

(defun agile-gtd-agenda-toggle-tickler ()
  "Toggle SOMEDAY and ask for a tickler schedule."
  (interactive)
  (agile-gtd-agenda-toggle-someday '(4)))

(defun agile-gtd-agenda-show-priorities (&optional priority)
  "Show agenda items up to PRIORITY."
  (interactive "P")
  (let ((new-priority
         (cond ((equal priority '(4))
                (max agile-gtd-priority-highest (1- agile-gtd-priority-default)))
               (priority)
               (t (upcase (read-char (format "Show up to priority (%c-%c): "
                                             org-priority-highest
                                             org-priority-lowest)))))))
    (unless (agile-gtd--priority-in-range-p new-priority)
      (user-error "Priority must be between org-priority-highest and org-priority-lowest"))
    (setq agile-gtd-max-priority-group new-priority)
    (agile-gtd-refresh)
    (message "Showing up to priority %c" new-priority)
    (org-agenda-redo-all)))

(defun agile-gtd-agenda-reset-show-priorities ()
  "Reset the agenda priority filter."
  (interactive)
  (setq agile-gtd-max-priority-group nil)
  (agile-gtd-refresh)
  (org-agenda-redo-all))

(defun agile-gtd-agenda-show-more-priorities ()
  "Expand the agenda to include lower-priority items."
  (interactive)
  (setq agile-gtd-max-priority-group
        (min (1+ (agile-gtd--current-max-priority-group))
             agile-gtd-priority-lowest))
  (agile-gtd-refresh)
  (org-agenda-redo-all))

(defun agile-gtd-agenda-show-less-priorities ()
  "Restrict the agenda to higher-priority items."
  (interactive)
  (setq agile-gtd-max-priority-group
        (max (1- (agile-gtd--current-max-priority-group))
             agile-gtd-priority-highest))
  (agile-gtd-refresh)
  (org-agenda-redo-all))

(org-ql-defpred agile-gtd-tickler ()
  "Match entries in the tickler."
  :normalizers ((`(,predicate-names)
                 (rec `(and (todo)
                            (tags-local ,agile-gtd-someday-tag)
                            (scheduled))))))

(org-ql-defpred agile-gtd-tickler-proj ()
  "Match projects in the tickler and pure tickler subtrees."
  :normalizers ((`(,predicate-names)
                 (rec `(and (todo ,(agile-gtd--project-keyword))
                            (or (agile-gtd-tickler)
                                (and (children (agile-gtd-tickler))
                                     (not (children (and (todo ,@(agile-gtd--action-keywords))
                                                         (not (agile-gtd-tickler))))))))))))

(org-ql-defpred agile-gtd-work ()
  "Match work related entries."
  :normalizers ((`(,predicate-names)
                 (rec `(tags ,agile-gtd-work-tag)))))

(org-ql-defpred agile-gtd-private ()
  "Match private entries."
  :normalizers ((`(,predicate-names)
                 (rec `(not (tags ,agile-gtd-work-tag))))))

(org-ql-defpred (agile-gtd-stuck-proj agile-gtd-stuck) ()
  "Match stuck projects."
  :normalizers ((`(,predicate-names)
                 (rec `(and (todo ,(agile-gtd--project-keyword))
                            (not (tags ,agile-gtd-someday-tag))
                            (not (children (todo ,@(agile-gtd--action-keywords))))
                            (not (agile-gtd-tickler-proj)))))))

(org-ql-defpred agile-gtd-standalone-next ()
  "Match standalone NEXT and WAIT items."
  :normalizers ((`(,predicate-names)
                 (rec `(and (todo ,@(agile-gtd--action-keywords))
                            (not (ancestors (or (todo ,(agile-gtd--project-keyword))
                                                (done)))))))))

(org-ql-defpred agile-gtd-tangling ()
  "Match actions whose ancestors are done."
  :normalizers ((`(,predicate-names)
                 (rec '(and (todo)
                            (ancestors (done)))))))

(org-ql-defpred agile-gtd-someday ()
  "Match SOMEDAY items excluding ticklers."
  :normalizers ((`(,predicate-names)
                 (rec `(and (tags ,agile-gtd-someday-tag)
                            (not (agile-gtd-tickler)))))))

(org-ql-defpred agile-gtd-habit ()
  "Match habits by tag or style."
  :normalizers ((`(,predicate-names)
                 (rec `(or (tags ,agile-gtd-habit-tag)
                           (habit))))))

(org-ql-defpred agile-gtd-deadline-prio (op priority)
  "Match entries whose deadline-based priority satisfies OP relative to PRIORITY.
Example: (agile-gtd-deadline-prio <= ?C) matches items with deadline within 7 days."
  :normalizers
  ((`(,predicate-names ,(and (or '= '< '> '<= '>=) comparator) ,prio)
    `(agile-gtd-deadline-prio ',comparator ,prio)))
  :body
  (let* ((element (org-element-at-point))
         (dl (org-element-property :deadline element)))
    (when dl
      (let* ((dl-days (- (time-to-days (org-timestamp-to-time dl))
                         (time-to-days (current-time))))
             (dl-rank (agile-gtd--deadline-rank dl-days))
             (prio-rank (agile-gtd--prio-rank priority)))
        (when prio-rank
          (funcall op dl-rank prio-rank))))))

(org-ql-defpred agile-gtd-parent-prio (op priority)
  "Match entries whose direct parent priority satisfies OP relative to PRIORITY.
Example: (agile-gtd-parent-prio <= ?C) matches items with parent priority A, B or C."
  :normalizers
  ((`(,predicate-names ,(and (or '= '< '> '<= '>=) comparator) ,prio)
    `(agile-gtd-parent-prio ',comparator ,prio)))
  :body
  (let* ((par-prio (agile-gtd--direct-parent-priority))
         (par-rank (agile-gtd--prio-rank par-prio))
         (prio-rank (agile-gtd--prio-rank priority)))
    (when (and par-rank prio-rank)
      (funcall op par-rank prio-rank))))

(org-ql-defpred agile-gtd-blocked ()
  "Match entries that are blocked (via `org-entry-blocked-p').
Integrates with org-edna when `org-edna-mode' is active via `org-blocker-hook'."
  :body
  (org-entry-blocked-p))

(org-ql-defpred agile-gtd-prio-deadline (priority)
  "Match entries at or above PRIORITY urgency.
An entry qualifies when any of the following hold:
- its own priority is >= PRIORITY
- it has no explicit priority and the current sprint threshold
  is more generous than `org-priority-default'
- its direct parent's priority qualifies
- its deadline urgency qualifies"
  :normalizers
  ((`(,predicate-names ,prio)
    (let ((include-no-prio (> (agile-gtd--current-max-priority-group)
                              org-priority-default)))
      (rec `(or (priority >= ,(char-to-string prio))
                ,@(when include-no-prio
                    '((not (priority))))
                (agile-gtd-parent-prio <= ,prio)
                (agile-gtd-deadline-prio <= ,prio)))))))

(defun agile-gtd-trigger-next-sibling ()
  "Set TRIGGER on the current task to advance the next sibling to NEXT."
  (interactive)
  (org-entry-put nil "TRIGGER" "next-sibling todo!(NEXT)"))

(defun agile-gtd-blocker-previous-sibling ()
  "Set BLOCKER on the current task to wait for the previous sibling."
  (interactive)
  (org-entry-put nil "BLOCKER" "previous-sibling"))

(defun agile-gtd-chain-task ()
  "Set both TRIGGER and BLOCKER to wire this task into a sequential chain."
  (interactive)
  (agile-gtd-trigger-next-sibling)
  (agile-gtd-blocker-previous-sibling))

(defun agile-gtd--item-rank ()
  "Return the virtual priority rank for the Org item at point."
  (let* ((element     (org-element-at-point))
         (prio        (org-element-property :priority element))
         (parent-prio (agile-gtd--direct-parent-priority))
         (dl          (org-element-property :deadline  element))
         (sc          (org-element-property :scheduled element))
         (today       (time-to-days (current-time)))
         (dl-delta    (when dl (- (time-to-days (org-timestamp-to-time dl)) today)))
         (sc-delta    (when sc (- (time-to-days (org-timestamp-to-time sc)) today))))
    (agile-gtd--backlog-rank prio parent-prio dl-delta sc-delta)))

(defun agile-gtd--item-rank< (a b)
  "Return non-nil if element A has a lower rank than element B.
A and B are Org elements as returned by `org-ql-select'.
Lower rank means higher priority.  Use as `:sort' arg to `org-ql-select'
or `org-ql-search'.
\nThis is a 2-argument comparison function compatible with `-sort'."
  (cl-flet ((rank-of (el)
              (let ((buf (get-buffer (org-element-property :buffer el)))
                    (pos (org-element-property :begin el)))
                (when (and buf pos)
                  (with-current-buffer buf
                    (save-excursion
                      (goto-char pos)
                      (agile-gtd--item-rank)))))))
    (< (or (rank-of a) agile-gtd--rank-inf)
       (or (rank-of b) agile-gtd--rank-inf))))

(defun agile-gtd--rank-to-prio-char (rank)
  "Return the priority character for numeric RANK, or nil if beyond the lowest priority.
Ranks below 1 (including negatives) clamp to `agile-gtd-priority-highest'.
This is the inverse of `agile-gtd--prio-rank'."
  (let* ((offset (/ (max (1- rank) 0) 10))
         (prio   (+ agile-gtd-priority-highest offset)))
    (when (<= prio agile-gtd-priority-lowest)
      prio)))

(defun agile-gtd--rank-describe ()
  "Display rank breakdown for the Org item at point."
  (let* ((element     (org-element-at-point))
         (prio        (org-element-property :priority element))
         (parent-prio (agile-gtd--direct-parent-priority))
         (dl          (org-element-property :deadline  element))
         (sc          (org-element-property :scheduled element))
         (today       (time-to-days (current-time)))
         (dl-delta    (when dl (- (time-to-days (org-timestamp-to-time dl)) today)))
         (sc-delta    (when sc (- (time-to-days (org-timestamp-to-time sc)) today)))
         (rank        (agile-gtd--backlog-rank prio parent-prio dl-delta sc-delta))
         (prio-str    (if prio (char-to-string prio) "none"))
         (par-str     (if parent-prio (char-to-string parent-prio) "none"))
         (date-str    (lambda (delta)
                        (if delta
                            (let* ((r     (agile-gtd--deadline-rank delta))
                                   (pchar (agile-gtd--rank-to-prio-char r))
                                   (sign  (if (>= delta 0) "+" ""))
                                   (band  (if pchar (format " (%c)" pchar) " (overdue)")))
                              (format "%s%dd%s" sign delta band))
                          "none"))))
    (message "Rank: %d  (Priority: %s  Parent: %s  Deadline: %s  Scheduled: %s)"
             rank prio-str par-str
             (funcall date-str dl-delta)
             (funcall date-str sc-delta))))

;;;###autoload
(defun agile-gtd-rank ()
  "Display the rank breakdown for the Org heading at point."
  (interactive)
  (agile-gtd--rank-describe))

;;;###autoload
(defun agile-gtd-agenda-rank ()
  "Display the rank breakdown for the agenda item at point."
  (interactive)
  (when-let ((marker (or (org-get-at-bol 'org-marker)
                         (org-get-at-bol 'org-hd-marker))))
    (org-with-point-at marker
      (agile-gtd--rank-describe))))

(defun agile-gtd--apply-priorities ()
  "Apply Agile GTD priority settings."
  (setq org-priority-highest agile-gtd-priority-highest
        org-priority-default agile-gtd-priority-default
        org-priority-lowest agile-gtd-priority-lowest
        org-priority-faces (agile-gtd--priority-faces)))

(defun agile-gtd--apply-org-modern-visuals ()
  "Apply Agile GTD org-modern visuals."
  (when agile-gtd-enable-org-modern-visuals
    (setq org-modern-priority (agile-gtd--priority-symbols))))

(defun agile-gtd--apply-todo-keywords ()
  "Apply Agile GTD TODO keywords and faces."
  (setq org-todo-keywords agile-gtd-todo-keywords
        org-todo-repeat-to-state agile-gtd-todo-repeat-to-state
        org-todo-keyword-faces
        '(("[-]" . agile-gtd-todo-active)
          ("NEXT" . agile-gtd-todo-next)
          ("WAIT" . agile-gtd-todo-onhold)
          ("IDEA" . agile-gtd-todo-idea)
          ("PROJ" . agile-gtd-todo-project)
          ("EPIC" . agile-gtd-todo-epic)
          ("KILL" . agile-gtd-todo-cancel))))

(defun agile-gtd--apply-tags ()
  "Apply Agile GTD workflow tags and project tags."
  (let* ((workflow-tags (agile-gtd--workflow-tag-alist))
         (project-tag-names (mapcar #'agile-gtd--project-tag agile-gtd-projects))
         (managed-names (append (agile-gtd--workflow-tag-names) project-tag-names))
         (current-tags (agile-gtd--delete-sublist workflow-tags org-tag-alist)))
    (setq org-tag-alist
          (append
           (cl-remove-if (lambda (entry)
                           (and (consp entry)
                                (stringp (car entry))
                                (member (car entry) managed-names)))
                         current-tags)
           workflow-tags))
    ;; Project tags — only add key binding when :key is non-nil
    (dolist (project agile-gtd-projects)
      (let ((tag (agile-gtd--project-tag project))
            (key (agile-gtd--project-key project)))
        (when (and tag key)
          (cl-pushnew (cons tag key) org-tag-alist
                      :test (lambda (a b) (equal (car a) (car b)))))))))

(defun agile-gtd--apply-refile-targets ()
  "Apply Agile GTD refile target settings."
  (when agile-gtd-enable-refile-targets
    (setq org-refile-targets '((nil :maxlevel . 9)
                               (org-agenda-files :maxlevel . 4)
                               (agile-gtd--someday-files :maxlevel . 4))
          org-refile-use-outline-path 'buffer-name
          org-outline-path-complete-in-steps nil
          org-refile-allow-creating-parent-nodes 'confirm)))

(defun agile-gtd--apply-agenda-files ()
  "Merge Agile GTD managed files into `org-agenda-files'."
  (when agile-gtd-enable-agenda-files
    (setq org-agenda-diary-file (agile-gtd--expand-org-path agile-gtd-diary-file)
          org-agenda-files (cl-union org-agenda-files
                                     (agile-gtd--managed-agenda-files)
                                     :test #'equal))))

(defun agile-gtd--apply-capture-templates ()
  "Apply Agile GTD capture templates."
  (setq org-capture-templates
        (agile-gtd--replace-by-key org-capture-templates
                                   (agile-gtd--capture-templates))))

(defun agile-gtd--apply-agenda-commands ()
  "Apply Agile GTD agenda commands and groups."
  (setq org-stuck-projects (agile-gtd--stuck-projects-setting)
        org-agenda-custom-commands
        (agile-gtd--replace-by-key org-agenda-custom-commands
                                   (agile-gtd--agenda-custom-commands)))
  (org-super-agenda-mode 1)
  (setq org-super-agenda-header-separator "\n"))

(defun agile-gtd-refresh ()
  "Refresh all derived Agile GTD configuration."
  (interactive)
  (agile-gtd--validate-configuration)
  (agile-gtd--apply-priorities)
  (agile-gtd--apply-org-modern-visuals)
  (agile-gtd--apply-todo-keywords)
  (agile-gtd--apply-tags)
  (agile-gtd--apply-agenda-files)
  (agile-gtd--apply-refile-targets)
  (agile-gtd--apply-capture-templates)
  (agile-gtd--apply-agenda-commands))

(defun agile-gtd-enable ()
  "Enable Agile GTD for the current Org configuration."
  (interactive)
  (agile-gtd-refresh))

;;;; Rolling clock ranges

(defconst agile-gtd--last-periods-regexp
  "\\`last\\(day\\|week\\|semimonth\\|month\\|quarter\\|year\\)s-\\(.+\\)\\'"
  "Regexp matching a `last<unit>s-N' range keyword.
Group 1 is the unit; group 2 is the count exactly as it was written.
The units are the six `:step' accepts, so the two vocabularies match.")

(defconst agile-gtd--last-periods-keys
  '((day . today)
    (week . thisweek)
    (month . thismonth)
    (quarter . thisq)
    (year . thisyear))
  "Org's own range keyword for the period of each unit currently in progress.
`semimonth' is absent because Org has no keyword for it.")

(defun agile-gtd--last-periods (key)
  "Return (UNIT . COUNT) when KEY is a `last<unit>s-N' keyword, else nil.
COUNT is the text written after the unit, which need not be a number.
Org's singular `lastweek' is a shift to the previous week and does not
match here; only the plural span form does."
  (let ((skey (format "%s" key)))
    (when (string-match agile-gtd--last-periods-regexp skey)
      (cons (intern (match-string 1 skey)) (match-string 2 skey)))))

(defun agile-gtd--last-periods-count (count key)
  "Return COUNT, the period count written in range keyword KEY, as a number.
N counts periods rather than offsets, so the smallest window is one."
  (unless (string-match-p "\\`[0-9]+\\'" count)
    (user-error "Time block %s counts periods, so N must be a whole number" key))
  (let ((n (string-to-number count)))
    (when (= n 0)
      (user-error "Time block %s counts periods, so N must be at least 1" key))
    n))

(defun agile-gtd--semimonth-index (time)
  "Return the number of the semimonth holding TIME.
Numbering the halves of every month consecutively is what lets a window
step back over month and year boundaries without a special case at each."
  (pcase-let ((`(,_ ,_ ,_ ,d ,m ,y . ,_) (decode-time time)))
    (+ (* 24 y) (* 2 (1- m)) (if (< d 16) 0 1))))

(defun agile-gtd--semimonth-start (index)
  "Return the time at which the semimonth numbered INDEX begins."
  (let ((half (mod index 24)))
    (org-encode-time 0 0 org-extend-today-until
                     (if (cl-evenp half) 1 16)
                     (1+ (/ half 2))
                     (/ index 24))))

(defun agile-gtd--last-periods-range (unit count time wstart mstart)
  "Return the last COUNT whole UNIT periods ending with the one holding TIME.
The value is a list of the window's start and end times.  WSTART and
MSTART are the week and month start days.

Every unit but `semimonth' resolves through Org itself, so the window
lands on exactly the boundaries of the reports it is read alongside.
Org has no semimonth keyword to borrow, so that unit counts halves of
months directly."
  (if (eq unit 'semimonth)
      (let ((index (agile-gtd--semimonth-index time)))
        (list (agile-gtd--semimonth-start (- index (1- count)))
              (agile-gtd--semimonth-start (1+ index))))
    (let ((key (alist-get unit agile-gtd--last-periods-keys)))
      ;; The window opens where the shift COUNT-1 periods back opens, and closes
      ;; where the period in progress closes.  Org reads a shift off the end of
      ;; a string but dispatches the plain keyword on a symbol.
      (list (car (org-clock-special-range
                  (format "%s-%d" key (1- count)) time nil wstart mstart))
            (nth 1 (org-clock-special-range key time nil wstart mstart))))))

(defun agile-gtd--clock-special-range (orig key &optional time as-strings wstart mstart)
  "Resolve a `last<unit>s-N' KEY, delegating every other KEY to ORIG.

KEY names the last N whole periods of one of the six units `:step'
accepts, ending with and including the period currently in progress.
So `lastweeks-1' is the current week alone, and equals `thisweek', while
`lastweeks-8' is that week together with the seven before it.  Measuring
the window in the same unit as its boundaries is what keeps every period
in it whole.

Every clock report funnels through this function, which is what makes
the keywords work in a plain clocktable, a stepped clocktable and a
clockmatrix alike.  TIME, AS-STRINGS, WSTART and MSTART keep the
meanings Org gives them."
  (pcase (agile-gtd--last-periods key)
    (`nil (funcall orig key time as-strings wstart mstart))
    (`(,unit . ,written)
     (let* ((count (agile-gtd--last-periods-count written key))
            (range (agile-gtd--last-periods-range unit count time wstart mstart))
            (text (format "the last %d %s%s" count unit (if (= count 1) "" "s"))))
       (if (not as-strings)
           (append range (list text))
         (let ((fmt (org-time-stamp-format 'with-time)))
           (list (format-time-string fmt (car range))
                 (format-time-string fmt (nth 1 range))
                 text)))))))

(defun agile-gtd--clocktable-shift-guard (&rest _)
  "Refuse to shift a clocktable whose `:block' spans a count of periods.
Org's shift command matches the digits of `lastweeks-8' as though they
were a bare year and rewrites the block to `9', destroying the parameter
with nothing left in the buffer to recover it from.  Its own fallback
already turns away the blocks it cannot shift, `untilnow' among them;
these join that set, under the same message, so the refusal is
indistinguishable from any other."
  (save-excursion
    (goto-char (line-beginning-position))
    (when (and (looking-at
                "^[ \t]*#\\+BEGIN:[ \t]+clocktable\\>.*?:block[ \t]+\\(\\S-+\\)")
               (agile-gtd--last-periods (match-string 1)))
      (user-error "Cannot shift clocktable block"))))

(advice-add 'org-clock-special-range :around #'agile-gtd--clock-special-range)
(advice-add 'org-clocktable-shift :before #'agile-gtd--clocktable-shift-guard)

;;;; Clock matrix dynamic block

(defconst agile-gtd--clockmatrix-step-headers
  '((day . "Day")
    (week . "Week")
    (semimonth . "Semimonth")
    (month . "Month")
    (quarter . "Quarter")
    (year . "Year"))
  "Label-column header for each `:step' a `clockmatrix' block accepts.")

(defun agile-gtd--clockmatrix-time (value)
  "Resolve VALUE from a clockmatrix range specification into a time.
VALUE is an absolute day number as used by the agenda, or an Org
timestamp string."
  (pcase value
    ((and (pred numberp) n)
     (pcase-let ((`(,m ,d ,y) (calendar-gregorian-from-absolute n)))
       (org-encode-time 0 0 org-extend-today-until d m y)))
    ((and (pred stringp) timestamp)
     (seconds-to-time (org-matcher-time timestamp)))
    (_ (user-error
        "Clockmatrix needs a range: set `:block', or both `:tstart' and `:tend'"))))

(defun agile-gtd--clockmatrix-range (params)
  "Return the range PARAMS report on, as a cons of start and end times.
`:block' takes precedence over `:tstart' and `:tend', as in clocktable."
  (let ((range (pcase (plist-get params :block)
                 (`nil nil)
                 (block (org-clock-special-range
                         block nil t
                         (or (plist-get params :wstart) 1)
                         (or (plist-get params :mstart) 1))))))
    (cons (agile-gtd--clockmatrix-time
           (if range (car range) (plist-get params :tstart)))
          (agile-gtd--clockmatrix-time
           (if range (nth 1 range) (plist-get params :tend))))))

(defun agile-gtd--clockmatrix-step-end (start step wstart mstart)
  "Return the end of the STEP period beginning at START.
WSTART and MSTART are the week and month start days.  The calendar
arithmetic follows Org's own stepped clocktables."
  (pcase-let ((`(,_ ,_ ,_ ,d ,m ,y ,dow . ,_) (decode-time start)))
    (pcase step
      (`day (org-encode-time 0 0 org-extend-today-until (1+ d) m y))
      (`week
       (let ((offset (if (= dow wstart) 7 (mod (- wstart dow) 7))))
         (org-encode-time 0 0 org-extend-today-until (+ d offset) m y)))
      (`semimonth (org-encode-time 0 0 0
                                   (if (< d 16) 16 1)
                                   (if (< d 16) m (1+ m)) y))
      (`month (org-encode-time 0 0 0 mstart (1+ m) y))
      (`quarter (org-encode-time 0 0 0 mstart (+ 3 m) y))
      (`year (org-encode-time 0 0 org-extend-today-until 1 1 (1+ y)))
      (_ (user-error "Unknown `:step' specification: %S" step)))))

(defun agile-gtd--clockmatrix-periods (start end step wstart mstart)
  "Return the STEP periods tiling START to END, as (FROM . TO) conses.
The first and last period are clipped to the range, so the periods
partition it exactly.  WSTART and MSTART are the week and month start
days."
  (let (periods)
    (while (time-less-p start end)
      (let ((next (agile-gtd--clockmatrix-step-end start step wstart mstart)))
        ;; A `:wstart' outside 0-6 can land the next period on the current one,
        ;; which would loop forever.  Refuse rather than hang.
        (unless (time-less-p start next)
          (user-error "Clockmatrix `:step' %s does not advance past %s: \
check `:wstart' (0-6) and `:mstart' (1-31)"
                      step (format-time-string "%Y-%m-%d" start)))
        (push (cons start (if (time-less-p end next) end next)) periods)
        (setq start next)))
    (nreverse periods)))

(defun agile-gtd--clockmatrix-label (start step)
  "Return the row label for the STEP period beginning at START.
A week is labelled by the date it starts on."
  (pcase step
    (`month (format-time-string "%Y-%m" start))
    (`year (format-time-string "%Y" start))
    (`quarter (pcase-let ((`(,_ ,_ ,_ ,_ ,m ,y . ,_) (decode-time start)))
                (format "%d-Q%d" y (1+ (/ (1- m) 3)))))
    (_ (format-time-string "%Y-%m-%d" start))))

(defun agile-gtd--clockmatrix-own-files (tag)
  "Return the existing files holding time clocked against project TAG.
That is the project's own file plus its archive.  A missing main file is
a misconfiguration and warns; a missing archive is expected and does not."
  (let* ((project (cl-find tag agile-gtd-projects
                           :key #'agile-gtd--project-tag :test #'equal))
         (name (agile-gtd--project-file (or project (list :tag tag))))
         (main (agile-gtd--expand-org-path name))
         (archive (agile-gtd--expand-org-path (concat "archive/" name))))
    (unless (file-exists-p main)
      (warn "Agile GTD: project %S has no file at %s, so it reports no time.  \
Set :file on its entry in `agile-gtd-projects', or use \
`:scope agenda-with-archives'" tag main))
    (cl-remove-if-not #'file-exists-p (list main archive))))

(defun agile-gtd--clockmatrix-files (tag scope)
  "Return the files to sum for project TAG under SCOPE.
SCOPE is nil for the project's own files, or `agenda-with-archives'."
  (pcase scope
    (`nil (agile-gtd--clockmatrix-own-files tag))
    (`agenda-with-archives (org-add-archive-files (org-agenda-files t)))
    (_ (user-error "Unknown `:scope' for clockmatrix: %S" scope))))

(defun agile-gtd--clockmatrix-minutes (files tag start end)
  "Return the minutes clocked against TAG in FILES between START and END.
Delegating the sum to Org is what makes a cell agree with the equivalent
clocktable, and clips clocks that cross START or END rather than
double-counting or dropping them."
  (let ((params (list :maxlevel 0
                      :match tag
                      :tstart (format-time-string (org-time-stamp-format t t) start)
                      :tend (format-time-string (org-time-stamp-format t t) end))))
    (cl-loop for file in files
             sum (with-current-buffer (or (find-buffer-visiting file)
                                          (find-file-noselect file))
                   (save-excursion
                     (save-restriction
                       (widen)
                       (or (nth 1 (org-clock-get-table-data file params)) 0)))))))

(defun agile-gtd--clockmatrix-rows (tags files periods step)
  "Return one row per period in PERIODS.
Each row is a cons of the period's label and the minutes clocked against
each of TAGS, read from the matching entry of FILES."
  (org-agenda-prepare-buffers
   (cl-remove-duplicates (apply #'append files) :test #'equal))
  (mapcar (lambda (period)
            (cons (agile-gtd--clockmatrix-label (car period) step)
                  (cl-mapcar (lambda (tag tag-files)
                               (agile-gtd--clockmatrix-minutes
                                tag-files tag (car period) (cdr period)))
                             tags files)))
          periods))

(defun agile-gtd--clockmatrix-prune-columns (tags rows)
  "Drop the entries of TAGS with no clocked time anywhere in ROWS.
Return a cons of the surviving tags and the correspondingly narrowed ROWS."
  (let ((kept (cl-loop for i from 0 below (length tags)
                       when (> (cl-loop for row in rows sum (nth i (cdr row))) 0)
                       collect i)))
    (cons (mapcar (lambda (i) (nth i tags)) kept)
          (mapcar (lambda (row)
                    (cons (car row) (mapcar (lambda (i) (nth i (cdr row))) kept)))
                  rows))))

(defun agile-gtd--clockmatrix-duration-format ()
  "Return `org-duration-format' with every unit above hours dropped.
Monthly totals read as 108:30 rather than 4d 12:30, while the rest of
the configured format is left alone."
  (if (not (consp org-duration-format))
      org-duration-format
    (or (cl-remove-if (lambda (entry)
                        (let ((unit (car entry)))
                          (and (stringp unit)
                               (> (or (cdr (assoc unit org-duration-units)) 0) 60))))
                      org-duration-format)
        'h:mm)))

(defun agile-gtd--clockmatrix-cell (minutes)
  "Format MINUTES as a table cell, left blank when there is no time."
  (if (> minutes 0)
      (org-duration-from-minutes minutes (agile-gtd--clockmatrix-duration-format))
    ""))

(defun agile-gtd--clockmatrix-row-total (row)
  "Return the total minutes in ROW, a label followed by per-project minutes."
  (apply #'+ (cdr row)))

(defun agile-gtd--clockmatrix-insert-row (cells)
  "Insert CELLS as one Org table row."
  (insert "| " (mapconcat #'identity cells " | ") " |\n"))

(defun org-dblock-write:clockmatrix (params)
  "Write a `clockmatrix' dynamic block according to PARAMS.
Render clocked time as a matrix with calendar periods down the rows and
projects across the columns, totalled on both axes.  Columns default to
the projects registered in `agile-gtd-projects'; a project with no time
anywhere in the range is dropped.  See the README for the full parameter
list."
  (let* ((step (or (plist-get params :step) 'month))
         (wstart (or (plist-get params :wstart) 1))
         (mstart (or (plist-get params :mstart) 1))
         (skip0 (plist-get params :stepskip0))
         (show-total (if (plist-member params :total)
                         (plist-get params :total)
                       t))
         (header (or (alist-get step agile-gtd--clockmatrix-step-headers)
                     (user-error "Unknown `:step' specification: %S" step)))
         (range (agile-gtd--clockmatrix-range params))
         (periods (agile-gtd--clockmatrix-periods
                   (car range) (cdr range) step wstart mstart))
         (tags (or (plist-get params :tags)
                   (mapcar #'agile-gtd--project-tag agile-gtd-projects)))
         (files (mapcar (lambda (tag)
                          (agile-gtd--clockmatrix-files
                           tag (plist-get params :scope)))
                        tags))
         (pruned (agile-gtd--clockmatrix-prune-columns
                  tags (agile-gtd--clockmatrix-rows tags files periods step)))
         (columns (car pruned))
         (rows (if skip0
                   (cl-remove-if (lambda (row)
                                   (= 0 (agile-gtd--clockmatrix-row-total row)))
                                 (cdr pruned))
                 (cdr pruned)))
         (table-start (point)))
    (agile-gtd--clockmatrix-insert-row
     (append (list header) columns (and show-total (list "Total"))))
    (insert "|-\n")
    (dolist (row rows)
      (agile-gtd--clockmatrix-insert-row
       (append (list (car row))
               (mapcar #'agile-gtd--clockmatrix-cell (cdr row))
               (and show-total
                    (list (agile-gtd--clockmatrix-cell
                           (agile-gtd--clockmatrix-row-total row)))))))
    (when show-total
      (insert "|-\n")
      (agile-gtd--clockmatrix-insert-row
       (append (list "Total")
               (cl-loop for i from 0 below (length columns)
                        collect (agile-gtd--clockmatrix-cell
                                 (cl-loop for row in rows sum (nth i (cdr row)))))
               (list (agile-gtd--clockmatrix-cell
                      (cl-loop for row in rows
                               sum (agile-gtd--clockmatrix-row-total row)))))))
    (goto-char table-start)
    (org-table-align)))

;;;###autoload
(defun agile-gtd-clockmatrix ()
  "Insert a `clockmatrix' dynamic block at point and render it."
  (interactive)
  (org-create-dblock (list :name "clockmatrix" :block 'thisyear :step 'month))
  (org-update-dblock))

(org-dynamic-block-define "clockmatrix" #'agile-gtd-clockmatrix)

(provide 'agile-gtd)

;;; agile-gtd.el ends here
