;;; em-hist.el --- history list management  -*- lexical-binding:t -*-

;; Copyright (C) 1999-2025 Free Software Foundation, Inc.

;; Author: John Wiegley <johnw@gnu.org>

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

;; Eshell's history facility imitates the syntax used by bash
;; ([(bash)History Interaction]).  Thus:
;;
;;   !ls           ; repeat the last command beginning with 'ls'
;;   !?ls          ; repeat the last command containing ls
;;   echo !ls:2    ; echo the second arg of the last 'ls' command
;;   !ls<tab>      ; complete against all possible words in this
;;                 ; position, by looking at the history list
;;   !ls<C-c SPC>  ; expand any matching history input at point
;;
;; Also, most of `comint-mode's keybindings are accepted:
;;
;;   M-r     ; search backward for a previous command by regexp
;;   M-s     ; search forward for a previous command by regexp
;;   M-p     ; access the last command entered, repeatable
;;   M-n     ; access the first command entered, repeatable
;;
;;   C-c M-r ; using current input, find a matching command thus, with
;;           ; 'ls' as the current input, it will go back to the same
;;           ; command that '!ls' would have selected
;;   C-c M-s ; same, but in reverse order
;;
;; Note that some of these keybindings are only available if the
;; `eshell-rebind' is not in use, in which case M-p does what C-c M-r
;; normally would do, and C-p is used instead of M-p.  It may seem
;; confusing, but the intention is to make the most useful
;; functionality the most easily accessible.  If `eshell-rebind' is
;; not being used, history navigation will use comint's keybindings;
;; if it is, history navigation tries to use similar keybindings to
;; bash.  This is all configurable, of course.

;;; Code:

(eval-when-compile (require 'cl-lib))

(require 'ring)
(require 'esh-opt)
(require 'esh-mode)

;;;###esh-module-autoload
(progn
(defgroup eshell-hist nil
  "This module provides command history management."
  :tag "History list management"
  :group 'eshell-module))

;;; User Variables:

(defcustom eshell-hist-load-hook nil
  "A list of functions to call when loading `eshell-hist'."
  :version "24.1"			; removed eshell-hist-initialize
  :type 'hook)

(defcustom eshell-hist-unload-hook
  (list
   (lambda ()
     (remove-hook 'kill-emacs-hook 'eshell-save-some-history)))
  "A hook that gets run when `eshell-hist' is unloaded."
  :type 'hook)
(make-obsolete-variable 'eshell-hist-unload-hook nil "30.1")

(defcustom eshell-history-file-name
  (expand-file-name "history" eshell-directory-name)
  "If non-nil, name of the file to read/write input history.
See also `eshell-read-history' and `eshell-write-history'.
If it is nil, Eshell will use the value of HISTFILE."
  :type '(choice (const :tag "Use HISTFILE" nil)
		 file))

(defcustom eshell-history-size 128
  "Size of the input history ring.  If nil, use envvar HISTSIZE."
  :type '(choice (const :tag "Use HISTSIZE" nil)
		 integer))

(defcustom eshell-hist-ignoredups nil
  "If non-nil, don't add input matching the last on the input ring.
The value `erase' mirrors the \"erasedups\" value of HISTCONTROL
in bash, and any other non-nil value mirrors the \"ignoredups\"
value."
  :type '(choice (const :tag "Don't ignore anything" nil)
                 (const :tag "Ignore consecutive duplicates" t)
                 (const :tag "Only keep last duplicate" erase)))

(defcustom eshell-save-history-on-exit t
  "Determine if history should be automatically saved.
History is always preserved after sanely exiting an Eshell buffer.
However, when Emacs is being shut down, this variable determines
whether to prompt the user.
If set to nil, it means never save history on termination of Emacs.
If set to `ask', ask if any Eshell buffers are open at exit time.
If set to t, history will always be saved, silently."
  :type '(choice (const :tag "Never" nil)
		 (const :tag "Ask" ask)
		 (const :tag "Always save" t)))

(defcustom eshell-history-append nil
  "If non-nil, append new entries to the history file when saving history."
  :type '(choice (const :tag "Overwrite history file" nil)
		 (const :tag "Append new entries to file" t))
  :version "30.1")

(defcustom eshell-input-filter 'eshell-input-filter-default
  "Predicate for filtering additions to input history.
Takes one argument, the input.  If non-nil, the input may be saved on
the input history list.  Default is to save anything that isn't all
whitespace."
  :type '(radio (function-item eshell-input-filter-default)
                (function-item eshell-input-filter-initial-space)
                (function :tag "Other function"))
  :risky t)

