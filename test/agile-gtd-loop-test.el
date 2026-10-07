;;; agile-gtd-loop-test.el --- The agent/human loop: whose move an item is -*- lexical-binding: t; -*-

;;; Commentary:

;; Two tags say whose move an item is: `agent' and `human'.  These tests
;; cover what agile-gtd does with them: it keeps them from passing to child
;; headings without touching the user's own exclusions, hands an item to the
;; agent with `agile-gtd-hand-over', tells whose turn an item is from its
;; tags, state and claim, and lists each turn under `h'.
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

(ert-deftest agile-gtd-loop-tags-carry-a-percent-prefix-by-default ()
  "The agent and human tags are `%agent' and `%human' unless configured."
  (should (equal (eval (car (get 'agile-gtd-agent-tag 'standard-value)) t) "%agent"))
  (should (equal (eval (car (get 'agile-gtd-human-tag 'standard-value)) t) "%human")))

(ert-deftest agile-gtd-loop-tags-stay-on-their-heading ()
  "A loop tag on a project does not hand its children over; other tags still pass."
  (agile-gtd-test-with-sandbox
    (agile-gtd-enable)
    (let ((text "* PROJ Project :%human:%agent:#work:\n** NEXT Step\n"))
      (should (equal (agile-gtd-loop-test-tags-of text "PROJ Project")
                     '("%human" "%agent" "#work")))
      (should (equal (agile-gtd-loop-test-tags-of text "NEXT Step") '("#work"))))))

(ert-deftest agile-gtd-loop-tags-keep-the-user-s-own-exclusions ()
  "The loop tags join the user's exclusions once, however often it refreshes."
  (agile-gtd-test-with-sandbox
    (setq org-tags-exclude-from-inheritance '("crypt"))
    (agile-gtd-enable)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "%agent" "%human")))
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "%agent" "%human")))))

(ert-deftest agile-gtd-loop-tags-follow-the-list-on-refresh ()
  "An extra tag added to the list is excluded on refresh, and one dropped is not.
The agent and human tags stay excluded whatever the list holds."
  (agile-gtd-test-with-sandbox
    (setq org-tags-exclude-from-inheritance '("crypt"))
    (agile-gtd-enable)
    (setq agile-gtd-loop-tags '("jira"))
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "%agent" "%human" "jira")))
    (setq agile-gtd-loop-tags nil)
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "%agent" "%human")))))

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
    (setq org-tags-exclude-from-inheritance '("crypt" "jira" "%human"))
    (setq agile-gtd-loop-tags '("jira"))
    (agile-gtd-enable)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "jira" "%human" "%agent")))
    (setq agile-gtd-loop-tags nil
          agile-gtd-human-tag "me")
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "jira" "%human" "%agent" "me")))))

