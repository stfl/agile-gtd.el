;; -*- mode: eask; lexical-binding: t; -*-

(package "agile-gtd"
         "0.2.0"
         "Agile GTD workflow for Org")

(website-url "https://github.com/stfl/agile-gtd")
(keywords "outlines" "calendar" "tools")
(package-file "agile-gtd.el")

(files "agile-gtd.el")

(source 'gnu)
(source 'melpa)

(depends-on "emacs" "30.2")
(depends-on "dash")
(depends-on "org-modern")
(depends-on "org-ql" "0.8")
(depends-on "org-super-agenda" "1.3")
(depends-on "org-edna" "1.1.2")

;; Stale bytecode is loaded in preference to newer source, so a test run can
;; silently exercise the last compile rather than the working tree.  The sweep
;; leaves .eask alone: that is the dependencies' own bytecode, not ours.
(script "test" "find . -maxdepth 2 -name '*.elc' -not -path './.eask/*' -delete && eask test ert test/agile-gtd-test.el test/agile-gtd-rank-test.el test/agile-gtd-org-ql-predicates-test.el test/agile-gtd-agenda-test.el test/agile-gtd-startup-test.el")
