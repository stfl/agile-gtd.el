;;; agile-gtd-startup-test.el --- Tests for project records and the tag check -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-agenda)
(require 'org-capture)
(require 'org-modern)
(require 'org-ql)
(require 'org-edna)
(require 'agile-gtd)

;;; Fixtures
;;
;; The tag check is about file-level tags, so the untagged fixture wears its
;; tag on a headline instead: that is the shape a user actually produces, and
;; the one that silently exports nothing.

(defconst agile-gtd-startup-test-tagged "\
#+filetags: :alpha:

* TODO Alpha task
"
  "A project file whose tag every entry in it inherits.")

(defconst agile-gtd-startup-test-untagged "\
* TODO Beta task :beta:
"
  "A project file whose tag reaches one headline and nothing else.")

(defun agile-gtd-startup-test-kill-buffers (dir)
  "Kill all buffers visiting a file under DIR."
  (dolist (buffer (buffer-list))
    (let ((file (buffer-file-name buffer)))
      (when (and file (string-prefix-p (file-name-as-directory dir) file))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(defmacro agile-gtd-startup-test-with-files (projects files &rest body)
  "Run BODY with PROJECTS registered and FILES written into the sandbox.

PROJECTS is a list of plists for `agile-gtd-projects'.  FILES is an
alist of (RELATIVE-NAME . CONTENT); intermediate directories are
created.  `org-archive-location' points inside the sandbox, so archives
resolve to real files and the missing-archive case is real too."
  (declare (indent 2) (debug t))
  `(let* ((tmpdir (make-temp-file "agile-gtd-startup-test-" t))
          (org-directory tmpdir)
          (org-agenda-files nil)
          (org-agenda-diary-file nil)
          (org-agenda-custom-commands nil)
          (org-agenda-new-buffers nil)
          (org-archive-location
           (expand-file-name "archive/%s::datetree" tmpdir))
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
          (agile-gtd-projects ,projects)
          (agile-gtd-enable-agenda-files t)
          (agile-gtd-enable-refile-targets t)
          (agile-gtd-enable-org-modern-visuals t))
     (unwind-protect
         (progn
           (pcase-dolist (`(,name . ,content) ,files)
             (let ((path (expand-file-name name tmpdir)))
               (make-directory (file-name-directory path) t)
               (with-temp-file path (insert content))))
           ,@body)
       (ignore-errors (org-super-agenda-mode -1))
       (agile-gtd-startup-test-kill-buffers tmpdir)
       (delete-directory tmpdir t))))

(defun agile-gtd-startup-test-warnings (thunk)
  "Call THUNK and return the warning messages it raised, in order."
  (let ((warnings nil))
    (cl-letf (((symbol-function 'display-warning)
               (lambda (_type message &rest _) (push message warnings))))
      (funcall thunk))
    (nreverse warnings)))

(defun agile-gtd-startup-test-offender (name tag)
  "Return how the tag check names sandbox file NAME belonging to TAG."
  (format "%s (%s)"
          (abbreviate-file-name (expand-file-name name org-directory))
          tag))

(defun agile-gtd-startup-test-snapshot (dir)
  "Return the name, content and modification time of every file under DIR."
  (mapcar (lambda (file)
            (list (file-relative-name file dir)
                  (with-temp-buffer
                    (insert-file-contents-literally file)
                    (buffer-string))
                  (file-attribute-modification-time (file-attributes file))))
          (sort (directory-files-recursively dir "") #'string<)))

;;; Project records

(ert-deftest agile-gtd-project-records-fill-in-the-implicit-defaults ()
  (let ((agile-gtd-projects
         '((:tag "glas" :name "Cafe Glas" :file "cafe-glas.org" :key ?g)
           (:tag "beta"))))
    (should (equal (agile-gtd-project-records)
                   '((:tag "glas" :name "Cafe Glas" :file "cafe-glas.org" :key ?g)
                     (:tag "beta" :name "beta" :file "beta.org" :key nil))))))

(ert-deftest agile-gtd-project-files-follow-the-records ()
  (let ((agile-gtd-projects
         '((:tag "glas" :name "Cafe Glas" :file "cafe-glas.org" :key ?g)
           (:tag "beta"))))
    (should (equal (agile-gtd-project-files)
                   '("cafe-glas.org" "beta.org")))))

;;; Startup tag check

(ert-deftest agile-gtd-check-project-tags-names-the-file-without-its-tag ()
  (agile-gtd-startup-test-with-files
      '((:tag "alpha") (:tag "beta"))
      (list (cons "alpha.org" agile-gtd-startup-test-tagged)
            (cons "beta.org" agile-gtd-startup-test-untagged))
    (should (equal (agile-gtd-startup-test-warnings #'agile-gtd-check-project-tags)
                   (list (format "Agile GTD: project files without their project tag: %s"
                                 (agile-gtd-startup-test-offender "beta.org" "beta")))))))

(ert-deftest agile-gtd-check-project-tags-writes-nothing ()
  (agile-gtd-startup-test-with-files
      '((:tag "alpha") (:tag "beta"))
      (list (cons "alpha.org" agile-gtd-startup-test-tagged)
            (cons "beta.org" agile-gtd-startup-test-untagged)
            (cons "archive/beta.org" agile-gtd-startup-test-untagged))
    (let ((before (agile-gtd-startup-test-snapshot org-directory)))
      (agile-gtd-startup-test-warnings #'agile-gtd-check-project-tags)
      (should (equal (agile-gtd-startup-test-snapshot org-directory) before)))))

(ert-deftest agile-gtd-check-project-tags-covers-an-existing-archive ()
  (agile-gtd-startup-test-with-files
      '((:tag "alpha"))
      (list (cons "alpha.org" agile-gtd-startup-test-tagged)
            (cons "archive/alpha.org" "* DONE Archived alpha task\n"))
    (should (equal (agile-gtd-startup-test-warnings #'agile-gtd-check-project-tags)
                   (list (format "Agile GTD: project files without their project tag: %s"
                                 (agile-gtd-startup-test-offender "archive/alpha.org"
                                                                  "alpha")))))))

(ert-deftest agile-gtd-check-project-tags-is-silent-when-every-file-carries-its-tag ()
  (agile-gtd-startup-test-with-files
      '((:tag "alpha")
        (:tag "glas" :name "Cafe Glas" :file "cafe-glas.org"))
      (list (cons "alpha.org" agile-gtd-startup-test-tagged)
            (cons "archive/alpha.org" "#+filetags: :alpha:\n\n* DONE Archived\n")
            (cons "cafe-glas.org" "#+filetags: :glas:\n\n* TODO Glas task\n"))
    (should-not (agile-gtd-startup-test-warnings #'agile-gtd-check-project-tags))))

(ert-deftest agile-gtd-enable-leaves-the-tag-check-to-interactive-sessions ()
  (agile-gtd-startup-test-with-files
      '((:tag "beta"))
      (list (cons "beta.org" agile-gtd-startup-test-untagged))
    (should-not (agile-gtd-startup-test-warnings
                 (lambda () (let ((noninteractive t)) (agile-gtd-enable)))))
    (should (agile-gtd-startup-test-warnings
             (lambda () (let ((noninteractive nil)) (agile-gtd-enable)))))))

(provide 'agile-gtd-startup-test)

;;; agile-gtd-startup-test.el ends here
