;;; agile-gtd-clock-range-test.el --- Tests for rolling clock ranges -*- lexical-binding: t; -*-

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

;; The keywords are generic, so they are driven through both dynamic blocks
;; that accept a range.  Clockmatrix brings its own sandbox and fixtures.
(require 'agile-gtd-clockmatrix-test)

;;; Fixtures
;;
;; These keywords are relative to today, so fixtures are derived from the run
;; date and assertions are made on relationships between rows rather than on
;; absolute labels.  Hard-coded dates would make the suite pass until a
;; particular week and then fail for reasons unrelated to the code.

(defun agile-gtd-clock-range-test-stamp (offset)
  "Return the Org date OFFSET days from today, with its day name.
The arithmetic runs at midday so a daylight-saving transition cannot
carry a date over into its neighbour."
  (pcase-let ((`(,_ ,_ ,_ ,d ,m ,y . ,_) (decode-time)))
    (format-time-string "%Y-%m-%d %a" (org-encode-time 0 0 12 (+ d offset) m y))))

(defun agile-gtd-clock-range-test-entry (clocks)
  "Return an Org entry tagged `alpha' holding CLOCKS.
Each element of CLOCKS is (DAY-OFFSET . HOURS), the offset counted from
today, so the fixture moves with the run date."
  (concat "* TODO Alpha task :alpha:\n:LOGBOOK:\n"
          (mapconcat (pcase-lambda (`(,offset . ,hours))
                       (let ((stamp (agile-gtd-clock-range-test-stamp offset)))
                         (format "CLOCK: [%s 09:00]--[%s %02d:00] => %2d:00\n"
                                 stamp stamp (+ 9 hours) hours)))
                     clocks "")
          ":END:\n"))

(defmacro agile-gtd-clock-range-test-with-clocks (clocks &rest body)
  "Run BODY with one project, `alpha', holding CLOCKS in the sandbox."
  (declare (indent 1) (debug t))
  `(agile-gtd-clockmatrix-test-with-data
       '((:tag "alpha" :name "Alpha"))
       (list (cons "alpha.org" (agile-gtd-clock-range-test-entry ,clocks)))
     ,@body))

(defun agile-gtd-clock-range-test-clocktable (clocks params)
  "Render a plain clocktable with PARAMS over an entry holding CLOCKS.
Return the whole buffer text.  Clocktable defaults to the current file,
so the entry and the block share one buffer."
  (let ((org-duration-format 'h:mm)
        (org-extend-today-until 0))
    (with-temp-buffer
      (org-mode)
      (insert (agile-gtd-clock-range-test-entry clocks)
              "\n#+BEGIN: clocktable "
              (replace-regexp-in-string "[ \t\n]+" " " params)
              "\n#+END:\n")
      (search-backward "#+BEGIN:")
      (org-update-dblock)
      (buffer-string))))

;;; Reading the rendered output

(defun agile-gtd-clock-range-test-rows (table)
  "Return TABLE's data rows, those between its two horizontal rules."
  (cl-loop for row in (cdr (memq 'hline table))
           until (eq row 'hline)
           collect row))

(defun agile-gtd-clock-range-test-labels (params)
  "Return the row labels a clockmatrix block with PARAMS renders."
  (mapcar #'car (agile-gtd-clock-range-test-rows
                 (agile-gtd-clockmatrix-test-table params))))

(defun agile-gtd-clock-range-test-gaps (dates)
  "Return the day counts between consecutive DATES."
  (cl-loop for (from to) on dates while to
           collect (- (time-to-days (org-time-string-to-time to))
                      (time-to-days (org-time-string-to-time from)))))

(defun agile-gtd-clock-range-test-weekday (date)
  "Return the `decode-time' day number DATE falls on, Sunday being 0."
  (nth 6 (decode-time (org-time-string-to-time date))))

(defun agile-gtd-clock-range-test-count (prefix text)
  "Return how many lines of TEXT begin with PREFIX."
  (cl-count-if (lambda (line) (string-prefix-p prefix line))
               (split-string text "\n")))

(defun agile-gtd-clock-range-test-step-dates (text)
  "Return the dates heading the sub-tables of a stepped clocktable TEXT."
  (let ((dates nil)
        (start 0))
    (while (string-match "report[^[\n]*\\[\\([0-9-]+\\)" text start)
      (push (match-string 1 text) dates)
      (setq start (match-end 1)))
    (nreverse dates)))

(defun agile-gtd-clock-range-test-table-lines (clocks params)
  "Return only the table rows a plain clocktable renders over CLOCKS.
The caption names the range, and that is precisely what differs between
two spellings of one window, so it is dropped."
  (cl-remove-if-not
   (lambda (line) (string-prefix-p "|" line))
   (split-string (agile-gtd-clock-range-test-clocktable clocks params) "\n")))

;;; The window

(ert-deftest agile-gtd-clock-range-spans-n-whole-periods-ending-with-this-one ()
  "`lastweeks-N' reports N weekly rows, the last of them the current week."
  (agile-gtd-clock-range-test-with-clocks '((0 . 1))
    (let ((labels (agile-gtd-clock-range-test-labels
                   ":block lastweeks-4 :step week :stepskip0 nil"))
          ;; What Org's own `thisweek' renders, rather than what its range
          ;; resolver returns: the expectation stays on observable output.
          (current (car (agile-gtd-clock-range-test-labels
                         ":block thisweek :step week :stepskip0 nil"))))
      (should (= 4 (length labels)))
      (should (equal current (car (last labels))))
      ;; Whole weeks throughout, so no period at either edge is a stub.
      (should (equal '(7 7 7) (agile-gtd-clock-range-test-gaps labels))))))

(ert-deftest agile-gtd-clock-range-counts-periods-rather-than-offsets ()
  "`lastweeks-1' is the current week, where Org's `lastweek' is the one before."
  ;; An hour this week and two in the week before, so the two readings cannot
  ;; agree by accident.
  (agile-gtd-clock-range-test-with-clocks '((0 . 1) (-7 . 2))
    (let ((span (agile-gtd-clockmatrix-test-table ":block lastweeks-1 :step week"))
          (current (agile-gtd-clockmatrix-test-table ":block thisweek :step week"))
          (previous (agile-gtd-clockmatrix-test-table ":block lastweek :step week")))
      (should (equal span current))
      (should-not (equal span previous))
      (should (equal '("1:00" "1:00")
                     (cdr (car (agile-gtd-clock-range-test-rows span)))))
      (should (equal '("2:00" "2:00")
                     (cdr (car (agile-gtd-clock-range-test-rows previous))))))))

(ert-deftest agile-gtd-clock-range-covers-every-step-unit ()
  "The keyword family matches `:step' unit for unit, with none missing."
  (agile-gtd-clock-range-test-with-clocks '((0 . 1))
    (dolist (unit '("day" "week" "semimonth" "month" "quarter" "year"))
      (ert-info ((format "unit=%s" unit))
        (should (= 3 (length (agile-gtd-clock-range-test-labels
                              (format ":block last%ss-3 :step %s :stepskip0 nil"
                                      unit unit)))))))))

(ert-deftest agile-gtd-clock-range-steps-semimonths-across-a-month-boundary ()
  "Semimonths start on the 1st and the 16th, whatever month they fall in."
  (agile-gtd-clock-range-test-with-clocks '((0 . 1))
    (let ((labels (agile-gtd-clock-range-test-labels
                   ":block lastsemimonths-5 :step semimonth :stepskip0 nil")))
      (should (= 5 (length labels)))
      ;; Five halves of a month always reach back over at least one boundary.
      (should (< 1 (length (delete-dups
                            (mapcar (lambda (l) (substring l 0 7)) labels)))))
      (dolist (label labels)
        (should (member (substring label 8) '("01" "16")))))))

(ert-deftest agile-gtd-clock-range-aligns-weeks-to-wstart ()
  "Week boundaries follow `:wstart', which starts the week on Monday."
  (agile-gtd-clock-range-test-with-clocks '((0 . 1) (-7 . 2))
    (pcase-dolist (`(,params ,weekday)
                   '((":block lastweeks-2 :step week :stepskip0 nil" 1)
                     (":block lastweeks-2 :step week :wstart 0 :stepskip0 nil" 0)))
      (ert-info ((format "params=%s" params))
        (let ((labels (agile-gtd-clock-range-test-labels params)))
          ;; Both boundaries move with `:wstart', so the window stays two
          ;; whole weeks rather than growing a stub at one end.
          (should (= 2 (length labels)))
          (should (equal '(7) (agile-gtd-clock-range-test-gaps labels)))
          (dolist (label labels)
            (should (= weekday (agile-gtd-clock-range-test-weekday label)))))))))

;;; A plain clocktable
;;
;; Exercising a real clocktable is what proves the keyword is generic; through
;; clockmatrix alone the feature's reason for existing would go unverified.

(ert-deftest agile-gtd-clock-range-resolves-in-a-plain-clocktable ()
  "A clocktable accepts the keyword and reports the whole window."
  (let ((text (agile-gtd-clock-range-test-clocktable
               '((0 . 1) (-7 . 2)) ":block lastweeks-2")))
    (should (string-match-p "for the last 2 weeks" text))
    (should (string-match-p "\\*Total time\\*.*\\*3:00\\*" text)))
  (let ((text (agile-gtd-clock-range-test-clocktable
               '((0 . 1) (-7 . 2)) ":block lastweeks-1")))
    (should (string-match-p "\\*Total time\\*.*\\*1:00\\*" text))))

(ert-deftest agile-gtd-clock-range-covers-the-current-week-in-a-clocktable ()
  "`lastweeks-1' selects the same window as `thisweek'."
  (let ((clocks '((0 . 1) (-7 . 2))))
    (should (equal (agile-gtd-clock-range-test-table-lines clocks ":block lastweeks-1")
                   (agile-gtd-clock-range-test-table-lines clocks ":block thisweek")))))

(ert-deftest agile-gtd-clock-range-steps-a-clocktable-over-the-window ()
  "`:step' chops the window into one sub-table per step period."
  (let ((weekly (agile-gtd-clock-range-test-clocktable
                 '((0 . 1) (-7 . 2)) ":block lastweeks-2 :step week")))
    (should (= 2 (agile-gtd-clock-range-test-count
                  "Weekly report starting on: " weekly)))
    (let ((dates (agile-gtd-clock-range-test-step-dates weekly)))
      (should (equal '(7) (agile-gtd-clock-range-test-gaps dates)))
      (dolist (date dates)
        (should (= 1 (agile-gtd-clock-range-test-weekday date)))))
    (should (string-match-p "\\*2:00\\*" weekly))
    (should (string-match-p "\\*1:00\\*" weekly))))

(ert-deftest agile-gtd-clock-range-accepts-a-step-finer-than-the-window ()
  "A step that divides the window cleanly is a sound way to read it."
  (let* ((daily (agile-gtd-clock-range-test-clocktable
                 '((0 . 1)) ":block lastweeks-2 :step day"))
         (dates (agile-gtd-clock-range-test-step-dates daily))
         (weekly (agile-gtd-clock-range-test-clocktable
                  '((0 . 1)) ":block lastweeks-2 :step week")))
    (should (= 14 (agile-gtd-clock-range-test-count "Daily report: " daily)))
    ;; Fourteen sub-tables are only a clean tiling if each is a whole day and
    ;; together they cover the same two weeks, edge to edge.
    (should (= 14 (length dates)))
    (should (equal (make-list 13 1) (agile-gtd-clock-range-test-gaps dates)))
    (should (equal (car (agile-gtd-clock-range-test-step-dates weekly))
                   (car dates)))))

;;; Reporting nonsense

(ert-deftest agile-gtd-clock-range-reports-a-count-that-is-not-one ()
  "N counts periods, so anything but a positive whole number is reported."
  (agile-gtd-clock-range-test-with-clocks '((0 . 1))
    (dolist (block '("lastweeks-0" "lastweeks--3" "lastweeks-several"))
      (ert-info ((format "block=%s" block))
        (let ((error-message
               (cadr (should-error
                      (agile-gtd-clockmatrix-test-table
                       (format ":block %s :step week" block))
                      :type 'user-error))))
          (should (string-match-p (regexp-quote block) error-message))
          (should (string-match-p "periods" error-message)))))))

(ert-deftest agile-gtd-clock-range-leaves-an-unknown-unit-to-org ()
  "A unit outside the family fails the way any other typo always has."
  (agile-gtd-clock-range-test-with-clocks '((0 . 1))
    (let ((error-message
           (cadr (should-error
                  (agile-gtd-clockmatrix-test-table
                   ":block lastfortnights-2 :step week")
                  :type 'user-error))))
      (should (string-match-p "No such time block" error-message))
      ;; Org reports the key it was handed, so the unit reaches it unmangled.
      (should (string-match-p "fortnight" error-message)))))

;;; The shift command

(defun agile-gtd-clock-range-test-shift (block)
  "Shift a clocktable whose `:block' is BLOCK, returning its `:block' after."
  (with-temp-buffer
    (org-mode)
    (insert (format "#+BEGIN: clocktable :block %s :step week\n#+END:\n" block))
    (goto-char (point-min))
    (org-clocktable-shift 'right 1)
    (goto-char (point-min))
    (and (looking-at ".*:block[ \t]+\\(\\S-+\\)") (match-string 1))))

(ert-deftest agile-gtd-clock-range-refuses-to-shift-a-rolling-block ()
  "Shifting such a block refuses in Org's own words and leaves it intact."
  (dolist (block '("lastweeks-8" "lastmonths-12"))
    (ert-info ((format "block=%s" block))
      ;; Org would otherwise read the digits as a bare year and rewrite the
      ;; block to it, with nothing left in the buffer to recover from.
      (should (equal "Cannot shift clocktable block"
                     (cadr (should-error (agile-gtd-clock-range-test-shift block)
                                         :type 'user-error))))
      (with-temp-buffer
        (org-mode)
        (insert (format "#+BEGIN: clocktable :block %s :step week\n#+END:\n" block))
        (goto-char (point-min))
        (ignore-errors (org-clocktable-shift 'right 1))
        (should (string-match-p (format ":block %s" block) (buffer-string)))))))

(ert-deftest agile-gtd-clock-range-still-shifts-a-block-org-can-shift ()
  "The refusal is narrow: a shiftable block shifts as it always has."
  (should (equal "thisweek-7" (agile-gtd-clock-range-test-shift "thisweek-8"))))

(provide 'agile-gtd-clock-range-test)

;;; agile-gtd-clock-range-test.el ends here
