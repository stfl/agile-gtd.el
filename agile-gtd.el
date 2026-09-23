;;; agile-gtd.el --- Agile GTD workflow for Org -*- lexical-binding: t; -*-

;; Copyright (C) 2026 Stefan Lendl

;; Author: Stefan Lendl <git@stfl.dev>
;; Version: 0.5.0
;; URL: https://github.com/stfl/agile-gtd
;; Package-Requires: ((emacs "30.2") (dash "2.19.1") (org-modern "1.6") (org-ql "0.8") (org-super-agenda "1.3") (org-edna "1.1.2") (org-records-mcp "0.10.1"))
;; Keywords: outlines, calendar, tools
;; SPDX-License-Identifier: GPL-3.0-or-later

;; This file is not part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; Agile GTD workflow for Org-mode.  Provides priority-based ranking, sprint
;; planning, backlog management, and agenda views using org-ql.

;;; Code:

(require 'cl-lib)
(require 'dash)
(require 'org)
(require 'org-agenda)
(require 'org-archive)
(require 'org-capture)
(require 'org-edna)
(require 'org-element)
(require 'org-habit)
(require 'org-id)
(require 'org-records-mcp)
(require 'org-ql)
(require 'org-ql-search)
(require 'org-super-agenda)

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
  "The projects this configuration knows about, one plist each.

  :tag   Org tag the project\\='s entries carry.  A required non-empty
         string, and the identity every consumer keys on.
  :name  Display name.  Defaults to the tag.
  :file  Org file, relative names expanded against `org-directory'.
         Defaults to \"<tag>.org\".
  :key   Character selecting the project\\='s agenda command and binding
         its `org-tag-alist' entry.  Optional; a project declaring
         anything but a character gets neither.

Keys beyond these are tolerated and ignored, so one list can serve
several packages at once.  This layout is shared by convention with
`org-clock-projects', which reads the same `:tag', `:name' and `:file'
with the same defaults and ignores `:key'; point its project function at
`agile-gtd-project-records' to keep one registry rather than two.

An entry that is not a plist, one whose `:tag' is not a non-empty
string, and one repeating a `:tag' an earlier entry already claims are
each skipped with a warning rather than an error, so one mistyped line
costs one project and not the session.  Where two entries claim one tag
the first wins.  Two projects sharing a file, or a display name, are
permitted."
  :type '(repeat (plist :options ((:tag string)
                                  (:name string)
                                  (:file file)
                                  (:key character))))
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

(defcustom agile-gtd-sprint-prio-threshold ?C
  "Priority cutoff of the `sprint' view range.
Items at this priority or above — by their own cookie, by their parent\\='s,
or by deadline urgency — are in the sprint.  See `agile-gtd-view-ranges'."
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

(defcustom agile-gtd-enable-org-records-mcp t
  "Whether `agile-gtd-refresh' should configure org-records-mcp.
When non-nil, every refresh generates one org-records-mcp view per
key and merges them into `org-records-mcp-views', merges the `rank' and
`parent-priority' computed fields into `org-records-mcp-computed-fields',
adds `rank' to `org-records-mcp-list-computed-fields', sorts views by
rank, describes the keys through
`org-records-mcp-view-catalogue-function', and sets
`org-records-mcp-allowed-files' to nil and
`org-records-mcp-file-scope-override' to t.  Views and computed fields
under other names are left alone.
Starting the MCP server stays with the user\\='s configuration."
  :type 'boolean
  :group 'agile-gtd)

(defcustom agile-gtd-enable-org-settings t
  "Whether `agile-gtd-refresh' should apply the Org settings the workflow needs.
When non-nil, every refresh turns on `org-edna-mode', adds `org-habit' to
`org-modules', turns off Org\='s own TODO dependency checks and sets the
logging, archive, habit, agenda and inheritance options the views rely
on.  docs/org-settings.org lists each value and why it is needed.  To
change one of them, set it after `agile-gtd-enable' runs."
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
  (dolist (priority (delq nil (list agile-gtd-backlog-priority-threshold)))
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

(defvar agile-gtd--warned-registry nil
  "The value of `agile-gtd-projects' `agile-gtd--warned-entries' belongs to.")

(defvar agile-gtd--warned-entries nil
  "Registry entries already warned about, compared with `equal'.
Identity cannot serve here: an entry is warned about once per registry
value, and the registry is walked afresh on every read.")

(defun agile-gtd--warn-skipped-project (entry reason)
  "Warn once that registry ENTRY is skipped, because REASON.
Once per entry per value of `agile-gtd-projects': the registry is read on
every agenda build and every refresh, and a warning repeated on each of
those buries the one that matters.  The warning shows the plist form so
the shape being asked for is in front of whoever reads it."
  (unless (member entry agile-gtd--warned-entries)
    (push entry agile-gtd--warned-entries)
    (warn (concat "Agile GTD: skipping project entry %S: %s."
                  "  A project is a plist"
                  " (:tag \"tag\" :name \"Name\" :file \"file.org\" :key ?k)"
                  " of which only :tag is required")
          entry reason)))

(defun agile-gtd-project-records ()
  "Return the registered projects as normalised records.
A record is a plist carrying `:tag', `:name', `:file' and `:key' with
every default already applied, so no consumer repeats the rules that
`agile-gtd-projects' leaves implicit.  All three of tag, name and file
can differ for one project, and consumers want different ones of them:
the tag matches clock entries, the name labels a prompt, the file names
what to scan.  `:key' is this package\\='s own extension to the shared
registry layout and survives normalisation here.

This is the funnel every consumer passes through, so it is where an
unusable entry is dropped: a bare string, a plist whose `:tag' is not a
non-empty string, and a plist repeating a tag an earlier entry already
claims are skipped with one warning apiece.  Dropping them here rather than at the
declaration is what keeps a typo from reaching `org-agenda-files',
`org-tag-alist' or an agenda command as a project named nothing, and
what keeps a `setq' of the registry as well guarded as a `setopt'."
  (unless (equal agile-gtd-projects agile-gtd--warned-registry)
    (setq agile-gtd--warned-registry agile-gtd-projects
          agile-gtd--warned-entries nil))
  (let ((claimed nil)
        (records nil))
    (dolist (project agile-gtd-projects (nreverse records))
      (let ((tag (and (consp project) (agile-gtd--project-tag project))))
        (cond
         ((not (consp project))
          (agile-gtd--warn-skipped-project project "it is not a plist"))
         ;; A tag has to be a non-empty string to be an identity.  An empty
         ;; one defaults the file to ".org", a real path under
         ;; `org-directory'; anything that is not a string reaches
         ;; `org-tag-alist' as a car Org cannot match.
         ((not (and (stringp tag) (not (string-empty-p tag))))
          (agile-gtd--warn-skipped-project project "it declares no :tag"))
         ((member tag claimed)
          (agile-gtd--warn-skipped-project
           project (format "the tag %S is already claimed" tag)))
         (t
          (push tag claimed)
          (push (list :tag tag
                      :name (agile-gtd--project-name project)
                      :file (agile-gtd--project-file project)
                      :key (agile-gtd--project-key project))
                records)))))))

(defun agile-gtd-project-files ()
  "Return the list of project files derived from `agile-gtd-projects'."
  (mapcar (lambda (record) (plist-get record :file))
          (agile-gtd-project-records)))

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

(defconst agile-gtd-view-ranges '(today sprint upcoming all someday)
  "Named agenda view ranges, ordered narrowest to widest.
A range is the one knob an agenda view is widened and narrowed by: it
fixes both the rank cutoff and whether parked items take part.  The
cutoffs derive from the priority defcustoms rather than from characters
written here, so reconfiguring the priority scale moves them with it.
`today' is the one range without a priority: it holds what is scheduled
or due today, or overdue.")

(defun agile-gtd-view-range-priority (range)
  "Return the cutoff priority character of RANGE, or nil for `today'.
Entries at this priority or above — by their own cookie, by their
parent\\='s, or by deadline urgency — are inside RANGE.  `today' cuts on
dates rather than on a priority; see `agile-gtd-view-range-cutoff'.
RANGE is one of `agile-gtd-view-ranges'."
  (pcase range
    ('today nil)
    ('sprint agile-gtd-sprint-prio-threshold)
    ('upcoming agile-gtd-priority-default)
    ((or 'all 'someday) agile-gtd-priority-lowest)
    (_ (user-error "Unknown Agile GTD view range: %S" range))))

(defun agile-gtd-view-range-cutoff (range)
  "Return the highest rank still inside RANGE.
`today' closes at 0, the rank of what is scheduled or due today, and of
everything overdue.  Every other range closes at its cutoff priority\\='s
`agile-gtd--rank-band-top'.  These are the numbers `agile-gtd-rank-groups'
closes its groups at, which is what keeps a range from admitting an entry
its groups have no heading for.  RANGE is one of `agile-gtd-view-ranges'."
  (if (eq range 'today)
      0
    (agile-gtd--rank-band-top (agile-gtd-view-range-priority range))))

(defun agile-gtd-view-range-parked-p (range)
  "Return non-nil when RANGE takes in parked items.
Parked means SOMEDAY entries and ticklers — the things deliberately set
aside — which only the widest range brings back into view."
  (eq range 'someday))

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

(defun agile-gtd--rank-band-top (priority)
  "Return the highest rank still inside PRIORITY\='s band, or nil.
A band is the ten ranks a priority owns: it opens at `agile-gtd--prio-rank'
and closes here, one below where the next priority opens.

One number does two jobs.  `agile-gtd-rank-groups' closes each priority
group at its band top, and a view range admits an entry when its rank is at
or below the cutoff priority\='s band top.  Filtering and grouping therefore
read the same boundary, and an agenda cannot show a heading for a priority
its range never claimed to reach."
  (when-let ((r (agile-gtd--prio-rank priority)))
    (+ (* 10 (/ r 10)) 9)))

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
  "Return the rank of an entry carrying no priority cookie of its own.
Org reads a missing cookie as `agile-gtd-priority-default', so the rank is
that priority\='s band top: below every entry that spells the default out,
above the first priority beneath it.  With default ?E it is 49, sitting
between E (41) and F (51)."
  (agile-gtd--rank-band-top agile-gtd-priority-default))

(defun agile-gtd--backlog-rank (prio parent-prio dl-delta &optional sc-delta)
  "Return the numeric rank of an entry.  Lower ranks come first.
PRIO and PARENT-PRIO are priority characters or nil.
DL-DELTA and SC-DELTA are integer days until deadline/scheduled, or nil.

Two ingredients, read differently.

A cookie sets the floor.  The entry\='s own cookie and its parent\='s are
both priority statements about the same work, so the stronger of the two
stands; an entry that states neither is default-priority work and takes
`agile-gtd--rank-default\='.  Inheriting matters: a bare next action under a
low project is low-priority work and must rank as such, or narrowing a view
range would leave it on screen while the project it belongs to is gone.

A date only ever lifts.  An approaching deadline, and a schedule that has
come due, make work more urgent than its cookie says; a date far enough out
to be less urgent says nothing, and leaves the floor where it was.
SC-DELTA is read only when it is at or below zero, because work scheduled
for a later day is not yet in hand at all."
  (let* ((own  (agile-gtd--prio-rank prio))
         (par  (agile-gtd--prio-rank parent-prio))
         (base (cond ((and own par) (min own par))
                     (own)
                     (par)
                     (t (agile-gtd--rank-default))))
         (dl   (if dl-delta (agile-gtd--deadline-rank dl-delta) agile-gtd--rank-inf))
         (sc   (if (and sc-delta (<= sc-delta 0))
                   (agile-gtd--deadline-rank sc-delta)
                 agile-gtd--rank-inf)))
    (min base dl sc)))

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

(defun agile-gtd--rank-for-item (item)
  "Return the effective backlog rank for agenda ITEM string, or nil."
  (when-let ((marker (org-find-text-property-in-string 'org-marker item)))
    (org-with-point-at marker
      (agile-gtd--item-rank))))

(defun agile-gtd-rank-groups ()
  "Return rank-mark org-super-agenda groups.

org-super-agenda hands an entry to the first group in this list that
claims it, so list order is precedence and `:order' is only what the
reader sees.  The two run opposite ways here, and deliberately.

Precedence, most specific first: the parked groups take their entries
before anything else can, because a tickler is a schedule and a SOMEDAY
tag and would otherwise be read as either; then what is due or overdue;
then what waits on a later date; then the priority bands, each closed at
its `agile-gtd--rank-band-top' so the next band down catches the rest.

On screen, in `:order': the priorities first, because they are the work
actually on offer, then Scheduled, then the parked groups last.

The Default group is listed ahead of the default priority's own group so
that `agile-gtd--rank-default' is claimed before that group's band-top
check could swallow it."
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
      :order 0)
     ;; Work carrying a date later than today is spoken for until that day
     ;; comes, so it is collected on its own rather than offered among the
     ;; priorities.  Only the widest range admits any of it in the first
     ;; place; at every other range this group renders empty.
     (:name "Scheduled"
      :scheduled future
      :order 900))
   (cl-mapcan
    (lambda (prio)
      (let* ((r    (agile-gtd--prio-rank prio))
             (hi   (unless (= prio agile-gtd-priority-lowest)
                     (agile-gtd--rank-band-top prio)))
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
     ;; Any deadline within the highest priority's deadline window ranks
     ;; inside `today' whatever the cookie, and the next-actions blocks leave
     ;; `today' to this block; the warning is where it shows instead.
     (org-deadline-warning-days
      ,(agile-gtd--deadline-window agile-gtd-priority-highest))
     (org-agenda-span '1)
     (org-super-agenda-groups ',(agile-gtd--today-groups))
     (org-agenda-start-day (org-today))
     ,@(when tag-filter-preset
         `((org-agenda-skip-function
            ',(agile-gtd--agenda-skip-form tag-filter-preset)))))))


(defun agile-gtd-agenda-query-next-actions (&optional tag-filter range hide-today)
  "Return org-ql sexp for next actions inside RANGE.
Next actions are the unblocked NEXT and WAIT entries, and every open
task of any state inside the `today' range, blocked or not: work due
today is shown even when its blocker is unresolved.

TAG-FILTER, when non-nil, is `and'-ed in to narrow by tag.
RANGE is one of `agile-gtd-view-ranges' and defaults to `sprint'.  The
default is pinned rather than read from whatever range an agenda buffer
happens to be showing, so a caller outside the agenda always gets one
query.
HIDE-TODAY, when non-nil, excludes everything inside the `today' range,
which the day block above an agenda\\='s next-actions block carries, so the
two sections do not name the same task twice.  The test is the rank, the
same one `today' is cut at, so it takes out both halves of the query:
what is scheduled, due today or overdue, and any deadline within the
deadline window of `agile-gtd-priority-highest' whatever the cookie,
which the day block shows as a deadline warning.  When nil, all of
these are included."
  (let* ((range (or range 'sprint))
         (parked (agile-gtd-view-range-parked-p range))
         (base `(and (or (and (todo ,@(agile-gtd--action-keywords))
                              (not (agile-gtd-blocked)))
                         (and (todo) (agile-gtd-within-range today)))
                     (agile-gtd-within-range ,range)
                     ,@(unless parked '((not (agile-gtd-someday))))
                     ,@(cond
                        ;; A parked range exists to show ticklers, and a
                        ;; tickler is a future schedule, which the rank
                        ;; test lets through while it keeps today's work
                        ;; out of the day block's way.
                        ((and hide-today parked)
                         '((not (agile-gtd-within-range today))))
                        (hide-today
                         '((not (agile-gtd-within-range today))
                           (not (scheduled))))
                        (parked nil)
                        (t '((not (scheduled :from +1))))))))
    (if tag-filter `(and ,base ,tag-filter) base)))

(defun agile-gtd-agenda-query-inbox ()
  "Return org-ql sexp for inbox items."
  `(and (todo)
        (tags ,@agile-gtd-inbox-tags)))

(defun agile-gtd-agenda-query-backlog (&optional tag-filter range)
  "Return org-ql sexp for the backlog inside RANGE.
The backlog holds projects and standalone next actions, blocked ones
included: it is what there is to plan, and a blocked step of a chain is
part of that plan before it can be started.
TAG-FILTER, when non-nil, is `and'-ed in to narrow by tag.
RANGE is one of `agile-gtd-view-ranges' and defaults to `all', which
cuts off at `agile-gtd-priority-lowest' and so admits every priority.
The default is pinned rather than read from whatever range an agenda
buffer happens to be showing, so a caller outside the agenda always gets
one query.

Work scheduled for a later day is not backlog work: it is already spoken
for, and becomes relevant on that day and not before.  Every range short
of the widest therefore leaves it out, and `someday' — which exists to
show what has been set aside — brings it back."
  (let* ((range (or range 'all))
         (parked (agile-gtd-view-range-parked-p range))
         (base `(and (or (todo ,(agile-gtd--project-keyword))
                         (agile-gtd-standalone-next))
                     (agile-gtd-within-range ,range)
                     (not (agile-gtd-habit))
                     ,@(unless parked
                         '((not (agile-gtd-someday))
                           (not (agile-gtd-tickler))
                           (not (scheduled :from +1)))))))
    (if tag-filter `(and ,base ,tag-filter) base)))

(defun agile-gtd-agenda-query-stuck-projects (&optional tag-filter)
  "Return org-ql sexp for stuck projects.
TAG-FILTER, when non-nil, is `and'-ed in to narrow by tag."
  (if tag-filter
      `(and (agile-gtd-stuck-proj) ,tag-filter)
    '(agile-gtd-stuck-proj)))

;; A ranged block carries a live call rather than a `',(...)' of an
;; already-built query, because `org-agenda-run-series' evaluates both the
;; block query and every lprops value at render time, with the agenda buffer
;; current.  Baking the query at the time the command list is built would fix
;; the range at startup and leave rotation nothing to change.
(defvar agile-gtd--agenda-range-override nil
  "Range forced onto the agenda currently being built, or nil.
Bound dynamically by the rotation commands around `org-agenda-redo'.
Nothing binds it during an ordinary build, so every block falls back to
the range it declares and no agenda leaks its range into another.")

(defvar-local agile-gtd--agenda-range nil
  "Range the current agenda buffer was last rendered at.
Set by `agile-gtd--agenda-block-range' as each ranged block renders, and
read back by the rotation commands.  Nil in an agenda whose blocks
declare no range, and outside the agenda entirely.")

(defun agile-gtd--agenda-block-range (declared)
  "Return the range the block rendering right now takes its cutoff from.
DECLARED is the block\\='s own range, used unless rotation has bound
`agile-gtd--agenda-range-override'.  The answer is recorded in the agenda
buffer so the rotation commands know where they are starting from."
  (let ((range (or agile-gtd--agenda-range-override declared)))
    (setq-local agile-gtd--agenda-range range)
    range))

(defun agile-gtd--agenda-block-header (name declared)
  "Return block header NAME with the active range appended.
DECLARED is the block\\='s own range, used unless rotation has bound
`agile-gtd--agenda-range-override'."
  (format "%s [%s]" name (or agile-gtd--agenda-range-override declared)))

(defun agile-gtd-agenda-ql-block (query)
  "Insert the agenda block for QUERY, headed even when nothing matches.
`org-ql-block' leaves out an empty block, header and all.  A ranged block
names its range in the header, and at a narrow range an empty block is
the expected answer: rotated to `today', the next-actions block under the
day block holds nothing.  Keeping its header on screen is what tells the
reader which range is active and that the block ran."
  (let ((size (buffer-size)))
    (org-ql-search-block query)
    (when (= size (buffer-size))
      (org-agenda-prepare)
      (insert (org-add-props (or org-ql-block-header "") nil
                'face 'org-agenda-structure)
              "\n\n"))))

(defun agile-gtd--project-areas ()
  "Return one area for each registered project, whether or not it has a `:key'.
A project area is named by its tag and filters on it.  Only a project
declaring a character `:key' gets an agenda command: the filter tests for a
character rather than for a non-nil `:key', because `char-to-string'
signals on anything else and this list is built while the agenda is
configured at startup — a `:key' of \"w\" would take the session down
rather than cost one project its command."
  (mapcar
   (lambda (project)
     (let ((tag (agile-gtd--project-tag project))
           (key (agile-gtd--project-key project)))
       (list :name tag
             :filter `(tags ,tag)
             :next-range 'upcoming
             :day-filter (list (concat "+" tag))
             :command (when (characterp key)
                        (list (concat "w" (char-to-string key))
                              (format "%s Agenda"
                                      (agile-gtd--project-name project)))))))
   (agile-gtd-project-records)))

(defun agile-gtd-areas ()
  "Return the areas the agenda commands and the org-records-mcp views are built from.
An area is a slice of the outline a question is asked of: everything, the
private or the work entries, or one project.  Each is a plist:

  :name        The key prefix naming the area, nil for everything.
  :filter      The org-ql expression restricting a query to the area, nil
               for everything.
  :next-range  The range next actions are asked at unless one is named.
  :day-filter  The tag filter preset of the area\\='s day block.
  :command     The agenda command\\='s key and description, or nil for an
               area without a command.

One table feeds both the agenda and the views, so a view key and the agenda
block it mirrors cannot answer differently."
  (append
   (list (list :name nil
               :filter nil
               :next-range 'sprint
               :day-filter nil
               :command '("a" "Main Agenda"))
         (list :name "private"
               :filter '(agile-gtd-private)
               :next-range 'sprint
               :day-filter (list (concat "-" agile-gtd-work-tag))
               :command '("pp" "Private Agenda Today"))
         (list :name "work"
               :filter '(agile-gtd-work)
               :next-range 'upcoming
               :day-filter (list (concat "+" agile-gtd-work-tag))
               :command '("ww" "Work Agenda Today")))
   (agile-gtd--project-areas)))

(defun agile-gtd--area (name)
  "Return the area NAME names, nil naming everything."
  (cl-find name (agile-gtd-areas)
           :key (lambda (area) (plist-get area :name))
           :test #'equal))

(defun agile-gtd--area-agenda-command (area)
  "Return the agenda command of AREA: its day, stuck projects and next actions.
The next-actions block opens at the area\\='s `:next-range' and hides what
the day block above it already carries."
  (let ((filter (plist-get area :filter))
        (range (plist-get area :next-range)))
    `(,@(plist-get area :command)
      (,(agile-gtd--agenda-day (plist-get area :day-filter))
       (org-ql-block ',(agile-gtd-agenda-query-stuck-projects filter)
                     ((org-ql-block-header "Stuck Projects")
                      (org-super-agenda-header-separator "")))
       (agile-gtd-agenda-ql-block (agile-gtd-agenda-query-next-actions
                                   ,(and filter `',filter)
                                   (agile-gtd--agenda-block-range ',range) t)
                                  ((org-ql-block-header
                                    (agile-gtd--agenda-block-header "Next Actions" ',range))
                                   (org-super-agenda-groups ',(agile-gtd-rank-groups)))))
      ;; A blocked task due today shows dimmed in the day block: the
      ;; next-actions block leaves today to it, so hiding it would drop the
      ;; task from the agenda.  The setting is the command's for the reason
      ;; the backlog commands give.
      ((org-agenda-dim-blocked-tasks t)))))

(defun agile-gtd--project-agenda-commands ()
  "Return an agenda command for each project declaring a `:key' character."
  (mapcar #'agile-gtd--area-agenda-command
          (cl-remove-if-not (lambda (area) (plist-get area :command))
                            (agile-gtd--project-areas))))

(defun agile-gtd--agenda-custom-commands ()
  "Return the Agile GTD agenda commands."
  `(("i" "Inbox"
     ((org-ql-block `(and (todo)
                          (tags ,@agile-gtd-inbox-tags))
                    ((org-ql-block-header "Inbox")
                     (org-super-agenda-groups '((:auto-property "CREATED")))))))
    ,(agile-gtd--area-agenda-command (agile-gtd--area nil))
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
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))))))
    ("rs" "Stuck Projects"
     ((org-ql-block '(agile-gtd-stuck-proj)
                    ((org-ql-block-header "Stuck Projects")
                     (org-super-agenda-header-separator "")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))))))
    ("rt" "Tangling TODOs"
     ((org-ql-block '(agile-gtd-tangling)
                    ((org-ql-block-header "Tangling TODOs")
                     (org-super-agenda-header-separator "")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))))))
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
    ,(agile-gtd--area-agenda-command (agile-gtd--area "private"))
    ;; A backlog shows blocked steps dimmed however other agendas treat them.
    ;; The setting is the command's, not the block's: Org marks entries while
    ;; a block renders but dims or hides them in `org-agenda-finalize', which
    ;; sees only the command's settings.
    ("pb" "Private Backlog"
     ((agile-gtd-agenda-ql-block (agile-gtd-agenda-query-backlog
                     '(agile-gtd-private) (agile-gtd--agenda-block-range 'all))
                    ((org-ql-block-header
                      (agile-gtd--agenda-block-header "Backlog" 'all))
                     (org-super-agenda-groups ',(agile-gtd-rank-groups)))))
     ((org-agenda-dim-blocked-tasks t)))
    ("ps" "Private Stuck Projects"
     ((org-ql-block ',(agile-gtd-agenda-query-stuck-projects '(agile-gtd-private))
                    ((org-ql-block-header "Stuck Projects")
                     (org-super-agenda-header-separator "")
                     (org-super-agenda-groups ',(agile-gtd-rank-groups))))))
    ("w" . "Work")
    ,(agile-gtd--area-agenda-command (agile-gtd--area "work"))
    ("wb" "Work Backlog"
     ((agile-gtd-agenda-ql-block (agile-gtd-agenda-query-backlog
                     '(agile-gtd-work) (agile-gtd--agenda-block-range 'all))
                    ((org-ql-block-header
                      (agile-gtd--agenda-block-header "Backlog" 'all))
                     (org-super-agenda-groups ',(agile-gtd-rank-groups)))))
     ((org-agenda-dim-blocked-tasks t)))
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

(defun agile-gtd-agenda-current-range ()
  "Return the range the current agenda buffer renders at.
Return nil outside an agenda buffer, and in an agenda built entirely
from blocks that declare no range."
  (and (derived-mode-p 'org-agenda-mode)
       agile-gtd--agenda-range))

(defun agile-gtd--agenda-require-range ()
  "Return the current agenda buffer\\='s range, or signal a `user-error'."
  (unless (derived-mode-p 'org-agenda-mode)
    (user-error "Not in an Org agenda buffer"))
  (or agile-gtd--agenda-range
      (user-error "This agenda has no ranged block to widen or narrow")))

(defun agile-gtd--agenda-rebuild-at (range)
  "Rebuild the current agenda with RANGE forced onto every ranged block.
A nil RANGE returns each block to the range it declares.
`org-agenda-redo' and not `org-agenda-redo-all': the override is a
dynamic binding, and rebuilding the other agenda buffers while it is in
effect would stamp this buffer\\='s range onto theirs."
  (let ((agile-gtd--agenda-range-override range))
    (org-agenda-redo)))

(defun agile-gtd-agenda-set-range (range)
  "Rebuild the current agenda at RANGE.
RANGE is one of `agile-gtd-view-ranges'."
  (interactive
   (progn
     (agile-gtd--agenda-require-range)
     (list (intern (completing-read "Agenda range: "
                                    (mapcar #'symbol-name agile-gtd-view-ranges)
                                    nil t)))))
  (agile-gtd--agenda-require-range)
  (unless (memq range agile-gtd-view-ranges)
    (user-error "Unknown Agile GTD view range: %S" range))
  (agile-gtd--agenda-rebuild-at range)
  (message "Agenda range: %s" range))

(defun agile-gtd-agenda-reset-range ()
  "Rebuild the current agenda at each block\\='s declared range."
  (interactive)
  (agile-gtd--agenda-require-range)
  (agile-gtd--agenda-rebuild-at nil)
  (message "Agenda range: back to the declared range"))

(defun agile-gtd--agenda-rotate-range (step)
  "Rebuild the current agenda STEP places along `agile-gtd-view-ranges'.
STEP is 1 to widen and -1 to narrow.  Rotation clamps at both ends
rather than wrapping, because the day\\='s work and the everything-view are
where someone is heading, not stations on a loop to be passed through."
  (let* ((current (agile-gtd--agenda-require-range))
         (position (cl-position current agile-gtd-view-ranges))
         (index (and position (+ position step)))
         (next (and index (>= index 0) (nth index agile-gtd-view-ranges))))
    (unless position
      (error "Range %s is not one of `agile-gtd-view-ranges'" current))
    (if (null next)
        (message "Already at the %s range (%s)"
                 (if (> step 0) "widest" "narrowest")
                 current)
      (agile-gtd--agenda-rebuild-at next)
      (message "Agenda range: %s" next))))

(defun agile-gtd-agenda-wider-range ()
  "Rebuild the current agenda one range wider, toward `someday'."
  (interactive)
  (agile-gtd--agenda-rotate-range 1))

(defun agile-gtd-agenda-narrower-range ()
  "Rebuild the current agenda one range narrower, toward `today'."
  (interactive)
  (agile-gtd--agenda-rotate-range -1))

(defalias 'agile-gtd-agenda-show-priorities #'agile-gtd-agenda-set-range)
(defalias 'agile-gtd-agenda-reset-show-priorities #'agile-gtd-agenda-reset-range)
(defalias 'agile-gtd-agenda-show-more-priorities #'agile-gtd-agenda-wider-range)
(defalias 'agile-gtd-agenda-show-less-priorities #'agile-gtd-agenda-narrower-range)

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

(org-ql-defpred (agile-gtd-within-range agile-gtd-prio-deadline) (range)
  "Match entries ranking inside RANGE.
RANGE is one of `agile-gtd-view-ranges', `today' included, or a priority
character, which admits entries at or above that priority\\='s band.
The test is `agile-gtd--item-rank' against `agile-gtd-view-range-cutoff'
— the one number that also closes a group in `agile-gtd-rank-groups'.
Reading the rank rather than re-deriving the cutoff from cookies, parents
and deadlines separately is what keeps a view range honest: every entry the
range admits has a group at or above the cutoff to land in, so the agenda
grows no heading for a priority the range stops short of.

Rank collapses four claims on urgency into one number — the entry\\='s own
cookie, its direct parent\\='s, an approaching deadline, and a schedule that
has come due — so each of those still admits an entry on its own.

The test is on RANGE and nothing global: one query, one cutoff, whatever
any agenda buffer happens to be showing."
  :normalizers
  ;; A range name reaches the body quoted; a character evaluates to itself.
  ((`(,predicate-names ,(and (pred symbolp) name))
    `(agile-gtd-within-range ',name))
   (`(,predicate-names ,arg)
    `(agile-gtd-within-range ,arg)))
  :body
  (when-let ((top (if (characterp range)
                      (agile-gtd--rank-band-top range)
                    (agile-gtd-view-range-cutoff range))))
    (<= (agile-gtd--item-rank) top)))

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
         (projects (agile-gtd-project-records))
         (project-tag-names (mapcar #'agile-gtd--project-tag projects))
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
    ;; A project earns an `org-tag-alist' entry only by declaring a character:
    ;; Org reads the cdr as a selection key, and a string or a symbol there
    ;; corrupts every tag prompt in the session.
    (dolist (project projects)
      (let ((tag (agile-gtd--project-tag project))
            (key (agile-gtd--project-key project)))
        (when (characterp key)
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

(defconst agile-gtd--org-records-mcp-views
  '((next . "unblocked NEXT/WAIT in the range, plus every open task of any \
state scheduled or due today or overdue, blocked or not")
    (backlog . "PROJ and standalone NEXT/WAIT in the range, blocked ones \
included, no habits")
    (stuck . "projects with no NEXT/WAIT child; takes no range"))
  "The views every area asks, each with what it holds for the catalogue.")

(defconst agile-gtd--org-records-mcp-global-views
  '((inbox . "open items carrying an inbox tag; asked of everything only, \
with no area and no range")
    (tangling . "open items under a done ancestor; asked of everything only, \
with no area and no range"))
  "The views asked of everything only, taking neither area nor range.")

(defun agile-gtd--org-records-mcp-range-description (range)
  "Return what RANGE admits, for the catalogue."
  (pcase range
    ('today (format "rank 0 or below: any deadline within %d days (the [#%c] \
deadline window), due today, overdue, or scheduled today or earlier"
                    (agile-gtd--deadline-window agile-gtd-priority-highest)
                    agile-gtd-priority-highest))
    ('someday (format "every priority, and the only range that brings back \
%s items, ticklers and work scheduled after today"
                      agile-gtd-someday-tag))
    (_ (format "priority %c and above, by cookie, parent or deadline"
               (agile-gtd-view-range-priority range)))))

(defun agile-gtd--org-records-mcp-catalogue-entry (indent text &optional flush)
  "Return TEXT filled to a paragraph, its first line at INDENT.
Continuation lines hang four columns further in, so a term and what it
means read apart, unless FLUSH is non-nil, which keeps them at INDENT."
  (with-temp-buffer
    (insert indent text)
    (let ((fill-column 72)
          (fill-prefix (if flush indent (concat indent "    "))))
      (fill-region (point-min) (point-max)))
    (concat (buffer-string) "\n")))

(defun agile-gtd--org-records-mcp-view-key (area view &optional range)
  "Return the key of VIEW asked of AREA at RANGE, as an interned symbol.
AREA is an area\\='s `:name', nil for everything; RANGE nil names the
short key, which runs at the area\\='s default."
  (intern (concat (and area (concat area "-"))
                  (symbol-name view)
                  (and range (concat "-" (symbol-name range))))))

(defun agile-gtd--org-records-mcp-area-views (area)
  "Return the org-records-mcp views of AREA: `next' and `backlog' at every range,
both again at the area\\='s default, and `stuck'."
  (let ((name (plist-get area :name))
        (filter (plist-get area :filter)))
    (cl-flet ((view (key query) (list key :query query)))
      (append
       (mapcan
        (lambda (range)
          (list (view (agile-gtd--org-records-mcp-view-key name 'next range)
                      (agile-gtd-agenda-query-next-actions filter range))
                (view (agile-gtd--org-records-mcp-view-key name 'backlog range)
                      (agile-gtd-agenda-query-backlog filter range))))
        agile-gtd-view-ranges)
       (list (view (agile-gtd--org-records-mcp-view-key name 'next)
                   (agile-gtd-agenda-query-next-actions
                    filter (plist-get area :next-range)))
             (view (agile-gtd--org-records-mcp-view-key name 'backlog)
                   (agile-gtd-agenda-query-backlog filter 'all))
             (view (agile-gtd--org-records-mcp-view-key name 'stuck)
                   (agile-gtd-agenda-query-stuck-projects filter)))))))

(defun agile-gtd-org-records-mcp-views ()
  "Return the org-records-mcp views agile-gtd generates, one per key.
A key is `[<area>-]<view>[-<range>]' and is the whole question: each view
carries a literal query and declares no filter or range, so org-records-mcp
refuses both.  The areas are `agile-gtd-areas', the same table the agenda
commands are built from."
  (append (mapcan #'agile-gtd--org-records-mcp-area-views (agile-gtd-areas))
          (list (list 'inbox :query (agile-gtd-agenda-query-inbox))
                (list 'tangling :query '(agile-gtd-tangling)))))

(defun agile-gtd--org-records-mcp-computed-fields ()
  "Return the computed fields agile-gtd gives every org-records-mcp node."
  (list (cons 'rank #'agile-gtd--item-rank)
        (cons 'parent-priority #'agile-gtd--direct-parent-priority)))

(defconst agile-gtd--org-records-mcp-list-computed-fields '(rank)
  "The computed fields an org-records-mcp match list carries unasked.
A list row carries the rank the list is sorted by; the parent's
priority belongs to a read of the row's link.")

(defun agile-gtd--org-records-mcp-list-computed-fields (current)
  "Return CURRENT with agile-gtd's list computed fields added.
CURRENT is `org-records-mcp-list-computed-fields': `all' stays as it is,
and a list keeps its own names, in order, ahead of agile-gtd's."
  (if (eq current 'all)
      current
    (append current
            (seq-difference agile-gtd--org-records-mcp-list-computed-fields
                            current))))

(defun agile-gtd--join-words (words)
  "Return WORDS joined as prose: \"a\", \"a and b\", \"a, b and c\"."
  (if (cdr words)
      (concat (string-join (butlast words) ", ") " and " (car (last words)))
    (or (car words) "")))

(defun agile-gtd-org-records-mcp-view-catalogue ()
  "Return the views part of the org-view tool description.
It states the key grammar with the areas, views and ranges that exist and
the default range of each area, rather than one line per key.  Set as
`org-records-mcp-view-catalogue-function'."
  (let* ((areas (agile-gtd-areas))
         (indent "           ")
         (item (concat indent "  "))
         (names (mapcar (lambda (area) (plist-get area :name)) (cdr areas)))
         (defaults
          (delq nil
                (mapcar
                 (lambda (range)
                   (when-let* ((named
                                (mapcar (lambda (area)
                                          (or (plist-get area :name) "everything"))
                                        (cl-remove-if-not
                                         (lambda (area)
                                           (eq (plist-get area :next-range) range))
                                         areas))))
                     (format "%s for %s" range (agile-gtd--join-words named))))
                 agile-gtd-view-ranges))))
    (concat
     (agile-gtd--org-records-mcp-catalogue-entry
      indent (format "Each key is the whole question and takes no filter or \
range.  A key is [<area>-]<view>[-<range>], for example private-next, \
%s-backlog-sprint or next-today."
                     (car (last names)))
      t)
     (agile-gtd--org-records-mcp-catalogue-entry
      indent (concat "area - omitted for everything, or one of: "
                     (string-join names ", ")))
     indent "view - what the key asks:\n"
     (mapconcat (lambda (view)
                  (agile-gtd--org-records-mcp-catalogue-entry
                   item (format "%s - %s" (car view) (cdr view))))
                (append agile-gtd--org-records-mcp-views agile-gtd--org-records-mcp-global-views)
                "")
     indent "range - narrowest first, optional on next and backlog:\n"
     (mapconcat (lambda (range)
                  (agile-gtd--org-records-mcp-catalogue-entry
                   item (format "%s - %s" range
                                (agile-gtd--org-records-mcp-range-description range))))
                agile-gtd-view-ranges "")
     (agile-gtd--org-records-mcp-catalogue-entry
      indent (concat "Without a range, next runs at "
                     (string-join defaults ", and at ")
                     "; backlog runs at all.  Every result is sorted by rank, \
most urgent first, and each node carries the computed field rank.  \
Ask for parent-priority by name in computed.")
      t))))

(defvar agile-gtd--org-records-mcp-view-names nil
  "The view names the last refresh put into `org-records-mcp-views'.
A refresh removes these before adding the current keys, so a key whose
project left the registry goes with it.")

(defun agile-gtd--merge-by-name (current additions &optional retired)
  "Return CURRENT with ADDITIONS replacing the entries of the same name.
Entries named in RETIRED are dropped as well; every other entry is kept."
  (let ((names (append (mapcar #'car additions) retired)))
    (append (cl-remove-if (lambda (entry) (memq (car-safe entry) names))
                          current)
            additions)))

(defun agile-gtd--apply-org-records-mcp ()
  "Configure org-records-mcp from the area table, unless `agile-gtd-enable-org-records-mcp' is off.
The server itself is started by the user\\='s configuration: org-records-mcp reads
the views on every call, so keys added here resolve at once, and builds the
org-view description when a client connects."
  (when agile-gtd-enable-org-records-mcp
    (let ((views (agile-gtd-org-records-mcp-views)))
      (setq org-records-mcp-views (agile-gtd--merge-by-name
                           org-records-mcp-views views agile-gtd--org-records-mcp-view-names)
            agile-gtd--org-records-mcp-view-names (mapcar #'car views)
            org-records-mcp-computed-fields (agile-gtd--merge-by-name
                                     org-records-mcp-computed-fields
                                     (agile-gtd--org-records-mcp-computed-fields))
            org-records-mcp-list-computed-fields (agile-gtd--org-records-mcp-list-computed-fields
                                                  org-records-mcp-list-computed-fields)
            org-records-mcp-query-sort-fn #'agile-gtd--item-rank<
            org-records-mcp-view-catalogue-function #'agile-gtd-org-records-mcp-view-catalogue
            org-records-mcp-allowed-files nil
            org-records-mcp-file-scope-override t))))

(defun agile-gtd--org-settings ()
  "Return the Org options the workflow depends on, as (VARIABLE . VALUE).
docs/org-settings.org gives the reason for each."
  `(;; Blocking is org-edna's alone: Org's own checks would block every
    ;; project with open children, and hide it from the agenda.
    (org-enforce-todo-dependencies . nil)
    (org-enforce-todo-checkbox-dependencies . nil)
    (org-agenda-dim-blocked-tasks . invisible)
    ;; Logging
    (org-log-into-drawer . t)
    (org-log-done . time+note)
    (org-log-repeat . time)
    (org-log-redeadline . time)
    (org-log-reschedule . time)
    (org-log-state-notes-insert-after-drawers . nil)
    ;; Archive and habits
    (org-archive-location . ,(agile-gtd--expand-org-path "archive/%s::datetree"))
    (org-habit-show-habits . t)
    (org-habit-preceding-days . 14)
    (org-habit-following-days . 7)
    ;; Agenda behaviour
    (org-agenda-use-time-grid . t)
    (org-agenda-skip-scheduled-if-done . t)
    (org-agenda-skip-unavailable-files . t)
    (org-agenda-skip-deadline-if-done . t)
    (org-agenda-skip-timestamp-if-done . t)
    (org-agenda-start-on-weekday . nil)
    (org-agenda-span . day)
    (org-agenda-start-day . "-0d")
    (org-deadline-warning-days . 7)
    (org-agenda-show-future-repeats . t)
    (org-agenda-skip-deadline-prewarning-if-scheduled . t)
    (org-agenda-tags-todo-honor-ignore-options . t)
    (org-agenda-skip-scheduled-delay-if-deadline . t)
    (org-agenda-skip-scheduled-if-deadline-is-shown . t)
    (org-agenda-skip-timestamp-if-deadline-is-shown . t)
    (org-agenda-todo-list-sublevels . t)
    (org-agenda-include-deadlines . t)
    ;; Inheritance: areas, clients and SOMEDAY arrive through filetags and
    ;; parents.
    (org-use-property-inheritance . t)
    (org-use-tag-inheritance . t)))

(defun agile-gtd--apply-org-settings ()
  "Apply the Org settings the workflow depends on.
Does nothing when `agile-gtd-enable-org-settings' is off.  Default values
are set rather than whatever binding is current: a file\='s startup options
make some of these local to its buffer, and a refresh run from that buffer
would otherwise change it alone."
  (when agile-gtd-enable-org-settings
    (org-edna-mode 1)
    (pcase-dolist (`(,variable . ,value) (agile-gtd--org-settings))
      (set-default variable value))
    ;; Org installs its own blockers from the Customize setters of the two
    ;; enforce options, which `set-default' does not run.
    (remove-hook 'org-blocker-hook
                 #'org-block-todo-from-children-or-siblings-or-parent)
    (remove-hook 'org-blocker-hook #'org-block-todo-from-checkboxes)
    (add-to-list 'org-modules 'org-habit)))

(defun agile-gtd-refresh ()
  "Refresh all derived Agile GTD configuration."
  (interactive)
  (agile-gtd--validate-configuration)
  (agile-gtd--apply-org-settings)
  (agile-gtd--apply-priorities)
  (agile-gtd--apply-org-modern-visuals)
  (agile-gtd--apply-todo-keywords)
  (agile-gtd--apply-tags)
  (agile-gtd--apply-agenda-files)
  (agile-gtd--apply-refile-targets)
  (agile-gtd--apply-capture-templates)
  (agile-gtd--apply-agenda-commands)
  (agile-gtd--apply-org-records-mcp))

(defun agile-gtd--project-untagged-files (record)
  "Return the files of RECORD that do not declare RECORD\\='s tag.
The files are the project\\='s own file and the archives Org resolves from
`org-archive-location', both of which hold clocked time that is selected
by inherited tag.  Only a file-level tag makes every entry in a file
inherit one, so a tag worn by individual headlines does not count; an
archive is the case that bites, because archiving stores the inherited
tags of a subtree in its `ARCHIVE_ITAGS' property rather than as real
tags.  Files that do not exist are Org\\='s to drop, and are not reported
here: this asks about tags, not about layout.

Org names an archive for itself — `<file>.org_archive' under the default
`org-archive-location' — and no `auto-mode-alist' entry claims that name,
so a buffer visiting one arrives in Fundamental mode where `org-file-tags'
is nil whatever the file says.  The mode is put on the buffer before its
tags are read, or every correctly tagged archive under the default layout
would be reported at every startup."
  (let ((tag (plist-get record :tag)))
    (when tag
      (cl-remove-if
       (lambda (file)
         (with-current-buffer (org-get-agenda-file-buffer file)
           (unless (derived-mode-p 'org-mode) (org-mode))
           (member tag org-file-tags)))
       (org-add-archive-files
        (list (agile-gtd--expand-org-path (plist-get record :file))))))))

(defun agile-gtd-check-project-tags ()
  "Warn about registered project files that do not carry their tag.
Pairing a project with its time is inherited-tag matching, so a file
missing its tag answers every query with nothing and says nothing about
why.  Reporting it here is the difference between learning of it at
startup and learning of it from an empty invoice.

The check never writes.  Org offers no built-in for setting a file tag,
and this package loads in batch, so repairing the files from here would
make a config sync, a doctor run or a test run mutate Org data as a side
effect.  The fix is manual and deliberate."
  (interactive)
  (let ((org-agenda-new-buffers nil)
        (offenders nil))
    (unwind-protect
        (dolist (record (agile-gtd-project-records))
          (dolist (file (agile-gtd--project-untagged-files record))
            (push (format "%s (%s)"
                          (abbreviate-file-name file)
                          (plist-get record :tag))
                  offenders)))
      ;; Reading a tag means visiting the file; a check that leaves the whole
      ;; registry open has changed the session it was meant to inspect.
      (org-release-buffers org-agenda-new-buffers))
    (setq offenders (nreverse offenders))
    (cond (offenders
           (warn "Agile GTD: project files without their project tag: %s"
                 (mapconcat #'identity offenders ", ")))
          ((called-interactively-p 'interactive)
           (message "Agile GTD: every project file carries its tag")))))

(defun agile-gtd-enable ()
  "Enable Agile GTD for the current Org configuration."
  (interactive)
  (agile-gtd-refresh)
  ;; The tag check visits every project file, and a warning raised by a batch
  ;; run is one nobody reads.
  (unless noninteractive
    (agile-gtd-check-project-tags)))

(provide 'agile-gtd)

;;; agile-gtd.el ends here
