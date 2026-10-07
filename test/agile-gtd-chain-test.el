;;; agile-gtd-chain-test.el --- Logging along an org-edna chain -*- lexical-binding: t; -*-

;;; Commentary:

;; Closing a step of an org-edna chain changes two headings in one command:
;; the step closed and the sibling its TRIGGER moves to NEXT.  Both changes
;; log, and Org keeps one log entry pending at a time.  These tests close a
;; step the two ways it is closed, by `org-todo' as a key does and through
;; org-records-mcp's set-todo tool with a note, and assert that each heading
;; ends up with its own entry.

;;; Code:

(require 'ert)
(require 'agile-gtd)
(require 'agile-gtd-test)
(require 'agile-gtd-loop-test)

(defconst agile-gtd-chain-test-release
  (concat "* PROJ Release\n"
          "** NEXT PR preparations\n"
          ":PROPERTIES:\n:TRIGGER:  next-sibling todo!(NEXT)\n:END:\n"
          "** TODO PR merged\n"
          ":PROPERTIES:\n:BLOCKER:  previous-sibling\n:TRIGGER:  next-sibling todo!(NEXT)\n:END:\n"
          "** TODO Tag the release\n"
          ":PROPERTIES:\n:BLOCKER:  previous-sibling\n:END:\n")
  "A chain of three steps, the first one actionable.")

(defun agile-gtd-chain-test-assert-each-step-logged-its-own (buffer note)
  "Assert the closed step in BUFFER logged NOTE and the triggered one its time."
  (let ((closed (agile-gtd-loop-test-entry buffer "DONE PR preparations"))
        (triggered (agile-gtd-loop-test-entry buffer "NEXT PR merged"))
        (untouched (agile-gtd-loop-test-entry buffer "TODO Tag the release")))
    (ert-info ("the closed step carries its DONE entry and the note")
      (should (= (length (plist-get closed :logbook)) 2))
      (should (string-match-p "\\`- State \"DONE\" +from \"NEXT\" +\\[.*\\] \\\\\\\\\\'"
                              (car (plist-get closed :logbook))))
      (should (equal (cadr (plist-get closed :logbook)) note)))
    (ert-info ("the triggered step logs when it became NEXT, and nothing more")
      (should (= (length (plist-get triggered :logbook)) 1))
      (should (string-match-p "\\`- State \"NEXT\" +from \"TODO\" +\\[.*\\]\\'"
                              (car (plist-get triggered :logbook)))))
    (ert-info ("the step after it is untouched")
      (should-not (plist-get untouched :logbook)))))

(ert-deftest agile-gtd-chain-closing-a-step-asks-for-its-own-note ()
  "Closing a chained step asks for the DONE note, and it lands on that step.
The trigger moving the next step to NEXT logs that change at once."
  (agile-gtd-loop-test-with-file agile-gtd-chain-test-release
    (agile-gtd-loop-test-goto buffer "NEXT PR preparations")
    (with-current-buffer buffer (org-todo "DONE"))
    (should (equal (agile-gtd-loop-test-write-note "Opened the PR")
                   "# Insert note for state change from \"NEXT\" to \"DONE\"."))
    (should-not (agile-gtd-loop-test-note-pending-p))
    (agile-gtd-chain-test-assert-each-step-logged-its-own buffer "Opened the PR")))

(ert-deftest agile-gtd-chain-closing-a-step-through-org-records-mcp-keeps-its-note ()
  "A note sent with org-records-mcp's set-todo lands on the step it closed."
  (agile-gtd-loop-test-with-file agile-gtd-chain-test-release
    (org-records-mcp--tool-node-set-todo
     (format "file:%s::*PR preparations" file) "NEXT" "DONE" nil "Opened the PR")
    (should-not (agile-gtd-loop-test-note-pending-p))
    (agile-gtd-chain-test-assert-each-step-logged-its-own buffer "Opened the PR")))

(ert-deftest agile-gtd-chain-advice-follows-the-org-settings-step ()
  "The advice comes with the org-edna-mode agile-gtd turns on, and goes without it.
With `agile-gtd-enable-org-settings' off, org-edna's action is its own."
  (agile-gtd-test-with-sandbox
    (agile-gtd-enable)
    (should (advice-member-p #'agile-gtd--org-edna-todo-keep-log-a 'org-edna-action/todo!))
    (let ((agile-gtd-enable-org-settings nil))
      (agile-gtd-refresh))
    (should-not (advice-member-p #'agile-gtd--org-edna-todo-keep-log-a
                                 'org-edna-action/todo!))))

(provide 'agile-gtd-chain-test)
;;; agile-gtd-chain-test.el ends here
