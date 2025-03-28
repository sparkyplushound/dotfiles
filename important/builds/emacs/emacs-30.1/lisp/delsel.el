;;; delsel.el --- delete selection if you insert  -*- lexical-binding:t -*-

;; Copyright (C) 1992, 1997-1998, 2001-2025 Free Software Foundation,
;; Inc.

;; Author: Matthieu Devin <devin@lucid.com>
;; Maintainer: emacs-devel@gnu.org
;; Created: 14 Jul 92
;; Keywords: convenience emulations

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

;; This file makes the active region be pending delete, meaning that
;; text inserted while the region is active will replace the region contents.
;; This is a popular behavior of personal computers text editors.

;; Interface:

;; Commands which will delete the selection need a 'delete-selection
;; property on their symbols; commands which insert text but don't
;; have this property won't delete the selection.  It can be one of
;; the values:
;;  `yank'
;;      For commands which do a yank; ensures the region about to be
;;      deleted isn't immediately yanked back, which would make the
;;      command a no-op.
;;  `supersede'
;;      Delete the active region and ignore the current command,
;;      i.e. the command will just delete the region.  This is for
;;      commands that normally delete small amounts of text, like
;;      a single character -- they will instead delete the whole
;;      active region.
;;  `kill'
;;      `kill-region' is used on the selection, rather than
;;      `delete-region'.  (Text selected with the mouse will typically
;;      be yankable anyhow.)
;;  t
;;      The normal case: delete the active region prior to executing
;;      the command which will insert replacement text.
;;  FUNCTION
;;      For commands which need to dynamically determine this behavior.
;;      FUNCTION should take no argument and return one of the above
;;      values, or nil.  In the latter case, FUNCTION should itself
;;      do with the active region whatever is appropriate."

;;; Code:

(defvar delete-selection-save-to-register nil
  "If non-nil, deleted region text is stored in this register.
Value must be the register (key) to use.")

(defcustom delete-selection-temporary-region nil
  "Whether to delete only temporary regions.
When non-nil, typed text replaces only the regions set by
mouse-dragging, shift-selection, and \"\\[universal-argument] \\[exchange-point-and-mark]\" when
`transient-mark-mode' is turned off.  If the value is the symbol
`selection', then replace only the regions set by mouse-dragging
and shift-selection."
  :version "29.1"
  :group 'editing-basics
  :type '(choice (const :tag "Replace all regions" nil)
                 (const :tag "Replace region from mouse, shift-selection, and \"C-u C-x C-x\"" t)
                 (const :tag "Replace region from mouse and shift-selection" selection)))

;;;###autoload
(defalias 'pending-delete-mode 'delete-selection-mode)

;;;###autoload
(define-minor-mode delete-selection-mode
  "Toggle Delete Selection mode.

When Delete Selection mode is enabled, typed text replaces the selection
if the selection is active.  Otherwise, typed text is just inserted at
point regardless of any selection.

See `delete-selection-helper' and `delete-selection-pre-hook' for
information on adapting behavior of commands in Delete Selection mode."
  :global t :group 'editing-basics
  (if (not delete-selection-mode)
      (remove-hook 'pre-command-hook 'delete-selection-pre-hook)
    (add-hook 'pre-command-hook 'delete-selection-pre-hook)))

(defvar delsel--replace-text-or-position nil)