(ert-deftest agile-gtd-loop-tags-are-excluded-with-the-org-settings-off ()
  "The loop depends on the exclusion, so it runs whatever `agile-gtd-enable-org-settings' says."
  (agile-gtd-test-with-sandbox
    (let ((agile-gtd-enable-org-settings nil))
      (setq org-tags-exclude-from-inheritance '("crypt"))
      (agile-gtd-enable)
      (should (equal org-tags-exclude-from-inheritance '("crypt" "%agent" "%human"))))))


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
          (format "* %s [#A] Draft the reply :%%human:#work:\n" state)
        (agile-gtd-loop-test-goto buffer "")
        (with-current-buffer buffer (agile-gtd-hand-over))
        (should (equal (agile-gtd-loop-test-write-note "Over to you")
                       (format "# Insert note for state change from \"%s\" to \"WAIT\"."
                               state)))
        (ert-info ("no second note is pending")
          (should-not (agile-gtd-loop-test-note-pending-p)))
        (let ((entry (agile-gtd-loop-test-entry buffer "WAIT")))
          (should (equal (plist-get entry :state) "WAIT"))
          (should (equal (plist-get entry :tags) '("#work" "%agent")))
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
          (format "* %sQuestion for the agent :%%human:\n" (if state (concat state " ") ""))
        (agile-gtd-loop-test-goto buffer "")
        (with-current-buffer buffer (agile-gtd-hand-over))
        (should (equal (agile-gtd-loop-test-write-note "Please research")
                       "# Insert note for this entry."))
        (should-not (agile-gtd-loop-test-note-pending-p))
        (let ((entry (agile-gtd-loop-test-entry buffer "")))
          (should (equal (plist-get entry :state) state))
          (should (equal (plist-get entry :tags) '("%agent")))
          (should (= (length (plist-get entry :logbook)) 2))
          (should (string-match-p "\\`- Note taken on \\[.*\\] \\\\\\\\\\'"
                                  (car (plist-get entry :logbook))))
          (should (equal (cadr (plist-get entry :logbook)) "Please research")))))))

(ert-deftest agile-gtd-hand-over-takes-an-empty-note ()
  "An empty note still hands the item over: the tag and the dated state change."
  (agile-gtd-loop-test-with-file "* NEXT Draft the reply :%human:\n"
    (agile-gtd-loop-test-goto buffer "NEXT")
    (with-current-buffer buffer (agile-gtd-hand-over))
    (agile-gtd-loop-test-write-note "")
    (let ((entry (agile-gtd-loop-test-entry buffer "WAIT")))
      (should (equal (plist-get entry :tags) '("%agent")))
      (should (= (length (plist-get entry :logbook)) 1))
      (should (string-match-p "\\`- State \"WAIT\" +from \"NEXT\" +\\[.*\\]\\'"
                              (car (plist-get entry :logbook)))))))

(ert-deftest agile-gtd-hand-over-cancelled-note-keeps-the-hand-over ()
  "Cancelling the note leaves the item handed over, with nothing logged."
  (agile-gtd-loop-test-with-file "* NEXT Draft the reply :%human:\n"
    (agile-gtd-loop-test-goto buffer "NEXT")
    (with-current-buffer buffer (agile-gtd-hand-over))
    (org-add-log-note)
    (with-current-buffer "*Org Note*"
      (insert "Never mind")
      (let ((org-note-abort t))
        (funcall org-finish-function)))
    (should-not (agile-gtd-loop-test-note-pending-p))
    (let ((entry (agile-gtd-loop-test-entry buffer "WAIT")))
      (should (equal (plist-get entry :tags) '("%agent")))
      (should-not (plist-get entry :logbook)))))

(ert-deftest agile-gtd-hand-over-refuses-a-closed-item ()
  "A done item is no one's move: handing it over changes nothing and asks nothing."
  (dolist (state '("DONE" "IDEA" "KILL"))
    (ert-info (state)
      (agile-gtd-loop-test-with-file (format "* %s Old question :%%human:\n" state)
        (agile-gtd-loop-test-goto buffer "")
        (should-error (with-current-buffer buffer (agile-gtd-hand-over))
                      :type 'user-error)
        (should-not (agile-gtd-loop-test-note-pending-p))
        (let ((entry (agile-gtd-loop-test-entry buffer "")))
          (should (equal (plist-get entry :state) state))
          (should (equal (plist-get entry :tags) '("%human"))))))))

(ert-deftest agile-gtd-hand-over-changes-nothing-when-wait-is-refused ()
  "When the item cannot move to WAIT, its tags stay as they were."
  (agile-gtd-loop-test-with-file
      "#+TODO: TODO NEXT | DONE\n* NEXT Draft the reply :%human:\n"
    (agile-gtd-loop-test-goto buffer "NEXT")
    (with-current-buffer buffer
      (org-mode)
      (should-error (agile-gtd-hand-over) :type 'user-error))
    (should-not (agile-gtd-loop-test-note-pending-p))
    (let ((entry (agile-gtd-loop-test-entry buffer "NEXT")))
      (should (equal (plist-get entry :state) "NEXT"))
      (should (equal (plist-get entry :tags) '("%human"))))))

(ert-deftest agile-gtd-hand-over-takes-one-item-whatever-the-region ()
  "An active region does not spread the state change over the headings in it."
  (agile-gtd-loop-test-with-file
      "* NEXT First reply :%human:\n* NEXT Second reply :%human:\n"
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
      (should (equal (plist-get first :tags) '("%agent")))
      (should (equal (plist-get second :tags) '("%human"))))))

(ert-deftest agile-gtd-hand-over-works-on-the-agenda-item-at-point ()
  "From an agenda line, the item in its Org file is handed over the same way."
  (agile-gtd-loop-test-with-file
      (concat "* NEXT [#A] Draft the reply :%human:\n"
              "* PROJ [#B] Plan the release :%human:\n"
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
      (should (equal (plist-get action :tags) '("%agent")))
      (should (equal (cadr (plist-get action :logbook)) "Over to you"))
      (should (equal (plist-get project :state) "PROJ"))
      (should (equal (plist-get project :tags) '("%agent")))
      (should (equal (cadr (plist-get project :logbook)) "Split it up")))
    (ert-info ("the agenda line shows the new state and tag")
      (with-current-buffer org-agenda-buffer-name
        (goto-char (point-min))
        (should (re-search-forward "WAIT .*Draft the reply.*:%agent:" nil t))))))

(ert-deftest agile-gtd-hand-over-leaves-a-waiting-action-in-the-next-actions ()
  "An action handed to the agent is a WAIT like any other: still a next action."
  (agile-gtd-loop-test-with-file "* NEXT [#A] Draft the reply :%human:\n"
    (agile-gtd-loop-test-goto buffer "NEXT")
    (with-current-buffer buffer (agile-gtd-hand-over))
    (agile-gtd-loop-test-write-note "Over to you")
    (should (equal (org-ql-select buffer (agile-gtd-agenda-query-next-actions)
                     :action '(org-get-heading t t t t))
                   '("Draft the reply")))))


;;; Whose turn it is

(defconst agile-gtd-loop-test-states
  '(nil "TODO" "NEXT" "WAIT" "PROJ" "EPIC" "DONE" "KILL" "IDEA")
  "Every state an item can be in, nil for a heading without a keyword.")

(defun agile-gtd-loop-test-combos ()
  "Return every combination the turns depend on, one plist each.
The keys are `:tags' (the loop tags on the item), `:state', `:claim' and
`:someday' (nil, `local' or `inherited')."
  (let (combos)
    (dolist (tags '(nil ("%agent") ("%human") ("%agent" "%human")))
      (dolist (state agile-gtd-loop-test-states)
        (dolist (claim '(nil t))
          (dolist (someday '(nil local inherited))
            (push (list :tags tags :state state :claim claim :someday someday)
                  combos)))))
    (nreverse combos)))

(defun agile-gtd-loop-test-combo-title (combo)
  "Return the title of the heading COMBO is written as."
  (format "tags-%s state-%s claim-%s someday-%s"
          (if (plist-get combo :tags) (string-join (plist-get combo :tags) "+") "none")
          (or (plist-get combo :state) "none")
          (if (plist-get combo :claim) "yes" "no")
          (or (plist-get combo :someday) "no")))

(defun agile-gtd-loop-test-combo-entry (combo level)
  "Return COMBO written as an Org entry at LEVEL."
  (let ((state (plist-get combo :state))
        (tags (append (plist-get combo :tags)
                      (when (eq (plist-get combo :someday) 'local) '("SOMEDAY")))))
    (concat (make-string level ?*) " "
            (if state (concat state " ") "")
            (agile-gtd-loop-test-combo-title combo)
            (if tags (format " :%s:" (string-join tags ":")) "")
            "\n"
            (if (plist-get combo :claim) ":PROPERTIES:\n:AGENT_CLAIM: claude\n:END:\n" ""))))

(defun agile-gtd-loop-test-combo-file (combos)
  "Return the Org text holding every one of COMBOS.
Those inheriting SOMEDAY sit under a parked heading that is in no loop."
  (cl-flet ((inherits (combo) (eq (plist-get combo :someday) 'inherited)))
    (concat (mapconcat (lambda (combo) (agile-gtd-loop-test-combo-entry combo 1))
                       (seq-remove #'inherits combos) "")
            "* Parked :SOMEDAY:\n"
            (mapconcat (lambda (combo) (agile-gtd-loop-test-combo-entry combo 2))
                       (seq-filter #'inherits combos) ""))))

(defun agile-gtd-loop-test-expected-turns (combo)
  "Return the turns COMBO answers by the definitions, sorted.
Each turn is tested on its own definition, with no precedence between
them, so an overlap or a gap in the definitions shows as a failure."
  (let* ((tags (plist-get combo :tags))
         (state (plist-get combo :state))
         (claim (plist-get combo :claim))
         (someday (plist-get combo :someday))
         (agent (member "%agent" tags))
         (human-alone (and (member "%human" tags) (not agent)))
         (done (member state '("DONE" "KILL" "IDEA")))
         (task (member state '("TODO" "NEXT")))
         (turns (append
                 (when (and human-alone (not claim) (not done)
                            (not (member state '("WAIT" "TODO"))))
                   '(human-turn))
                 (when (and agent (not done) (not claim))
                   '(delegated))
                 (when (and human-alone (not claim) (member state '("WAIT" "TODO")))
                   '(replied))
                 (when (and human-alone (not claim) done)
                   '(answered))
                 (when (or (and agent done)
                           (and claim (or task (not agent) someday)))
                   '(withdrawn))
                 (when (and agent claim (not done) (not task) (not someday))
                   '(agent-wait)))))
    (sort (copy-sequence
           (append turns
                   (when (seq-intersection turns '(delegated replied answered withdrawn))
                     '(agent-turn))))
          #'string<)))

(defconst agile-gtd-loop-test-turn-queries
  '((human-turn . (human-turn))
    (agent-turn . (agent-turn))
    (agent-wait . (agent-wait))
    (delegated . (agent-turn delegated))
    (replied . (agent-turn replied))
    (answered . (agent-turn answered))
    (withdrawn . (agent-turn withdrawn)))
  "Each turn, and each kind of agent turn, with the query asking for it.")

(defun agile-gtd-loop-test-turns-by-title (buffer)
  "Return a table from each title in BUFFER to the turns it answers, sorted."
  (let ((table (make-hash-table :test #'equal)))
    (pcase-dolist (`(,name . ,query) agile-gtd-loop-test-turn-queries)
      (dolist (title (org-ql-select buffer query :action '(org-get-heading t t t t)))
        (push name (gethash title table))))
    (maphash (lambda (title turns) (puthash title (sort turns #'string<) table))
             table)
    table))

(ert-deftest agile-gtd-turns-exactly-one-holds-for-every-looped-item ()
  "A heading carrying a loop tag or the claim is in exactly one turn.
The headings cover every combination of the loop tags, the state, the
claim and SOMEDAY, its own or inherited.  An agent turn is of exactly one
kind, a heading in no loop is in no turn, and each heading answers what
the definitions say, with org-ql's preamble and without."
  (let ((combos (agile-gtd-loop-test-combos)))
    (agile-gtd-loop-test-with-file (agile-gtd-loop-test-combo-file combos)
      (dolist (org-ql-use-preamble '(t nil))
        (let ((turns (agile-gtd-loop-test-turns-by-title buffer)))
          (dolist (combo combos)
            (let* ((title (agile-gtd-loop-test-combo-title combo))
                   (actual (gethash title turns))
                   (looped (or (plist-get combo :tags) (plist-get combo :claim))))
              (ert-info ((format "%s, preamble %s" title org-ql-use-preamble))
                (should (= (length (seq-intersection
                                    actual '(human-turn agent-turn agent-wait)))
                           (if looped 1 0)))
                (should (= (length (seq-intersection
                                    actual '(delegated replied answered withdrawn)))
                           (if (memq 'agent-turn actual) 1 0)))
                (should (equal actual (agile-gtd-loop-test-expected-turns combo))))))
          (should-not (gethash "Parked" turns)))))))

(defun agile-gtd-loop-test-turns-of (content &optional setup)
  "Return each heading of CONTENT with the turns it answers, in file order.
SETUP, when non-nil, is called after `agile-gtd-enable' and before the
queries.  The answer with org-ql's preamble and without must agree."
  (agile-gtd-loop-test-with-file content
    (when setup (funcall setup))
    (let (answers)
      (dolist (org-ql-use-preamble '(t nil))
        (let ((turns (agile-gtd-loop-test-turns-by-title buffer)))
          (push (with-current-buffer buffer
                  (org-map-entries
                   (lambda ()
                     (let ((title (org-get-heading t t t t)))
                       (cons title (gethash title turns))))))
                answers)))
      (should (equal (car answers) (cadr answers)))
      (car answers))))

(ert-deftest agile-gtd-turns-read-the-tags-off-the-item-alone ()
  "A step under a project tagged for either side is in no turn.
That holds even where Org lets the tags pass to children."
  (should (equal (agile-gtd-loop-test-turns-of
                  (concat "* PROJ Project for the human :%human:\n"
                          "** NEXT Step for the human\n"
                          "* PROJ Project for the agent :%agent:\n"
                          "** NEXT Step for the agent\n"
                          "* WAIT Work the agent holds :%agent:\n"
                          ":PROPERTIES:\n:AGENT_CLAIM: claude\n:END:\n"
                          "** WAIT Step under the work\n")
                  (lambda ()
                    (setq org-tags-exclude-from-inheritance nil
                          org-use-property-inheritance t)))
                 '(("Project for the human" human-turn)
                   ("Step for the human")
                   ("Project for the agent" agent-turn delegated)
                   ("Step for the agent")
                   ("Work the agent holds" agent-wait)
                   ("Step under the work")))))

(ert-deftest agile-gtd-turns-ignore-a-loop-tag-in-the-title ()
  "A title holding `:%agent:' or `:%human:' tags nothing.
org-ql's own `tags-local' finds such a title by its preamble and takes it
for a tag; the turns read the heading's real tags."
  (should (equal (agile-gtd-loop-test-turns-of
                  (concat "* NEXT Fix the :%agent: parser\n"
                          "* NEXT Ask :%human: about it :#work:\n"
                          "* NEXT Review the :%agent: config :%human:\n"))
                 '(("Fix the :%agent: parser")
                   ("Ask :%human: about it")
                   ("Review the :%agent: config" human-turn)))))

(ert-deftest agile-gtd-turns-move-on-no-note ()
  "Notes in the LOGBOOK move no turn, whoever wrote the newest."
  (should (equal (agile-gtd-loop-test-turns-of
                  (concat "* NEXT The human answered in a note :%human:\n"
                          ":LOGBOOK:\n"
                          "- Note taken on [2026-10-07 Wed 11:00] \\\\\n"
                          "  Take the second one.\n"
                          "- Note taken on [2026-10-07 Wed 10:00] \\\\\n"
                          "  agent: Which one?\n"
                          ":END:\n"
                          "* WAIT The agent asked in a note :%human:\n"
                          ":LOGBOOK:\n"
                          "- Note taken on [2026-10-07 Wed 11:00] \\\\\n"
                          "  agent: Which one?\n"
                          ":END:\n"))
                 '(("The human answered in a note" human-turn)
                   ("The agent asked in a note" agent-turn replied)))))

(ert-deftest agile-gtd-turns-follow-the-renamed-tags-and-claim ()
  "The tags and the claim property are read by their option names."
  (should (equal (agile-gtd-loop-test-turns-of
                  (concat "* NEXT Asked by the agent :me:\n"
                          "* WAIT Claimed by the new name :ai:\n"
                          ":PROPERTIES:\n:CLAIMED_BY: claude\n:END:\n"
                          "* WAIT Claimed by the old name :ai:\n"
                          ":PROPERTIES:\n:AGENT_CLAIM: claude\n:END:\n"
                          "* NEXT The old agent tag :%agent:\n"
                          "* NEXT The old human tag :%human:\n")
                  (lambda ()
                    (setq agile-gtd-agent-tag "ai"
                          agile-gtd-human-tag "me"
                          agile-gtd-agent-claim-property "CLAIMED_BY")))
                 '(("Asked by the agent" human-turn)
                   ("Claimed by the new name" agent-wait)
                   ("Claimed by the old name" agent-turn delegated)
                   ("The old agent tag")
                   ("The old human tag")))))

(ert-deftest agile-gtd-turns-answer-to-their-long-names ()
  "Each turn answers to its `agile-gtd-' name as to its short one."
  (agile-gtd-loop-test-with-file
      (concat "* NEXT The human's move :%human:\n"
              "* NEXT The agent's move :%agent:\n"
              "* WAIT The agent's work :%agent:\n"
              ":PROPERTIES:\n:AGENT_CLAIM: claude\n:END:\n")
    (pcase-dolist (`(,short ,long) '(((human-turn) (agile-gtd-human-turn))
                                     ((agent-turn) (agile-gtd-agent-turn))
                                     ((agent-turn delegated) (agile-gtd-agent-turn delegated))
                                     ((agent-wait) (agile-gtd-agent-wait))))
      (ert-info ((format "%S" long))
        (let ((titles (org-ql-select buffer short :action '(org-get-heading t t t t))))
          (should titles)
          (should (equal (org-ql-select buffer long :action '(org-get-heading t t t t))
                         titles)))))))

(ert-deftest agile-gtd-agent-turn-refuses-an-unknown-kind ()
  "A misspelt kind of agent turn fails loudly rather than matching nothing."
  (agile-gtd-loop-test-with-file "* NEXT The agent's move :%agent:\n"
    (dolist (query '((agent-turn delegate) (agent-turn human-turn) (agent-turn 'agent-wait)))
      (ert-info ((format "%S" query))
        (should-error (org-ql-select buffer query) :type 'user-error)))))


;;; The `h' command

(defconst agile-gtd-loop-test-moves
  (concat "* NEXT [#A] Chain first\n"
          "* NEXT [#C] Blocked question :%human:\n"
          ":PROPERTIES:\n:BLOCKER:  previous-sibling\n:END:\n"
          "* NEXT [#B] Question for the human :%human:\n"
          "* PROJ [#F] Project for the human :%human:\n"
          "** NEXT Step under the human's project\n"
          "* Plain heading for the human :%human:\n"
          "* TODO [#B] Deferred question :%human:\n"
          "* DONE Answered question :%human:\n"
          "* NEXT [#A] Task for the agent :%agent:\n"
          "* WAIT [#B] Work the agent holds :%agent:\n"
          ":PROPERTIES:\n:AGENT_CLAIM: claude\n:END:\n")
  "Items in each turn, and items in none.")

(defconst agile-gtd-loop-test-h-headers '("Your move" "Agent's move" "Agent working")
  "The headers of the blocks of `h', in order.")

(defun agile-gtd-loop-test-h-text ()
  "Run `h' and return the agenda's text."
  (org-agenda nil "h")
  (with-current-buffer org-agenda-buffer-name
    (buffer-substring-no-properties (point-min) (point-max))))

(defun agile-gtd-loop-test-h-block-of (text title)
  "Return the header of the block of `h' TEXT that lists TITLE, or nil."
  (when-let* ((pos (string-search title text)))
    (cl-find-if (lambda (header) (< (string-search header text) pos))
                (reverse agile-gtd-loop-test-h-headers))))

(ert-deftest agile-gtd-agenda-h-lists-each-turn-in-its-block ()
  "`h' shows the human's moves, the agent's moves and the agent's work, by rank."
  (agile-gtd-loop-test-with-file agile-gtd-loop-test-moves
    (let* ((text (agile-gtd-loop-test-h-text))
           (headers (mapcar (lambda (header) (string-search header text))
                            agile-gtd-loop-test-h-headers))
           (moves '("Question for the human" "Blocked question"
                    "Plain heading for the human" "Project for the human")))
      (should (cl-every #'identity headers))
      (should (apply #'< headers))
      (ert-info ("the human's moves, most urgent first")
        (dolist (title moves)
          (should (equal (agile-gtd-loop-test-h-block-of text title) "Your move")))
        (should (apply #'< (mapcar (lambda (title) (string-search title text)) moves))))
      (ert-info ("the agent's moves")
        (dolist (title '("Task for the agent" "Deferred question" "Answered question"))
          (should (equal (agile-gtd-loop-test-h-block-of text title) "Agent's move"))))
      (ert-info ("the agent's work")
        (should (equal (agile-gtd-loop-test-h-block-of text "Work the agent holds")
                       "Agent working")))
      (dolist (other '("Step under the human's project" "Chain first"))
        (ert-info (other)
          (should-not (string-search other text))))
      (ert-info ("the blocked one shown dimmed, where blocked tasks are hidden")
        (should (eq org-agenda-dim-blocked-tasks 'invisible))
        (with-current-buffer org-agenda-buffer-name
          (goto-char (point-min))
          (search-forward "Blocked question")
          (let ((pos (match-beginning 0)))
            (should-not (invisible-p pos))
            (should (cl-some (lambda (ov)
                               (eq (overlay-get ov 'face) 'org-agenda-dimmed-todo-face))
                             (overlays-at pos)))))))))

(ert-deftest agile-gtd-agenda-h-keeps-every-header-when-empty ()
  "With no item in any turn, `h' still shows each block's header."
  (agile-gtd-loop-test-with-file "* NEXT [#A] Nobody's move\n"
    (let ((text (agile-gtd-loop-test-h-text)))
      (dolist (header agile-gtd-loop-test-h-headers)
        (should (string-search header text))))))

(ert-deftest agile-gtd-agenda-h-searches-the-loop-files-too ()
  "`h' searches `agile-gtd-loop-files' beside the agenda files, and only `h' does."
  (agile-gtd-loop-test-with-file "* NEXT [#A] Agenda question :%human:\n"
    (let ((loop-file (expand-file-name "agentic.org" org-directory)))
      (with-temp-file loop-file
        (insert "* NEXT [#A] Loop question :%human:\n"
                "* WAIT [#B] Loop work :%agent:\n"
                ":PROPERTIES:\n:AGENT_CLAIM: claude\n:END:\n"))
      (setq agile-gtd-loop-files '("agentic.org"))
      (unwind-protect
          (progn
            (let ((text (agile-gtd-loop-test-h-text)))
              (should (equal (agile-gtd-loop-test-h-block-of text "Agenda question") "Your move"))
              (should (equal (agile-gtd-loop-test-h-block-of text "Loop question") "Your move"))
              (should (equal (agile-gtd-loop-test-h-block-of text "Loop work") "Agent working")))
            (ert-info ("a redo searches them again")
              (with-current-buffer org-agenda-buffer-name
                (org-agenda-redo)
                (should (string-search "Loop question" (buffer-string)))))
            (ert-info ("the agenda files stay as they were")
              (should (equal org-agenda-files (list file))))
            (ert-info ("the main agenda searches the agenda files alone")
              (org-agenda nil "a")
              (with-current-buffer org-agenda-buffer-name
                (should (string-search "Agenda question" (buffer-string)))
                (should-not (string-search "Loop question" (buffer-string))))))
        (when-let* ((loop-buffer (find-buffer-visiting loop-file)))
          (kill-buffer loop-buffer))))))

(provide 'agile-gtd-loop-test)
;;; agile-gtd-loop-test.el ends here
