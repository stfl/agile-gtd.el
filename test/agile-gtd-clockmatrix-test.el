;;; agile-gtd-clockmatrix-test.el --- Tests for the clockmatrix dynamic block -*- lexical-binding: t; -*-

(require 'ert)
(require 'cl-lib)
(require 'org)
(require 'org-agenda)
(require 'org-capture)
(require 'org-clock)
(require 'org-modern)
(require 'org-ql)
(require 'org-edna)
(require 'agile-gtd)

;; Reuse the sandbox from the predicates tests
(require 'agile-gtd-org-ql-predicates-test)

;;; Fixtures

(defconst agile-gtd-clockmatrix-test-projects
  '((:tag "alpha" :name "Alpha")
    (:tag "beta"  :name "Beta")
    (:tag "gamma" :name "Gamma"))
  "Projects registered for most clockmatrix tests.")

(defconst agile-gtd-clockmatrix-test-files
  '(("alpha.org" . "\
* TODO Alpha task :alpha:
:LOGBOOK:
CLOCK: [2026-05-04 Mon 09:00]--[2026-05-04 Mon 11:00] =>  2:00
CLOCK: [2026-06-02 Tue 09:00]--[2026-06-02 Tue 12:30] =>  3:30
:END:
")
    ("archive/alpha.org" . "\
* DONE Archived alpha task :alpha:
:LOGBOOK:
CLOCK: [2026-05-11 Mon 09:00]--[2026-05-11 Mon 10:15] =>  1:15
:END:
")
    ("beta.org" . "\
* TODO Beta task :beta:
:LOGBOOK:
CLOCK: [2026-05-05 Tue 14:00]--[2026-05-05 Tue 15:15] =>  1:15
CLOCK: [2026-05-20 Wed 10:00]--[2026-05-20 Wed 10:30] =>  0:30
:END:
")
    ("gamma.org" . "\
* TODO Gamma task :gamma:
:LOGBOOK:
CLOCK: [2025-11-03 Mon 09:00]--[2025-11-03 Mon 10:45] =>  1:45
:END:
"))
  "Synthetic project files with known clocked time.

Totals for 2026: alpha 6:45 (2:00 + 3:30 in its own file, 1:15 in its
archive), beta 1:45, gamma nothing.  Gamma's only clock is in 2025.")

(defun agile-gtd-clockmatrix-test-kill-buffers (dir)
  "Kill all buffers visiting a file under DIR."
  (dolist (buffer (buffer-list))
    (let ((file (buffer-file-name buffer)))
      (when (and file (string-prefix-p (file-name-as-directory dir) file))
        (with-current-buffer buffer (set-buffer-modified-p nil))
        (kill-buffer buffer)))))

(defmacro agile-gtd-clockmatrix-test-with-data (projects files &rest body)
  "Run BODY with PROJECTS registered and FILES written into the sandbox.

PROJECTS is a list of plists for `agile-gtd-projects'.  FILES is an
alist of (RELATIVE-NAME . CONTENT); intermediate directories are
created.  Durations render as `h:mm' so assertions do not depend on the
ambient `org-duration-format'."
  (declare (indent 2) (debug t))
  `(agile-gtd-org-ql-test-with-sandbox
    (let ((org-duration-format 'h:mm)
          (org-extend-today-until 0)
          (org-archive-location
           (expand-file-name "archive/%s::datetree" org-directory))
          (sandbox org-directory))
      (unwind-protect
          (progn
            (pcase-dolist (`(,name . ,content) ,files)
              (let ((path (expand-file-name name sandbox)))
                (make-directory (file-name-directory path) t)
                (with-temp-file path (insert content))))
            (setq agile-gtd-projects ,projects)
            ,@body)
        (agile-gtd-clockmatrix-test-kill-buffers sandbox)))))

(defun agile-gtd-clockmatrix-test-render (params)
  "Insert a clockmatrix block with PARAMS, refresh it, return the block text.

PARAMS may be written across several lines for readability; it is folded
onto the single `#+BEGIN:' line."
  (with-temp-buffer
    (org-mode)
    (insert "#+BEGIN: clockmatrix "
            (replace-regexp-in-string "[ \t\n]+" " " params)
            "\n#+END:\n")
    (goto-char (point-min))
    (org-update-dblock)
    (buffer-string)))

(defun agile-gtd-clockmatrix-test-table (params)
  "Render a clockmatrix block with PARAMS and return its table as Lisp.

Rows are lists of trimmed cell strings; horizontal rules are `hline'."
  (let ((text (agile-gtd-clockmatrix-test-render params)))
    (with-temp-buffer
      (org-mode)
      (insert text)
      (goto-char (point-min))
      (forward-line 1)
      (and (org-at-table-p) (org-table-to-lisp)))))

(defun agile-gtd-clockmatrix-test-warnings (params)
  "Render a clockmatrix block with PARAMS, returning the warnings it emits."
  (let ((warnings nil))
    (cl-letf (((symbol-function 'display-warning)
               (lambda (_type message &rest _) (push message warnings))))
      (agile-gtd-clockmatrix-test-table params))
    (nreverse warnings)))

;;; Matrix shape and cell attribution

(ert-deftest agile-gtd-clockmatrix-renders-periods-against-projects ()
  "Periods are rows, projects are columns, with totals on both axes."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step month
                     :stepskip0 t")
                   '(("Month" "alpha" "beta" "Total")
                     hline
                     ("2026-05" "3:15" "1:45" "5:00")
                     ("2026-06" "3:30" "" "3:30")
                     hline
                     ("Total" "6:45" "1:45" "8:30"))))))

(ert-deftest agile-gtd-clockmatrix-keeps-a-project-in-historical-ranges ()
  "A project with no recent time still appears in a range that covers it."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2025-01-01\" :tend \"2026-01-01\" :step month
                     :stepskip0 t")
                   '(("Month" "gamma" "Total")
                     hline
                     ("2025-11" "1:45" "1:45")
                     hline
                     ("Total" "1:45" "1:45"))))))

(ert-deftest agile-gtd-clockmatrix-keeps-all-zero-rows-by-default ()
  "Empty periods appear in the table without a `:stepskip0' override."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-04-01\" :tend \"2026-07-01\" :step month")
                   '(("Month" "alpha" "beta" "Total")
                     hline
                     ("2026-04" "" "" "")
                     ("2026-05" "3:15" "1:45" "5:00")
                     ("2026-06" "3:30" "" "3:30")
                     hline
                     ("Total" "6:45" "1:45" "8:30"))))))

(ert-deftest agile-gtd-clockmatrix-drops-all-zero-rows-with-stepskip0-t ()
  "`:stepskip0 t' removes periods where every project shows no time."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-04-01\" :tend \"2026-07-01\" :step month
                     :stepskip0 t")
                   '(("Month" "alpha" "beta" "Total")
                     hline
                     ("2026-05" "3:15" "1:45" "5:00")
                     ("2026-06" "3:30" "" "3:30")
                     hline
                     ("Total" "6:45" "1:45" "8:30"))))))

(ert-deftest agile-gtd-clockmatrix-suppresses-totals ()
  "`:total nil' drops the Total column and the Total row."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step month
                     :total nil :stepskip0 t")
                   '(("Month" "alpha" "beta")
                     hline
                     ("2026-05" "3:15" "1:45")
                     ("2026-06" "3:30" ""))))))

(ert-deftest agile-gtd-clockmatrix-honours-tags-override ()
  "`:tags' replaces the columns derived from `agile-gtd-projects'."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step month
                     :tags (\"beta\") :stepskip0 t")
                   '(("Month" "beta" "Total")
                     hline
                     ("2026-05" "1:45" "1:45")
                     hline
                     ("Total" "1:45" "1:45"))))))

;;; Period stepping

(ert-deftest agile-gtd-clockmatrix-labels-rows-per-step ()
  "Each `:step' names its label column and formats its row labels."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (pcase-dolist (`(,step ,tstart ,tend ,header ,label)
                   '(("day" "2026-05-04" "2026-05-05" "Day" "2026-05-04")
                     ("week" "2026-05-04" "2026-05-11" "Week" "2026-05-04")
                     ("semimonth" "2026-05-01" "2026-05-16" "Semimonth" "2026-05-01")
                     ("month" "2026-05-01" "2026-06-01" "Month" "2026-05")
                     ("quarter" "2026-04-01" "2026-07-01" "Quarter" "2026-Q2")
                     ("year" "2026-01-01" "2027-01-01" "Year" "2026")))
      (ert-info ((format "step=%s" step))
        (let ((table (agile-gtd-clockmatrix-test-table
                      (format ":tstart \"%s\" :tend \"%s\" :step %s :tags (\"alpha\")"
                              tstart tend step))))
          (should (equal (car table) (list header "alpha" "Total")))
          (should (equal (car (nth 2 table)) label)))))))

(ert-deftest agile-gtd-clockmatrix-steps-weeks-from-the-range-start ()
  "Weekly rows start on `:wstart', with a partial first week."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-05-01\" :tend \"2026-05-15\" :step week
                     :stepskip0 t")
                   '(("Week" "alpha" "beta" "Total")
                     hline
                     ("2026-05-04" "2:00" "1:15" "3:15")
                     ("2026-05-11" "1:15" "" "1:15")
                     hline
                     ("Total" "3:15" "1:15" "4:30"))))))

(ert-deftest agile-gtd-clockmatrix-splits-clocks-across-period-boundaries ()
  "A clock spanning two periods is split between them and sums to its length."
  (agile-gtd-clockmatrix-test-with-data
      '((:tag "delta" :name "Delta"))
      '(("delta.org" . "\
* TODO Delta task :delta:
:LOGBOOK:
CLOCK: [2026-05-31 Sun 22:15]--[2026-06-01 Mon 01:00] =>  2:45
:END:
"))
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-05-01\" :tend \"2026-07-01\" :step month")
                   '(("Month" "delta" "Total")
                     hline
                     ("2026-05" "1:45" "1:45")
                     ("2026-06" "1:00" "1:00")
                     hline
                     ("Total" "2:45" "2:45"))))))