(defun eshell-hist--update-keymap (symbol value)
  "Update `eshell-hist-mode-map' for `eshell-hist-match-partial'."
  ;; Don't try to set this before it is bound.  See below.
  (when (and (boundp 'eshell-hist-mode-map)
             (eq symbol 'eshell-hist-match-partial))
    (dolist (keyb
             (if value
                 `(("M-p"     . ,#'eshell-previous-matching-input-from-input)
                   ("M-n"     . ,#'eshell-next-matching-input-from-input)
                   ("C-c M-p" . ,#'eshell-previous-input)
                   ("C-c M-n" . ,#'eshell-next-input))
               `(("M-p"     . ,#'eshell-previous-input)
                 ("M-n"     . ,#'eshell-next-input)
                 ("C-c M-p" . ,#'eshell-previous-matching-input-from-input)
                 ("C-c M-n" . ,#'eshell-next-matching-input-from-input))))
      (keymap-set eshell-hist-mode-map (car keyb) (cdr keyb))))
  (set-default symbol value))

(defcustom eshell-hist-match-partial t
  "If non-nil, movement through history is constrained by current input.
Otherwise, typing \\`M-p' and \\`M-n' will always go to the next history
element, regardless of any text on the command line.  In that case,
\\`C-c M-r' and \\`C-c M-s' still offer that functionality."
  :type 'boolean
  :set 'eshell-hist--update-keymap)

(defcustom eshell-hist-move-to-end t
  "If non-nil, move to the end of the buffer before cycling history."
  :type 'boolean)

(defcustom eshell-hist-event-designator
  "^!\\(!\\|-?[0-9]+\\|\\??[^:^$%*?]+\\??\\|#\\)"
  "The regexp used to identifier history event designators."
  :type 'regexp)

(defcustom eshell-hist-word-designator
  "^:?\\([0-9]+\\|[$^%*]\\)?\\(-[0-9]*\\|[$^%*]\\)?"
  "The regexp used to identify history word designators."
  :type 'regexp)

(defcustom eshell-hist-modifier
  "^\\(:\\([hretpqx&g]\\|s/\\([^/]*\\)/\\([^/]*\\)/\\)\\)*"
  "The regexp used to identity history modifiers."
  :type 'regexp)

(defcustom eshell-hist-rebind-keys-alist
  '(([(control ?p)]   . eshell-previous-input)
    ([(control ?n)]   . eshell-next-input)
    ([(control up)]   . eshell-previous-input)
    ([(control down)] . eshell-next-input)
    ([(control ?r)]   . eshell-isearch-backward)
    ([(control ?s)]   . eshell-isearch-forward)
    ([(meta ?r)]      . eshell-previous-matching-input)
    ([(meta ?s)]      . eshell-next-matching-input)
    ([(meta ?p)]      . eshell-previous-matching-input-from-input)
    ([(meta ?n)]      . eshell-next-matching-input-from-input)
    ([up]             . eshell-previous-matching-input-from-input)
    ([down]           . eshell-next-matching-input-from-input))
  "History keys to bind differently if point is in input text."
  :type '(repeat (cons (vector :tag "Keys to bind"
			       (repeat :inline t sexp))
		       (function :tag "Command"))))

;;; Internal Variables:

(defvar eshell-history-ring nil)
(defvar eshell-history-index nil)
(defvar eshell-matching-input-from-input-string "")
(defvar eshell-save-history-index nil)
(defvar eshell-hist--new-items nil
  "The number of new history items that have not been written to
file.  This variable is local in each eshell buffer.")

(defvar-keymap eshell-isearch-map
  :doc "Keymap used in isearch in Eshell."
  :parent isearch-mode-map
  "C-m"         #'eshell-isearch-return
  "C-r"         #'eshell-isearch-repeat-backward
  "C-s"         #'eshell-isearch-repeat-forward
  "C-g"         #'eshell-isearch-abort
  "<backspace>" #'eshell-isearch-delete-char
  "<delete>"    #'eshell-isearch-delete-char
  "C-c C-c"     #'eshell-isearch-cancel)

(defvar-keymap eshell-hist-mode-map
  "<up>"     #'eshell-previous-matching-input-from-input
  "<down>"   #'eshell-next-matching-input-from-input
  "C-<up>"   #'eshell-previous-input
  "C-<down>" #'eshell-next-input
  "M-r"      #'eshell-previous-matching-input
  "M-s"      #'eshell-next-matching-input
  "C-c M-r"  #'eshell-previous-matching-input-from-input
  "C-c M-s"  #'eshell-next-matching-input-from-input
  "C-c C-l"  #'eshell-list-history
  "C-c C-x"  #'eshell-get-next-from-history)
;; Update `eshell-hist-mode-map' for `eshell-hist-match-partial'.
(eshell-hist--update-keymap 'eshell-hist-match-partial
                            eshell-hist-match-partial)

(defvar eshell-rebind-keys-alist)

;;; Functions:

(defun eshell-input-filter-default (input)
  "Do not add blank input to input history.
Returns non-nil if INPUT is blank."
  (not (string-blank-p input)))

(defun eshell-input-filter-initial-space (input)
  "Do not add input beginning with empty space to history.
Returns nil if INPUT is prepended by blank space, otherwise non-nil."
  (not (string-match-p "\\`\\s-+" input)))

(define-minor-mode eshell-hist-mode
  "Minor mode for the eshell-hist module.

\\{eshell-hist-mode-map}"
  :keymap eshell-hist-mode-map)

(defun eshell-hist-initialize ()    ;Called from `eshell-mode' via intern-soft!
  "Initialize the history management code for one Eshell buffer."
  (when (eshell-using-module 'eshell-cmpl)
    (add-hook 'pcomplete-try-first-hook
	      #'eshell-complete-history-reference nil t))

  (if (and (eshell-using-module 'eshell-rebind)
	   (not eshell-non-interactive-p))
      (let ((rebind-alist eshell-rebind-keys-alist))
        (setq-local eshell-rebind-keys-alist
	      (append rebind-alist eshell-hist-rebind-keys-alist))
        (setq-local search-invisible t)
        (setq-local search-exit-option t)
	(add-hook 'isearch-mode-hook
                  (lambda ()
                    (if (>= (point) eshell-last-output-end)
                        (setq overriding-terminal-local-map
                              eshell-isearch-map)))
                  nil t)
	(add-hook 'isearch-mode-end-hook
                  (lambda ()
                    (setq overriding-terminal-local-map nil))
                  nil t))
    (eshell-hist-mode))

  (make-local-variable 'eshell-history-size)
  (or eshell-history-size
      (let ((hsize (getenv "HISTSIZE")))
        (setq eshell-history-size
	      (if (and (stringp hsize)
		       (integerp (setq hsize (string-to-number hsize)))
		       (> hsize 0))
		  hsize
		128))))

  (make-local-variable 'eshell-history-file-name)
  (or eshell-history-file-name
      (setq eshell-history-file-name (getenv "HISTFILE")))

  (make-local-variable 'eshell-history-index)
  (make-local-variable 'eshell-save-history-index)
  (setq-local eshell-hist--new-items 0)

  (setq-local eshell-history-ring nil)
  (when eshell-history-file-name
    (eshell-read-history nil t))

  (unless eshell-history-ring
    (setq eshell-history-ring (make-ring eshell-history-size)))

  (add-hook 'eshell-exit-hook #'eshell--save-history nil t)

  (add-hook 'kill-emacs-query-functions #'eshell-save-some-history)

  (add-hook 'eshell-input-filter-functions #'eshell-add-to-history nil t))

(defun eshell--save-history ()
  "Save the history for current Eshell buffer."
  (eshell-write-history nil eshell-history-append))

(defun eshell-save-some-history ()
  "Save the history for any open Eshell buffers."
  (dolist (buf (buffer-list))
    (if (buffer-live-p buf)
	(with-current-buffer buf
	  (if (and eshell-mode
		   eshell-history-file-name
		   eshell-save-history-on-exit
		   (or (eq eshell-save-history-on-exit t)
		       (y-or-n-p
			(format-message
			 "Save input history for Eshell buffer `%s'? "
			 (buffer-name buf)))))
	      (eshell--save-history)))))
  t)

(defun eshell/history (&rest args)
  "List in help buffer the buffer's input history."
  (eshell-eval-using-options
   "history" args
   '((?r "read" nil read-history
	 "clear current history list and read from history file to it")
     (?w "write" nil write-history
	 "write current history list to history file")
     (?a "append" nil append-history
	 "append new history in current buffer to history file")
     (?h "help" nil nil "display this usage message")
     :usage "[n] [-rwa [filename]]"
     :post-usage
"When Eshell is started, history is read from `eshell-history-file-name'.
This is also the location where history info will be saved by this command,
unless a different file is specified on the command line.")
   (and (or (not (ring-p eshell-history-ring))
	   (ring-empty-p eshell-history-ring))
	(error "No history"))
   (let (length file)
     (when (and args (string-match "^[0-9]+$" (car args)))
       (setq length (min (string-to-number (car args))
			 (ring-length eshell-history-ring))
	     args (cdr args)))
     (and length
	  (or read-history write-history append-history)
	  (error "history: extra arguments"))
     (when (and args (stringp (car args)))
       (setq file (car args)
	     args (cdr args)))
     (cond
      (read-history (eshell-read-history file))
      (write-history (eshell-write-history file))
      (append-history (eshell-write-history file t))
      (t
       (let* ((index (1- (or length (ring-length eshell-history-ring))))
	      (ref (- (ring-length eshell-history-ring) index)))
	 ;; We have to build up a list ourselves from the ring vector.
         (eshell-with-buffered-print
           (while (>= index 0)
             (eshell-buffered-print
              (format "%5d  %s\n" ref (eshell-get-history index)))
             (setq index (1- index)
                   ref (1+ ref))))))))
   nil))

(defun eshell-put-history (input &optional ring at-beginning)
  "Put a new input line into the history ring."
  (unless ring (setq ring eshell-history-ring))
  (if at-beginning
      (ring-insert-at-beginning ring input)
    (ring-insert ring input)))

(defun eshell-get-history (index &optional ring)
  "Get an input line from the history ring."
  (ring-ref (or ring eshell-history-ring) index))

(defun eshell-add-input-to-history (input)
  "Add the string INPUT to the history ring.
Input is entered into the input history ring, if the value of
variable `eshell-input-filter' returns non-nil when called on the
input."
  (when (and (funcall eshell-input-filter input)
             (pcase eshell-hist-ignoredups
               ('nil t)                 ; Always add to history
               ('erase                  ; Add, removing any old occurrences
                (while-let ((old-index (ring-member eshell-history-ring input)))
                  ;; Remove the old occurrences of this input so we can
                  ;; add it to the end.
                  (ring-remove eshell-history-ring old-index))
                t)
               (_                       ; Add if not already the latest entry
                (or (ring-empty-p eshell-history-ring)
                    (not (string-equal (eshell-get-history 0) input))))))
    (setq eshell-hist--new-items
          (min eshell-history-size (1+ eshell-hist--new-items)))
    (eshell-put-history input))
  (setq eshell-save-history-index eshell-history-index)
  (setq eshell-history-index nil))

(defun eshell-add-to-history ()
  "Add last Eshell command to the history ring.
The command is entered into the input history ring, if the value of
variable `eshell-input-filter' returns non-nil when called on the
command."
  (when (> (1- eshell-last-input-end) eshell-last-input-start)
    (let ((input (buffer-substring eshell-last-input-start
				   (1- eshell-last-input-end))))
      (eshell-add-input-to-history input))))

(defun eshell-read-history (&optional filename silent)
  "Sets the buffer's `eshell-history-ring' from a history file.
The name of the file is given by the variable
`eshell-history-file-name'.  The history ring is of size
`eshell-history-size', regardless of file size.  If
`eshell-history-file-name' is nil this function does nothing.

If the optional argument SILENT is non-nil, we say nothing about a
failure to read the history file.

This function is useful for major mode commands and mode hooks.

The structure of the history file should be one input command per
line, with the most recent command last.  See also
`eshell-hist-ignoredups' and `eshell-write-history'."
  (let ((file (or filename eshell-history-file-name)))
    (cond
     ((or (null file)
	  (equal file ""))
      nil)
     ((not (file-readable-p file))
      (or silent
	  (message "Cannot read history file %s" file)))
     (t
      (let* ((count 0)
	     (size eshell-history-size)
	     (ring (make-ring size))
	     (ignore-dups eshell-hist-ignoredups))
	(with-temp-buffer
	  (insert-file-contents file)
	  ;; Watch for those date stamps in history files!
	  (goto-char (point-max))
	  (while (and (< count size)
		      (re-search-backward "^[ \t]*\\([^#\n].*\\)[ \t]*$"
					  nil t))
	    (let ((history (match-string 1)))
              (when (or (ring-empty-p ring)
                        (null ignore-dups)
                        (and (not (string-equal
                                   (ring-ref ring (1- (ring-length ring)))
                                   history))
                             (not (and (eq ignore-dups 'erase)
                                       (ring-member ring history)))))
                (ring-insert-at-beginning
		 ring (subst-char-in-string ?\177 ?\n history))
                (setq count (1+ count))))))
	(setq eshell-history-ring ring
	      eshell-history-index nil
              eshell-hist--new-items 0))))))

(defun eshell-write-history (&optional filename append)
  "Writes the buffer's `eshell-history-ring' to a history file.
If the optional argument FILENAME is nil, the value of
`eshell-history-file-name' is used.  This function does nothing
if the value resolves to nil.

If the optional argument APPEND is non-nil, then append new
history items to the history file.  Otherwise, overwrite the
contents of the file with `eshell-history-ring' (so long as it is
not empty).

Useful within process sentinels.

See also `eshell-read-history'."
  (let* ((file (or filename eshell-history-file-name))
	 (resolved-file (if (stringp file) (file-truename file))))
    (cond
     ((or (null file)
	  (equal file "")
	  (null eshell-history-ring)
	  (ring-empty-p eshell-history-ring)
          (and append (= eshell-hist--new-items 0)))
      nil)
     ((not (file-writable-p resolved-file))
      (message "Cannot write history file %s" resolved-file))
     (t
      (let* ((ring eshell-history-ring)
	     (index (if append eshell-hist--new-items (ring-length ring))))
	;; Write it all out into a buffer first.  Much faster, but
	;; messier, than writing it one line at a time.
	(with-temp-buffer
	  (while (> index 0)
	    (setq index (1- index))
	    (let ((start (point)))
              ;; Remove properties before inserting, to avoid trouble
              ;; with read-only strings (Bug#28700).
              (insert (substring-no-properties (ring-ref ring index)) ?\n)
	      (subst-char-in-region start (1- (point)) ?\n ?\177)))
	  (eshell-with-private-file-modes
	   (write-region (point-min) (point-max) resolved-file append
			 'no-message)))
        (setq eshell-hist--new-items 0))))))

(defun eshell-list-history ()
  "List in help buffer the buffer's input history."
  (interactive)
  (let (prefix prelen)
    (save-excursion
      (if (re-search-backward "!\\(.+\\)" (line-beginning-position) t)
	  (setq prefix (match-string 1)
		prelen (length prefix))))
    (if (or (not (ring-p eshell-history-ring))
	    (ring-empty-p eshell-history-ring))
	(message "No history")
      (let ((history nil)
	    (history-buffer " *Input History*")
	    (index (1- (ring-length eshell-history-ring)))
	    (conf (current-window-configuration)))
	;; We have to build up a list ourselves from the ring vector.
	(while (>= index 0)
	  (let ((hist (eshell-get-history index)))
	    (if (or (not prefix)
		    (and (>= (length hist) prelen)
			 (string= (substring hist 0 prelen) prefix)))
		(setq history (cons hist history))))
	  (setq index (1- index)))
	;; Change "completion" to "history reference"
	;; to make the display accurate.
	(with-output-to-temp-buffer history-buffer
	  (display-completion-list
	   (completion-hilit-commonality history (length prefix)))
	  (set-buffer history-buffer)
	  (forward-line 3)
	  (while (search-backward "completion" nil 'move)
	    (replace-match "history reference")))
        (redisplay)
	(message "Hit space to flush")
	(let ((ch (read-event)))
	  (if (eq ch ?\ )
	      (set-window-configuration conf)
	    (push ch unread-command-events)))))))

(defun eshell-hist-word-reference (ref)
  "Return the word designator index referred to by REF."
  (cond
   ((string-match "^[0-9]+$" ref)
    (string-to-number ref))
   ((string= "^" ref) 1)
   ((string= "$" ref) nil)
   ((string= "%" ref)
    (error "`%%' history word designator not yet implemented"))))

(defun eshell-hist-parse-arguments (&optional b e)
  "Parse current command arguments in a history-code-friendly way."
  (let ((end (or e (point)))
	(begin (or b (save-excursion (beginning-of-line) (point))))
	(posb (list t))
	(pose (list t))
	(textargs (list t))
	hist args)
    (unless (catch 'eshell-incomplete
	      (ignore
	       (setq args (eshell-parse-arguments begin end))))
      (save-excursion
	(goto-char begin)
	(while (< (point) end)
	  (if (get-text-property (point) 'arg-begin)
	      (nconc posb (list (point))))
	  (if (get-text-property (point) 'arg-end)
	      (nconc pose
		     (list (if (= (1+ (point)) end)
			       (1+ (point))
			     (point)))))
	  (forward-char))
	(setq posb (cdr posb)
	      pose (cdr pose))
	(cl-assert (= (length posb) (length args)))
	(cl-assert (<= (length posb) (length pose))))
      (setq hist (buffer-substring-no-properties begin end))
      (let ((b posb) (e pose))
	(while b
	  (nconc textargs
		 (list (substring hist (- (car b) begin)
				  (- (car e) begin))))
	  (setq b (cdr b)
		e (cdr e))))
      (setq textargs (cdr textargs))
      (cl-assert (= (length textargs) (length args)))
      (list textargs posb pose))))

(defun eshell-expand-history-references (beg end)
  "Parse and expand any history references in current input."
  (let ((result (eshell-hist-parse-arguments beg end))
	(full-line (buffer-substring-no-properties beg end)))
    (when result
      (let ((textargs (nreverse (nth 0 result)))
	    (posb (nreverse (nth 1 result)))
	    (pose (nreverse (nth 2 result)))
	    (full-line-subst (eshell-history-substitution full-line)))
	(save-excursion
	  (if full-line-subst
	      ;; Found a ^foo^bar substitution
	      (progn
		(goto-char beg)
		(insert-and-inherit full-line-subst)
		(delete-char (- end beg)))
	    ;; Try to expand other substitutions
	    (while textargs
	      (let ((str (eshell-history-reference (car textargs))))
		(unless (eq str (car textargs))
		  (goto-char (car posb))
		  (insert-and-inherit str)
		  (delete-char (- (car pose) (car posb)))))
	      (setq textargs (cdr textargs)
		    posb (cdr posb)
		    pose (cdr pose)))))))))

(defvar pcomplete-stub)
(defvar pcomplete-last-completion-raw)
(declare-function pcomplete-actual-arg "pcomplete")

(defun eshell-complete-history-reference ()
  "Complete a history reference, by completing the event designator."
  (let ((arg (pcomplete-actual-arg)))
    (when (string-match "\\`![^:^$*%]*\\'" arg)
      (setq pcomplete-stub (substring arg 1)
	    pcomplete-last-completion-raw t)
      (throw 'pcomplete-completions
	     (let ((history nil)
		   (index (1- (ring-length eshell-history-ring)))
		   (stublen (length pcomplete-stub)))
	       ;; We have to build up a list ourselves from the ring
	       ;; vector.
	       (while (>= index 0)
		 (let ((hist (eshell-get-history index)))
		   (if (and (>= (length hist) stublen)
			    (string= (substring hist 0 stublen)
				     pcomplete-stub)
			    (string-match "^\\([^:^$*% \t\n]+\\)" hist))
		       (setq history (cons (match-string 1 hist)
					   history))))
		 (setq index (1- index)))
	       (let ((fhist (list t)))
		 ;; uniquify the list, but preserve the order
		 (while history
		   (unless (member (car history) fhist)
		     (nconc fhist (list (car history))))
		   (setq history (cdr history)))
		 (cdr fhist)))))))

(defun eshell-history-substitution (line)
  "Expand quick hist substitutions formatted as ^foo^bar^.
Returns nil if string does not match quick substitution format,
and acts like !!:s/foo/bar/ otherwise."
  ;; `^string1^string2^'
  ;;      Quick Substitution.  Repeat the last command, replacing
  ;;      STRING1 with STRING2.  Equivalent to `!!:s/string1/string2/'
  (when (and (eshell-using-module 'eshell-pred)
	     (string-match
	      "^\\^\\([^^]+\\)\\^\\([^^]+\\)\\(?:\\^\\(.*\\)\\)?$"
	      line))
    ;; Save trailing match as `eshell-history-reference' runs string-match.
    (let ((matched-end (match-string 3 line)))
      (concat
       (eshell-history-reference
	(format "!!:s/%s/%s/"
		(match-string 1 line)
		(match-string 2 line)))
       matched-end))))

(defun eshell-history-reference (reference)
  "Expand directory stack REFERENCE.
The syntax used here was taken from the Bash info manual.
Returns the resultant reference, or the same string REFERENCE if none
matched."
  ;; `!'
  ;;      Start a history substitution, except when followed by a
  ;;      space, tab, the end of the line, = or (.
  (if (not (string-match "^![^ \t\n=(]" reference))
      reference
    (setq eshell-history-index nil)
    (let ((event (eshell-hist-parse-event-designator reference)))
      (unless event
	(error "Could not find history event `%s'" reference))
      (setq eshell-history-index (car event)
	    reference (substring reference (cdr event))
	    event (eshell-get-history eshell-history-index))
      (if (not (string-match "^[:^$*%]" reference))
	  event
	(let ((word (eshell-hist-parse-word-designator
		     event reference)))
	  (unless word
	    (error "Unable to honor word designator `%s'" reference))
	  (unless (string-match "^[:^$*%][[$^*%0-9-]" reference)
	    (setcdr word 0))
	  (setq event (car word)
		reference (substring reference (cdr word)))
	  (if (not (and (eshell-using-module 'eshell-pred)
			(string-match "^:" reference)))
	      event
	    (eshell-hist-parse-modifier event reference)))))))

(defun eshell-hist-parse-event-designator (reference)
  "Parse a history event designator beginning in REFERENCE."
  (let* ((index (string-match eshell-hist-event-designator reference))
	 (end (and index (match-end 0))))
    (unless index
      (error "Invalid history event designator `%s'" reference))
    (let* ((event (match-string 1 reference))
	   (pos
	    (cond
	     ((string= event "!") (ring-length eshell-history-ring))
	     ((string= event "#") (error "!# not yet implemented"))
	     ((string-match "^-?[0-9]+$" event)
	      (let ((num (string-to-number event)))
		(if (>= num 0)
		    (- (ring-length eshell-history-ring) num)
		  (1- (abs num)))))
	     ((string-match "^\\(\\??\\)\\([^?]+\\)\\??$" event)
	      (let ((pref (if (> (length (match-string 1 event)) 0)
			      "" "^"))
		    (str (match-string 2 event)))
		(save-match-data
		  (eshell-previous-matching-input-string-position
		   (concat pref (regexp-quote str)) 1))))
	     (t
	      (error "Failed to parse event designator `%s'" event)))))
      (and pos (cons pos end)))))

(defun eshell-hist-parse-word-designator (hist reference)
  "Parse a history word designator beginning for HIST in REFERENCE."
  (let* ((index (string-match eshell-hist-word-designator reference))
	 (end (and index (match-end 0))))
    (unless (memq (aref reference 0) '(?: ?^ ?$ ?* ?%))
      (error "Invalid history word designator `%s'" reference))
    (let ((nth (match-string 1 reference))
	  (mth (match-string 2 reference))
	  (here (point))
	  textargs)
      (insert hist)
      (setq textargs (car (eshell-hist-parse-arguments here (point))))
      (delete-region here (point))
      (if (string= nth "*")
	  (if mth
	      (error "Invalid history word designator `%s'"
		     reference)
	    (setq nth 1 mth "-$")))
      (if (not mth)
	  (if nth
	      (setq mth nth)
	    (setq nth 0 mth "$"))
	(if (string= mth "-")
	    (setq mth (- (length textargs) 2))
	  (if (string= mth "*")
	      (setq mth "$")
	    (if (not (and (> (length mth) 1)
			  (eq (aref mth 0) ?-)))
		(error "Invalid history word designator `%s'"
		       reference)
	      (setq mth (substring mth 1))))))
      (unless (numberp nth)
	(setq nth (eshell-hist-word-reference nth)))
      (unless (numberp mth)
	(setq mth (eshell-hist-word-reference mth)))
      (cons (mapconcat #'identity (seq-subseq textargs nth (1+ mth)) " ")
	    end))))

(defun eshell-hist-parse-modifier (hist reference)
  "Parse a history modifier beginning for HIST in REFERENCE."
  (cl-assert (eshell-using-module 'em-pred))
  (declare-function eshell-parse-modifiers "em-pred" ())
  (let ((here (point)))
    (insert reference)
    (prog1
	(save-restriction
	  (narrow-to-region here (point))
	  (goto-char (point-min))
	  (let ((modifiers (cdr (eshell-parse-modifiers))))
	    (dolist (mod modifiers)
	      (setq hist (car (funcall mod (list hist)))))
	    hist))
      (delete-region here (point)))))

(defun eshell-get-next-from-history ()
  "After fetching a line from input history, this fetches the next.
In other words, this recalls the input line after the line you
recalled last.  You can use this to repeat a sequence of input lines."
  (interactive)
  (if eshell-save-history-index
      (progn
	(setq eshell-history-index (1+ eshell-save-history-index))
	(eshell-next-input 1))
    (message "No previous history command")))

(defun eshell-search-arg (arg)
  ;; First make sure there is a ring and that we are after the process
  ;; mark
  (if (and eshell-hist-move-to-end
	   (< (point) eshell-last-output-end))
      (goto-char eshell-last-output-end))
  (cond ((or (null eshell-history-ring)
	     (ring-empty-p eshell-history-ring))
	 (error "Empty input ring"))
	((zerop arg)
	 ;; arg of zero resets search from beginning, and uses arg of
	 ;; 1
	 (setq eshell-history-index nil)
	 1)
	(t
	 arg)))

(defun eshell-search-start (arg)
  "Index to start a directional search, starting at `eshell-history-index'."
  (if eshell-history-index
      ;; If a search is running, offset by 1 in direction of arg
      (mod (+ eshell-history-index (if (> arg 0) 1 -1))
	   (ring-length eshell-history-ring))
    ;; For a new search, start from beginning or end, as appropriate
    (if (>= arg 0)
	0                               ; First elt for forward search
      ;; Last elt for backward search
      (1- (ring-length eshell-history-ring)))))

(defun eshell-previous-input-string (arg)
  "Return the string ARG places along the input ring.
Moves relative to `eshell-history-index'."
  (eshell-get-history (if eshell-history-index
			  (mod (+ arg eshell-history-index)
			       (ring-length eshell-history-ring))
			arg)))

(defun eshell-previous-input (arg)
  "Cycle backwards through input history."
  (interactive "*p")
  (eshell-previous-matching-input "." arg))

(defun eshell-next-input (arg)
  "Cycle forwards through input history."
  (interactive "*p")
  (eshell-previous-input (- arg)))

(defun eshell-previous-matching-input-string (regexp arg)
  "Return the string matching REGEXP ARG places along the input ring.
Moves relative to `eshell-history-index'."
  (let* ((pos (eshell-previous-matching-input-string-position regexp arg)))
    (if pos (eshell-get-history pos))))

(defun eshell-previous-matching-input-string-position
  (regexp arg &optional start)
  "Return the index matching REGEXP ARG places along the input ring.
Moves relative to START, or `eshell-history-index'."
  (if (or (not (ring-p eshell-history-ring))
	  (ring-empty-p eshell-history-ring))
      (error "No history"))
  (let* ((len (ring-length eshell-history-ring))
	 (motion (if (> arg 0) 1 -1))
	 (n (mod (- (or start (eshell-search-start arg)) motion) len))
	 (tried-each-ring-item nil)
	 (case-fold-search (eshell-under-windows-p))
	 (prev nil))
    ;; Do the whole search as many times as the argument says.
    (while (and (/= arg 0) (not tried-each-ring-item))
      ;; Step once.
      (setq prev n
	    n (mod (+ n motion) len))
      ;; If we haven't reached a match, step some more.
      (while (and (not tried-each-ring-item)
		  (not (string-match regexp (eshell-get-history n))))
	(setq n (mod (+ n motion) len)
	      ;; If we have gone all the way around in this search.
	      tried-each-ring-item (= n prev)))
      (setq arg (if (> arg 0) (1- arg) (1+ arg))))
    ;; Now that we know which ring element to use, if we found it,
    ;; return that.
    (if (string-match regexp (eshell-get-history n))
	n)))

(defun eshell-previous-matching-input (regexp arg)
  "Search backwards through input history for match for REGEXP.
\(Previous history elements are earlier commands.)
With prefix argument N, search for Nth previous match.
If N is negative, find the next or Nth next match."
  (interactive (eshell-regexp-arg "Previous input matching (regexp): "))
  (setq arg (eshell-search-arg arg))
  (if (> eshell-last-output-end (point))
      (error "Point not located after prompt"))
  (let ((pos (eshell-previous-matching-input-string-position regexp arg)))
    ;; Has a match been found?
    (if (null pos)
	(error "Not found")
      (setq eshell-history-index pos)
      (unless (minibuffer-window-active-p (selected-window))
	(message "History item: %d" (- (ring-length eshell-history-ring) pos)))
      ;; Can't use kill-region as it sets this-command
      (delete-region eshell-last-output-end (point))
      (insert-and-inherit (eshell-get-history pos)))))

(defun eshell-next-matching-input (regexp arg)
  "Search forwards through input history for match for REGEXP.
\(Later history elements are more recent commands.)
With prefix argument N, search for Nth following match.
If N is negative, find the previous or Nth previous match."
  (interactive (eshell-regexp-arg "Next input matching (regexp): "))
  (eshell-previous-matching-input regexp (- arg)))

(defun eshell-previous-matching-input-from-input (arg)
  "Search backwards through input history for match for current input.
\(Previous history elements are earlier commands.)
With prefix argument N, search for Nth previous match.
If N is negative, search forwards for the -Nth following match."
  (interactive "p")
  (if (not (memq last-command '(eshell-previous-matching-input-from-input
				eshell-next-matching-input-from-input)))
      ;; Starting a new search
      (setq eshell-matching-input-from-input-string
	    (buffer-substring (save-excursion (beginning-of-line) (point))
			      (point))
	    eshell-history-index nil))
  (eshell-previous-matching-input
   (concat "^" (regexp-quote eshell-matching-input-from-input-string))
   arg))

(defun eshell-next-matching-input-from-input (arg)
  "Search forwards through input history for match for current input.
\(Following history elements are more recent commands.)
With prefix argument N, search for Nth following match.
If N is negative, search backwards for the -Nth previous match."
  (interactive "p")
  (eshell-previous-matching-input-from-input (- arg)))

(defun eshell-test-imatch ()
  "If isearch match good, put point at the beginning and return non-nil."
  (if (get-text-property (point) 'history)
      (progn (beginning-of-line) t)
    (let ((before (point)))
      (beginning-of-line)
      (if (and (not (bolp))
	       (<= (point) before))
	  t
	(if isearch-forward
	    (progn
	      (end-of-line)
	      (forward-char))
	  (beginning-of-line)
	  (backward-char))))))

(defun eshell-return-to-prompt ()
  "Once a search string matches, insert it at the end and go there."
  (setq isearch-other-end nil)
  (let ((found (eshell-test-imatch)) before)
    (while (and (not found)
		(setq before
		      (funcall (if isearch-forward
				   're-search-forward
				 're-search-backward)
			       isearch-string nil t)))
      (setq found (eshell-test-imatch)))
    (if (not found)
	(progn
	  (goto-char eshell-last-output-end)
	  (delete-region (point) (point-max)))
      (setq before (point))
      (let ((text (buffer-substring-no-properties
		   (point) (line-end-position)))
	    (orig (marker-position eshell-last-output-end)))
	(goto-char eshell-last-output-end)
	(delete-region (point) (point-max))
	(when (and text (> (length text) 0))
	  (insert text)
	  (put-text-property (1- (point)) (point)
			     'last-search-pos before)
	  (set-marker eshell-last-output-end orig)
	  (goto-char eshell-last-output-end))))))

(defun eshell-prepare-for-search ()
  "Make sure the old history file is at the beginning of the buffer."
  (unless (get-text-property (point-min) 'history)
    (save-excursion
      (goto-char (point-min))
      (let ((end (copy-marker (point) t)))
	(insert-file-contents eshell-history-file-name)
	(set-text-properties (point-min) end
			     '(history t invisible t))))))

(defun eshell-isearch-backward (&optional invert)
  "Do incremental regexp search backward through past commands."
  (interactive)
  (let ((inhibit-read-only t))
    (eshell-prepare-for-search)
    (goto-char (point-max))
    (set-marker eshell-last-output-end (point))
    (delete-region (point) (point-max)))
  (isearch-mode invert t 'eshell-return-to-prompt))

(defun eshell-isearch-repeat-backward (&optional invert)
  "Do incremental regexp search backward through past commands."
  (interactive)
  (let ((old-pos (get-text-property (1- (point-max))
				    'last-search-pos)))
    (when old-pos
      (goto-char old-pos)
      (if invert
	  (end-of-line)
	(backward-char)))
    (setq isearch-forward invert)
    (isearch-search-and-update)))

(defun eshell-isearch-forward ()
  "Do incremental regexp search backward through past commands."
  (interactive)
  (eshell-isearch-backward t))

(defun eshell-isearch-repeat-forward ()
  "Do incremental regexp search backward through past commands."
  (interactive)
  (eshell-isearch-repeat-backward t))

(defun eshell-isearch-cancel ()
  (interactive)
  (goto-char eshell-last-output-end)
  (delete-region (point) (point-max))
  (call-interactively 'isearch-cancel))

(defun eshell-isearch-abort ()
  (interactive)
  (goto-char eshell-last-output-end)
  (delete-region (point) (point-max))
  (call-interactively 'isearch-abort))

(defun eshell-isearch-delete-char ()
  (interactive)
  (save-excursion
  (isearch-delete-char)))

(defun eshell-isearch-return ()
  (interactive)
  (isearch-done)
  (eshell-send-input))

(defun em-hist-unload-function ()
  (remove-hook 'kill-emacs-hook 'eshell-save-some-history))

(provide 'em-hist)
;;; em-hist.el ends here
