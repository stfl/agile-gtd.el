;;; agile-gtd-loop-test.el --- The agent/human loop: whose move an item is -*- lexical-binding: t; -*-

;;; Commentary:

;; Two tags say whose move an item is: `agent' and `human'.  These tests
;; cover what agile-gtd does with them: it keeps them from passing to child
;; headings without touching the user's own exclusions.

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
  "A tag added to the list is excluded on refresh, and one dropped from it is not."
  (agile-gtd-test-with-sandbox
    (setq org-tags-exclude-from-inheritance '("crypt"))
    (agile-gtd-enable)
    (setq agile-gtd-loop-tags '("agent" "human" "jira"))
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "agent" "human" "jira")))
    (setq agile-gtd-loop-tags '("agent"))
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "agent")))
    (setq agile-gtd-loop-tags nil)
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt")))))

(ert-deftest agile-gtd-loop-tags-never-take-a-user-exclusion-away ()
  "A tag the user excluded before agile-gtd did stays excluded when the list drops it."
  (agile-gtd-test-with-sandbox
    (setq org-tags-exclude-from-inheritance '("crypt" "human"))
    (agile-gtd-enable)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "human" "agent")))
    (setq agile-gtd-loop-tags '("agent"))
    (agile-gtd-refresh)
    (should (equal org-tags-exclude-from-inheritance '("crypt" "human" "agent")))))

(provide 'agile-gtd-loop-test)
;;; agile-gtd-loop-test.el ends here
