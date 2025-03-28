;;; hi-lock.el --- minor mode for interactive automatic highlighting  -*- lexical-binding: t -*-

;; Copyright (C) 2000-2025 Free Software Foundation, Inc.

;; Author: David M. Koppelman <koppel@ece.lsu.edu>
;; Keywords: faces, minor-mode, matching, display

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
;;
;;  With the hi-lock commands text matching interactively entered
;;  regexp's can be highlighted.  For example, `M-x highlight-regexp
;;  RET clearly RET RET' will highlight all occurrences of `clearly'
;;  using a yellow background face.  New occurrences of `clearly' will
;;  be highlighted as they are typed.  `M-x unhighlight-regexp RET'
;;  will remove the highlighting.  Any existing face can be used for
;;  highlighting and a set of appropriate faces is provided.  The
;;  regexps can be written into the current buffer in a form that will
;;  be recognized the next time the corresponding file is read (when
;;  file patterns is turned on).
;;
;;  Applications:
;;
;;    In program source code highlight a variable to quickly see all
;;    places it is modified or referenced:
;;    M-x highlight-regexp RET ground_contact_switches_closed RET RET
;;
;;    In a shell or other buffer that is showing lots of program
;;    output, highlight the parts of the output you're interested in:
;;    M-x highlight-regexp RET Total execution time [0-9]+ RET hi-blue-b RET
;;
;;    In buffers displaying tables, highlight the lines you're interested in:
;;    M-x highlight-lines-matching-regexp RET January 2000 RET hi-black-b RET
;;
;;    When writing text, highlight personal cliches.  This can be
;;    amusing.
;;    M-x highlight-phrase RET as can be seen RET RET
;;
;;  Setup:
;;
;;    Put the following code in your init file.  This turns on
;;    hi-lock mode and adds a "Regexp Highlighting" entry
;;    to the edit menu.
;;
;;    (global-hi-lock-mode 1)
;;
;;    To enable the use of patterns found in files (presumably placed
;;    there by hi-lock) include the following in your init file:
;;
;;    (setq hi-lock-file-patterns-policy 'ask)
;;
;;    If you get tired of being asked each time a file is loaded replace
;;    `ask' with a function that returns t if patterns should be read.
;;
;;    You might also want to bind the hi-lock commands to more
;;    finger-friendly sequences:

;;    (keymap-set hi-lock-map "C-z C-h" 'highlight-lines-matching-regexp)
;;    (keymap-set hi-lock-map "C-z i" 'hi-lock-find-patterns)
;;    (keymap-set hi-lock-map "C-z h" 'highlight-regexp)
;;    (keymap-set hi-lock-map "C-z p" 'highlight-phrase)
;;    (keymap-set hi-lock-map "C-z r" 'unhighlight-regexp)
;;    (keymap-set hi-lock-map "C-z b" 'hi-lock-write-interactive-patterns))

;;    See the documentation for hi-lock-mode `C-h f hi-lock-mode' for
;;    additional instructions.

;; Sample file patterns:

; Hi-lock: (("^;;; .*" (0 (quote hi-black-hb) t)))
; Hi-lock: ( ("make-variable-buffer-\\(local\\)" (0 font-lock-keyword-face)(1 'italic append)))))
; Hi-lock: end

;;; Code:

(defgroup hi-lock nil
  "Interactively add and remove font-lock patterns for highlighting text."
  :link '(custom-manual "(emacs)Highlight Interactively")
  :group 'font-lock)

(defcustom hi-lock-file-patterns-range 10000
  "Limit of search in a buffer for hi-lock patterns.
When a file is visited and hi-lock mode is on, patterns starting
up to this limit are added to font-lock's patterns.  See documentation
of functions `hi-lock-mode' and `hi-lock-find-patterns'."
  :type 'natnum
  :group 'hi-lock)

(defcustom hi-lock-highlight-range 2000000
  "Size of area highlighted by hi-lock when font-lock not active.
Font-lock is not active in buffers that do their own highlighting,
such as the buffer created by `list-colors-display'.  In those buffers
hi-lock patterns will only be applied over a range of
`hi-lock-highlight-range' characters.  If font-lock is active then
highlighting will be applied throughout the buffer."
  :type 'natnum
  :group 'hi-lock)

(defcustom hi-lock-exclude-modes
  '(rmail-mode mime/viewer-mode gnus-article-mode term-mode)
  "List of major modes in which hi-lock will not run.
For security reasons since font lock patterns can specify function
calls."
  :type '(repeat symbol)
  :group 'hi-lock)

(defcustom hi-lock-file-patterns-policy 'ask
  "Specify when hi-lock should use patterns found in file.
If `ask', prompt when patterns found in buffer; if bound to a function,
use patterns when function returns t (function is called with patterns
as first argument); if `always', use file patterns without prompt;
if nil or `never' or anything else, don't use file patterns."
  :type '(choice (const :tag "Do not use file patterns" never)
                 (const :tag "Always use file patterns" always)
                 (const :tag "Ask about file patterns" ask)
                 (function :tag "Function to check file patterns"))
  :group 'hi-lock
  ;; It can have a function value.
  :risky t
  :version "22.1")

(defcustom hi-lock-auto-select-face nil
  "When nil, highlighting commands prompt for the face to use.
When non-nil, highlighting command determine the faces to use
by cycling through the faces in `hi-lock-face-defaults'."
  :type 'boolean
  :version "24.4")

(defgroup hi-lock-faces nil
  "Faces for hi-lock."
  :group 'hi-lock
  :group 'faces)

(defface hi-yellow
  '((((min-colors 88) (background dark))
     (:background "yellow1" :foreground "black"))
    (((background dark)) (:background "yellow" :foreground "black"))
    (((min-colors 88)) (:background "yellow1"))
    (t (:background "yellow")))
  "Default face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-pink
  '((((background dark)) (:background "pink" :foreground "black"))
    (t (:background "pink")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-green
  '((((min-colors 88) (background dark))
     (:background "light green" :foreground "black"))
    (((background dark)) (:background "green" :foreground "black"))
    (((min-colors 88)) (:background "light green"))
    (t (:background "green")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-blue
  '((((background dark)) (:background "light blue" :foreground "black"))
    (t (:background "light blue")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-salmon
  '((((min-colors 88) (background dark))
     (:background "light salmon" :foreground "black"))
    (((background dark)) (:background "red" :foreground "black"))
    (((min-colors 88)) (:background "light salmon"))
    (t (:background "red")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces
  :version "27.1")

(defface hi-aquamarine
  '((((min-colors 88) (background dark))
     (:background "aquamarine" :foreground "black"))
    (((background dark)) (:background "blue" :foreground "black"))
    (((min-colors 88)) (:background "aquamarine"))
    (t (:background "blue")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces
  :version "27.1")

(defface hi-black-b
  '((t (:weight bold)))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-blue-b
  '((((min-colors 88)) (:weight bold :foreground "blue1"))
    (t (:weight bold :foreground "blue")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-green-b
  '((((min-colors 88)) (:weight bold :foreground "green3"))
    (t (:weight bold :foreground "green")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-red-b
  '((((min-colors 88)) (:weight bold :foreground "firebrick2"))
    (t (:weight bold :foreground "red")))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defface hi-black-hb
  '((t (:weight bold :height 1.67 :inherit variable-pitch)))
  "Face for hi-lock mode."
  :group 'hi-lock-faces)

(defvar-local hi-lock-file-patterns nil
  "Patterns found in file for hi-lock.  Should not be changed.")
(put 'hi-lock-file-patterns 'permanent-local t)

(defvar-local hi-lock-interactive-patterns nil
  "Patterns provided to hi-lock by user.  Should not be changed.")
(put 'hi-lock-interactive-patterns 'permanent-local t)

(defvar-local hi-lock-interactive-lighters nil
  "Human-readable lighters for `hi-lock-interactive-patterns'.")
(put 'hi-lock-interactive-lighters 'permanent-local t)

(defcustom hi-lock-face-defaults
  '("hi-yellow" "hi-pink" "hi-green" "hi-blue" "hi-salmon" "hi-aquamarine"
    "hi-black-b" "hi-blue-b" "hi-red-b" "hi-green-b" "hi-black-hb")
  "Default face names for hi-lock interactive functions."
  :type '(repeat string)
  :version "29.1")

(defvar hi-lock-file-patterns-prefix "Hi-lock"
  "String used to identify hi-lock patterns at the start of files.")

(defvar hi-lock-archaic-interface-message-used nil
  "Non-nil if user alerted that `global-hi-lock-mode' is now the global switch.
Earlier versions of hi-lock used `hi-lock-mode' as the global switch;
the message is issued if it appears that `hi-lock-mode' is used assuming
that older functionality.  This variable avoids multiple reminders.")

(defvar hi-lock-archaic-interface-deduce nil
  "If non-nil, sometimes assume that `hi-lock-mode' means `global-hi-lock-mode'.
Assumption is made if `hi-lock-mode' used in the *scratch* buffer while
a library is being loaded.")

(easy-menu-define hi-lock-menu nil
  "Menu for hi-lock mode."
  '("Hi Lock"
    ["Highlight Regexp..." highlight-regexp
     :help "Highlight text matching PATTERN (a regexp)."]
    ["Highlight Phrase..." highlight-phrase
     :help "Highlight text matching PATTERN (a regexp processed to match phrases)."]
    ["Highlight Lines..." highlight-lines-matching-regexp
     :help "Highlight lines containing match of PATTERN (a regexp)."]
    ["Highlight Symbol at Point" highlight-symbol-at-point
     :help "Highlight symbol found near point without prompting."]
    ["Remove Highlighting..." unhighlight-regexp
     :help "Remove previously entered highlighting pattern."
     :enable hi-lock-interactive-patterns]
    ["Patterns to Buffer" hi-lock-write-interactive-patterns
     :help "Insert interactively added REGEXPs into buffer at point."
     :enable hi-lock-interactive-patterns]
    ["Patterns from Buffer" hi-lock-find-patterns
     :help "Use patterns (if any) near top of buffer."]))

(defvar-keymap hi-lock-map
  :doc "Keymap for `hi-lock-mode'."
  :name "Hi Lock"
  "C-x w i" #'hi-lock-find-patterns
  "C-x w l" #'highlight-lines-matching-regexp
  "C-x w p" #'highlight-phrase
  "C-x w h" #'highlight-regexp
  "C-x w ." #'highlight-symbol-at-point
  "C-x w r" #'unhighlight-regexp
  "C-x w b" #'hi-lock-write-interactive-patterns)

;; Visible Functions

;;;###autoload
(define-minor-mode hi-lock-mode
  "Toggle selective highlighting of patterns (Hi Lock mode).

Hi Lock mode is automatically enabled when you invoke any of the
highlighting commands listed below, such as \\[highlight-regexp].
To enable Hi Lock mode in all buffers, use `global-hi-lock-mode'
or add (global-hi-lock-mode 1) to your init file.

In buffers where Font Lock mode is enabled, patterns are
highlighted using font lock.  In buffers where Font Lock mode is
disabled, patterns are applied using overlays; in this case, the
highlighting will not be updated as you type.  The Font Lock mode
is considered \"enabled\" in a buffer if its `major-mode'
causes `font-lock-specified-p' to return non-nil, which means
the major mode specifies support for Font Lock.

When Hi Lock mode is enabled, a \"Regexp Highlighting\" submenu
is added to the \"Edit\" menu.  The commands in the submenu,
which can be called interactively, are:

\\[highlight-regexp] REGEXP FACE
  Highlight matches of pattern REGEXP in current buffer with FACE.

\\[highlight-phrase] PHRASE FACE
  Highlight matches of phrase PHRASE in current buffer with FACE.
  (PHRASE can be any REGEXP, but spaces will be replaced by matches
  to whitespace and initial lower-case letters will become case insensitive.)

\\[highlight-lines-matching-regexp] REGEXP FACE
  Highlight lines containing matches of REGEXP in current buffer with FACE.

\\[highlight-symbol-at-point]
  Highlight the symbol found near point without prompting, using the next
  available face automatically.

\\[unhighlight-regexp] REGEXP
  Remove highlighting on matches of REGEXP in current buffer.

\\[hi-lock-write-interactive-patterns]
  Write active REGEXPs into buffer as comments (if possible).  They may
  be read the next time file is loaded or when the \\[hi-lock-find-patterns] command
  is issued.  The inserted regexps are in the form of font lock keywords.
  (See `font-lock-keywords'.)  They may be edited and re-loaded with \\[hi-lock-find-patterns],
  any valid `font-lock-keywords' form is acceptable.  When a file is
  loaded the patterns are read if `hi-lock-file-patterns-policy' is
  `always', or if it's `ask' and the user responds y to the prompt,
  or if `hi-lock-file-patterns-policy' is bound to a function and that
  function returns t.

\\[hi-lock-find-patterns]
  Re-read patterns stored in buffer (in the format produced by \\[hi-lock-write-interactive-patterns]).

When hi-lock is started and if the mode is not excluded or patterns
rejected, the beginning of the buffer is searched for lines of the
form:
  Hi-lock: (FOO ...)

where (FOO ...) is a list of patterns.  The patterns must start before
position \(number of characters into buffer)
`hi-lock-file-patterns-range'.  Patterns will be read until
Hi-lock: end is found.  A mode is excluded if it's in the list
`hi-lock-exclude-modes'."
  :group 'hi-lock
  :lighter (:eval (if (or hi-lock-interactive-patterns
			  hi-lock-file-patterns)
		      " Hi" ""))
  :global nil
  :keymap hi-lock-map
  (when (and (equal (buffer-name) "*scratch*")
             load-in-progress
             (not (called-interactively-p 'interactive))
             (not hi-lock-archaic-interface-message-used))
    (setq hi-lock-archaic-interface-message-used t)
    (if hi-lock-archaic-interface-deduce
        (global-hi-lock-mode hi-lock-mode)
      (warn "%s"
       "Possible archaic use of (hi-lock-mode).
Use (global-hi-lock-mode 1) in .emacs to enable hi-lock for all buffers,
use (hi-lock-mode 1) for individual buffers.")))
  (if hi-lock-mode
      ;; Turned on.
      (progn
	(define-key-after menu-bar-edit-menu [hi-lock]
	  (cons "Regexp Highlighting" hi-lock-menu))
	(hi-lock-find-patterns)
        (add-hook 'font-lock-mode-hook 'hi-lock-font-lock-hook nil t)
        ;; Remove regexps from font-lock-keywords (bug#13891).
	(add-hook 'change-major-mode-hook (lambda () (hi-lock-mode -1)) nil t)
	(add-hook 'revert-buffer-restore-functions
		  #'hi-lock-revert-buffer-rehighlight nil t))
    ;; Turned off.
    (when (or hi-lock-interactive-patterns
	      hi-lock-file-patterns)
      (when hi-lock-interactive-patterns
	(font-lock-remove-keywords nil hi-lock-interactive-patterns)
	(setq hi-lock-interactive-patterns nil
	      hi-lock-interactive-lighters nil))
      (when hi-lock-file-patterns
	(font-lock-remove-keywords nil hi-lock-file-patterns)
	(setq hi-lock-file-patterns nil))
      (remove-overlays nil nil 'hi-lock-overlay t)
      (font-lock-flush))
    (define-key-after menu-bar-edit-menu [hi-lock] nil)
    (remove-hook 'font-lock-mode-hook 'hi-lock-font-lock-hook t)
    (remove-hook 'revert-buffer-restore-functions
		 #'hi-lock-revert-buffer-rehighlight t)))

;;;###autoload
(define-globalized-minor-mode global-hi-lock-mode
  hi-lock-mode turn-on-hi-lock-if-enabled
  :group 'hi-lock)

(defun turn-on-hi-lock-if-enabled ()
  (setq hi-lock-archaic-interface-message-used t)
  (unless (memq major-mode hi-lock-exclude-modes)
    (hi-lock-mode 1)))

;;;###autoload
(defalias 'highlight-lines-matching-regexp 'hi-lock-line-face-buffer)
;;;###autoload
(defun hi-lock-line-face-buffer (regexp &optional face)
  "Highlight all lines that match REGEXP using FACE.
The lines that match REGEXP will be displayed by merging
the attributes of FACE with any other face attributes
of text in those lines.

Interactively, prompt for REGEXP using `read-regexp', then FACE.
Use the global history list for FACE.

If REGEXP contains upper case characters (excluding those preceded by `\\')
and `search-upper-case' is non-nil, the matching is case-sensitive.

Use Font lock mode, if enabled, to highlight REGEXP.  Otherwise,
use overlays for highlighting.  If overlays are used, the
highlighting will not update as you type."
  (interactive
   (list
    (hi-lock-regexp-okay
     (read-regexp "Regexp to highlight line" 'regexp-history-last))
    (hi-lock-read-face-name)))
  (or (facep face) (setq face 'hi-yellow))
  (unless hi-lock-mode (hi-lock-mode 1))
  (hi-lock-set-pattern
   ;; The \\(?:...\\) grouping construct ensures that a leading ^, +, * or ?
   ;; or a trailing $ in REGEXP will be interpreted correctly.
   (concat "^.*\\(?:" regexp "\\).*\\(?:$\\)\n?") face nil nil
   (if (and case-fold-search search-upper-case)
       (isearch-no-upper-case-p regexp t)
     case-fold-search)))


;;;###autoload
(defalias 'highlight-regexp 'hi-lock-face-buffer)
;;;###autoload
(defun hi-lock-face-buffer (regexp &optional face subexp lighter)
  "Set face of each match of REGEXP to FACE.
Interactively, prompt for REGEXP using `read-regexp', then FACE.
Use the global history list for FACE.  Limit face setting to the
corresponding SUBEXP (interactively, the prefix argument) of REGEXP.
If SUBEXP is omitted or nil, the entire REGEXP is highlighted.

LIGHTER is a human-readable string that can be used to select
a regexp to unhighlight by its name instead of selecting a possibly
complex regexp or closure.

If REGEXP contains upper case characters (excluding those preceded by `\\')
and `search-upper-case' is non-nil, the matching is case-sensitive.

Use Font lock mode, if enabled, to highlight REGEXP.  Otherwise,
use overlays for highlighting.  If overlays are used, the
highlighting will not update as you type.  The Font Lock mode
is considered \"enabled\" in a buffer if its `major-mode'
causes `font-lock-specified-p' to return non-nil, which means
the major mode specifies support for Font Lock."
  (interactive
   (list
    (hi-lock-regexp-okay
     (read-regexp "Regexp to highlight"
                  (if (use-region-p)
                      (prog1
                          (buffer-substring (region-beginning)
                                            (region-end))
                        (deactivate-mark))
                    'regexp-history-last)))
    (hi-lock-read-face-name)
    current-prefix-arg))
  (when (stringp face)
    (setq face (intern face)))
  (or (facep face) (setq face 'hi-yellow))
  (unless hi-lock-mode (hi-lock-mode 1))
  (hi-lock-set-pattern
   regexp face subexp lighter
   (if (and case-fold-search search-upper-case)
       (isearch-no-upper-case-p regexp t)
     case-fold-search)
   search-spaces-regexp))

;;;###autoload
(defalias 'highlight-phrase 'hi-lock-face-phrase-buffer)
;;;###autoload
(defun hi-lock-face-phrase-buffer (regexp &optional face)
  "Set face of each match of phrase REGEXP to FACE.
Interactively, prompt for REGEXP using `read-regexp', then FACE.
Use the global history list for FACE.

If REGEXP contains upper case characters (excluding those preceded by `\\')
and `search-upper-case' is non-nil, the matching is case-sensitive.
Also set `search-spaces-regexp' to the value of `search-whitespace-regexp'.

Use Font lock mode, if enabled, to highlight REGEXP.  Otherwise,
use overlays for highlighting.  If overlays are used, the
highlighting will not update as you type.  The Font Lock mode
is considered \"enabled\" in a buffer if its `major-mode'
causes `font-lock-specified-p' to return non-nil, which means
the major mode specifies support for Font Lock."
  (interactive
   (list
    (hi-lock-regexp-okay
     (read-regexp "Phrase to highlight" 'regexp-history-last))
    (hi-lock-read-face-name)))
  (or (facep face) (setq face 'hi-yellow))
  (unless hi-lock-mode (hi-lock-mode 1))
  (hi-lock-set-pattern
   regexp face nil nil
   (if (and case-fold-search search-upper-case)
       (isearch-no-upper-case-p regexp t)
     case-fold-search)
   search-whitespace-regexp))

;;;###autoload
(defalias 'highlight-symbol-at-point 'hi-lock-face-symbol-at-point)
;;;###autoload
(defun hi-lock-face-symbol-at-point ()
  "Highlight each instance of the symbol at point.
Uses the next face from `hi-lock-face-defaults' without prompting,
unless you use a prefix argument.
Uses `find-tag-default-as-symbol-regexp' to retrieve the symbol at point.

If REGEXP contains upper case characters (excluding those preceded by `\\')
and `search-upper-case' is non-nil, the matching is case-sensitive.

This uses Font lock mode if it is enabled; otherwise it uses overlays,
in which case the highlighting will not update as you type.  The Font
Lock mode is considered \"enabled\" in a buffer if its `major-mode'
causes `font-lock-specified-p' to return non-nil, which means
the major mode specifies support for Font Lock."
  (interactive)
  (let* ((regexp (hi-lock-regexp-okay
		  (find-tag-default-as-symbol-regexp)))
	 (hi-lock-auto-select-face t)
	 (face (hi-lock-read-face-name)))
    (or (facep face) (setq face 'hi-yellow))
    (unless hi-lock-mode (hi-lock-mode 1))
    (hi-lock-set-pattern
     regexp face nil nil
     (if (and case-fold-search search-upper-case)
         (isearch-no-upper-case-p regexp t)
       case-fold-search))))

(defun hi-lock-keyword->face (keyword)
  (cadr (cadr (cadr keyword))))    ; Keyword looks like (REGEXP (0 'FACE) ...).

(declare-function x-popup-menu "menu.c" (position menu))

(defun hi-lock--regexps-at-point ()
  (let ((regexps '()))
    ;; When using overlays, there is no ambiguity on the best
    ;; choice of regexp.
    (let ((regexp (get-char-property (point) 'hi-lock-overlay-regexp)))
      (when regexp (push regexp regexps)))
    ;; With font-locking on, check if the cursor is on a highlighted text.
    (let* ((faces-after (get-text-property (point) 'face))
           (faces-before
            (unless (bobp) (get-text-property (1- (point)) 'face)))
           ;; Use proper-list-p to handle faces like (foreground-color . "red3")
           (faces-after (if (proper-list-p faces-after) faces-after (list faces-after)))
           (faces-before (if (proper-list-p faces-before) faces-before (list faces-before)))
           (faces (mapcar #'hi-lock-keyword->face
                          hi-lock-interactive-patterns))
           (face-after (seq-some (lambda (face) (car (memq face faces))) faces-after))
           (face-before (seq-some (lambda (face) (car (memq face faces))) faces-before)))
      (when (and face-before face-after (not (eq face-before face-after)))
        (setq face-before nil))
      (when (or face-after face-before)
        (let* ((beg (if face-before
                        (or (previous-single-property-change (point) 'face)
                            (point-min))
                      (point)))
               (end (if face-after
                        (or (next-single-property-change (point) 'face)
                            (point-max))
                      (point))))
          ;; Compute hi-lock patterns that match the
          ;; highlighted text at point.  Use this later in
          ;; during completing-read.
          (dolist (hi-lock-pattern hi-lock-interactive-patterns)
            (let ((pattern (or (rassq hi-lock-pattern hi-lock-interactive-lighters)
                               (car hi-lock-pattern))))
              (cond
               ((stringp pattern)
                (when (string-match pattern (buffer-substring-no-properties beg end))
                  (push pattern regexps)))
               ((functionp (cadr pattern))
                (save-excursion
                  (goto-char beg)
                  (when (funcall (cadr pattern) end)
                    (push (car pattern) regexps))))))))))
    regexps))

(defvar-local hi-lock--unused-faces nil
  "List of faces that is not used and is available for highlighting new text.
Face names from this list come from `hi-lock-face-defaults'.")

;;;###autoload
(defalias 'unhighlight-regexp 'hi-lock-unface-buffer)
;;;###autoload
(defun hi-lock-unface-buffer (regexp)
  "Remove highlighting of each match to REGEXP set by hi-lock.
Interactively, prompt for REGEXP, accepting only regexps
previously inserted by hi-lock interactive functions.
If REGEXP is t (or if \\[universal-argument] was specified interactively),
then remove all hi-lock highlighting."
  (interactive
   (cond
    (current-prefix-arg (list t))
    ((and (display-popup-menus-p)
          last-nonmenu-event
          (listp last-nonmenu-event)
          use-dialog-box)
     (catch 'snafu
       (or
        (x-popup-menu
         t
         (cons
          'keymap
          (cons "Select Pattern to Unhighlight"
                (mapcar (lambda (pattern)
                          (let ((lighter
                                 (or (car (rassq pattern hi-lock-interactive-lighters))
                                     (car pattern))))
                            (list lighter
                                  (format
                                   "%s (%s)" lighter
                                   (hi-lock-keyword->face pattern))
                                  (cons nil nil)
                                  lighter)))
                        hi-lock-interactive-patterns))))
        ;; If the user clicks outside the menu, meaning that they
        ;; change their mind, x-popup-menu returns nil, and
        ;; interactive signals a wrong number of arguments error.
        ;; To prevent that, we return an empty string, which will
        ;; effectively disable the rest of the function.
        (throw 'snafu '("")))))
    (t
     ;; Un-highlighting triggered via keyboard action.
     (unless hi-lock-interactive-patterns
       (user-error "No highlighting to remove"))
     ;; Infer the regexp to un-highlight based on cursor position.
     (let* ((defaults (or (hi-lock--regexps-at-point)
                          (mapcar (lambda (pattern)
                                    (or (car (rassq pattern hi-lock-interactive-lighters))
                                        (car pattern)))
                                  hi-lock-interactive-patterns))))
       (list
        (completing-read (format-prompt "Regexp to unhighlight" (car defaults))
                         (mapcar (lambda (pattern)
                                   (cons (or (car (rassq pattern hi-lock-interactive-lighters))
                                             (car pattern))
                                         (cdr pattern)))
                                 hi-lock-interactive-patterns)
			 nil t nil nil defaults))))))

  (when (assoc regexp hi-lock-interactive-lighters)
    (setq regexp (cadr (assoc regexp hi-lock-interactive-lighters))))

  (dolist (keyword (if (eq regexp t) hi-lock-interactive-patterns
                     (list (assoc regexp hi-lock-interactive-patterns))))
    (when keyword
      (let ((face (hi-lock-keyword->face keyword)))
        ;; Make `face' the next one to use by default.
        (when (symbolp face)          ;Don't add it if it's a list (bug#13297).
          (add-to-list 'hi-lock--unused-faces (face-name face))))
      ;; FIXME: Calling `font-lock-remove-keywords' causes
      ;; `font-lock-specified-p' to go from nil to non-nil (because it
      ;; calls font-lock-set-defaults).  This is yet-another bug in
      ;; font-lock-add/remove-keywords, which we circumvent here by
      ;; testing `font-lock-fontified' (bug#19796).
      (if font-lock-fontified (font-lock-remove-keywords nil (list keyword)))
      (setq hi-lock-interactive-patterns
            (delq keyword hi-lock-interactive-patterns))
      (remove-overlays
       nil nil 'hi-lock-overlay-regexp
       (or (car (rassq keyword hi-lock-interactive-lighters))
           (hi-lock--hashcons (car keyword))))
      (setq hi-lock-interactive-lighters
            (rassq-delete-all keyword hi-lock-interactive-lighters))
      (font-lock-flush))))

;;;###autoload
(defun hi-lock-write-interactive-patterns ()
  "Write interactively added patterns, if any, into buffer at point.

Interactively added patterns are those normally specified using
`highlight-regexp' and `highlight-lines-matching-regexp'; they can
be found in variable `hi-lock-interactive-patterns'."
  (interactive)
  (if (null hi-lock-interactive-patterns)
      (user-error "There are no interactive patterns"))
  (let ((beg (point)))
    (mapc
     (lambda (pattern)
       (insert (format "%s: (%s)\n"
		       hi-lock-file-patterns-prefix
		       (prin1-to-string pattern))))
     hi-lock-interactive-patterns)
    (comment-region beg (point)))
  (when (> (point) hi-lock-file-patterns-range)
    (warn "Inserted keywords not close enough to top of file")))

;; Implementation Functions

(defun hi-lock-regexp-okay (regexp)
  "Return REGEXP if it appears suitable for a font-lock pattern.

Otherwise signal an error.  A pattern that matches the null string is
not suitable."
  (cond
   ((null regexp)
    (error "Regexp cannot match nil"))
   ((string-match regexp "")
    (error "Regexp cannot match an empty string"))
   (t regexp)))

(defun hi-lock-read-face-name ()
  "Return face for interactive highlighting.
When `hi-lock-auto-select-face' is non-nil, just return the next face.
Otherwise, or with a prefix argument, read a face from the minibuffer
with completion and history."
  (unless hi-lock-interactive-patterns
    (setq hi-lock--unused-faces hi-lock-face-defaults))
  (let* ((last-used-face
	  (when hi-lock-interactive-patterns
	    (face-name (hi-lock-keyword->face
                        (car hi-lock-interactive-patterns)))))
	 (defaults (seq-uniq
                    (append hi-lock--unused-faces
			    (cdr (member last-used-face hi-lock-face-defaults))
			    hi-lock-face-defaults)
                    #'equal))
	 face)
    (if (and hi-lock-auto-select-face (not current-prefix-arg))
	(setq face (or (pop hi-lock--unused-faces) (car defaults)))
      (setq face (symbol-name (read-face-name "Highlight using face" defaults)))
      ;; Update list of un-used faces.
      (setq hi-lock--unused-faces (remove face hi-lock--unused-faces))
      ;; Grow the list of defaults.
      (add-to-list 'hi-lock-face-defaults face t))
    (intern face)))

(defvar hi-lock-use-overlays nil
  "Whether to always use overlays instead of font-lock rules.
When `font-lock-mode' is enabled and the buffer specifies font-lock rules,
highlighting is performed by adding new font-lock rules to the existing ones,
so when new matching strings are added, they are highlighted by font-lock.
Otherwise, overlays are used, but new highlighting overlays are not added
when new matching strings are inserted to the buffer.
However, sometimes overlays are still preferable even in buffers
where font-lock is enabled, when hi-lock overlays take precedence
over other overlays in the same buffer.")

(defun hi-lock-set-pattern (regexp face &optional subexp lighter case-fold spaces-regexp)
  "Highlight SUBEXP of REGEXP with face FACE.
If omitted or nil, SUBEXP defaults to zero, i.e. the entire
REGEXP is highlighted.  LIGHTER is a human-readable string to
display instead of a regexp.  Non-nil CASE-FOLD ignores case.
SPACES-REGEXP is a regexp to substitute spaces in font-lock search."
  ;; Hashcons the regexp, so it can be passed to remove-overlays later.
  (setq regexp (hi-lock--hashcons regexp))
  (setq subexp (or subexp 0))
  (when lighter (setq lighter (propertize lighter 'regexp regexp)))
  (let ((pattern (list (lambda (limit)
                         (let ((case-fold-search case-fold)
                               (search-spaces-regexp spaces-regexp))
                           (re-search-forward regexp limit t)))
                       (list subexp (list 'quote face) 'prepend)))
        (no-matches t))
    ;; Refuse to highlight a text that is already highlighted.
    (if (or (assoc regexp hi-lock-interactive-patterns)
            (assoc (or lighter regexp) hi-lock-interactive-lighters))
        (add-to-list 'hi-lock--unused-faces (face-name face))
      (push pattern hi-lock-interactive-patterns)
      (push (cons (or lighter regexp) pattern) hi-lock-interactive-lighters)
      (if (and font-lock-mode (font-lock-specified-p major-mode)
               (not hi-lock-use-overlays))
	  (progn
	    (font-lock-add-keywords nil (list pattern) t)
	    (font-lock-flush))
        (let* ((range-min (- (point) (/ hi-lock-highlight-range 2)))
               (range-max (+ (point) (/ hi-lock-highlight-range 2)))
               (search-start
                (max (point-min)
                     (- range-min (max 0 (- range-max (point-max))))))
               (search-end
                (min (point-max)
                     (+ range-max (max 0 (- (point-min) range-min)))))
               (case-fold-search case-fold)
               (search-spaces-regexp spaces-regexp))
          (save-excursion
            (goto-char search-start)
            (while (re-search-forward regexp search-end t)
              (when no-matches (setq no-matches nil))
              (let ((overlay (make-overlay (match-beginning subexp)
                                           (match-end subexp))))
                (overlay-put overlay 'hi-lock-overlay t)
                (overlay-put overlay 'hi-lock-overlay-regexp (or lighter regexp))
                ;; Use priority higher than default used by e.g. diff-refine.
                (overlay-put overlay 'priority 1)
                (overlay-put overlay 'face face))
              (goto-char (match-end 0)))
            (when no-matches
              (add-to-list 'hi-lock--unused-faces (face-name face))
              (setq hi-lock-interactive-patterns
                    (cdr hi-lock-interactive-patterns)
                    hi-lock-interactive-lighters
                    (cdr hi-lock-interactive-lighters))))
          (when (or (> search-start (point-min)) (< search-end (point-max)))
            (message "Hi-lock added only in range %d-%d" search-start search-end)))))))

(defun hi-lock-set-file-patterns (patterns)
  "Replace file patterns list with PATTERNS and refontify."
  (when (or hi-lock-file-patterns patterns)
    (font-lock-remove-keywords nil hi-lock-file-patterns)
    (setq hi-lock-file-patterns patterns)
    (font-lock-add-keywords nil hi-lock-file-patterns t)
    (font-lock-flush)))

;;;###autoload
(defun hi-lock-find-patterns ()
  "Add patterns from the current buffer to the list of hi-lock patterns."
  (interactive)
  (unless (memq major-mode hi-lock-exclude-modes)
    (let ((all-patterns nil)
          (target-regexp (concat "\\<" hi-lock-file-patterns-prefix ":")))
      (save-excursion
	(save-restriction
	  (widen)
	  (goto-char (point-min))
	  (re-search-forward target-regexp
			     (+ (point) hi-lock-file-patterns-range) t)
	  (beginning-of-line)
	  (while (and (re-search-forward target-regexp (+ (point) 100) t)
		      (not (looking-at "\\s-*end")))
            (condition-case nil
                (setq all-patterns (append (read (current-buffer)) all-patterns))
              (error (message "Invalid pattern list expression at line %d"
                              (line-number-at-pos)))))))
      (when (and all-patterns
                 hi-lock-mode
                 (cond
                  ((eq this-command 'hi-lock-find-patterns) t)
                  ((functionp hi-lock-file-patterns-policy)
                   (funcall hi-lock-file-patterns-policy all-patterns))
                  ((eq hi-lock-file-patterns-policy 'ask)
                   (y-or-n-p "Add patterns from this buffer to hi-lock? "))
                  ((eq hi-lock-file-patterns-policy 'always) t)
                  (t nil)))
        (hi-lock-set-file-patterns all-patterns)
        (if (called-interactively-p 'interactive)
            (message "Hi-lock added %d patterns." (length all-patterns)))))))

(defun hi-lock-font-lock-hook ()
  "Add hi-lock patterns to font-lock's."
  (when font-lock-fontified
    (font-lock-add-keywords nil hi-lock-file-patterns t)
    (font-lock-add-keywords nil hi-lock-interactive-patterns t)))

(defun hi-lock-revert-buffer-rehighlight ()
  "Rehighlight hi-lock patterns after `revert-buffer'.
Apply the previous patterns after reverting the buffer."
  (when (or hi-lock-interactive-lighters hi-lock-file-patterns)
    (let ((patterns hi-lock-interactive-lighters)
          (policy (if hi-lock-file-patterns 'always 'never))
          rehighlight)
      (lambda ()
        ;; When using revert-buffer without preserve-modes
        (unless hi-lock-mode
          ;; Don't ask about file patterns again
          (let ((hi-lock-file-patterns-policy policy))
            (hi-lock-mode 1))
          (setq rehighlight t))
        ;; When using hi-lock overlays, then need to update them
        (unless (and font-lock-mode (font-lock-specified-p major-mode)
                     (not hi-lock-use-overlays))
          (hi-lock-unface-buffer t)
          (setq rehighlight t))
        (when rehighlight
          (setq hi-lock--unused-faces hi-lock-face-defaults)
          (dolist (pattern (reverse patterns))
            (let ((face (hi-lock-keyword->face (cdr pattern))))
              (highlight-regexp (or (get-text-property 0 'regexp (car pattern))
                                    (car pattern))
                                face)
              (setq hi-lock--unused-faces
                    (remove (face-name face) hi-lock--unused-faces)))))))))

(defvar hi-lock--hashcons-hash
  (make-hash-table :test 'equal :weakness t)
  "Hash table used to hash cons regexps.")

(defun hi-lock--hashcons (string)
  "Return unique object equal to STRING."
  (or (gethash string hi-lock--hashcons-hash)
      (puthash string string hi-lock--hashcons-hash)))

(defun hi-lock-unload-function ()
  "Unload the Hi-Lock library."
  (global-hi-lock-mode -1)
  ;; continue standard unloading
  nil)

;;; Mouse support
(defalias 'highlight-symbol-at-mouse 'hi-lock-face-symbol-at-mouse)
(defun hi-lock-face-symbol-at-mouse (event)
  "Highlight symbol at mouse click EVENT."
  (interactive "e")
  (save-excursion
    (mouse-set-point event)
    (highlight-symbol-at-point)))

;;;###autoload
(defun hi-lock-context-menu (menu click)
  "Populate MENU with a menu item to highlight symbol at CLICK."
  (when (thing-at-mouse click 'symbol)
    (define-key-after menu [highlight-search-separator] menu-bar-separator
      'middle-separator)
    (define-key-after menu [highlight-search-mouse]
      '(menu-item "Highlight Symbol" highlight-symbol-at-mouse
                  :help "Highlight symbol at point")
      'highlight-search-separator))
  menu)

(provide 'hi-lock)

;;; hi-lock.el ends here
