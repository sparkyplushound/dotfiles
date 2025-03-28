;;; ob-exp.el --- Exportation of Babel Source Blocks -*- lexical-binding: t; -*-

;; Copyright (C) 2009-2025 Free Software Foundation, Inc.

;; Authors: Eric Schulte
;;	Dan Davison
;; Keywords: literate programming, reproducible research
;; URL: https://orgmode.org

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

;;; Code:

(require 'org-macs)
(org-assert-version)

(require 'ob-core)

(declare-function org-babel-lob-get-info "ob-lob" (&optional datum no-eval))
(declare-function org-element-at-point "org-element" (&optional pom cached-only))
(declare-function org-element-context "org-element" (&optional element))
(declare-function org-element-property "org-element-ast" (property node))
(declare-function org-element-begin "org-element" (node))
(declare-function org-element-end "org-element" (node))
(declare-function org-element-type "org-element-ast" (node &optional anonymous))
(declare-function org-escape-code-in-string "org-src" (s))
(declare-function org-export-copy-buffer "ox"
                  (&optional buffer drop-visibility
                             drop-narrowing drop-contents
                             drop-locals))
(declare-function org-in-commented-heading-p "org" (&optional no-inheritance element))
(declare-function org-in-archived-heading-p "org" (&optional no-inheritance element))
(declare-function org-src-preserve-indentation-p "org-src" (node))

(defcustom org-export-use-babel t
  "Switch controlling code evaluation and header processing during export.
When set to nil no code will be evaluated as part of the export
process and no header arguments will be obeyed.  Users who wish
to avoid evaluating code on export should use the header argument
`:eval never-export'."
  :group 'org-babel
  :version "24.1"
  :type '(choice (const :tag "Never" nil)
		 (const :tag "Always" t))
  :safe #'null)


(defmacro org-babel-exp--at-source (&rest body)
  "Evaluate BODY at the source of the Babel block at point.
Source is located in `org-babel-exp-reference-buffer'.  The value
returned is the value of the last form in BODY.  Assume that
point is at the beginning of the Babel block."
  (declare (indent 1) (debug body))
  `(let ((source (get-text-property (point) 'org-reference)))
     ;; Source blocks created during export process (e.g., by other
     ;; source blocks) are not referenced.  In this case, do not move
     ;; point at all.
     (with-current-buffer (if source org-babel-exp-reference-buffer
			    (current-buffer))
       (org-with-wide-buffer
	(when source (goto-char source))
	,@body))))

(defun org-babel-exp-src-block (&optional element)
  "Process source block for export.
Depending on the \":export\" header argument, replace the source
code block like this:

both ---- display the code and the results

code ---- the default, display the code inside the block but do
          not process

results - just like none only the block is run on export ensuring
          that its results are present in the Org mode buffer

none ---- do not display either code or results upon export

Optional argument ELEMENT must contain source block element at point.

Assume point is at block opening line."
  (interactive)
  (save-excursion
    (let* ((info (org-babel-get-src-block-info nil element))
	   (lang (nth 0 info))
	   (raw-params (nth 2 info))
	   hash)
      ;; bail if we couldn't get any info from the block
      (unless noninteractive
	(message "org-babel-exp process %s at position %d..."
		 lang
		 (line-beginning-position)))
      (when info
	;; if we're actually going to need the parameters
	(when (member (cdr (assq :exports (nth 2 info))) '("both" "results"))
	  (let ((lang-headers (intern (concat "org-babel-default-header-args:"
					      lang))))
	    (org-babel-exp--at-source
		(setf (nth 2 info)
		      (org-babel-process-params
		       (apply #'org-babel-merge-params
			      org-babel-default-header-args
			      (and (boundp lang-headers)
				   (symbol-value lang-headers))
			      (append (org-babel-params-from-properties lang)
				      (list raw-params)))))))
	  (setf hash (org-babel-sha1-hash info :export)))
	(org-babel-exp-do-export info 'block hash)))))

(defcustom org-babel-exp-call-line-template
  ""
  "Template used to export call lines.
This template may be customized to include the call line name
with any export markup.  The template is filled out using
`org-fill-template', and the following %keys may be used.

 line --- call line

An example value would be \"\\n: call: %line\" to export the call line
wrapped in a verbatim environment.

Note: the results are inserted separately after the contents of
this template."
  :group 'org-babel
  :type 'string)

(defun org-babel-exp-process-buffer ()
  "Execute all Babel blocks in current buffer."
  (interactive)
  (when org-export-use-babel
    (let ((case-fold-search t)
	  (regexp "\\(call\\|src\\)_\\|^[ \t]*#\\+\\(BEGIN_SRC\\|CALL:\\)")
	  ;; Get a pristine copy of current buffer so Babel
	  ;; references are properly resolved and source block
	  ;; context is preserved.
	  (org-babel-exp-reference-buffer (org-export-copy-buffer))
	  element)
      (unwind-protect
	  (save-excursion
	    ;; First attach to every source block their original
	    ;; position, so that they can be retrieved within
	    ;; `org-babel-exp-reference-buffer', even after heavy
	    ;; modifications on current buffer.
	    ;;
	    ;; False positives are harmless, so we don't check if
	    ;; we're really at some Babel object.  Moreover,
	    ;; `line-end-position' ensures that we propertize
	    ;; a noticeable part of the object, without affecting
	    ;; multiple objects on the same line.
	    (goto-char (point-min))
	    (while (re-search-forward regexp nil t)
	      (let ((s (match-beginning 0)))
		(put-text-property s (line-end-position) 'org-reference s)))
	    ;; Evaluate from top to bottom every Babel block
	    ;; encountered.
	    (goto-char (point-min))
	    ;; We are about to do a large number of changes in
	    ;; buffer, but we do not care about folding in this
	    ;; buffer.
	    (org-fold-core-ignore-modifications
	      (while (re-search-forward regexp nil t)
		(setq element (save-match-data (org-element-at-point)))
		(unless (save-match-data
			  (or (org-in-commented-heading-p nil element)
			      (org-in-archived-heading-p nil element)))
		  (let* ((object? (match-end 1))
			 (element (save-match-data
				    (if object?
					(org-element-context element)
				      ;; No deep inspection if we're
				      ;; just looking for an element.
				      element)))
			 (type
			  (pcase (org-element-type element)
			    ;; Discard block elements if we're looking
			    ;; for inline objects.  False results
			    ;; happen when, e.g., "call_" syntax is
			    ;; located within affiliated keywords:
			    ;;
			    ;; #+name: call_src
			    ;; #+begin_src ...
			    ((and (or `babel-call `src-block) (guard object?))
			     nil)
			    (type type)))
			 (begin
			  (copy-marker (org-element-begin element)))
			 (end
			  (copy-marker
			   (save-excursion
			     (goto-char (org-element-end element))
			     (skip-chars-backward " \r\t\n")
			     (point)))))
		    (pcase type
		      (`inline-src-block
		       (let* ((info
			       (org-babel-get-src-block-info nil element))
			      (params (nth 2 info)))
			 (setf (nth 1 info)
			       (if (and (cdr (assq :noweb params))
					(string= "yes"
						 (cdr (assq :noweb params))))
				   (org-babel-expand-noweb-references
				    info org-babel-exp-reference-buffer)
				 (nth 1 info)))
			 (goto-char begin)
			 (let ((replacement
				(org-babel-exp-do-export info 'inline)))
			   (cond
                            ((equal replacement "")
			     ;; Replacement code is empty: remove
			     ;; inline source block, including extra
			     ;; white space that might have been
			     ;; created when inserting results.
			     (delete-region begin
					    (progn (goto-char end)
						   (skip-chars-forward " \t")
						   (point))))
                            ((not replacement)
                             ;; Replacement code cannot be determined.
                             ;; Leave the code block as is.
                             (goto-char end))
			    ;; Otherwise: remove inline source block
			    ;; but preserve following white spaces.
			    ;; Then insert value.
                            ((not (string= replacement
					 (buffer-substring begin end)))
			     (delete-region begin end)
			     (insert replacement))
                            ;; Replacement is the same as the source
                            ;; block.  Continue onwards.
                            (t (goto-char end))))))
		      ((or `babel-call `inline-babel-call)
		       (org-babel-exp-do-export
			(or (org-babel-lob-get-info element)
			    (user-error "Unknown Babel reference: %s"
					(org-element-property :call element)))
			'lob)
		       (let ((rep
			      (org-fill-template
			       org-babel-exp-call-line-template
			       `(("line"  .
				  ,(org-element-property :value element))))))
			 ;; If replacement is empty, completely remove
			 ;; the object/element, including any extra
			 ;; white space that might have been created
			 ;; when including results.
			 (cond
                          ((equal rep "")
			   (delete-region
			    begin
			    (progn (goto-char end)
				   (if (not (eq type 'babel-call))
				       (progn (skip-chars-forward " \t")
					      (point))
                                     (unless (eobp)
				       (skip-chars-forward " \r\t\n")
				       (line-beginning-position))))))
                          ((not rep)
                           ;; Replacement code cannot be determined.
                           ;; Leave the code block as is.
                           (goto-char end))
                          (t
			   ;; Otherwise, preserve trailing
			   ;; spaces/newlines and then, insert
			   ;; replacement string.
			   (goto-char begin)
			   (delete-region begin end)
			   (insert rep)))))
		      (`src-block
		       (let ((match-start (copy-marker (match-beginning 0)))
			     (ind (org-current-text-indentation)))
			 ;; Take care of matched block: compute
			 ;; replacement string.  In particular, a nil
			 ;; REPLACEMENT means the block is left as-is
			 ;; while an empty string removes the block.
			 (let ((replacement
				(progn (goto-char match-start)
				       (org-babel-exp-src-block element))))
			   (cond ((not replacement) (goto-char end))
				 ((equal replacement "")
				  (goto-char end)
                                  (unless (eobp)
				    (skip-chars-forward " \r\t\n")
				    (forward-line 0))
				  (delete-region begin (point)))
				 (t
				  (if (org-src-preserve-indentation-p element)
				      ;; Indent only code block
				      ;; markers.
				      (with-temp-buffer
				        ;; Do not use tabs for block
				        ;; indentation.
				        (when (fboundp 'indent-tabs-mode)
					  (indent-tabs-mode -1)
					  ;; FIXME: Emacs 26
					  ;; compatibility.
					  (setq-local indent-tabs-mode nil))
				        (insert replacement)
				        (skip-chars-backward " \r\t\n")
				        (indent-line-to ind)
				        (goto-char 1)
				        (indent-line-to ind)
				        (setq replacement (buffer-string)))
				    ;; Indent everything.
				    (with-temp-buffer
				      ;; Do not use tabs for block
				      ;; indentation.
				      (when (fboundp 'indent-tabs-mode)
					(indent-tabs-mode -1)
					;; FIXME: Emacs 26
					;; compatibility.
					(setq-local indent-tabs-mode nil))
				      (insert replacement)
				      (indent-rigidly
				       1 (point) ind)
				      (setq replacement (buffer-string))))
				  (goto-char match-start)
				  (let ((rend (save-excursion
						(goto-char end)
						(line-end-position))))
				    (if (string-equal replacement
						      (buffer-substring match-start rend))
					(goto-char rend)
				      (delete-region match-start
					             (save-excursion
					               (goto-char end)
					               (line-end-position)))
				      (insert replacement))))))
			 (set-marker match-start nil))))
		    (set-marker begin nil)
		    (set-marker end nil))))))
	(kill-buffer org-babel-exp-reference-buffer)
	(remove-text-properties (point-min) (point-max)
				'(org-reference nil))))))

(defun org-babel-exp-do-export (info type &optional hash)
  "Return a string with the exported content of a code block defined by INFO.
TYPE is the code block type: `block', `inline', or `lob'.  HASH is the
result hash.

Return nil when exported content cannot be determined.

The function respects the value of the :exports header argument."
  (let ((silently (lambda () (let ((session (cdr (assq :session (nth 2 info)))))
			  (unless (equal "none" session)
			    (org-babel-exp-results info type 'silent)))))
	(clean (lambda () (if (eq type 'inline)
			 (org-babel-remove-inline-result)
		       (org-babel-remove-result info)))))
    (pcase (or (cdr (assq :exports (nth 2 info))) "code")
      ("none" (funcall silently) (funcall clean) "")
      ("code" (funcall silently) (funcall clean) (org-babel-exp-code info type))
      ("results" (org-babel-exp-results info type nil hash) "")
      ("both"
       (org-babel-exp-results info type nil hash)
       (org-babel-exp-code info type))
      (unknown-value
       (warn "Unknown value of src block parameter :exports %S" unknown-value)
       nil))))

(defcustom org-babel-exp-code-template
  "#+begin_src %lang%switches%header-args\n%body\n#+end_src"
  "Template used to export the body of code blocks.
This template may be customized to include additional information
such as the code block name, or the values of particular header
arguments.  The template is filled out using `org-fill-template',
and the following %keys may be used.

 lang ------ the language of the code block
 name ------ the name of the code block
 body ------ the body of the code block
 switches -- the switches associated to the code block
 header-args the header arguments of the code block

In addition to the keys mentioned above, every header argument
defined for the code block may be used as a key and will be
replaced with its value."
  :group 'org-babel
  :type 'string
  :package-version '(Org . "9.7"))

(defcustom org-babel-exp-inline-code-template
  "src_%lang[%switches%header-args]{%body}"
  "Template used to export the body of inline code blocks.
This template may be customized to include additional information
such as the code block name, or the values of particular header
arguments.  The template is filled out using `org-fill-template',
and the following %keys may be used.

 lang ------ the language of the code block
 name ------ the name of the code block
 body ------ the body of the code block
 switches -- the switches associated to the code block
 header-args the header arguments of the code block

In addition to the keys mentioned above, every header argument
defined for the code block may be used as a key and will be
replaced with its value."
  :group 'org-babel
  :type 'string
  :package-version '(Org . "9.7"))

(defun org-babel-exp-code (info type)
  "Return the original code block of TYPE defined by INFO, formatted for export."
  (setf (nth 1 info)
	(if (string= "strip-export" (cdr (assq :noweb (nth 2 info))))
	    (replace-regexp-in-string
	     (org-babel-noweb-wrap) "" (nth 1 info))
	  (if (org-babel-noweb-p (nth 2 info) :export)
	      (org-babel-expand-noweb-references
	       info org-babel-exp-reference-buffer)
	    (nth 1 info))))
  (org-fill-template
   (if (eq type 'inline)
       org-babel-exp-inline-code-template
     org-babel-exp-code-template)
   `(("lang"  . ,(nth 0 info))
     ;; Inline source code should not be escaped.
     ("body"  . ,(let ((body (nth 1 info)))
                   (if (eq type 'inline) body
                     (org-escape-code-in-string body))))
     ("switches" . ,(let ((f (nth 3 info)))
		      (and (org-string-nw-p f) (concat " " f))))
     ("flags" . ,(let ((f (assq :flags (nth 2 info))))
		   (and f (concat " " (cdr f)))))
     ("header-args"
      .
      ,(org-babel-exp--at-source
           (when-let ((params (org-element-property :parameters (org-element-context))))
             (concat " " params))))
     ,@(mapcar (lambda (pair)
		 (cons (substring (symbol-name (car pair)) 1)
		       (format "%S" (cdr pair))))
	       (nth 2 info))
     ("name"  . ,(or (nth 4 info) "")))))

(defun org-babel-exp-results (info type &optional silent hash)
  "Evaluate and return the results of the current code block for export.
INFO is as returned by `org-babel-get-src-block-info'.  TYPE is the
code block type.  HASH is the result hash.

Results are prepared in a manner suitable for export by Org mode.
This function is called by `org-babel-exp-do-export'.  The code
block will be evaluated.  Optional argument SILENT can be used to
inhibit insertion of results into the buffer."
  (unless (and hash (equal hash (org-babel-current-result-hash)))
    (let ((lang (nth 0 info))
	  (body (if (org-babel-noweb-p (nth 2 info) :eval)
		    (org-babel-expand-noweb-references
		     info org-babel-exp-reference-buffer)
		  (nth 1 info)))
	  (info (copy-sequence info))
	  (org-babel-current-src-block-location (point-marker)))
      ;; Skip code blocks which we can't evaluate.
      (if (not (fboundp (intern (concat "org-babel-execute:" lang))))
          (warn "org-export: No org-babel-execute function for %s.  Not updating exported results." lang)
	(org-babel-eval-wipe-error-buffer)
	(setf (nth 1 info) body)
	(setf (nth 2 info)
	      (org-babel-exp--at-source
		  (org-babel-process-params
		   (org-babel-merge-params
		    (nth 2 info)
		    `((:results . ,(if silent "silent" "replace")))))))
	(pcase type
	  (`block (org-babel-execute-src-block nil info))
	  (`inline
	    ;; Position the point on the inline source block
	    ;; allowing `org-babel-insert-result' to check that the
	    ;; block is inline.
	    (goto-char (nth 5 info))
	    (org-babel-execute-src-block nil info))
	  (`lob
	   (save-excursion
	     (goto-char (nth 5 info))
	     (org-babel-execute-src-block nil info))))))))

(provide 'ob-exp)

;;; ob-exp.el ends here
