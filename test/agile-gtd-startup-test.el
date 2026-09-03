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
(require 'agile-gtd-test)

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

PROJECTS is a list of plists for `agile-gtd-projects\'.  FILES is an
alist of (RELATIVE-NAME . CONTENT); intermediate directories are
created.  `agile-gtd-test-with-sandbox\' settles the Org and Agile GTD
state and owns the temporary directory; what this adds to it is the
registry under test, an archive location inside that directory so
archives resolve to real files and the missing-archive case is real too,
and an empty warned-entry set, for the reason
`agile-gtd-startup-test-with-registry\' gives."
  (declare (indent 2) (debug t))
  `(agile-gtd-test-with-sandbox
     (let ((org-agenda-new-buffers nil)
           (org-archive-location
            (expand-file-name "archive/%s::datetree" org-directory))
           (agile-gtd-projects ,projects)
           (agile-gtd--warned-registry nil)
           (agile-gtd--warned-entries nil))
       (unwind-protect
           (progn
             (pcase-dolist (`(,name . ,content) ,files)
               (let ((path (expand-file-name name org-directory)))
                 (make-directory (file-name-directory path) t)
                 (with-temp-file path (insert content))))
             ,@body)
         ;; Before the sandbox deletes the directory out from under them.
         (agile-gtd-startup-test-kill-buffers org-directory)))))

(defmacro agile-gtd-startup-test-with-registry (projects &rest body)
  "Run BODY with PROJECTS registered and no entry yet warned about.
The warned-entry set is keyed by `equal' on the offending entry and is
emptied only when the registry stops being `equal' to the value last
read.  Two tests declaring `equal' registries would therefore share one
set, and whichever ran second would see no warning at all — a pass that
depends on test order rather than on behaviour."
  (declare (indent 1) (debug t))
  `(let ((agile-gtd-projects ,projects)
         (agile-gtd--warned-registry nil)
         (agile-gtd--warned-entries nil))
     ,@body))

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

;;; The registry layout both packages read

(defconst agile-gtd-startup-test-contract-registry
  '((:tag "solo")
    (:tag "acme" :name "Acme Ltd")
    (:tag "glas" :file "cafe-glas.org")
    (:tag "sub" :file "clients/sub.org")
    (:tag "keyed" :name "Keyed Ltd" :key ?k))
  "The declared half of the registry layout both packages read.
One row per way a project can be written down: a tag on its own, a tag
with the name it is called by, a tag with the file its time is kept in, a
file naming a directory below the org directory, and an entry carrying
`:key', which is this package\\='s own extension.

The same rows appear in the clock package\\='s suite, in
test/org-clock-projects-export-test.el of the org-clock-projects
repository, where the normalised half carries no `:key'.  Nothing
mechanically keeps the two copies equal: they are the shared layout\\='s
only guarantee, so a change to either belongs in both.")

(defconst agile-gtd-startup-test-contract-records
  '((:tag "solo" :name "solo" :file "solo.org" :key nil)
    (:tag "acme" :name "Acme Ltd" :file "acme.org" :key nil)
    (:tag "glas" :name "glas" :file "cafe-glas.org" :key nil)
    (:tag "sub" :name "sub" :file "clients/sub.org" :key nil)
    (:tag "keyed" :name "Keyed Ltd" :file "keyed.org" :key ?k))
  "What `agile-gtd-startup-test-contract-registry' normalises to.
A name defaults to the tag and a file to `<tag>.org'; a declared file is
kept exactly as written, relative names included.  `:key' survives, which
is what lets a project keep its agenda command and its tag binding while
the clock package reading the same list ignores the key entirely.")

(ert-deftest agile-gtd-project-records-fill-in-the-implicit-defaults ()
  "Every way of declaring a project normalises to the documented record.
This is this package\\='s half of the contract the clock package holds the
other half of; `:key' is the one column only this half has."
  (agile-gtd-startup-test-with-registry agile-gtd-startup-test-contract-registry
    (should (equal (agile-gtd-project-records)
                   agile-gtd-startup-test-contract-records))))

(ert-deftest agile-gtd-project-files-follow-the-records ()
  (agile-gtd-startup-test-with-registry agile-gtd-startup-test-contract-registry
    (should (equal (agile-gtd-project-files)
                   (mapcar (lambda (record) (plist-get record :file))
                           agile-gtd-startup-test-contract-records)))))

;;; Unusable registry entries

(defconst agile-gtd-startup-test-bad-registry
  '("solo.org"
    (:name "Nameless" :file "nameless.org" :key ?n)
    (:tag "" :file "empty.org" :key ?e)
    (:tag "glas" :name "Cafe Glas" :file "cafe-glas.org" :key ?g)
    (:tag "glas" :name "Second Glas" :file "second-glas.org" :key ?d))
  "One usable project among one of each entry the funnel cannot use.
A bare string, a plist declaring no `:tag', a plist whose `:tag' is a
string carrying nothing, and a second entry claiming a tag an earlier one
already holds.  The empty tag is the one that looks legal: it matches
every entry and no entry, so it has to be dropped on the same grounds as
a missing one.  The usable project sits between the offenders, so a
funnel that stops at the first of them loses a project rather than only a
warning.  Every key here is free: `w' followed by `n', `e', `g' or `d'
names no agenda command this package already defines.")

(defconst agile-gtd-startup-test-skipped
  '(("solo.org" . "not a plist")
    ((:name "Nameless" :file "nameless.org" :key ?n) . "no :tag")
    ((:tag "" :file "empty.org" :key ?e) . "no :tag")
    ((:tag "glas" :name "Second Glas" :file "second-glas.org" :key ?d)
     . "already claimed"))
  "Each entry of `agile-gtd-startup-test-bad-registry' that is dropped.
Paired with the words of the reason its warning gives, in the order the
registry is walked.")

(defconst agile-gtd-startup-test-kept
  '((:tag "glas" :name "Cafe Glas" :file "cafe-glas.org" :key ?g))
  "What `agile-gtd-startup-test-bad-registry' normalises to.
The duplicate loses to the entry that claimed the tag first, so the name
and the file that survive are the first entry\\='s.")

(defun agile-gtd-startup-test-registry-warnings ()
  "Read the registry and return the warnings the read raised, in order."
  (agile-gtd-startup-test-warnings #'agile-gtd-project-records))

(ert-deftest agile-gtd-project-records-skip-unusable-entries-with-one-warning-each ()
  "An unusable entry costs its own project and one warning, not the session."
  (agile-gtd-startup-test-with-registry agile-gtd-startup-test-bad-registry
    (let ((warnings (agile-gtd-startup-test-registry-warnings)))
      (should (= (length warnings) (length agile-gtd-startup-test-skipped)))
      (cl-loop for warning in warnings
               for (entry . reason) in agile-gtd-startup-test-skipped
               do (ert-info ((format "entry=%S" entry))
                    (should (string-match-p (regexp-quote (format "%S" entry))
                                            warning))
                    (should (string-match-p (regexp-quote reason) warning))
                    ;; The warning has to explain itself: whoever reads it
                    ;; is looking at a declaration in a shape the funnel
                    ;; rejects, and needs to be shown the shape it accepts.
                    (should (string-match-p (regexp-quote ":tag \"tag\"")
                                            warning)))))
    (should (equal (agile-gtd-project-records)
                   agile-gtd-startup-test-kept))))

(ert-deftest agile-gtd-project-records-warn-once-per-registry-value ()
  "Repeated reads of one registry warn once; an edited registry warns afresh.
The registry is read on every agenda build and every refresh.  A warning
repeated on each of those buries the one that matters, and a warning
silenced for the rest of the session hides an edit that made things
worse."
  (agile-gtd-startup-test-with-registry agile-gtd-startup-test-bad-registry
    (should (= (length (agile-gtd-startup-test-registry-warnings))
               (length agile-gtd-startup-test-skipped)))
    (should-not (agile-gtd-startup-test-registry-warnings))
    (setq agile-gtd-projects (cons '(:tag "extra") agile-gtd-projects))
    (should (= (length (agile-gtd-startup-test-registry-warnings))
               (length agile-gtd-startup-test-skipped)))))

(ert-deftest agile-gtd-skipped-entries-reach-no-consumer ()
  "Nothing a skipped entry declared reaches the configuration a refresh writes.
The tagless entry is the one that matters most: with no `:tag' its file
defaults to `.org', which is a real path under `org-directory' and a real
agenda file, so the drop has to happen before the file list is built and
not after."
  (agile-gtd-startup-test-with-files
      agile-gtd-startup-test-bad-registry
      (list (cons "cafe-glas.org" "#+filetags: :glas:\n\n* TODO Glas task\n"))
    (agile-gtd-startup-test-warnings #'agile-gtd-refresh)
    (should (equal (agile-gtd-project-files) '("cafe-glas.org")))
    (let ((bases (mapcar #'file-name-nondirectory org-agenda-files))
          (keys (mapcar #'car org-agenda-custom-commands)))
      (should (member "cafe-glas.org" bases))
      (should-not (member ".org" bases))
      (should-not (member "nameless.org" bases))
      (should-not (member "empty.org" bases))
      (should-not (member "second-glas.org" bases))
      (should (member "wg" keys))
      (should-not (member "wn" keys))
      (should-not (member "we" keys))
      (should-not (member "wd" keys)))
    (should (equal ?g (cdr (assoc "glas" org-tag-alist))))
    (should-not (rassq ?n org-tag-alist))
    (should-not (rassq ?e org-tag-alist))
    (should-not (rassq ?d org-tag-alist))))

(ert-deftest agile-gtd-a-non-character-key-costs-only-its-own-binding ()
  "A `:key' that is not a character keeps its project and earns no binding.
`char-to-string' signals on anything but a character and `org-tag-alist'
reads the cdr of an entry as a selection key, so a `:key' of \"g\" would
either take the startup down or corrupt every tag prompt in the session.
The project itself is usable and stays: this is not a skip."
  (agile-gtd-startup-test-with-files
      '((:tag "glas" :name "Cafe Glas" :file "cafe-glas.org" :key "g"))
      (list (cons "cafe-glas.org" "#+filetags: :glas:\n\n* TODO Glas task\n"))
    (should-not (agile-gtd-startup-test-warnings #'agile-gtd-refresh))
    (should (equal (agile-gtd-project-records)
                   '((:tag "glas" :name "Cafe Glas" :file "cafe-glas.org"
                           :key "g"))))
    (should (member (expand-file-name "cafe-glas.org" org-directory)
                    org-agenda-files))
    (should-not (assoc "glas" org-tag-alist))
    (should-not (member "wg" (mapcar #'car org-agenda-custom-commands)))))

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

(ert-deftest agile-gtd-check-project-tags-reads-a-stock-archive ()
  "A tagged archive under Org\'s default layout is not reported.
`org-archive-location\' names the archive `<file>.org_archive\' unless it
is configured otherwise, and no `auto-mode-alist\' entry claims that name,
so a buffer visiting one arrives in Fundamental mode where `org-file-tags\'
is nil whatever the file says.  Read that way, every correctly tagged
archive on a stock Org setup is reported at every startup, forever."
  (agile-gtd-startup-test-with-files
      '((:tag "alpha"))
      (list (cons "alpha.org" agile-gtd-startup-test-tagged)
            (cons "alpha.org_archive" agile-gtd-startup-test-tagged))
    (let ((org-archive-location "%s_archive::"))
      (should-not (agile-gtd-startup-test-warnings
                   #'agile-gtd-check-project-tags)))))

(ert-deftest agile-gtd-check-project-tags-names-an-untagged-stock-archive ()
  "The stock-layout archive is still reported when it really lacks the tag."
  (agile-gtd-startup-test-with-files
      '((:tag "alpha"))
      (list (cons "alpha.org" agile-gtd-startup-test-tagged)
            (cons "alpha.org_archive" agile-gtd-startup-test-untagged))
    (let ((org-archive-location "%s_archive::"))
      (should (equal (agile-gtd-startup-test-warnings
                      #'agile-gtd-check-project-tags)
                     (list (format "Agile GTD: project files without their project tag: %s"
                                   (agile-gtd-startup-test-offender
                                    "alpha.org_archive" "alpha"))))))))

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
