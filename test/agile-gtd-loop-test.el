;;; agile-gtd-loop-test.el --- The agent/human loop: whose move an item is -*- lexical-binding: t; -*-

;;; Commentary:

;; Two tags say whose move an item is: `agent' and `human'.  These tests
;; cover what agile-gtd does with them: it keeps them from passing to child
;; headings without touching the user's own exclusions, hands an item to the
;; agent with `agile-gtd-hand-over', and lists the human's moves under `h'.
;;
;; A hand-over asks for its note the way Org does, from `post-command-hook'
;; once the command returns.  The tests take that note as a user does: they
;; run the pending `org-add-log-note', type into *Org Note* and finish it.

;;; Code:

(require 'ert)
(require 'agile-gtd)
(require 'agile-gtd-test)


;;; Inheritance

(defun agile-gtd-loop-test-tags-of (text heading)
  "Return the tags Org gives HEADING in an Org buffer holding TEXT."
  (with-temp-buffer
    (org-mode)
    (insert text)
    (goto-char (point-min))
    (re-search-forward (concat "^\\*+ " (regexp-quote heading)))
    (org-get-tags)))

(ert-deftest agile-gtd-loop-tags-stay-on-their-heading ()
  "A loop tag on a project does not hand its children over; other tags still pass."
  (agile-gtd-test-with-sandbox
    (agile-gtd-enable)
    (let ((text "* PROJ Project :human:agent:#work:\n** NEXT Step\n"))
      (should (equal (agile-gtd-loop-test-tags-of text "PROJ Project")
                     '("human" "agent" "#work")))
      (should (equal (agile-gtd-loop-test-tags-of text "NEXT Step") '("#work"))))))

(ert-deftest agile-gtd-loop-tags-keep-the-user-s-own-exclusions ()
  "The loop tags join the user's exclusions once, however often it refreshes."
  (agile-gtd-test-with-sandbox
    (setq org-tags-exclude-from-inheritance '("crypt"))
    (agile-gtd-enable)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "agent" "human")))
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "agent" "human")))))

(ert-deftest agile-gtd-loop-tags-follow-the-list-on-refresh ()
  "An extra tag added to the list is excluded on refresh, and one dropped is not.
The agent and human tags stay excluded whatever the list holds."
  (agile-gtd-test-with-sandbox
    (setq org-tags-exclude-from-inheritance '("crypt"))
    (agile-gtd-enable)
    (setq agile-gtd-loop-tags '("jira"))
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "agent" "human" "jira")))
    (setq agile-gtd-loop-tags nil)
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "agent" "human")))))

(ert-deftest agile-gtd-loop-tags-follow-a-renamed-tag ()
  "Renaming the agent or human tag excludes the new name and frees the old one."
  (agile-gtd-test-with-sandbox
    (setq org-tags-exclude-from-inheritance '("crypt"))
    (agile-gtd-enable)
    (setq agile-gtd-agent-tag "ai"
          agile-gtd-human-tag "me")
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "ai" "me")))
    (should (equal (agile-gtd-loop-test-tags-of "* PROJ Project :ai:me:\n** NEXT Step\n"
                                                "NEXT Step")
                   nil))))

(ert-deftest agile-gtd-loop-tags-never-take-a-user-exclusion-away ()
  "A tag the user excluded before agile-gtd did stays excluded when the list drops it."
  (agile-gtd-test-with-sandbox
    (setq org-tags-exclude-from-inheritance '("crypt" "jira" "human"))
    (setq agile-gtd-loop-tags '("jira"))
    (agile-gtd-enable)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "jira" "human" "agent")))
    (setq agile-gtd-loop-tags nil
          agile-gtd-human-tag "me")
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "jira" "human" "agent" "me")))))