(ert-deftest agile-gtd-clockmatrix-steps-semimonths-twice-in-a-month ()
  "Semimonth periods split a month at the 16th."
  (agile-gtd-clockmatrix-test-with-data
      '((:tag "delta" :name "Delta"))
      '(("delta.org" . "\
* TODO Delta task :delta:
:LOGBOOK:
CLOCK: [2026-05-04 Mon 09:00]--[2026-05-04 Mon 10:00] =>  1:00
CLOCK: [2026-05-20 Wed 09:00]--[2026-05-20 Wed 11:00] =>  2:00
CLOCK: [2026-06-02 Tue 09:00]--[2026-06-02 Tue 09:30] =>  0:30
:END:
"))
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-05-01\" :tend \"2026-07-01\" :step semimonth
                     :stepskip0 t")
                   '(("Semimonth" "delta" "Total")
                     hline
                     ("2026-05-01" "1:00" "1:00")
                     ("2026-05-16" "2:00" "2:00")
                     ("2026-06-01" "0:30" "0:30")
                     hline
                     ("Total" "3:30" "3:30"))))))

(ert-deftest agile-gtd-clockmatrix-caps-durations-at-hours ()
  "Durations past 24 hours read as hours and minutes, not days.
The ambient `org-duration-format' renders a day unit; the matrix drops it
so that monthly totals stay readable."
  (agile-gtd-clockmatrix-test-with-data
      '((:tag "delta" :name "Delta"))
      '(("delta.org" . "\
* TODO Delta task :delta:
:LOGBOOK:
CLOCK: [2026-05-04 Mon 00:00]--[2026-05-05 Tue 01:30] => 25:30
:END:
"))
    (let ((org-duration-format '(("d") (special . h:mm))))
      ;; Emacs' default format would render this as "1d 1:30".
      (should (equal (org-duration-from-minutes 1530) "1d 1:30"))
      (should (equal (agile-gtd-clockmatrix-test-table
                      ":tstart \"2026-05-01\" :tend \"2026-06-01\" :step month")
                     '(("Month" "delta" "Total")
                       hline
                       ("2026-05" "25:30" "25:30")
                       hline
                       ("Total" "25:30" "25:30")))))))

(ert-deftest agile-gtd-clockmatrix-refuses-a-step-that-cannot-advance ()
  "An out-of-range `:wstart' is reported rather than looping forever."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    ;; `:wstart' is a `decode-time' day number, so Sunday is 0, not 7.  With 7
    ;; the week step lands back on its own start date.
    (let ((error-message
           (cadr (should-error
                  (agile-gtd-clockmatrix-test-table
                   ":tstart \"2026-05-03\" :tend \"2026-05-18\" :step week :wstart 7")
                  :type 'user-error))))
      (should (string-match-p ":wstart" error-message)))))

(ert-deftest agile-gtd-clockmatrix-honours-a-non-default-wstart ()
  "Weeks can start on a day other than Monday."
  (agile-gtd-clockmatrix-test-with-data
      '((:tag "delta" :name "Delta"))
      '(("delta.org" . "\
* TODO Delta task :delta:
:LOGBOOK:
CLOCK: [2026-05-04 Mon 09:00]--[2026-05-04 Mon 10:00] =>  1:00
CLOCK: [2026-05-10 Sun 09:00]--[2026-05-10 Sun 11:00] =>  2:00
:END:
"))
    ;; Weeks starting on Sunday put 2026-05-10 in its own row; starting on
    ;; Monday it falls in the week of 2026-05-04 together with the other clock.
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-05-03\" :tend \"2026-05-17\" :step week :wstart 0
                     :stepskip0 t")
                   '(("Week" "delta" "Total")
                     hline
                     ("2026-05-03" "1:00" "1:00")
                     ("2026-05-10" "2:00" "2:00")
                     hline
                     ("Total" "3:00" "3:00"))))
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-05-03\" :tend \"2026-05-17\" :step week :wstart 1
                     :stepskip0 t")
                   '(("Week" "delta" "Total")
                     hline
                     ("2026-05-04" "3:00" "3:00")
                     hline
                     ("Total" "3:00" "3:00"))))))

(ert-deftest agile-gtd-clockmatrix-clips-the-last-period-to-the-range-end ()
  "The final period stops at the range end rather than running past it."
  (agile-gtd-clockmatrix-test-with-data
      '((:tag "delta" :name "Delta"))
      '(("delta.org" . "\
* TODO Delta task :delta:
:LOGBOOK:
CLOCK: [2026-05-12 Tue 09:00]--[2026-05-12 Tue 10:00] =>  1:00
CLOCK: [2026-05-16 Sat 09:00]--[2026-05-16 Sat 12:00] =>  3:00
:END:
"))
    ;; The week starting 2026-05-11 runs to 2026-05-18, but the range ends on
    ;; 2026-05-15, so the clock on 2026-05-16 is outside the report entirely.
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-05-01\" :tend \"2026-05-15\" :step week
                     :stepskip0 t")
                   '(("Week" "delta" "Total")
                     hline
                     ("2026-05-11" "1:00" "1:00")
                     hline
                     ("Total" "1:00" "1:00"))))))

(ert-deftest agile-gtd-clockmatrix-resolves-block-keyword-ranges ()
  "`:block' selects the range with clocktable's own vocabulary."
  (let ((today (format-time-string "%Y-%m-%d")))
    (agile-gtd-clockmatrix-test-with-data
        '((:tag "alpha" :name "Alpha"))
        (list (cons "alpha.org"
                    (format "\
* TODO Alpha task :alpha:
:LOGBOOK:
CLOCK: [%s 09:00]--[%s 10:30] =>  1:30
:END:
" today today)))
      (should (equal (agile-gtd-clockmatrix-test-table ":block today :step day")
                     `(("Day" "alpha" "Total")
                       hline
                       (,today "1:30" "1:30")
                       hline
                       ("Total" "1:30" "1:30")))))))

;;; Scope and file resolution

(ert-deftest agile-gtd-clockmatrix-agenda-with-archives-scope-agrees ()
  "The wider audit scope reports the same numbers as the project files."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (setq org-agenda-files
          (mapcar (lambda (f) (expand-file-name f org-directory))
                  '("alpha.org" "beta.org" "gamma.org")))
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step month
                     :scope agenda-with-archives")
                   (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step month")))))

(ert-deftest agile-gtd-clockmatrix-warns-about-a-missing-project-file ()
  "A project whose main file is absent warns instead of reporting zero."
  (agile-gtd-clockmatrix-test-with-data
      '((:tag "alpha" :name "Alpha")
        (:tag "ghost" :name "Ghost"))
      '(("alpha.org" . "\
* TODO Alpha task :alpha:
:LOGBOOK:
CLOCK: [2026-05-04 Mon 09:00]--[2026-05-04 Mon 11:00] =>  2:00
:END:
"))
    (let ((warnings (agile-gtd-clockmatrix-test-warnings
                     ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step month")))
      (should (= 1 (length warnings)))
      (let ((warning (car warnings)))
        (should (string-match-p "ghost" warning))
        (should (string-match-p
                 (regexp-quote (expand-file-name "ghost.org" org-directory))
                 warning))
        (should (string-match-p ":file" warning))
        (should (string-match-p "agenda-with-archives" warning))))))

(ert-deftest agile-gtd-clockmatrix-does-not-warn-about-a-missing-archive ()
  "A project without an archive file is not a misconfiguration."
  (agile-gtd-clockmatrix-test-with-data
      '((:tag "alpha" :name "Alpha"))
      '(("alpha.org" . "\
* TODO Alpha task :alpha:
:LOGBOOK:
CLOCK: [2026-05-04 Mon 09:00]--[2026-05-04 Mon 11:00] =>  2:00
:END:
"))
    (should-not (agile-gtd-clockmatrix-test-warnings
                 ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step month"))))

(ert-deftest agile-gtd-clockmatrix-reads-a-project-from-a-renamed-file ()
  "A project registered with `:file' is read from that file."
  (agile-gtd-clockmatrix-test-with-data
      '((:tag "glas" :name "Cafe Glas" :file "cafe-glas.org"))
      '(("cafe-glas.org" . "\
* TODO Glas task :glas:
:LOGBOOK:
CLOCK: [2026-05-04 Mon 09:00]--[2026-05-04 Mon 10:00] =>  1:00
:END:
"))
    (should-not (agile-gtd-clockmatrix-test-warnings
                 ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step month
                  :stepskip0 t"))
    (should (equal (agile-gtd-clockmatrix-test-table
                    ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step month
                     :stepskip0 t")
                   '(("Month" "glas" "Total")
                     hline
                     ("2026-05" "1:00" "1:00")
                     hline
                     ("Total" "1:00" "1:00"))))))

;;; Block plumbing

(ert-deftest agile-gtd-clockmatrix-is-a-registered-dynamic-block ()
  "The block is offered by Org's dynamic-block insertion menu."
  (should (eq (cdr (assoc "clockmatrix" org-dynamic-block-alist))
              #'agile-gtd-clockmatrix)))

(ert-deftest agile-gtd-clockmatrix-requires-a-range ()
  "Without `:block' or `:tstart'/`:tend' the block says what is missing."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (let ((error-message
           (cadr (should-error (agile-gtd-clockmatrix-test-table ":step month")
                               :type 'user-error))))
      (should (string-match-p ":block" error-message))
      (should (string-match-p ":tstart" error-message)))))

(ert-deftest agile-gtd-clockmatrix-rejects-an-unknown-step ()
  "An unusable `:step' is reported rather than silently ignored."
  (agile-gtd-clockmatrix-test-with-data
      agile-gtd-clockmatrix-test-projects
      agile-gtd-clockmatrix-test-files
    (should-error (agile-gtd-clockmatrix-test-table
                   ":tstart \"2026-01-01\" :tend \"2027-01-01\" :step fortnight")
                  :type 'user-error)))

(provide 'agile-gtd-clockmatrix-test)

;;; agile-gtd-clockmatrix-test.el ends here
