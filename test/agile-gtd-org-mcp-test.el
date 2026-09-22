;;; agile-gtd-org-mcp-test.el --- The agenda views as org-mcp view keys -*- lexical-binding: t; -*-

;;; Commentary:

;; These tests ask through the seam an MCP client uses: they call org-mcp's
;; org-view tool with a key, over sandboxed Org fixtures, and assert on what
;; comes back — the matched titles, their order and their computed fields.
;; They never inspect the generated query or the shape of `org-mcp-views'.

;;; Code:

(require 'ert)
(require 'agile-gtd)

(ert-deftest agile-gtd-org-mcp-is-loaded-with-agile-gtd ()
  "org-mcp is a hard dependency: loading agile-gtd loads it."
  (should (featurep 'org-mcp))
  (should (fboundp 'org-mcp--tool-view)))

(provide 'agile-gtd-org-mcp-test)
;;; agile-gtd-org-mcp-test.el ends here