(ert-deftest agile-gtd-loop-tags-are-excluded-with-the-org-settings-off ()
  "The loop depends on the exclusion, so it runs whatever `agile-gtd-enable-org-settings' says."
  (agile-gtd-test-with-sandbox
    (let ((agile-gtd-enable-org-settings nil))
      (setq org-tags-exclude-from-inheritance '("crypt"))
      (agile-gtd-enable)
      (should (equal org-tags-exclude-from-inheritance '("crypt" "agent" "human"))))))


;;; Handing over

(defmacro agile-gtd-loop-test-with-file (content &rest body)
  "Run BODY after `agile-gtd-enable' with `buffer' visiting a file holding CONTENT.
The file is the only agenda file."
  (declare (indent 1) (debug t))
  `(agile-gtd-test-with-sandbox
     (let ((file (expand-file-name "loop.org" org-directory))
           (org-agenda-window-setup 'current-window)
           (org-agenda-sticky nil))
       (with-temp-file file (insert ,content))
       (agile-gtd-enable)
       (setq org-agenda-files (list file))
       (let ((buffer (find-file-noselect file)))
         (unwind-protect
             (save-window-excursion ,@body)
           (when-let* ((agenda (get-buffer org-agenda-buffer-name)))
             (kill-buffer agenda))
           (when-let* ((note (get-buffer "*Org Note*")))
             (kill-buffer note))
           (remove-hook 'post-command-hook #'org-add-log-note)
           (with-current-buffer buffer (set-buffer-modified-p nil))
           (kill-buffer buffer))))))

(defun agile-gtd-loop-test-goto (buffer heading)
  "Move point in BUFFER to the line of HEADING, matched after the stars."
  (with-current-buffer buffer
    (goto-char (point-min))
    (re-search-forward (concat "^\\*+ " (regexp-quote heading)))
    (beginning-of-line)))

(defun agile-gtd-loop-test-note-pending-p ()
  "Non-nil when Org waits to ask for a note once the command returns.
Org adds its prompt to the global `post-command-hook'; an agenda buffer
keeps a local value of its own, which runs the global one."
  (memq #'org-add-log-note (default-value 'post-command-hook)))

(defun agile-gtd-loop-test-write-note (text)
  "Take the note Org is waiting for, as a user does, typing TEXT.
Return the instruction line *Org Note* opens with, which names what the
note is for.  Signals a test failure when no note is pending."
  (should (agile-gtd-loop-test-note-pending-p))
  (org-add-log-note)
  (with-current-buffer "*Org Note*"
    (let ((purpose (buffer-substring-no-properties
                    (point-min) (save-excursion (goto-char (point-min))
                                                (line-end-position)))))
      (goto-char (point-max))
      (insert text)
      (funcall org-finish-function)
      purpose)))

(defun agile-gtd-loop-test-entry (buffer heading)
  "Return HEADING's state, own tags and LOGBOOK entries in BUFFER.
The entries are the drawer's lines between its delimiters, trimmed."
  (with-current-buffer buffer
    (save-excursion
      (agile-gtd-loop-test-goto buffer heading)
      (let* ((end (save-excursion (outline-next-heading) (point)))
             (logbook (when (re-search-forward "^[ \t]*:LOGBOOK:\n\\(\\(?:.*\n\\)*?\\)[ \t]*:END:" end t)
                        (mapcar #'string-trim
                                (split-string (match-string-no-properties 1) "\n" t)))))
        (agile-gtd-loop-test-goto buffer heading)
        (list :state (org-get-todo-state)
              :tags (org-get-tags nil t)
              :logbook logbook)))))

(ert-deftest agile-gtd-hand-over-moves-an-action-to-wait-with-one-note ()
  "A TODO or NEXT item goes to WAIT, and the one note asked is the WAIT note.
The human tag leaves, the agent tag arrives, and other tags stay."
  (dolist (state '("TODO" "NEXT"))
    (ert-info (state)
      (agile-gtd-loop-test-with-file
          (format "* %s [#A] Draft the reply :human:#work:\n" state)
        (agile-gtd-loop-test-goto buffer "")
        (with-current-buffer buffer (agile-gtd-hand-over))
        (should (equal (agile-gtd-loop-test-write-note "Over to you")
                       (format "# Insert note for state change from \"%s\" to \"WAIT\"."
                               state)))
        (ert-info ("no second note is pending")
          (should-not (agile-gtd-loop-test-note-pending-p)))
        (let ((entry (agile-gtd-loop-test-entry buffer "WAIT")))
          (should (equal (plist-get entry :state) "WAIT"))
          (should (equal (plist-get entry :tags) '("#work" "agent")))
          (should (= (length (plist-get entry :logbook)) 2))
          (should (string-match-p
                   (format "\\`- State \"WAIT\" +from \"%s\" +\\[.*\\] \\\\\\\\\\'" state)
                   (car (plist-get entry :logbook))))
          (should (equal (cadr (plist-get entry :logbook)) "Over to you")))))))

(ert-deftest agile-gtd-hand-over-keeps-any-other-state-and-takes-a-plain-note ()
  "A project, an epic, a waiting item or a plain heading keeps its state.
The note is an ordinary LOGBOOK note."
  (dolist (state '("PROJ" "EPIC" "WAIT" nil))
    (ert-info ((or state "no keyword"))
      (agile-gtd-loop-test-with-file
          (format "* %sQuestion for the agent :human:\n" (if state (concat state " ") ""))
        (agile-gtd-loop-test-goto buffer "")
        (with-current-buffer buffer (agile-gtd-hand-over))
        (should (equal (agile-gtd-loop-test-write-note "Please research")
                       "# Insert note for this entry."))
        (should-not (agile-gtd-loop-test-note-pending-p))
        (let ((entry (agile-gtd-loop-test-entry buffer "")))
          (should (equal (plist-get entry :state) state))
          (should (equal (plist-get entry :tags) '("agent")))
          (should (= (length (plist-get entry :logbook)) 2))
          (should (string-match-p "\\`- Note taken on \\[.*\\] \\\\\\\\\\'"
                                  (car (plist-get entry :logbook))))
          (should (equal (cadr (plist-get entry :logbook)) "Please research")))))))

(ert-deftest agile-gtd-hand-over-takes-an-empty-note ()
  "An empty note still hands the item over: the tag and the dated state change."
  (agile-gtd-loop-test-with-file "* NEXT Draft the reply :human:\n"
    (agile-gtd-loop-test-goto buffer "NEXT")
    (with-current-buffer buffer (agile-gtd-hand-over))
    (agile-gtd-loop-test-write-note "")
    (let ((entry (agile-gtd-loop-test-entry buffer "WAIT")))
      (should (equal (plist-get entry :tags) '("agent")))
      (should (= (length (plist-get entry :logbook)) 1))
      (should (string-match-p "\\`- State \"WAIT\" +from \"NEXT\" +\\[.*\\]\\'"
                              (car (plist-get entry :logbook)))))))

(ert-deftest agile-gtd-hand-over-cancelled-note-keeps-the-hand-over ()
  "Cancelling the note leaves the item handed over, with nothing logged."
  (agile-gtd-loop-test-with-file "* NEXT Draft the reply :human:\n"
    (agile-gtd-loop-test-goto buffer "NEXT")
    (with-current-buffer buffer (agile-gtd-hand-over))
    (org-add-log-note)
    (with-current-buffer "*Org Note*"
      (insert "Never mind")
      (let ((org-note-abort t))
        (funcall org-finish-function)))
    (should-not (agile-gtd-loop-test-note-pending-p))
    (let ((entry (agile-gtd-loop-test-entry buffer "WAIT")))
      (should (equal (plist-get entry :tags) '("agent")))
      (should-not (plist-get entry :logbook)))))

(ert-deftest agile-gtd-hand-over-refuses-a-closed-item ()
  "A done item is no one's move: handing it over changes nothing and asks nothing."
  (dolist (state '("DONE" "IDEA" "KILL"))
    (ert-info (state)
      (agile-gtd-loop-test-with-file (format "* %s Old question :human:\n" state)
        (agile-gtd-loop-test-goto buffer "")
        (should-error (with-current-buffer buffer (agile-gtd-hand-over))
                      :type 'user-error)
        (should-not (agile-gtd-loop-test-note-pending-p))
        (let ((entry (agile-gtd-loop-test-entry buffer "")))
          (should (equal (plist-get entry :state) state))
          (should (equal (plist-get entry :tags) '("human"))))))))

(ert-deftest agile-gtd-hand-over-changes-nothing-when-wait-is-refused ()
  "When the item cannot move to WAIT, its tags stay as they were."
  (agile-gtd-loop-test-with-file
      "#+TODO: TODO NEXT | DONE\n* NEXT Draft the reply :human:\n"
    (agile-gtd-loop-test-goto buffer "NEXT")
    (with-current-buffer buffer
      (org-mode)
      (should-error (agile-gtd-hand-over) :type 'user-error))
    (should-not (agile-gtd-loop-test-note-pending-p))
    (let ((entry (agile-gtd-loop-test-entry buffer "NEXT")))
      (should (equal (plist-get entry :state) "NEXT"))
      (should (equal (plist-get entry :tags) '("human"))))))

(ert-deftest agile-gtd-hand-over-takes-one-item-whatever-the-region ()
  "An active region does not spread the state change over the headings in it."
  (agile-gtd-loop-test-with-file
      "* NEXT First reply :human:\n* NEXT Second reply :human:\n"
    (with-current-buffer buffer
      (let ((org-loop-over-headlines-in-active-region t)
            (transient-mark-mode t))
        (goto-char (point-max))
        (set-mark (point))
        (goto-char (point-min))
        (activate-mark)
        (should (region-active-p))
        (agile-gtd-hand-over)
        (deactivate-mark)))
    (agile-gtd-loop-test-write-note "Over to you")
    (let ((first (agile-gtd-loop-test-entry buffer "WAIT First"))
          (second (agile-gtd-loop-test-entry buffer "NEXT Second")))
      (should (equal (plist-get first :tags) '("agent")))
      (should (equal (plist-get second :tags) '("human"))))))

(ert-deftest agile-gtd-hand-over-works-on-the-agenda-item-at-point ()
  "From an agenda line, the item in its Org file is handed over the same way."
  (agile-gtd-loop-test-with-file
      (concat "* NEXT [#A] Draft the reply :human:\n"
              "* PROJ [#B] Plan the release :human:\n"
              "** NEXT Collect the changes\n")
    (org-agenda nil "h")
    (with-current-buffer org-agenda-buffer-name
      (goto-char (point-min))
      (search-forward "Draft the reply")
      (agile-gtd-hand-over))
    (should (string-match-p "state change from \"NEXT\" to \"WAIT\""
                            (agile-gtd-loop-test-write-note "Over to you")))
    (with-current-buffer org-agenda-buffer-name
      (goto-char (point-min))
      (search-forward "Plan the release")
      (agile-gtd-hand-over))
    (should (equal (agile-gtd-loop-test-write-note "Split it up")
                   "# Insert note for this entry."))
    (let ((action (agile-gtd-loop-test-entry buffer "WAIT"))
          (project (agile-gtd-loop-test-entry buffer "PROJ")))
      (should (equal (plist-get action :tags) '("agent")))
      (should (equal (cadr (plist-get action :logbook)) "Over to you"))
      (should (equal (plist-get project :state) "PROJ"))
      (should (equal (plist-get project :tags) '("agent")))
      (should (equal (cadr (plist-get project :logbook)) "Split it up")))
    (ert-info ("the agenda line shows the new state and tag")
      (with-current-buffer org-agenda-buffer-name
        (goto-char (point-min))
        (should (re-search-forward "WAIT .*Draft the reply.*:agent:" nil t))))))

(ert-deftest agile-gtd-hand-over-leaves-a-waiting-action-in-the-next-actions ()
  "An action handed to the agent is a WAIT like any other: still a next action."
  (agile-gtd-loop-test-with-file "* NEXT [#A] Draft the reply :human:\n"
    (agile-gtd-loop-test-goto buffer "NEXT")
    (with-current-buffer buffer (agile-gtd-hand-over))
    (agile-gtd-loop-test-write-note "Over to you")
    (should (equal (org-ql-select buffer (agile-gtd-agenda-query-next-actions)
                     :action '(org-get-heading t t t t))
                   '("Draft the reply")))))


;;; The human's moves

(defconst agile-gtd-loop-test-moves
  (concat "* NEXT [#A] Chain first\n"
          "* NEXT [#C] Blocked question :human:\n"
          ":PROPERTIES:\n:BLOCKER:  previous-sibling\n:END:\n"
          "* TODO [#B] Question for the human :human:\n"
          "* PROJ [#F] Project for the human :human:\n"
          "** NEXT Step under the human's project\n"
          "* DONE Answered question :human:\n"
          "* NEXT [#A] The agent's move :agent:\n"
          "* Plain heading for the human :human:\n")
  "Items whose move is the human's, the agent's, or nobody's.")

(ert-deftest agile-gtd-agenda-human-view-lists-the-human-s-moves ()
  "`h' lists the open items tagged `human' themselves, by rank, blocked ones too."
  (agile-gtd-loop-test-with-file agile-gtd-loop-test-moves
    (org-agenda nil "h")
    (let ((text (with-current-buffer org-agenda-buffer-name
                  (buffer-substring-no-properties (point-min) (point-max))))
          (moves '("Question for the human" "Blocked question" "Project for the human")))
      (should (string-match-p "My Moves" text))
      (ert-info ("most urgent first")
        (let ((positions (mapcar (lambda (title) (string-search title text)) moves)))
          (should (cl-every #'identity positions))
          (should (apply #'< positions))))
      (ert-info ("the blocked one shown dimmed, where blocked tasks are hidden")
        (should (eq org-agenda-dim-blocked-tasks 'invisible))
        (with-current-buffer org-agenda-buffer-name
          (goto-char (point-min))
          (search-forward "Blocked question")
          (let ((pos (match-beginning 0)))
            (should-not (invisible-p pos))
            (should (cl-some (lambda (ov)
                               (eq (overlay-get ov 'face) 'org-agenda-dimmed-todo-face))
                             (overlays-at pos))))))
      (dolist (other '("Step under the human's project" "Answered question"
                       "The agent's move" "Plain heading for the human" "Chain first"))
        (ert-info (other)
          (should-not (string-search other text)))))))

(ert-deftest agile-gtd-agenda-query-human-reads-the-tag-off-the-item-alone ()
  "A step under a project tagged `human' is not a move of the human's.
That holds even where Org lets the tag pass to children."
  (agile-gtd-loop-test-with-file agile-gtd-loop-test-moves
    (setq org-tags-exclude-from-inheritance nil)
    (should (equal (org-ql-select buffer (agile-gtd-agenda-query-human)
                     :action '(org-get-heading t t t t))
                   '("Blocked question" "Question for the human" "Project for the human")))))

(ert-deftest agile-gtd-agenda-human-view-keeps-its-header-when-empty ()
  "With no move of the human's open, `h' still says what it is."
  (agile-gtd-loop-test-with-file "* NEXT [#A] The agent's move :agent:\n"
    (org-agenda nil "h")
    (with-current-buffer org-agenda-buffer-name
      (should (string-search "My Moves" (buffer-string))))))

(provide 'agile-gtd-loop-test)
;;; agile-gtd-loop-test.el ends here
