;;; agile-gtd-org-mcp-test.el --- The agenda views as org-mcp view keys -*- lexical-binding: t; -*-

;;; Commentary:

;; These tests ask through the seam an MCP client uses: they call org-mcp's
;; org-view tool with a key, over sandboxed Org fixtures, and assert on what
;; comes back — the matched titles, their order and their computed fields.
;; They never inspect the generated query or the shape of `org-mcp-views'.

;;; Code:

(require 'ert)
(require 'json)
(require 'org-edna)
(require 'agile-gtd)
(require 'agile-gtd-test)

(ert-deftest agile-gtd-org-mcp-is-loaded-with-agile-gtd ()
  "org-mcp is a hard dependency: loading agile-gtd loads it."
  (should (featurep 'org-mcp))
  (should (fboundp 'org-mcp--tool-view)))


;;; Fixtures

(defconst agile-gtd-org-mcp-test-projects
  '((:tag "alpha" :name "Alpha" :key ?a)
    (:tag "beta"))
  "A `#work' project with an agenda key, and a private one without.")

(defun agile-gtd-org-mcp-test-todo ()
  "Return the fixture for the todo file: private, work, inbox and leftovers."
  (let ((today (format-time-string "%Y-%m-%d %a"))
        (tomorrow (format-time-string
                   "%Y-%m-%d %a" (time-add (current-time) (days-to-time 1)))))
    (concat
     "* NEXT [#A] Private sprint action\n\n"
     ;; Inside the [#A] deadline window, so inside `today' by rank.
     "* NEXT [#A] Private due tomorrow\n"
     (format "DEADLINE: <%s>\n\n" tomorrow)
     "* NEXT Private default action\n\n"
     "* NEXT [#G] Private low action\n\n"
     "* TODO Private todo scheduled today\n"
     (format "SCHEDULED: <%s>\n\n" today)
     ;; A chain: each step is blocked by the one before it.
     "* NEXT [#A] Private chain first\n\n"
     "* NEXT [#A] Private chain blocked\n"
     ":PROPERTIES:\n:BLOCKER:  previous-sibling\n:END:\n\n"
     "* NEXT Private blocked due today\n"
     (format "DEADLINE: <%s>\n" today)
     ":PROPERTIES:\n:BLOCKER:  previous-sibling\n:END:\n\n"
     ;; A project due today: the project is inside `today', its step is not.
     "* PROJ Private project due today\n"
     (format "DEADLINE: <%s>\n" today)
     "** NEXT Private step of the project due today\n\n"
     "* PROJ Private stuck project\n"
     "** TODO Private notes\n\n"
     "* NEXT [#A] Private someday :SOMEDAY:\n\n"
     "* NEXT [#B] Work action :#work:\n\n"
     "* NEXT Work default action :#work:\n\n"
     "* PROJ [#C] Work project :#work:\n"
     "** NEXT Work project step\n\n"
     "* TODO Inbox capture :#inbox:\n\n"
     "* DONE Finished parent\n"
     "** NEXT Tangled leftover\n")))

(defconst agile-gtd-org-mcp-test-alpha
  "#+FILETAGS: :alpha:#work:
* NEXT [#B] Alpha action

* NEXT Alpha default action

* PROJ Alpha stuck project
** TODO Alpha notes
"
  "The fixture for the `alpha' project file.")

(defconst agile-gtd-org-mcp-test-beta
  "#+FILETAGS: :beta:
* NEXT Beta default action

* NEXT [#A] Beta urgent action
"
  "The fixture for the `beta' project file.")

(defmacro agile-gtd-org-mcp-test-with-fixtures (&rest body)
  "Run BODY after `agile-gtd-enable' over the fixture files in a sandbox."
  (declare (indent 0) (debug t))
  `(agile-gtd-test-with-sandbox
     (let ((agile-gtd-projects agile-gtd-org-mcp-test-projects)
           (org-use-tag-inheritance t)
           (org-tags-exclude-from-inheritance nil)
           (org-blocker-hook (list #'org-edna-blocker-function)))
       (dolist (file `(("todo.org" . ,(agile-gtd-org-mcp-test-todo))
                       ("alpha.org" . ,agile-gtd-org-mcp-test-alpha)
                       ("beta.org" . ,agile-gtd-org-mcp-test-beta)))
         (with-temp-file (expand-file-name (car file) org-directory)
           (insert (cdr file))))
       (unwind-protect
           (progn
             (agile-gtd-enable)
             ;; Only the fixtures exist; the inbox file the registry names
             ;; does not, and the view tool searches the files that do.
             (setq org-agenda-files
                   (mapcar (lambda (name) (expand-file-name name org-directory))
                           '("todo.org" "alpha.org" "beta.org")))
             ,@body)
         (dolist (buffer (buffer-list))
           (when (and (buffer-file-name buffer)
                      (file-in-directory-p (buffer-file-name buffer) org-directory))
             (kill-buffer buffer)))))))

(defun agile-gtd-org-mcp-test-view (key &optional filter range)
  "Return the nodes the org-view tool answers KEY with, as alists.
FILTER and RANGE are passed as a client would pass them."
  (append (alist-get 'children
                     (json-parse-string (org-mcp--tool-view key filter range)
                                        :object-type 'alist
                                        :false-object :false))
          nil))

(defun agile-gtd-org-mcp-test-titles (key)
  "Return the titles the org-view tool answers KEY with, in order."
  (mapcar (lambda (node) (alist-get 'title node))
          (agile-gtd-org-mcp-test-view key)))

(defun agile-gtd-org-mcp-test-computed (node field)
  "Return the computed FIELD of NODE."
  (alist-get field (alist-get 'computed node)))

(defun agile-gtd-org-mcp-test-node (key title)
  "Return the node titled TITLE in the answer to KEY."
  (cl-find title (agile-gtd-org-mcp-test-view key)
           :key (lambda (node) (alist-get 'title node))
           :test #'equal))

(defun agile-gtd-org-mcp-test-refusal (thunk)
  "Return the message THUNK is refused with, or nil when it is not refused."
  (condition-case err
      (progn (funcall thunk) nil)
    (error (error-message-string err))))

(defconst agile-gtd-org-mcp-test-areas '("" "private-" "work-" "alpha-" "beta-")
  "The key prefix of every area the fixture configures.")


;;; The views

(ert-deftest agile-gtd-org-mcp-next-is-the-sprint-plus-what-is-due-today ()
  "`next' holds the unblocked sprint actions and every open task due today."
  (agile-gtd-org-mcp-test-with-fixtures
    (let ((titles (agile-gtd-org-mcp-test-titles "next")))
      (should (equal (sort (copy-sequence titles) #'string<)
                     (sort (list "Private todo scheduled today"
                                 "Private blocked due today"
                                 "Private due tomorrow"
                                 "Private project due today"
                                 "Private sprint action"
                                 "Private chain first"
                                 "Beta urgent action"
                                 "Work action"
                                 "Alpha action"
                                 "Work project step")
                           #'string<))))))

(ert-deftest agile-gtd-org-mcp-work-next-sprint-holds-a-sprint-project-s-steps ()
  "A step with no cookie rises into `work-next-sprint' with its sprint project.
Its own default priority stays out of the sprint, so a sibling action
with no project stays out."
  (agile-gtd-org-mcp-test-with-fixtures
    (let ((titles (agile-gtd-org-mcp-test-titles "work-next-sprint")))
      (should (member "Work project step" titles))
      (should-not (member "Work default action" titles)))))

(ert-deftest agile-gtd-org-mcp-next-today-holds-any-open-state-blocked-or-not ()
  "`next-today' holds what is due today, a plain TODO and a blocked action alike.
An [#A] deadline one day out is inside `today' too."
  (agile-gtd-org-mcp-test-with-fixtures
    (should (equal (sort (agile-gtd-org-mcp-test-titles "next-today") #'string<)
                   '("Private blocked due today" "Private due tomorrow"
                     "Private project due today" "Private todo scheduled today")))))

(ert-deftest agile-gtd-org-mcp-a-project-due-today-is-a-next-action ()
  "A project due today is in `next-today' and in its area's `next'.
Its undated step is not pulled along: it ranks where its own cookie puts it."
  (agile-gtd-org-mcp-test-with-fixtures
    (dolist (key '("next-today" "private-next"))
      (ert-info (key)
        (let ((titles (agile-gtd-org-mcp-test-titles key)))
          (should (member "Private project due today" titles))
          (should-not (member "Private step of the project due today" titles)))))))

(ert-deftest agile-gtd-org-mcp-next-leaves-out-blocked-work-that-is-not-due ()
  "A blocked action is offered by `next' only when it is due."
  (agile-gtd-org-mcp-test-with-fixtures
    (dolist (key '("next" "next-all" "private-next-someday"))
      (ert-info (key)
        (let ((titles (agile-gtd-org-mcp-test-titles key)))
          (should-not (member "Private chain blocked" titles))
          (should (member "Private blocked due today" titles)))))))

(ert-deftest agile-gtd-org-mcp-backlog-includes-blocked-work ()
  "`backlog' is what there is to plan, blocked steps included."
  (agile-gtd-org-mcp-test-with-fixtures
    (let ((titles (agile-gtd-org-mcp-test-titles "private-backlog")))
      (should (member "Private chain blocked" titles))
      (should (member "Private chain first" titles))
      (should (member "Private stuck project" titles)))))

(ert-deftest agile-gtd-org-mcp-someday-alone-brings-back-parked-work ()
  "Only the `someday' range returns SOMEDAY work."
  (agile-gtd-org-mcp-test-with-fixtures
    (should-not (member "Private someday" (agile-gtd-org-mcp-test-titles "private-backlog")))
    (should (member "Private someday"
                    (agile-gtd-org-mcp-test-titles "private-backlog-someday")))
    (should (member "Private someday"
                    (agile-gtd-org-mcp-test-titles "private-next-someday")))))

(ert-deftest agile-gtd-org-mcp-area-filters ()
  "Each area answers for its own entries: private, work, and one project each."
  (agile-gtd-org-mcp-test-with-fixtures
    (ert-info ("private takes every entry without the work tag, beta included")
      (let ((titles (agile-gtd-org-mcp-test-titles "private-next")))
        (should (member "Private sprint action" titles))
        (should (member "Beta urgent action" titles))
        (should-not (member "Work action" titles))
        (should-not (member "Alpha action" titles))))
    (ert-info ("work takes the work tag, the alpha project included")
      (should (equal (sort (agile-gtd-org-mcp-test-titles "work-next") #'string<)
                     '("Alpha action" "Alpha default action" "Work action"
                       "Work default action" "Work project step"))))
    (ert-info ("a project takes its own tag")
      (should (equal (sort (agile-gtd-org-mcp-test-titles "alpha-next") #'string<)
                     '("Alpha action" "Alpha default action"))))
    (ert-info ("a project without an agenda key gets keys too")
      (should (equal (sort (agile-gtd-org-mcp-test-titles "beta-next") #'string<)
                     '("Beta default action" "Beta urgent action")))
      (should (equal (agile-gtd-org-mcp-test-titles "beta-next-sprint")
                     '("Beta urgent action"))))))

(ert-deftest agile-gtd-org-mcp-every-view-runs-at-every-range-inside-its-cutoff ()
  "Each area answers `next' and `backlog' at each range, inside its cutoff."
  (agile-gtd-org-mcp-test-with-fixtures
    (dolist (area agile-gtd-org-mcp-test-areas)
      (dolist (view '("next" "backlog"))
        (dolist (range agile-gtd-view-ranges)
          (let ((key (format "%s%s-%s" area view range)))
            (ert-info (key)
              (dolist (node (agile-gtd-org-mcp-test-view key))
                (should (<= (agile-gtd-org-mcp-test-computed node 'rank)
                            (agile-gtd-view-range-cutoff range)))))))))))

(ert-deftest agile-gtd-org-mcp-short-keys-run-at-the-agenda-defaults ()
  "`next' defaults as the agenda does, and `backlog' to `all'."
  (agile-gtd-org-mcp-test-with-fixtures
    (dolist (case '(("" sprint) ("private-" sprint) ("work-" backlog)
                    ("alpha-" backlog) ("beta-" backlog)))
      (pcase-let ((`(,area ,range) case))
        (ert-info ((format "%snext" area))
          (should (equal (agile-gtd-org-mcp-test-titles (concat area "next"))
                         (agile-gtd-org-mcp-test-titles
                          (format "%snext-%s" area range)))))
        (ert-info ((format "%sbacklog" area))
          (should (equal (agile-gtd-org-mcp-test-titles (concat area "backlog"))
                         (agile-gtd-org-mcp-test-titles
                          (concat area "backlog-all")))))))
    (ert-info ("the defaults differ where the ranges hold different entries")
      (should-not (member "Private default action"
                          (agile-gtd-org-mcp-test-titles "private-next")))
      (should (member "Work default action"
                      (agile-gtd-org-mcp-test-titles "work-next"))))))

(ert-deftest agile-gtd-org-mcp-stuck-per-area ()
  "`stuck' finds projects without a next action, in each area."
  (agile-gtd-org-mcp-test-with-fixtures
    (should (equal (sort (agile-gtd-org-mcp-test-titles "stuck") #'string<)
                   '("Alpha stuck project" "Private stuck project")))
    (should (equal (agile-gtd-org-mcp-test-titles "private-stuck")
                   '("Private stuck project")))
    (should (equal (agile-gtd-org-mcp-test-titles "work-stuck")
                   '("Alpha stuck project")))
    (should (equal (agile-gtd-org-mcp-test-titles "alpha-stuck")
                   '("Alpha stuck project")))
    (should-not (agile-gtd-org-mcp-test-titles "beta-stuck"))))

(ert-deftest agile-gtd-org-mcp-inbox-and-tangling-are-global ()
  "`inbox' and `tangling' exist once, and take neither area nor range."
  (agile-gtd-org-mcp-test-with-fixtures
    (should (equal (agile-gtd-org-mcp-test-titles "inbox") '("Inbox capture")))
    (should (equal (agile-gtd-org-mcp-test-titles "tangling") '("Tangled leftover")))
    (dolist (key '("private-inbox" "work-tangling" "inbox-today" "tangling-all"
                   "stuck-sprint"))
      (ert-info (key)
        (should (string-match-p "Unknown view"
                                (agile-gtd-org-mcp-test-refusal
                                 (lambda () (agile-gtd-org-mcp-test-view key)))))))))

(defun agile-gtd-org-mcp-test-area-keys (area)
  "Return the thirteen keys the grammar gives AREA, a key prefix."
  (mapcar (lambda (key) (concat area key))
          (append '("next" "backlog" "stuck")
                  (mapcan (lambda (view)
                            (mapcar (lambda (range) (format "%s-%s" view range))
                                    agile-gtd-view-ranges))
                          '("next" "backlog")))))

(defun agile-gtd-org-mcp-test-listed-keys ()
  "Return the keys org-view names when it refuses an unknown one."
  (let ((message (agile-gtd-org-mcp-test-refusal
                  (lambda () (agile-gtd-org-mcp-test-view "no-such-key")))))
    ;; The rendered error closes on a quote, which is not part of the last name.
    (should (string-match "Configured views: \\([^\"]*\\)" message))
    (split-string (match-string 1 message) ", " t)))

(ert-deftest agile-gtd-org-mcp-key-count ()
  "Thirteen keys per area, plus `inbox' and `tangling', and every one resolves."
  (agile-gtd-org-mcp-test-with-fixtures
    (let ((resolves (lambda (key)
                      (not (agile-gtd-org-mcp-test-refusal
                            (lambda () (agile-gtd-org-mcp-test-view key))))))
          (listed (agile-gtd-org-mcp-test-listed-keys)))
      (ert-info ("the grammar's keys and the keys org-view lists are one set")
        (should (equal (sort (copy-sequence listed) #'string<)
                       (sort (append '("inbox" "tangling")
                                     (mapcan #'agile-gtd-org-mcp-test-area-keys
                                             agile-gtd-org-mcp-test-areas))
                             #'string<))))
      (dolist (key listed)
        (ert-info (key)
          (should (funcall resolves key))))
      (ert-info ("one more project is thirteen more keys, each resolving")
        (setq agile-gtd-projects (append agile-gtd-projects '((:tag "gamma"))))
        (agile-gtd-refresh)
        (let ((added (cl-set-difference (agile-gtd-org-mcp-test-listed-keys)
                                        listed :test #'equal)))
          (should (equal (sort added #'string<)
                         (sort (agile-gtd-org-mcp-test-area-keys "gamma-")
                               #'string<)))
          (dolist (key added)
            (ert-info (key)
              (should (funcall resolves key)))))))))


;;; Order and computed fields

(ert-deftest agile-gtd-org-mcp-results-come-in-rank-order ()
  "Every key answers most urgent first, by the rank it reports."
  (agile-gtd-org-mcp-test-with-fixtures
    (dolist (key '("next" "next-all" "private-backlog" "work-next" "backlog-someday"))
      (ert-info (key)
        (let ((ranks (mapcar (lambda (node) (agile-gtd-org-mcp-test-computed node 'rank))
                             (agile-gtd-org-mcp-test-view key))))
          (should (cdr ranks))
          (should (apply #'<= ranks)))))
    (ert-info ("what is due today leads")
      (should (member (car (agile-gtd-org-mcp-test-titles "next"))
                      '("Private todo scheduled today" "Private blocked due today"
                        "Private due tomorrow"))))))

(ert-deftest agile-gtd-org-mcp-nodes-carry-rank-parent-priority-and-blocked ()
  "Each node carries `rank', `parent-priority' and `blocked'."
  (agile-gtd-org-mcp-test-with-fixtures
    (let ((step (agile-gtd-org-mcp-test-node "work-next" "Work project step")))
      (should (= (agile-gtd-org-mcp-test-computed step 'rank) (agile-gtd--prio-rank ?C)))
      (should (= (agile-gtd-org-mcp-test-computed step 'parent-priority) ?C))
      (should (eq (agile-gtd-org-mcp-test-computed step 'blocked) :false)))
    (let ((blocked (agile-gtd-org-mcp-test-node "private-backlog" "Private chain blocked")))
      (should (eq (agile-gtd-org-mcp-test-computed blocked 'blocked) t)))
    (let ((due (agile-gtd-org-mcp-test-node "next-today" "Private blocked due today")))
      (should (eq (agile-gtd-org-mcp-test-computed due 'blocked) t))
      (should (<= (agile-gtd-org-mcp-test-computed due 'rank) 0)))))


;;; Refusals

(ert-deftest agile-gtd-org-mcp-refuses-an-unknown-key-with-the-valid-names ()
  "A mistyped key fails loudly and names the keys there are."
  (agile-gtd-org-mcp-test-with-fixtures
    (let ((message (agile-gtd-org-mcp-test-refusal
                    (lambda () (agile-gtd-org-mcp-test-view "alpah-next")))))
      (should message)
      (should (string-match-p "Unknown view" message))
      (should (string-match-p "alpha-next" message)))))

(ert-deftest agile-gtd-org-mcp-keys-refuse-filter-and-range ()
  "A key is the whole question: it takes no filter and no range."
  (agile-gtd-org-mcp-test-with-fixtures
    (dolist (key '("next" "private-backlog" "stuck" "inbox"))
      (ert-info (key)
        (should (string-match-p "takes no filter"
                                (agile-gtd-org-mcp-test-refusal
                                 (lambda () (agile-gtd-org-mcp-test-view key "work")))))
        (should (string-match-p "takes no range"
                                (agile-gtd-org-mcp-test-refusal
                                 (lambda () (agile-gtd-org-mcp-test-view
                                             key nil "sprint")))))))))


;;; Applying the configuration

(ert-deftest agile-gtd-org-mcp-enable-configures-org-mcp ()
  "The sort, the scope settings and the catalogue are set by the apply step."
  (agile-gtd-test-with-sandbox
    (setq org-mcp-allowed-files '("mine.org")
          org-mcp-file-scope-override '("~/elsewhere"))
    (agile-gtd-enable)
    (should (eq org-mcp-query-sort-fn #'agile-gtd--item-rank<))
    (should (null org-mcp-allowed-files))
    (should (eq org-mcp-file-scope-override t))
    (should (functionp org-mcp-view-catalogue-function))))

(ert-deftest agile-gtd-org-mcp-flag-off-configures-nothing ()
  "With `agile-gtd-enable-org-mcp' off, org-mcp is left exactly as it was."
  (agile-gtd-test-with-sandbox
    (let* ((agile-gtd-enable-org-mcp nil)
           (agile-gtd-projects agile-gtd-org-mcp-test-projects)
           (views '((mine :query (todo))))
           (computed '((mine . ignore)))
           (files '("mine.org"))
           (org-mcp-views (copy-tree views))
           (org-mcp-computed-fields (copy-tree computed))
           (org-mcp-allowed-files (copy-sequence files))
           (org-mcp-file-scope-override nil)
           (org-mcp-query-sort-fn nil)
           (org-mcp-view-catalogue-function nil))
      (agile-gtd-enable)
      (ert-info ("org-view knows the user's view and no key")
        (should-not (agile-gtd-org-mcp-test-refusal
                     (lambda () (agile-gtd-org-mcp-test-view "mine"))))
        (should (equal (agile-gtd-org-mcp-test-listed-keys) '("mine"))))
      (should (equal org-mcp-computed-fields computed))
      (should (equal org-mcp-allowed-files files))
      (should (null org-mcp-file-scope-override))
      (should (null org-mcp-query-sort-fn))
      (should (null org-mcp-view-catalogue-function)))))

(ert-deftest agile-gtd-org-mcp-user-views-and-fields-survive-a-refresh ()
  "agile-gtd replaces only its own keys and fields, however often it refreshes.
A view and a computed field of the user's own answer through the tool after
every refresh; one the user named like an agile-gtd key or field answers as
agile-gtd's."
  (agile-gtd-org-mcp-test-with-fixtures
    (setq org-mcp-views (append org-mcp-views
                                (list (list 'mine :query '(tags "#inbox"))
                                      (list 'next :query '(todo "DONE"))))
          org-mcp-computed-fields (append org-mcp-computed-fields
                                          (list (cons 'mine (lambda () "own value"))
                                                (cons 'rank (lambda () "stale")))))
    (dotimes (refresh 2)
      (agile-gtd-refresh)
      (ert-info ((format "after refresh %d" (1+ refresh)))
        (let ((nodes (agile-gtd-org-mcp-test-view "mine")))
          (should (equal (mapcar (lambda (node) (alist-get 'title node)) nodes)
                         '("Inbox capture")))
          (should (equal (agile-gtd-org-mcp-test-computed (car nodes) 'mine)
                         "own value")))
        (ert-info ("agile-gtd's own names answer as agile-gtd's")
          (let ((node (agile-gtd-org-mcp-test-node "next" "Private sprint action")))
            (should node)
            (should (= (agile-gtd-org-mcp-test-computed node 'rank)
                       (agile-gtd--prio-rank ?A))))
          (should-not (member "Finished parent"
                              (agile-gtd-org-mcp-test-titles "next"))))
        (ert-info ("a refresh lists nothing twice")
          (let ((listed (agile-gtd-org-mcp-test-listed-keys)))
            (should (equal listed (delete-dups (copy-sequence listed))))
            (should (member "mine" listed))))))))

(ert-deftest agile-gtd-org-mcp-keys-follow-the-registry-on-refresh ()
  "A project added before a refresh resolves at once; a removed one is gone."
  (agile-gtd-org-mcp-test-with-fixtures
    (should-error (agile-gtd-org-mcp-test-view "gamma-next"))
    (setq agile-gtd-projects (append agile-gtd-projects '((:tag "gamma"))))
    (agile-gtd-refresh)
    (should-not (agile-gtd-org-mcp-test-refusal
                 (lambda () (agile-gtd-org-mcp-test-view "gamma-next"))))
    (setq agile-gtd-projects '((:tag "alpha" :key ?a)))
    (agile-gtd-refresh)
    (should (agile-gtd-org-mcp-test-refusal
             (lambda () (agile-gtd-org-mcp-test-view "gamma-next"))))
    (should (agile-gtd-org-mcp-test-refusal
             (lambda () (agile-gtd-org-mcp-test-view "beta-next"))))))

(ert-deftest agile-gtd-org-mcp-catalogue-states-the-grammar ()
  "The org-view description states the grammar rather than listing every key."
  (agile-gtd-org-mcp-test-with-fixtures
    ;; The catalogue is filled to a paragraph; phrases are matched across
    ;; its line breaks.
    (let ((description (replace-regexp-in-string
                        "[ \n]+" " " (org-mcp--view-tool-description))))
      (should (string-match-p (regexp-quote "[<area>-]<view>[-<range>]") description))
      (dolist (word '("private" "work" "alpha" "beta"
                      "next" "backlog" "stuck" "inbox" "tangling"
                      "today" "sprint" "all" "someday"))
        (ert-info (word)
          (should (string-match-p (regexp-quote word) description))))
      (ert-info ("the per-area defaults")
        (should (string-match-p "sprint for everything and private" description))
        (should (string-match-p "backlog for work, alpha and beta" description)))
      (ert-info ("no line per key")
        (should-not (string-match-p "alpha-next-someday" description))))))

(provide 'agile-gtd-org-mcp-test)
;;; agile-gtd-org-mcp-test.el ends here
