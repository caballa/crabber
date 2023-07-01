;;; crabir-mode.el --- Major mode for the CrabIR language.
;;; Add in your emacs:
;;;
;;; (setq auto-mode-alist (cons '("\\.crabir$" . crabir-mode) auto-mode-alist))
;;; (autoload 'crabir-mode "crab" "Major mode for Crab language" t)
;;; (load-file "path/to/crabir-mode.el")
;;;

(defvar crab-font-lock-keywords
  (list
   `(,(regexp-opt '("cfg") 'symbols) . font-lock-function-name-face)   
   ;; Comments
   '("\#" . font-lock-comment-face)
   ;; Variables
   '("@[-a-zA-Z$\._][-a-zA-Z$\._0-9]*" . font-lock-variable-name-face)
   '(".str.[0-9]+" . font-lock-variable-name-face)   
   ;; Labels
   '("[-a-zA-Z$\._0-9]+:" . font-lock-variable-name-face)
   ;; Types
   `(,(regexp-opt '("i1" "i8" "i16" "i32" "i64") 'symbols) . font-lock-type-face)
   ;; Integer literals
   '("\\b[-]?[0-9]+\\b" . font-lock-preprocessor-face)
   ;; Keywords
   `(,(regexp-opt '("declare" "true" "false") 'symbols) . font-lock-constant-face)
   ;; Arithmetic and Logical Operators
   `(,(regexp-opt '("add" "sub" "mul" "sdiv" "udiv" "urem" "srem" "and" "or" "xor") 'symbols) . font-lock-keyword-face)
   ;; Special instructions
   `(,(regexp-opt '("call" "ite") 'symbols) . font-lock-keyword-face)
   ;; Control instructions
   `(,(regexp-opt '("assume" "if" "else" "goto" "unreachable") 'symbols) . font-lock-keyword-face)   
   ;; Verification instructions
   `(,(regexp-opt '("havoc" "assert") 'symbols) . font-lock-keyword-face)
   ;; Intrinsics
   `(,(regexp-opt '("value_partition_start" "value_partition_end") 'symbols) . font-lock-builtin-face)
   ;; Array operations
   `(,(regexp-opt '("array_store" "array_load" "array_assign") 'symbols) . font-lock-keyword-face)
   ;; Boolean operations
   `(,(regexp-opt '("not") 'symbols) . font-lock-keyword-face)
   ;; Memory operators
   `(,(regexp-opt '("region_init" "region_copy" "region_cast" "make_ref" "remove_ref" "load_from_ref" "store_to_ref" "gep_ref" "ref_to_int" "int_to_ref") 'symbols) . font-lock-keyword-face)
   ;; Casts
   `(,(regexp-opt '("trunc" "sext" "zext") 'symbols) . font-lock-keyword-face))
  "Syntax highlighting for CrabIR.")

;; Emacs 23 compatibility.
(defalias 'crabir-mode-prog-mode
  (if (fboundp 'prog-mode)
      'prog-mode
    'fundamental-mode))

;;;###autoload
(define-derived-mode crabir-mode crabir-mode-prog-mode "Crab"
  "Major mode for editing Crab source files."
  (setq font-lock-defaults `(crab-font-lock-keywords))
)

;;; (set-face-foreground 'font-lock-comment-face "red3")

;; Associate .crabir files with crabir-mode
;;;###autoload
(add-to-list 'auto-mode-alist (cons (purecopy "\\.crabir\\'")  'crabir-mode))

(provide 'crabir-mode)

;;; crabir-mode.el ends here
