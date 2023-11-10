;;; jack-ts-mode.el --- Major mode for jack buffers using tree-sitter -*- lexical-binding: t; -*-

;; Author: Noah Peart <noah.v.peart@gmail.com>
;; URL: https://github.com/nverno/jack-ts-mode
;; Version: 1.0.0
;; Package-Requires: ((emacs "29.1"))
;; Created: 10 November 2023
;; Keywords: tree-sitter languages jack nand2tetris

;; This file is not part of GNU Emacs.
;;
;; This program is free software; you can redistribute it and/or
;; modify it under the terms of the GNU General Public License as
;; published by the Free Software Foundation; either version 3, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
;; General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; see the file COPYING.  If not, write to
;; the Free Software Foundation, Inc., 51 Franklin Street, Fifth
;; Floor, Boston, MA 02110-1301, USA.

;;; Commentary:
;;
;; Major mode for Jack language developed as part of the Nand2Tetris course from
;; https://www.nand2tetris.org/.
;;
;; Features:
;; - font-locking
;; - indentation
;; - structural navigation with tree-sitter objects
;; - imenu
;;
;;; Installation:
;;
;; Install the tree-sitter parser from https://github.com/nverno/tree-sitter-jack.
;;
;; ```lisp
;; (add-to-list 'treesit-language-source-alist
;;              '(jack "https://github.com/nverno/tree-sitter-jack"))
;; (treesit-install-language-grammar 'jack)
;; ```
;;
;;; Code:

