;;; agile-gtd-test.el --- Tests for agile-gtd -*- lexical-binding: t; -*-

(require 'ert)
(require 'org)
(require 'org-agenda)
(require 'org-capture)
(require 'org-modern)
(require 'agile-gtd)

(defmacro agile-gtd-test-with-sandbox (&rest body)
  "Run BODY with isolated Org and Agile GTD state."
  (declare (indent 0) (debug t))
  `(let* ((tmpdir (make-temp-file "agile-gtd-test-" t))
          (org-directory tmpdir)
          (org-agenda-files nil)
          (org-agenda-diary-file nil)
          (org-agenda-custom-commands nil)
          (org-capture-templates nil)
          (org-refile-targets nil)
          (org-refile-use-outline-path nil)
          (org-outline-path-complete-in-steps nil)
          (org-refile-allow-creating-parent-nodes nil)
          (org-stuck-projects nil)
          (org-super-agenda-header-separator nil)
          (org-tag-alist '(("@home" . ?h)))
          (org-todo-keywords nil)
          (org-todo-repeat-to-state nil)
          (org-todo-keyword-faces nil)
          (org-priority-highest ?A)
          (org-priority-default ?B)
          (org-priority-lowest ?C)
          (org-priority-faces nil)
          (org-modern-priority nil)
          (agile-gtd-projects nil)
          (agile-gtd-enable-agenda-files t)
          (agile-gtd-enable-refile-targets t)
          (agile-gtd-enable-org-modern-visuals t)
          (agile-gtd-enable-org-records-mcp t)
          (agile-gtd--org-records-mcp-view-names nil)
          (org-records-mcp-views nil)
          (org-records-mcp-computed-fields nil)
          (org-records-mcp-query-sort-fn nil)
          (org-records-mcp-view-catalogue-function nil)
          (org-records-mcp-allowed-files nil)
          (org-records-mcp-file-scope-override nil)
          (agile-gtd-enable-org-settings t)
          (org-edna-mode nil)
          (org-blocker-hook nil)
          (org-trigger-hook nil)
          (org-enforce-todo-dependencies nil)
          (org-enforce-todo-checkbox-dependencies nil)
          (org-agenda-dim-blocked-tasks t)
          (org-log-into-drawer org-log-into-drawer)
          (org-log-done org-log-done)
          (org-log-repeat org-log-repeat)
          (org-log-redeadline org-log-redeadline)
          (org-log-reschedule org-log-reschedule)
          (org-log-state-notes-insert-after-drawers
           org-log-state-notes-insert-after-drawers)
          (org-archive-location org-archive-location)
          (org-modules org-modules)
          (org-habit-show-habits org-habit-show-habits)
          (org-habit-preceding-days org-habit-preceding-days)
          (org-habit-following-days org-habit-following-days)
          (org-agenda-use-time-grid org-agenda-use-time-grid)
          (org-agenda-skip-scheduled-if-done org-agenda-skip-scheduled-if-done)
          (org-agenda-skip-unavailable-files org-agenda-skip-unavailable-files)
          (org-agenda-skip-deadline-if-done org-agenda-skip-deadline-if-done)
          (org-agenda-skip-timestamp-if-done org-agenda-skip-timestamp-if-done)
          (org-agenda-start-on-weekday org-agenda-start-on-weekday)
          (org-agenda-span org-agenda-span)
          (org-agenda-start-day org-agenda-start-day)
          (org-deadline-warning-days org-deadline-warning-days)
          (org-agenda-show-future-repeats org-agenda-show-future-repeats)
          (org-agenda-skip-deadline-prewarning-if-scheduled
           org-agenda-skip-deadline-prewarning-if-scheduled)
          (org-agenda-tags-todo-honor-ignore-options
           org-agenda-tags-todo-honor-ignore-options)
          (org-agenda-skip-scheduled-delay-if-deadline
           org-agenda-skip-scheduled-delay-if-deadline)
          (org-agenda-skip-scheduled-if-deadline-is-shown
           org-agenda-skip-scheduled-if-deadline-is-shown)
          (org-agenda-skip-timestamp-if-deadline-is-shown
           org-agenda-skip-timestamp-if-deadline-is-shown)
          (org-agenda-todo-list-sublevels org-agenda-todo-list-sublevels)
          (org-agenda-include-deadlines org-agenda-include-deadlines)
          (org-use-property-inheritance org-use-property-inheritance)
          (org-use-tag-inheritance org-use-tag-inheritance))
     (unwind-protect
         (progn
           ,@body)
       (ignore-errors (org-super-agenda-mode -1))
       (delete-directory tmpdir t))))

(ert-deftest agile-gtd-enable-applies-core-settings ()
  (agile-gtd-test-with-sandbox
    (let ((agile-gtd-projects '((:tag "projects"))))
      (agile-gtd-enable)
      (should org-super-agenda-mode)
      (should (equal org-agenda-files
                     (mapcar (lambda (file)
                               (expand-file-name file org-directory))
                             '("inbox.org"
                               "todo.org"
                               "projects.org"))))
      (should (equal org-agenda-diary-file
                     (expand-file-name "diary.org" org-directory)))
      (should (= org-priority-highest agile-gtd-priority-highest))
      (should (= org-priority-default agile-gtd-priority-default))
      (should (= org-priority-lowest agile-gtd-priority-lowest))
      (should (equal org-priority-faces (agile-gtd--priority-faces)))
      (should (equal org-modern-priority (agile-gtd--priority-symbols)))
      (should (equal org-todo-keywords agile-gtd-todo-keywords))
      (should (equal org-todo-repeat-to-state agile-gtd-todo-repeat-to-state))
      (should (equal org-refile-targets
                     '((nil :maxlevel . 9)
                       (org-agenda-files :maxlevel . 4)
                       (agile-gtd--someday-files :maxlevel . 4))))
      (should (equal org-stuck-projects (agile-gtd--stuck-projects-setting)))
      (should (assoc "P" org-capture-templates))
      (should (assoc "a" org-agenda-custom-commands)))))

(ert-deftest agile-gtd-enable-applies-org-settings ()
  "Enabling sets the Org options the workflow depends on."
  (agile-gtd-test-with-sandbox
    (agile-gtd-enable)
    (ert-info ("Dependencies")
      (should org-edna-mode)
      (should (memq #'org-edna-blocker-function org-blocker-hook))
      (should (memq #'org-edna-trigger-function org-trigger-hook))
      (should-not org-enforce-todo-dependencies)
      (should-not org-enforce-todo-checkbox-dependencies)
      (should (eq org-agenda-dim-blocked-tasks 'invisible)))
    (ert-info ("Logging")
      (should (eq org-log-into-drawer t))
      (should (eq org-log-done 'time+note))
      (should (eq org-log-repeat 'time))
      (should (eq org-log-redeadline 'time))
      (should (eq org-log-reschedule 'time))
      (should-not org-log-state-notes-insert-after-drawers))
    (ert-info ("Archive and habits")
      (should (equal org-archive-location
                     (expand-file-name "archive/%s::datetree" org-directory)))
      (should (featurep 'org-habit))
      (should (memq 'org-habit org-modules))
      (should (eq org-habit-show-habits t))
      (should (= org-habit-preceding-days 14))
      (should (= org-habit-following-days 7)))
    (ert-info ("Agenda behaviour")
      (should (eq org-agenda-span 'day))
      (should (equal org-agenda-start-day "-0d"))
      (should-not org-agenda-start-on-weekday)
      (should (= org-deadline-warning-days 7))
      (should (eq org-agenda-skip-unavailable-files t))
      (should (eq org-agenda-skip-scheduled-if-done t))
      (should (eq org-agenda-skip-deadline-if-done t))
      (should (eq org-agenda-skip-timestamp-if-done t))
      (should (eq org-agenda-skip-deadline-prewarning-if-scheduled t))
      (should (eq org-agenda-skip-scheduled-delay-if-deadline t))
      (should (eq org-agenda-skip-scheduled-if-deadline-is-shown t))
      (should (eq org-agenda-skip-timestamp-if-deadline-is-shown t))
      (should (eq org-agenda-show-future-repeats t))
      (should (eq org-agenda-tags-todo-honor-ignore-options t))
      (should (eq org-agenda-todo-list-sublevels t))
      (should (eq org-agenda-include-deadlines t))
      (should (eq org-agenda-use-time-grid t)))
    (ert-info ("Inheritance")
      (should (eq org-use-property-inheritance t))
      (should (eq org-use-tag-inheritance t)))))

(ert-deftest agile-gtd-enable-removes-org-own-blockers ()
  "Org's own dependency blockers leave `org-blocker-hook' with their options.
Setting the options is not enough: Org installs those blockers from the
options' Customize setters, which a plain assignment does not run."
  (agile-gtd-test-with-sandbox
    (setq org-enforce-todo-dependencies t
          org-enforce-todo-checkbox-dependencies t)
    (add-hook 'org-blocker-hook #'org-block-todo-from-children-or-siblings-or-parent)
    (add-hook 'org-blocker-hook #'org-block-todo-from-checkboxes)
    (agile-gtd-enable)
    (should (equal org-blocker-hook (list #'org-edna-blocker-function)))))

(ert-deftest agile-gtd-enable-org-settings-archive-follows-org-directory ()
  "The archive location is read from `org-directory' on every refresh."
  (agile-gtd-test-with-sandbox
    (agile-gtd-enable)
    (let ((org-directory (expand-file-name "elsewhere" org-directory)))
      (agile-gtd-refresh)
      (should (equal org-archive-location
                     (expand-file-name "archive/%s::datetree" org-directory))))))

(ert-deftest agile-gtd-refresh-applies-org-settings-once ()
  "Refreshing again adds no second habit module or Edna hook."
  (agile-gtd-test-with-sandbox
    (agile-gtd-enable)
    (agile-gtd-refresh)
    (should (= 1 (cl-count 'org-habit org-modules)))
    (should (= 1 (cl-count #'org-edna-blocker-function org-blocker-hook)))
    (should (= 1 (cl-count #'org-edna-trigger-function org-trigger-hook)))))

(ert-deftest agile-gtd-enable-org-settings-off-leaves-org-alone ()
  "With `agile-gtd-enable-org-settings' off, enabling touches none of them."
  (agile-gtd-test-with-sandbox
    (let* ((agile-gtd-enable-org-settings nil)
           (variables '(org-agenda-dim-blocked-tasks org-log-into-drawer
                        org-log-done org-archive-location org-modules
                        org-habit-preceding-days org-agenda-span
                        org-deadline-warning-days org-use-property-inheritance))
           (before (mapcar #'symbol-value variables)))
      (agile-gtd-enable)
      (should-not org-edna-mode)
      (should-not org-blocker-hook)
      (should (equal (mapcar #'symbol-value variables) before)))))

(ert-deftest agile-gtd-refresh-does-not-duplicate-workflow-tags ()
  (agile-gtd-test-with-sandbox
    (let ((expected nil))
      (setq org-tag-alist '(("@home" . ?h)
                            ("custom" . ?c)))
      (setq expected (append (copy-tree org-tag-alist)
                             (agile-gtd--workflow-tag-alist)))
      (agile-gtd-refresh)
      (should (equal org-tag-alist expected))
      (agile-gtd-refresh)
      (should (equal org-tag-alist expected)))))

(ert-deftest agile-gtd-capture-templates-include-priority-and-protocol-support ()
  (agile-gtd-test-with-sandbox
    (let* ((templates (agile-gtd--capture-templates))
           (project (assoc "p" templates))
           (protocol (assoc "P" templates)))
      (should project)
      (should protocol)
      (should (string-match-p (regexp-quote (agile-gtd--priority-prompt-choices))
                              (nth 4 project)))
      (should (string-match-p (regexp-quote "agile-gtd--protocol-description")
                              (nth 4 protocol))))))

(ert-deftest agile-gtd-rank-groups-cover-the-range ()
  "Every group is accounted for, and the fixed ones lead in precedence order.
org-super-agenda gives an entry to the first group that claims it, so the
four listed here have to come before the priority bands: each recognises
something a band would otherwise swallow."
  (agile-gtd-test-with-sandbox
    (let* ((groups (agile-gtd-rank-groups))
           (fixed '("Tickler" "Someday" "Today & Overdue" "Scheduled")))
      ;; fixed + one per priority + the extra Default split + the catch-all
      (should (= (length groups)
                 (+ (length fixed) 2 (length (agile-gtd--priority-range)))))
      (should (equal (mapcar (lambda (g) (plist-get g :name))
                             (seq-take groups (length fixed)))
                     fixed))
      (should (equal (plist-get (car (last groups)) :name)
                     "Not Grouped")))))

(ert-deftest agile-gtd-query-helpers-return-stable-sexps ()
  (agile-gtd-test-with-sandbox
    (should (equal (agile-gtd-agenda-query-stuck-projects)
                   '(agile-gtd-stuck-proj)))
    (should (equal (agile-gtd-action-keywords)
                   '("NEXT" "WAIT")))
    (should (equal (agile-gtd-project-keyword) "PROJ"))))

(ert-deftest agile-gtd-protocol-description-normalizes-brackets ()
  (should (equal (agile-gtd--protocol-description "[hello] [world]")
                 "(hello) (world)")))

(provide 'agile-gtd-test)
;;; agile-gtd-test.el ends here
