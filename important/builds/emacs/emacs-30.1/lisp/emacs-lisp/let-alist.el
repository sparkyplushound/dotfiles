;;; let-alist.el --- Easily let-bind values of an assoc-list by their names -*- lexical-binding: t; -*-

;; Copyright (C) 2014-2025 Free Software Foundation, Inc.

;; Author: Artur Malabarba <emacs@endlessparentheses.com>
;; Package-Requires: ((emacs "24.1"))
;; Version: 1.0.6
;; Keywords: extensions lisp
;; Prefix: let-alist
;; Separator: -

;; This is a GNU ELPA :core package.  Avoid functionality that is not
;; compatible with the version of Emacs recorded above.

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;; This package offers a single macro, `let-alist'.  This macro takes a
;; first argument (whose value must be an alist) and a body.
;;
;; The macro expands to a let form containing body, where each dotted
;; symbol inside body is let-bound to their cdrs in the alist.  Dotted
;; symbol is any symbol starting with a `.'.  Only those present in
;; the body are let-bound and this search is done at compile time.
;;
;; For instance, the following code
;;
;;   (let-alist alist
;;     (if (and .title .body)
;;         .body
;;       .site
;;       .site.contents))
;;
;; essentially expands to
;;
;;   (let ((.title (cdr (assq 'title alist)))
;;         (.body  (cdr (assq 'body alist)))
;;         (.site  (cdr (assq 'site alist)))
;;         (.site.contents (cdr (assq 'contents (cdr (assq 'site alist))))))
;;     (if (and .title .body)
;;         .body
;;       .site
;;       .site.contents))
;;
;; If you nest `let-alist' invocations, the inner one can't access
;; the variables of the outer one.  You can, however, access alists
;; inside the original alist by using dots inside the symbol, as
;; displayed in the example above by the `.site.contents'.

;;; Code:


(defun let-alist--deep-dot-search (data)
  "Return alist of symbols inside DATA that start with a `.'.
Perform a deep search and return an alist where each car is the
symbol, and each cdr is the same symbol without the `.'."
  (cond
   ((symbolp data)
    (let ((name (symbol-name data)))
      (when (string-match "\\`\\." name)
        ;; Return the cons cell inside a list, so it can be appended
        ;; with other results in the clause below.
        (list (cons data (intern (replace-match "" nil nil name)))))))
   ((vectorp data)
    (apply #'nconc (mapcar #'let-alist--deep-dot-search data)))
   ((not (consp data)) nil)
   ((eq (car data) 'let-alist)
    ;; For nested ‘let-alist’ forms, ignore symbols appearing in the
    ;; inner body because they don’t refer to the alist currently
    ;; being processed.  See Bug#24641.
    (let-alist--deep-dot-search (cadr data)))
   (t (append (let-alist--deep-dot-search (car data))
              (let-alist--deep-dot-search (cdr data))))))

(defun let-alist--access-sexp (symbol variable)
  "Return a sexp used to access SYMBOL inside VARIABLE."
  (let* ((clean (let-alist--remove-dot symbol))
         (name (symbol-name clean)))
    (if (string-match "\\`\\." name)
        clean
      (let-alist--list-to-sexp
       (mapcar #'intern (nreverse (split-string name "\\.")))
       variable))))

(defun let-alist--list-to-sexp (list var)
  "Turn symbols LIST into recursive calls to `cdr' `assq' on VAR."
  `(cdr (assq ',(car list)
              ,(if (cdr list) (let-alist--list-to-sexp (cdr list) var)
                 var))))

(defun let-alist--remove-dot (symbol)
  "Return SYMBOL, sans an initial dot."
  (let ((name (symbol-name symbol)))
    (if (string-match "\\`\\." name)
        (intern (replace-match "" nil nil name))
      symbol)))


;;; The actual macro.
;;;###autoload
(defmacro let-alist (alist &rest body)
  "Let-bind dotted symbols to their cdrs in ALIST and execute BODY.
Dotted symbol is any symbol starting with a `.'.  Only those present
in BODY are let-bound and this search is done at compile time.

For instance, the following code

  (let-alist alist
    (if (and .title .body)
        .body
      .site
      .site.contents))

essentially expands to

  (let ((.title (cdr (assq \\='title alist)))
        (.body  (cdr (assq \\='body alist)))
        (.site  (cdr (assq \\='site alist)))
        (.site.contents (cdr (assq \\='contents (cdr (assq \\='site alist))))))
    (if (and .title .body)
        .body
      .site
      .site.contents))

If you nest `let-alist' invocations, the inner one can't access
the variables of the outer one.  You can, however, access alists
inside the original alist by using dots inside the symbol, as
displayed in the example above.

To refer to a non-`let-alist' variable starting with a dot in BODY, use
two dots instead of one.  For example, in the following form `..foo'
refers to the variable `.foo' bound outside of the `let-alist':

    (let ((.foo 42)) (let-alist \\='((foo . nil)) ..foo))

Note that there is no way to differentiate the case where a key
is missing from when it is present, but its value is nil.  Thus,
the following form evaluates to nil:

    (let-alist \\='((some-key . nil))
      .some-key)"
  (declare (indent 1) (debug t))
  (let ((var (make-symbol "alist")))
    `(let ((,var ,alist))
       (let ,(mapcar (lambda (x) `(,(car x) ,(let-alist--access-sexp (car x) var)))
                     (delete-dups (let-alist--deep-dot-search body)))
         ,@body))))

(provide 'let-alist)

;;; let-alist.el ends here