(eval-when-compile (require 'cl-lib))
(require 'treesit)

(defcustom jack-ts-mode-indent-level 4
  "Number of spaces for each indententation step."
  :group 'jack
  :type 'integer
  :safe 'integerp)

;;; Syntax

(defvar jack-ts-mode--syntax-table
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?_  "_"     table)
    (modify-syntax-entry ?\\ "\\"    table)
    (modify-syntax-entry ?+  "."     table)
    (modify-syntax-entry ?-  "."     table)
    (modify-syntax-entry ?=  "."     table)
    (modify-syntax-entry ?%  "."     table)
    (modify-syntax-entry ?<  "."     table)
    (modify-syntax-entry ?>  "."     table)
    (modify-syntax-entry ?&  "."     table)
    (modify-syntax-entry ?|  "."     table)
    (modify-syntax-entry ?\' "\""    table)
    (modify-syntax-entry ?\240 "."   table)
    (modify-syntax-entry ?/  ". 124b" table)
    (modify-syntax-entry ?*  ". 23"   table)
    (modify-syntax-entry ?\n "> b"  table)
    (modify-syntax-entry ?\^m "> b" table)
    (modify-syntax-entry ?$ "_" table)
    (modify-syntax-entry ?` "\"" table)
    table)
  "Syntax table for `jack-ts-mode'.")

;;; Indentation

(defvar jack-ts-mode--indent-rules
  `((jack
     ((parent-is "source_file") parent 0)
     ((node-is ")") parent-bol 0)
     ((node-is "}") parent-bol 0)
     ((node-is "]") parent-bol 0)
     ((node-is "subroutine_body") parent-bol 0)
     (no-node parent-bol 0)
     (catch-all parent-bol jack-ts-mode-indent-level)))
  "Tree-sitter indentation rules for `jack-ts-mode'.")

;;; Font-Lock

(defvar jack-ts-mode--feature-list
  '(( comment definition)
    ( keyword string)
    ( type constant number assignment function property)
    ( operator variable bracket delimiter))
  "`treesit-font-lock-feature-list' for `jack-ts-mode'.")

(defvar jack-ts-mode--keywords
  '("class" "constructor" "method" "function"
    "field" "static" "var"
    "let" "if" "else" "while" "do" "return")
  "Jack keywords for tree-sitter font-locking.")

(defvar jack-ts-mode--operators
  '("-" "~"
    "+" "/" "*"
    "&" "|" "<" ">" "=")
  "Jack operators for tree-sitter font-locking.")

(defvar jack-ts-mode--font-lock-settings
  (treesit-font-lock-rules
   :language 'jack
   :feature 'comment
   '((comment) @font-lock-comment-face
     (doc_comment) @font-lock-doc-face)

   :language 'jack
   :feature 'string
   '((string) @font-lock-string-face)

   :language 'jack
   :feature 'keyword
   `([,@jack-ts-mode--keywords (this)] @font-lock-keyword-face)

   :language 'jack
   :feature 'definition
   '((class_declaration
      (identifier) @font-lock-type-face)

     (subroutine_declaration
      name: (identifier) @font-lock-function-name-face
      (formal_parameters
       (parameter
        (identifier) @font-lock-variable-name-face :*)
       :?))

     (class_variable_declaration
      (identifier) @font-lock-variable-name-face)

     (local_variable_declaration
      (identifier) @font-lock-variable-name-face))

   :language 'jack
   :feature 'type
   '((type) @font-lock-type-face

     (member_expression
      object: (identifier) @font-lock-type-face
      "." @font-lock-delimiter-face))
   
   :language 'jack
   :feature 'constant
   '([(true) (false) (null)] @font-lock-constant-face)

   :language 'jack
   :feature 'function
   '((call_expression
      function: (identifier) @font-lock-function-call-face)

     (call_expression
      function: (member_expression
                 property: (identifier) @font-lock-function-call-face)))

   :language 'jack
   :feature 'assignment
   '((let_statement
      (identifier) @font-lock-variable-name-face
      :anchor "=" )

     (let_statement
      (subscript_expression
       object: (identifier) @font-lock-variable-name-face)
      :anchor "=" ))
   
   :language 'jack
   :feature 'variable
   '((identifier) @font-lock-variable-use-face)
   
   :language 'jack
   :feature 'number
   '((integer) @font-lock-number-face)

   :language 'jack
   :feature 'operator
   `([,@jack-ts-mode--operators] @font-lock-operator-face)

   :language 'jack
   :feature 'delimiter
   '(["." "," ";"] @font-lock-delimiter-face)

   :language 'jack
   :feature 'bracket
   '(["(" ")" "{" "}" "[" "]"] @font-lock-bracket-face))
  "Tree-sitter font-lock settings for Jack.")

;;; Navigation

(defun jack-ts-mode--defun-name (node)
  "Find name of NODE."
  (treesit-node-text
   (or (treesit-node-child-by-field-name node "name")
       node)))

(defvar jack-ts-mode--sentence-nodes nil
  "See `treesit-sentence-type-regexp' for more information.")

(defvar jack-ts-mode--sexp-nodes nil
  "See `treesit-sexp-type-regexp' for more information.")

(defvar jack-ts-mode--text-nodes
  (rx (or "string" "comment" "doc_comment"))
  "See `treesit-text-type-regexp' for more information.")

;;;###autoload
(define-derived-mode jack-ts-mode prog-mode "Jack"
  "Major mode for editing Jack source code.

\\{jack-ts-mode-map}"
  :group 'jack
  :syntax-table jack-ts-mode--syntax-table
  (when (treesit-ready-p 'jack)
    (treesit-parser-create 'jack)

    ;; Comments
    (setq-local comment-start "//")
    (setq-local comment-end "")
    (setq-local comment-start-skip "//+[ \t]*")
    (setq-local parse-sexp-ignore-comments t)

    ;; Indentation
    (setq-local treesit-simple-indent-rules jack-ts-mode--indent-rules)

    ;; Font-Locking
    (setq-local treesit-font-lock-settings jack-ts-mode--font-lock-settings)
    (setq-local treesit-font-lock-feature-list jack-ts-mode--feature-list)

    ;; Navigation
    (setq-local treesit-defun-tactic 'nested)
    (setq-local treesit-defun-name-function #'jack-ts-mode--defun-name)
    (setq-local treesit-defun-type-regexp
                (rx (or "subroutine_declaration"
                        "class_declaration")))

    (setq-local treesit-thing-settings
                `((jack
                   (sexp ,jack-ts-mode--sexp-nodes)
                   (sentence ,jack-ts-mode--sentence-nodes)
                   (text ,jack-ts-mode--text-nodes))))

    ;; Imenu
    (setq-local treesit-simple-imenu-settings
                `(("Subroutine" "\\`subroutine_declaration\\'")
                  ("Class" "\\`class_declaration\\'")))

    (treesit-major-mode-setup)))

(when (treesit-ready-p 'jack)
  (add-to-list 'auto-mode-alist '("\\.jack\\'" . jack-ts-mode)))

(provide 'jack-ts-mode)
;; Local Variables:
;; coding: utf-8
;; indent-tabs-mode: nil
;; End:
;;; jack-ts-mode.el ends here
