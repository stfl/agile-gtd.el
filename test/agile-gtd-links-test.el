;;; agile-gtd-links-test.el --- Storing links: location-scoped IDs and the kill ring -*- lexical-binding: t; -*-

;;; Commentary:

;; These tests call `org-store-link' the way a key does, through
;; `call-interactively', on fixture files inside and outside the sandbox's
;; `org-directory', and assert on the heading's properties, on
;; `org-stored-links' and on the kill ring.  The org-records-mcp test calls
;; that package's own link minting with both advices installed.

;;; Code:

(require 'ert)
(require 'agile-gtd)
(require 'agile-gtd-test)

(defmacro agile-gtd-links-test-with-files (&rest body)
  "Run BODY in the sandbox with agile-gtd enabled and link state isolated.
BODY sees `outside', a directory that is not under `org-directory'."
  (declare (indent 0) (debug t))
  `(agile-gtd-test-with-sandbox
     (let ((outside (make-temp-file "agile-gtd-links-outside-" t))
           (org-roam-directory nil)
           (org-stored-links nil)
           (org-id-track-globally nil)
           (org-id-link-to-org-use-id nil)
           (kill-ring nil)
           (kill-ring-yank-pointer nil)
           (interprogram-cut-function nil)
           (interprogram-paste-function nil))
       (unwind-protect
           (progn
             (agile-gtd-enable)
             ,@body)
         (dolist (buffer (buffer-list))
           (when-let* ((file (buffer-file-name buffer)))
             (when (or (file-in-directory-p file outside)
                       (file-in-directory-p file org-directory))
               (with-current-buffer buffer (set-buffer-modified-p nil))
               (kill-buffer buffer))))
         (delete-directory outside t)))))

(defun agile-gtd-links-test--visit (file content heading)
  "Write CONTENT to FILE, visit it and move to the line of HEADING.
Return the buffer."
  (with-temp-file file (insert content))
  (with-current-buffer (find-file-noselect file)
    (goto-char (point-min))
    (re-search-forward (concat "^\\*+ " (regexp-quote heading)))
    (beginning-of-line)
    (current-buffer)))

(defun agile-gtd-links-test--store (buffer)
  "Store a link interactively from point in BUFFER."
  (with-current-buffer buffer
    (call-interactively #'org-store-link)))

(ert-deftest agile-gtd-links-heading-under-org-directory-gets-an-id ()
  "Under `org-directory' the heading is linked, and copied, by a new :ID:."
  (agile-gtd-links-test-with-files
    (let ((buffer (agile-gtd-links-test--visit
                   (expand-file-name "notes.org" org-directory)
                   "* Plan\n" "Plan")))
      (agile-gtd-links-test--store buffer)
      (with-current-buffer buffer
        (let ((id (org-entry-get nil "ID")))
          (should id)
          (should-not (org-entry-get nil "CUSTOM_ID"))
          (should (equal (caar org-stored-links) (concat "id:" id)))
          (should (equal (car kill-ring) (concat "id:" id))))))))

(ert-deftest agile-gtd-links-heading-elsewhere-gets-a-custom-id ()
  "Outside `org-directory' the heading gets a slug and never an :ID:."
  (agile-gtd-links-test-with-files
    (let* ((file (expand-file-name "x.org" outside))
           (buffer (agile-gtd-links-test--visit
                    file "* Some Heading\n" "Some Heading")))
      (agile-gtd-links-test--store buffer)
      (with-current-buffer buffer
        (should (equal (org-entry-get nil "CUSTOM_ID") "some-heading"))
        (should-not (org-entry-get nil "ID")))
      (should (equal (car kill-ring)
                     (concat "file:" (expand-file-name file)
                             "::#some-heading"))))))

(ert-deftest agile-gtd-links-kill-ring-copy-leaves-the-stored-link-alone ()
  "The kill ring gets an absolute path; `org-stored-links' keeps Org's own."
  (agile-gtd-links-test-with-files
    (let* ((file (expand-file-name "x.org" outside))
           (buffer (agile-gtd-links-test--visit
                    file "* Some Heading\n" "Some Heading"))
           (process-environment (cons (concat "HOME=" outside)
                                      process-environment))
           (abbreviated-home-dir nil))
      (agile-gtd-links-test--store buffer)
      (should (equal (caar org-stored-links) "file:~/x.org::#some-heading"))
      (should (equal (car kill-ring)
                     (concat "file:" (expand-file-name file)
                             "::#some-heading"))))))

(ert-deftest agile-gtd-links-id-wins-over-custom-id ()
  "With both identifiers, Org stores two links and the `id:' one is copied."
  (agile-gtd-links-test-with-files
    (let ((buffer (agile-gtd-links-test--visit
                   (expand-file-name "notes.org" org-directory)
                   (concat "* Both\n:PROPERTIES:\n"
                           ":ID:       11111111-2222-3333-4444-555555555555\n"
                           ":CUSTOM_ID: both\n:END:\n")
                   "Both")))
      (dotimes (_ 2)
        (agile-gtd-links-test--store buffer)
        (should (equal (car kill-ring)
                       "id:11111111-2222-3333-4444-555555555555"))))))

(ert-deftest agile-gtd-links-non-interactive-call-is-untouched ()
  "A non-interactive call creates no identifier and copies nothing."
  (agile-gtd-links-test-with-files
    (let* ((file (expand-file-name "x.org" outside))
           (buffer (agile-gtd-links-test--visit
                    file "* Some Heading\n" "Some Heading")))
      (with-current-buffer buffer
        (should (equal (org-store-link nil nil)
                       (concat "[[file:" (abbreviate-file-name file)
                               "::*Some Heading][Some Heading]]")))
        (should-not (buffer-modified-p))
        (should-not (org-entry-get nil "CUSTOM_ID")))
      (should-not kill-ring))))

(ert-deftest agile-gtd-links-org-records-mcp-mints-its-own-links ()
  "org-records-mcp's link minting works with both advices installed.
It calls `org-store-link' non-interactively and refuses any advice that
changes the buffer or the form of the link."
  (agile-gtd-links-test-with-files
    (dolist (dir (list org-directory outside))
      (let* ((file (expand-file-name "mcp.org" dir))
             (buffer (agile-gtd-links-test--visit file "* Task\n" "Task")))
        (with-current-buffer buffer
          (should (equal (org-records-mcp--link-at-point)
                         (concat "file:" (abbreviate-file-name file)
                                 "::*Task")))
          (should-not (buffer-modified-p)))
        (should-not kill-ring)))))

(ert-deftest agile-gtd-links-flags-off-remove-the-advice ()
  "A refresh with both flags off leaves `org-store-link' unadvised."
  (agile-gtd-links-test-with-files
    (should (advice-member-p #'agile-gtd--org-store-link-ids-a
                             'org-store-link))
    (should (advice-member-p #'agile-gtd--org-store-link-kill-ring-a
                             'org-store-link))
    (let ((agile-gtd-enable-link-ids nil)
          (agile-gtd-enable-link-kill-ring nil))
      (agile-gtd-refresh)
      (should-not (advice-member-p #'agile-gtd--org-store-link-ids-a
                                   'org-store-link))
      (should-not (advice-member-p #'agile-gtd--org-store-link-kill-ring-a
                                   'org-store-link)))))

(provide 'agile-gtd-links-test)
;;; agile-gtd-links-test.el ends here