;;;###autoload
(defun delete-active-region (&optional killp)
  "Delete the active region.
If KILLP is non-nil, or if called interactively with a prefix argument,
the active region is killed instead of deleted."
  (interactive "P")
  (cond
   (killp
    ;; Don't allow `kill-region' to change the value of `this-command'.
    (let (this-command)
      (kill-region (point) (mark) t)))
   (delete-selection-save-to-register
    (set-register delete-selection-save-to-register
                  (funcall region-extract-function t))
    (setq delsel--replace-text-or-position
          (cons (current-buffer)
                (and (consp buffer-undo-list) (car buffer-undo-list)))))
   (t
    (funcall region-extract-function 'delete-only))))

(defun delete-selection-repeat-replace-region (arg)
  "Repeat replacing text of highlighted region with typed text.
Search for the next stretch of text identical to the region last replaced
by typing text over it and replaces it with the same stretch of text.
With ARG (interactively, prefix numeric argument), repeat that many times.
Just `\\[universal-argument]' means repeat until the end of the buffer's accessible portion."
  (interactive "P")
  (let ((old-text (and delete-selection-save-to-register
                       (get-register delete-selection-save-to-register)))
        (count (if (consp arg) (point-max)
                 (prefix-numeric-value current-prefix-arg))))
    (if (not (and old-text
                  (> (length old-text) 0)
                  (or (stringp delsel--replace-text-or-position)
                      (buffer-live-p (car delsel--replace-text-or-position)))))
        (message "No known previous replacement")
      ;; If this is the first use after overwriting regions,
      ;; find the replacement text by looking at the undo list.
      (when (consp delsel--replace-text-or-position)
        (let ((buffer (car delsel--replace-text-or-position))
              (elt (cdr delsel--replace-text-or-position)))
          (setq delsel--replace-text-or-position nil)
          (with-current-buffer buffer
            (save-restriction
              (widen)
              ;; Find the text that replaced the region via the undo list.
              (let ((ul buffer-undo-list) u s e)
                (when elt
                  (while (consp ul)
                    (setq u (car ul) ul (cdr ul))
                    (cond
                     ((eq u elt) ;; got it
                      (setq ul nil))
                     ((and (consp u) (integerp (car u)) (integerp (cdr u)))
                      (if (and s (= (cdr u) s))
                          (setq s (car u))
                        (setq s (car u) e (cdr u)))))))
                (cond ((and s e (<= s e) (= s (mark t)))
                       (setq delsel--replace-text-or-position
                             (filter-buffer-substring s e))
                       (set-text-properties
                        0 (length delsel--replace-text-or-position)
                        nil delsel--replace-text-or-position))
                      ((and (null s) (eq u elt)) ;; Nothing inserted.
                       (setq delsel--replace-text-or-position ""))
                      (t
                       (message "Cannot locate replacement text"))))))))
      (while (and (> count 0)
                  delsel--replace-text-or-position
                  (search-forward old-text nil t))
        (replace-match delsel--replace-text-or-position nil t)
        (setq count (1- count))))))

(defun delete-selection-helper (type)
  "Delete selection according to TYPE:
 `yank'
     For commands which do a yank; ensures the region about to be
     deleted isn't immediately yanked back, which would make the
     command a no-op.
 `supersede'
     Delete the active region and ignore the current command,
     i.e. the command will just delete the region.  This is for
     commands that normally delete small amounts of text, like
     a single character -- they will instead delete the whole
     active region.
 `kill'
     `kill-region' is used on the selection, rather than
     `delete-region'.  (Text selected with the mouse will
     typically be yankable anyhow.)
 FUNCTION
     For commands which need to dynamically determine this
     behavior.  FUNCTION should take no argument and return a
     value acceptable as TYPE, or nil.  In the latter case,
     FUNCTION should itself do with the active region whatever is
     appropriate.
 Other non-nil values
     The normal case: delete the active region prior to executing
     the command which will insert replacement text."
  (condition-case data
      (cond ((eq type 'kill)            ;Deprecated, backward compatibility.
	     (delete-active-region t)
	     (if (and overwrite-mode
		      (eq this-command 'self-insert-command))
		 (let ((overwrite-mode nil))
		   (self-insert-command
		    (prefix-numeric-value current-prefix-arg))
		   (setq this-command 'ignore))))
	    ((eq type 'yank)
	     ;; Before a yank command, make sure we don't yank the
	     ;; head of the kill-ring that really comes from the
	     ;; currently active region we are going to delete.
	     ;; That would make yank a no-op.
	     (when (and (string= (buffer-substring-no-properties
				  (point) (mark))
				 (car kill-ring))
			(fboundp 'mouse-region-match)
			(mouse-region-match))
	       (current-kill 1))
             (let ((pos (copy-marker (region-beginning))))
               (delete-active-region)
               ;; If the region was, say, rectangular, make sure we yank
               ;; from the top, to "replace".
               (goto-char pos)))
	    ((eq type 'supersede)
	     (let ((empty-region (= (point) (mark))))
	       (delete-active-region)
	       (unless empty-region
		 (setq this-command 'ignore))))
	    ((functionp type) (delete-selection-helper (funcall type)))
	    (type
	     (delete-active-region)
	     (if (and overwrite-mode
		      (eq this-command 'self-insert-command))
		 (let ((overwrite-mode nil))
		   (self-insert-command
		    (prefix-numeric-value current-prefix-arg))
		   (setq this-command 'ignore)))))
    ;; If the user has quit here (for instance, if the user is
    ;; presented with a "changed on disk; really edit the buffer?"
    ;; prompt, but hit `C-g'), just ding.
    (quit (ding))
    ;; If ask-user-about-supersession-threat signals an error,
    ;; stop safe_run_hooks from clearing out pre-command-hook.
    (file-supersession (message "%s" (cadr data)) (ding))
    (text-read-only
     ;; This signal may come either from `delete-active-region' or
     ;; `self-insert-command' (when `overwrite-mode' is non-nil).
     ;; To avoid clearing out `pre-command-hook' we handle this case
     ;; by issuing a simple message.  Note, however, that we do not
     ;; handle all related problems: When read-only text ends before
     ;; the end of the region, the latter is not deleted but any
     ;; subsequent insertion will succeed.  We could avoid this case
     ;; by doing a (setq this-command 'ignore) here.  This would,
     ;; however, still not handle the case where read-only text ends
     ;; precisely where the region starts: In that case the deletion
     ;; would succeed but the subsequent insertion would fail with a
     ;; text-read-only error.  To handle that case we would have to
     ;; investigate text properties at both ends of the region and
     ;; skip the deletion when inserting text is forbidden there.
     (message "Text is read-only") (ding))))

(defun delete-selection-pre-hook ()
  "Function run before commands that delete selections are executed.
Commands which will delete the selection need a `delete-selection'
property on their symbol; commands which insert text but don't
have this property won't delete the selection.
See `delete-selection-helper'."
  (when (and delete-selection-mode (use-region-p)
	     (not buffer-read-only)
             (or (null delete-selection-temporary-region)
                 (and delete-selection-temporary-region
                      (consp transient-mark-mode)
                      (eq (car transient-mark-mode) 'only))
                 (and (not (eq delete-selection-temporary-region 'selection))
                      (eq transient-mark-mode 'lambda))))
    (delete-selection-helper (and (symbolp this-command)
                                  (get this-command 'delete-selection)))))

(defun delete-selection-uses-region-p ()
  "Return t when `delete-selection-mode' should not delete the region.

The `self-insert-command' could be the current command or may be
called by the current command.  If this function returns nil,
then `delete-selection' is allowed to delete the region.

This function is intended for use as the value of the
`delete-selection' property of a command, and shouldn't be used
for anything else.  In particular, `self-insert-command' has this
function as its `delete-selection' property, so that \"electric\"
self-insert commands that act on the region could adapt themselves
to `delete-selection-mode'."
  (not (run-hook-with-args-until-success
        'self-insert-uses-region-functions)))

(put 'self-insert-command 'delete-selection 'delete-selection-uses-region-p)

(put 'insert-char 'delete-selection t)
(put 'quoted-insert 'delete-selection t)

(put 'yank 'delete-selection 'yank)
(put 'yank-pop 'delete-selection 'yank)
(put 'yank-from-kill-ring 'delete-selection 'yank)
(put 'clipboard-yank 'delete-selection 'yank)
(put 'insert-register 'delete-selection t)
;; delete-backward-char and delete-forward-char already delete the selection by
;; default, but not delete-char.
(put 'delete-char 'delete-selection 'supersede)

(put 'reindent-then-newline-and-indent 'delete-selection t)
(put 'newline-and-indent 'delete-selection t)
(put 'newline 'delete-selection t)
(put 'electric-newline-and-maybe-indent 'delete-selection t)
(put 'open-line 'delete-selection t)

;; This is very useful for canceling a selection in the minibuffer without
;; aborting the minibuffer.
(defun minibuffer-keyboard-quit ()
  "Abort recursive edit.
In Delete Selection mode, if the mark is active, just deactivate it;
then it takes a second \\[keyboard-quit] to abort the minibuffer."
  (interactive)
  (if (and delete-selection-mode (region-active-p))
      (setq deactivate-mark t)
    (abort-minibuffers)))

(define-key minibuffer-local-map "\C-g" 'minibuffer-keyboard-quit)

(defun delsel-unload-function ()
  "Unload the Delete Selection library."
  (define-key minibuffer-local-map "\C-g" 'abort-recursive-edit)
  (dolist (sym '(self-insert-command insert-char quoted-insert yank
                 clipboard-yank insert-register newline-and-indent
                 reindent-then-newline-and-indent newline open-line))
    (put sym 'delete-selection nil))
  ;; continue standard unloading
  nil)

(provide 'delsel)

;;; delsel.el ends here
