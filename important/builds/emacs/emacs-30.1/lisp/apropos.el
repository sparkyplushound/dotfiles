;;; apropos.el --- apropos commands for users and programmers  -*- lexical-binding: t -*-

;; Copyright (C) 1989-2025 Free Software Foundation, Inc.

;; Author: Joe Wells <jbw@bigbird.bu.edu>
;;	Daniel Pfeiffer <occitan@esperanto.org> (rewrite)
;; Keywords: help
;; Package: emacs

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

;; The ideas for this package were derived from the C code in
;; src/keymap.c and elsewhere.

;; The idea for super-apropos is based on the original implementation
;; by Lynn Slater <lrs@esl.com>.

;; History:
;; Fixed bug, current-local-map can return nil.
;; Change, doesn't calculate key-bindings unless needed.
;; Added super-apropos capability, changed print functions.
;; Made fast-apropos and super-apropos share code.
;; Sped up fast-apropos again.
;; Added apropos-do-all option.
;; Added fast-command-apropos.
;; Changed doc strings to comments for helping functions.
;; Made doc file buffer read-only, buried it.
;; Only call substitute-command-keys if do-all set.

;; Optionally use configurable faces to make the output more legible.
;; Differentiate between command, function and macro.
;; Apropos-command (ex command-apropos) does cmd and optionally user var.
;; Apropos shows all 3 aspects of symbols (fn, var and plist)
;; Apropos-documentation (ex super-apropos) now finds all it should.
;; New apropos-value snoops through all values and optionally plists.
;; Reading DOC file doesn't load nroff.
;; Added hypertext following of documentation, mouse-2 on variable gives value
;;   from buffer in active window.

;;; Code:

(eval-when-compile (require 'cl-lib))

(defgroup apropos nil
  "Apropos commands for users and programmers."
  :group 'help
  :prefix "apropos")

;; I see a degradation of maybe 10-20% only.
(defcustom apropos-do-all nil
  "Non-nil means apropos commands will search more extensively.
This may be slower.  This option affects the following commands:

`apropos-user-option' will search all variables, not just user options.
`apropos-command' will also search non-interactive functions.
`apropos' will search all symbols, not just functions, variables, faces,
and those with property lists.
`apropos-value' will also search in property lists and functions.
`apropos-documentation' will search all documentation strings, not just
those in the etc/DOC documentation file.

This option only controls the default behavior.  Each of the above
commands also has an optional argument to request a more extensive search.

Additionally, this option makes the function `apropos-library'
include keybinding information in its output."
  :type 'boolean)

(defface apropos-symbol
  '((t (:inherit bold)))
  "Face for the symbol name in Apropos output."
  :version "24.3")

(defface apropos-keybinding
  '((t (:inherit underline)))
  "Face for lists of keybinding in Apropos output."
  :version "24.3")

(defface apropos-property
  '((t (:inherit font-lock-builtin-face)))
  "Face for property name in Apropos output, or nil for none."
  :version "24.3")

(defface apropos-button
  '((t (:inherit (font-lock-variable-name-face button))))
  "Face for buttons that indicate a face in Apropos."
  :version "28.1")

(defface apropos-function-button
  '((t (:inherit (font-lock-function-name-face button))))
  "Button face indicating a function, macro, or command in Apropos."
  :version "24.3")

(defface apropos-variable-button
  '((t (:inherit (font-lock-variable-name-face button))))
  "Button face indicating a variable in Apropos."
  :version "24.3")

(defface apropos-user-option-button
  '((t (:inherit (font-lock-variable-name-face button))))
  "Button face indicating a user option in Apropos."
  :version "24.4")

(defface apropos-misc-button
  '((t (:inherit (font-lock-constant-face button))))
  "Button face indicating a miscellaneous object type in Apropos."
  :version "24.3")

(defcustom apropos-match-face 'match
  "Face for matching text in Apropos documentation/value, or nil for none.
This applies when you look for matches in the documentation or variable value
for the pattern; the part that matches gets displayed in this font."
  :type '(choice (const nil) face)
  :version "24.3")

(defcustom apropos-sort-by-scores nil
  "Non-nil means sort matches by scores; best match is shown first.
This applies to all `apropos' commands except `apropos-documentation'.
If value is `verbose', the computed score is shown for each match."
  :type '(choice (const :tag "off" nil)
		 (const :tag "on" t)
		 (const :tag "show scores" verbose)))

(defcustom apropos-documentation-sort-by-scores t
  "Non-nil means sort matches by scores; best match is shown first.
This applies to `apropos-documentation' only.
If value is `verbose', the computed score is shown for each match."
  :type '(choice (const :tag "off" nil)
		 (const :tag "on" t)
		 (const :tag "show scores" verbose)))

(defvar apropos-mode-map
  (let ((map (copy-keymap button-buffer-map)))
    (set-keymap-parent map special-mode-map)
    ;; Use `apropos-follow' instead of just using the button
    ;; definition of RET, so that users can use it anywhere in an
    ;; apropos item, not just on top of a button.
    (define-key map "\C-m" #'apropos-follow)

    ;; Movement keys
    (define-key map "n" #'apropos-next-symbol)
    (define-key map "p" #'apropos-previous-symbol)
    map)
  "Keymap used in Apropos mode.")

(defvar apropos-mode-hook nil
  "Hook run when mode is turned on.")

(defvar apropos-pattern nil
  "Apropos pattern as entered by user.")

(defvar apropos-pattern-quoted nil
  "Apropos pattern passed through `regexp-quote'.")

(defvar apropos-words ()
  "Current list of apropos words extracted from `apropos-pattern'.")

(defvar apropos-all-words ()
  "Current list of words and synonyms.")

(defvar apropos-regexp nil
  "Regexp used in current apropos run.")

(defvar apropos-all-words-regexp nil
  "Regexp matching `apropos-all-words'.")

(defvar apropos-files-scanned ()
  "List of elc files already scanned in current run of `apropos-documentation'.")

(defvar apropos-accumulator ()
  "Alist of symbols already found in current apropos run.
Each element has the form

  (SYMBOL SCORE FUN-DOC VAR-DOC PLIST WIDGET-DOC FACE-DOC CUS-GROUP-DOC)

where SYMBOL is the symbol name, SCORE is its relevance score (a
number), FUN-DOC is the function docstring, VAR-DOC is the
variable docstring, PLIST is the list of the symbols names in the
property list, WIDGET-DOC is the widget docstring, FACE-DOC is
the face docstring, and CUS-GROUP-DOC is the custom group
docstring.  Each docstring is either nil or a string.")

(defvar apropos-synonyms '(
  ("find" "open" "edit")
  ("kill" "cut")
  ("yank" "paste")
  ("region" "selection"))
  "List of synonyms known by apropos.
Each element is a list of words where the first word is the standard Emacs
term, and the rest of the words are alternative terms.")

(defvar apropos--current nil
  "List of current Apropos function followed by its arguments.
Used by `apropos--revert-buffer' to regenerate the current
Apropos buffer.  Each Apropos command should ensure it is set
before `apropos-mode' makes it buffer-local.")


;;; Button types used by apropos

(define-button-type 'apropos-symbol
  'face 'apropos-symbol
  'help-echo "\\`mouse-2', \\`RET': Display more help on this symbol"
  'follow-link t
  'action #'apropos-symbol-button-display-help)

(defun apropos-symbol-button-display-help (button)
  "Display further help for the `apropos-symbol' button BUTTON."
  (button-activate
   (or (apropos-next-label-button (button-start button))
       (error "There is nothing to follow for `%s'" (button-label button)))))

(define-button-type 'apropos-function
  'apropos-label "Function"
  'apropos-short-label "f"
  'face 'apropos-function-button
  'help-echo "\\`mouse-2', \\`RET': Display more help on this function"
  'follow-link t
  'action (lambda (button)
	    (describe-function (button-get button 'apropos-symbol))))

(define-button-type 'apropos-macro
  'apropos-label "Macro"
  'apropos-short-label "m"
  'face 'apropos-function-button
  'help-echo "\\`mouse-2', \\`RET': Display more help on this macro"
  'follow-link t
  'action (lambda (button)
	    (describe-function (button-get button 'apropos-symbol))))

(define-button-type 'apropos-command
  'apropos-label "Command"
  'apropos-short-label "c"
  'face 'apropos-function-button
  'help-echo "\\`mouse-2', \\`RET': Display more help on this command"
  'follow-link t
  'action (lambda (button)
	    (describe-function (button-get button 'apropos-symbol))))

;; We used to use `customize-variable-other-window' instead for a
;; customizable variable, but that is slow.  It is better to show an
;; ordinary help buffer and let the user click on the customization
;; button in that buffer, if he wants to.
;; Likewise for `customize-face-other-window'.
(define-button-type 'apropos-variable
  'apropos-label "Variable"
  'apropos-short-label "v"
  'face 'apropos-variable-button
  'help-echo "\\`mouse-2', \\`RET': Display more help on this variable"
  'follow-link t
  'action (lambda (button)
	    (describe-variable (button-get button 'apropos-symbol))))

(define-button-type 'apropos-user-option
  'apropos-label "User option"
  'apropos-short-label "o"
  'face 'apropos-user-option-button
  'help-echo "\\`mouse-2', \\`RET': Display more help on this user option"
  'follow-link t
  'action (lambda (button)
	    (describe-variable (button-get button 'apropos-symbol))))

(define-button-type 'apropos-face
  'apropos-label "Face"
  'apropos-short-label "F"
  'face 'apropos-button
  'help-echo "\\`mouse-2', \\`RET': Display more help on this face"
  'follow-link t
  'action (lambda (button)
	    (describe-face (button-get button 'apropos-symbol))))

(define-button-type 'apropos-group
  'apropos-label "Group"
  'apropos-short-label "g"
  'face 'apropos-misc-button
  'help-echo "\\`mouse-2', \\`RET': Display more help on this group"
  'follow-link t
  'action (lambda (button)
	    (customize-group-other-window
	     (button-get button 'apropos-symbol))))

(define-button-type 'apropos-widget
  'apropos-label "Widget"
  'apropos-short-label "w"
  'face 'apropos-misc-button
  'help-echo "\\`mouse-2', \\`RET': Display more help on this widget"
  'follow-link t
  'action (lambda (button)
	    (widget-browse-other-window (button-get button 'apropos-symbol))))

(define-button-type 'apropos-plist
  'apropos-label "Properties"
  'apropos-short-label "p"
  'face 'apropos-misc-button
  'help-echo "\\`mouse-2', \\`RET': Display more help on this plist"
  'follow-link t
  'action (lambda (button)
	    (apropos-describe-plist (button-get button 'apropos-symbol))))

(define-button-type 'apropos-library
  'help-echo "\\`mouse-2', \\`RET': Display more help on this library"
  'follow-link t
  'action (lambda (button)
	    (apropos-library (button-get button 'apropos-symbol))))

(defun apropos-next-label-button (pos)
  "Return the next apropos label button after POS, or nil if there's none.
Will also return nil if more than one `apropos-symbol' button is encountered
before finding a label."
  (let* ((button (next-button pos t))
	 (already-hit-symbol nil)
	 (label (and button (button-get button 'apropos-label)))
	 (type (and button (button-get button 'type))))
    (while (and button
		(not label)
		(or (not (eq type 'apropos-symbol))
		    (not already-hit-symbol)))
      (when (eq type 'apropos-symbol)
	(setq already-hit-symbol t))
      (setq button (next-button (button-start button)))
      (when button
	(setq label (button-get button 'apropos-label))
	(setq type (button-get button 'type))))
    (and label button)))


(defun apropos-words-to-regexp (words wild)
  "Return a regexp matching any two of the words in WORDS.
WILD should be a subexpression matching wildcards between matches."
  (setq words (delete-dups (copy-sequence words)))
  (if (null (cdr words))
      (car words)
    (mapconcat
     (lambda (w)
       (concat "\\(?:" w "\\)" ;; parens for synonyms
               wild "\\(?:"
               (mapconcat #'identity
			  (delq w (copy-sequence words))
			  "\\|")
               "\\)"))
     words
     "\\|")))

;;;###autoload
(defun apropos-read-pattern (subject)
  "Read an apropos pattern, either a word list or a regexp.
Returns the user pattern, either a list of words which are matched
literally, or a string which is used as a regexp to search for.

SUBJECT is a string that is included in the prompt to identify what
kind of objects to search."
  (let ((pattern
	 (read-string (concat "Search for " subject " (word list or regexp): "))))
    (if (string-equal (regexp-quote pattern) pattern)
	;; Split into words
	(or (split-string pattern "[ \t]+" t)
	    (user-error "No word list given"))
      pattern)))

(defun apropos-parse-pattern (pattern &optional multiline-p)
  "Rewrite a list of words to a regexp matching all permutations.
If PATTERN is a string, that means it is already a regexp.
MULTILINE-P, if non-nil, means produce a regexp that will match
the words even if separated by newlines.
This updates variables `apropos-pattern', `apropos-pattern-quoted',
`apropos-regexp', `apropos-words', and `apropos-all-words-regexp'."
  (setq apropos-words nil
	apropos-all-words nil)
  (if (consp pattern)
      ;; We don't actually make a regexp matching all permutations.
      ;; Instead, for e.g. "a b c", we make a regexp matching
      ;; any combination of two or more words like this:
      ;; (a|b|c).*(a|b|c) which may give some false matches,
      ;; but as long as it also gives the right ones, that's ok.
      ;; (Actually, when MULTILINE-P is non-nil, instead of '.' we
      ;; use a trick that would find a match even if the words are
      ;; on different lines.
      (let ((words pattern))
	(setq apropos-pattern (mapconcat #'identity pattern " ")
	      apropos-pattern-quoted (regexp-quote apropos-pattern))
	(dolist (word words)
	  (let ((syn apropos-synonyms) (s word) (a word))
	    (while syn
	      (if (member word (car syn))
		  (progn
		    (setq a (mapconcat #'identity (car syn) "\\|"))
		    (if (member word (cdr (car syn)))
			(setq s a))
		    (setq syn nil))
		(setq syn (cdr syn))))
	    (setq apropos-words (cons s apropos-words)
		  apropos-all-words (cons a apropos-all-words))))
	(setq apropos-all-words-regexp
	      (apropos-words-to-regexp apropos-all-words
                                       ;; The [^b-a] trick matches any
                                       ;; character including a newline.
                                       (if multiline-p "[^b-a]+?" ".+")))
	(setq apropos-regexp
	      (apropos-words-to-regexp apropos-words
                                       (if multiline-p "[^b-a]*?" ".*?"))))
    (setq apropos-pattern-quoted (regexp-quote pattern)
	  apropos-all-words-regexp pattern
	  apropos-pattern pattern
	  apropos-regexp pattern)))

(defun apropos-calc-scores (str words)
  "Return apropos scores for string STR matching WORDS.
Value is a list of offsets of the words into the string."
  (let (scores i)
    (if words
	(dolist (word words scores)
	  (if (setq i (string-match word str))
	      (setq scores (cons i scores))))
      ;; Return list of start and end position of regexp
      (and (string-match apropos-pattern str)
	   (list (match-beginning 0) (match-end 0))))))

(defun apropos-score-str (str)
  "Return apropos score for string STR."
  (if str
      (let* ((l (length str))
	     (score (- (/ l 10))))
	(dolist (s (apropos-calc-scores str apropos-all-words) score)
	  (setq score (+ score 1000 (/ (* (- l s) 1000) l)))))
      0))

(defun apropos-score-doc (doc)
  "Return apropos score for documentation string DOC."
  (let ((l (length doc)))
    (if (> l 0)
	(let ((score 0))
	  (when (string-match apropos-pattern-quoted doc)
	    (setq score 10000))
	  (dolist (s (apropos-calc-scores doc apropos-all-words) score)
	    (setq score (+ score 50 (/ (* (- l s) 50) l)))))
      0)))

(defun apropos-score-symbol (symbol &optional weight)
  "Return apropos score for SYMBOL."
  (setq symbol (symbol-name symbol))
  (let ((score 0)
	(l (length symbol)))
    (dolist (s (apropos-calc-scores symbol apropos-words) (* score (or weight 3)))
      (setq score (+ score (- 60 l) (/ (* (- l s) 60) l))))))

(defun apropos-true-hit (str words)
  "Return t if STR is a genuine hit.
This may fail if only one of the keywords is matched more than once.
This requires at least two keywords (unless only one was given)."
  (or (not str)
      (not words)
      (not (cdr words))
      (> (length (apropos-calc-scores str words)) 1)))

(defun apropos-false-hit-symbol (symbol)
  "Return t if SYMBOL is not really matched by the current keywords."
  (not (apropos-true-hit (symbol-name symbol) apropos-words)))

(defun apropos-false-hit-str (str)
  "Return t if STR is not really matched by the current keywords."
  (not (apropos-true-hit str apropos-words)))

(defun apropos-true-hit-doc (doc)
  "Return t if DOC is really matched by the current keywords."
  (apropos-true-hit doc apropos-all-words))

(defun apropos--revert-buffer (_ignore-auto noconfirm)
  "Regenerate current Apropos buffer using `apropos--current'.
Intended as a value for `revert-buffer-function'."
  (when (or noconfirm (yes-or-no-p "Revert apropos buffer? "))
    (apply #'funcall apropos--current)))

(define-derived-mode apropos-mode special-mode "Apropos"
  "Major mode for following hyperlinks in output of apropos commands.

\\{apropos-mode-map}"
  (make-local-variable 'apropos--current)
  (setq-local revert-buffer-function #'apropos--revert-buffer)
  (setq-local outline-search-function #'outline-search-level
              outline-level (lambda () 1)
              outline-minor-mode-cycle t
              outline-minor-mode-highlight t
              outline-minor-mode-use-buttons 'insert))

(defvar apropos-multi-type t
  "If non-nil, this apropos query concerns multiple types.
This is used to decide whether to print the result's type or not.")

;;;###autoload
(defun apropos-user-option (pattern &optional do-all)
  "Show user options that match PATTERN.
PATTERN can be a word, a list of words (separated by spaces),
or a regexp (using some regexp special characters).  If it is a word,
search for matches for that word as a substring.  If it is a list of words,
search for matches for any two (or more) of those words.

With \\[universal-argument] prefix, or if `apropos-do-all' is non-nil, also show
variables, not just user options."
  (interactive (list (apropos-read-pattern
		      (if (or current-prefix-arg apropos-do-all)
			  "variable" "user option"))
                     current-prefix-arg))
  (apropos-command pattern (or do-all apropos-do-all)
		   (if (or do-all apropos-do-all)
                       (lambda (symbol)
                         (and (boundp symbol)
                              (get symbol 'variable-documentation)))
		     #'custom-variable-p)))

;;;###autoload
(defun apropos-variable (pattern &optional do-not-all)
  "Show variables that match PATTERN.
With the optional argument DO-NOT-ALL non-nil (or when called
interactively with the prefix \\[universal-argument]), show user
options only, i.e. behave like `apropos-user-option'."
  (interactive (list (apropos-read-pattern
		      (if current-prefix-arg "user option" "variable"))
                     current-prefix-arg))
  (let ((apropos-do-all (if do-not-all nil t)))
    (apropos-user-option pattern)))

;;;###autoload
(defun apropos-local-variable (pattern &optional buffer)
  "Show buffer-local variables that match PATTERN.
Optional arg BUFFER (default: current buffer) is the buffer to check.

The output includes variables that are not yet set in BUFFER, but that
will be buffer-local when set."
  (interactive (list (apropos-read-pattern "buffer-local variable")))
  (unless buffer (setq buffer  (current-buffer)))
  (apropos-command pattern nil (lambda (symbol)
                                 (and (local-variable-if-set-p symbol)
                                      (get symbol 'variable-documentation)))))

;;;###autoload
(defun apropos-function (pattern)
  "Show functions that match PATTERN.

PATTERN can be a word, a list of words (separated by spaces),
or a regexp (using some regexp special characters).  If it is a word,
search for matches for that word as a substring.  If it is a list of words,
search for matches for any two (or more) of those words.

This is the same as running `apropos-command' with a \\[universal-argument] prefix,
or a non-nil `apropos-do-all' argument."
  (interactive (list (apropos-read-pattern "function")))
  (apropos-command pattern t))

;; For auld lang syne:
;;;###autoload
(defalias 'command-apropos #'apropos-command)
;;;###autoload
(defun apropos-command (pattern &optional do-all var-predicate)
  "Show commands (interactively callable functions) that match PATTERN.
PATTERN can be a word, a list of words (separated by spaces),
or a regexp (using some regexp special characters).  If it is a word,
search for matches for that word as a substring.  If it is a list of words,
search for matches for any two (or more) of those words.

With \\[universal-argument] prefix, or if `apropos-do-all' is non-nil, also show
noninteractive functions.

If VAR-PREDICATE is non-nil, show only variables, and only those that
satisfy the predicate VAR-PREDICATE.

When called from a Lisp program, a string PATTERN is used as a regexp,
while a list of strings is used as a word list."
  (interactive (list (apropos-read-pattern
		      (if (or current-prefix-arg apropos-do-all)
			  "command or function" "command"))
		     current-prefix-arg))
  (setq apropos--current (list #'apropos-command pattern do-all var-predicate))
  (apropos-parse-pattern pattern)
  (let ((message
	 (let ((standard-output (get-buffer-create "*Apropos*")))
	   (help-print-return-message 'identity))))
    (or do-all (setq do-all apropos-do-all))
    (setq apropos-accumulator
	  (apropos-internal apropos-regexp
			    (or var-predicate
                                ;; We used to use `functionp' here, but this
                                ;; rules out macros.  `fboundp' rules in
                                ;; keymaps, but it seems harmless.
				(if do-all 'fboundp 'commandp))))
    (let ((tem apropos-accumulator))
      (while tem
	(if (or (get (car tem) 'apropos-inhibit)
		(apropos-false-hit-symbol (car tem)))
	    (setq apropos-accumulator (delq (car tem) apropos-accumulator)))
	(setq tem (cdr tem))))
    (let ((p apropos-accumulator)
	  doc symbol score)
      (while p
	(setcar p (list
		   (setq symbol (car p))
		   (setq score (apropos-score-symbol symbol))
		   (unless var-predicate
		     (if (fboundp symbol)
			 (if (setq doc (condition-case nil
                                           (documentation symbol t)
                                         (error 'error)))
                             ;; Eg alias to undefined function.
                             (if (eq doc 'error)
                                 "(documentation error)"
			       (setq score (+ score (apropos-score-doc doc)))
			       (substring doc 0 (string-search "\n" doc)))
			   "(not documented)")))
		   (and var-predicate
			(funcall var-predicate symbol)
			(if (setq doc (documentation-property
				       symbol 'variable-documentation t))
			     (progn
			       (setq score (+ score (apropos-score-doc doc)))
			       (substring doc 0
					  (string-search "\n" doc)))))))
	(setcar (cdr (car p)) score)
	(setq p (cdr p))))
    (and (let ((apropos-multi-type do-all))
           (apropos-print t nil nil t))
	 message
	 (message "%s" message))))


;;;###autoload
(defun apropos-documentation-property (symbol property raw)
  "Like (documentation-property SYMBOL PROPERTY RAW) but handle errors."
  (condition-case ()
      (let ((doc (documentation-property symbol property raw)))
	(if doc (substring doc 0 (string-search "\n" doc))
	  "(not documented)"))
    (error "(error retrieving documentation)")))


;;;###autoload
(defun apropos (pattern &optional do-all)
  "Show all meaningful Lisp symbols whose names match PATTERN.
Symbols are shown if they are defined as functions, variables, or
faces, or if they have nonempty property lists, or if they are
known keywords.

PATTERN can be a word, a list of words (separated by spaces),
or a regexp (using some regexp special characters).  If it is a word,
search for matches for that word as a substring.  If it is a list of words,
search for matches for any two (or more) of those words.

With \\[universal-argument] prefix, or if `apropos-do-all' is non-nil,
consider all symbols (if they match PATTERN).

Return list of symbols and documentation found.

The *Apropos* window will be selected if `help-window-select' is
non-nil."
  (interactive (list (apropos-read-pattern "symbol")
		     current-prefix-arg))
  (setq apropos--current (list #'apropos pattern do-all))
  (apropos-parse-pattern pattern)
  (apropos-symbols-internal
   (apropos-internal apropos-regexp
		     (and (not do-all)
			  (not apropos-do-all)
			  (lambda (symbol)
			    (or (fboundp symbol)
				(boundp symbol)
				(facep symbol)
				(symbol-plist symbol)))))
   (or do-all apropos-do-all)))

(defun apropos-library-button (sym)
  (if (null sym)
      "<nothing>"
    (let ((name (symbol-name sym)))
      (make-text-button name nil
                        'type 'apropos-library
                        'face 'apropos-symbol
                        'apropos-symbol name))))

;;;###autoload
(defun apropos-library (file)
  "List the variables and functions defined by library FILE.
FILE should be one of the libraries currently loaded and should
thus be found in `load-history'.  If `apropos-do-all' is non-nil,
the output includes key-bindings of commands."
  (interactive
   (let* ((libs (delq nil (mapcar #'car load-history)))
          (libs
           (nconc (delq nil
                        (mapcar
                         (lambda (l)
                           (setq l (file-name-nondirectory l))
                           (while
                               (not (equal (setq l (file-name-sans-extension l))
                                           l)))
                           l)
                         libs))
                  libs)))
     (list (completing-read "Describe library: " libs nil t))))
  (setq apropos--current (list #'apropos-library file))
  (let ((symbols nil)
	;; (autoloads nil)
	(provides nil)
	(requires nil)
        (lh-entry (assoc file load-history)))
    (unless lh-entry
      ;; `file' may be the "shortname".
      (let ((lh load-history)
            (re (concat "\\(?:\\`\\|[\\/]\\)" (regexp-quote file)
                        "\\(\\.\\|\\'\\)")))
        (while (and lh (null lh-entry))
          (if (and (stringp (caar lh)) (string-match re (caar lh)))
              (setq lh-entry (car lh))
            (setq lh (cdr lh)))))
      (unless lh-entry (error "Unknown library `%s'" file)))
    (dolist (x (cdr lh-entry))
      (pcase (car-safe x)
	;; (autoload (push (cdr x) autoloads))
	('require (push (cdr x) requires))
	('provide (push (cdr x) provides))
        ('t nil)                     ; Skip "was an autoload" entries.
        ;; FIXME: Print information about each individual method: both
        ;; its docstring and specializers (bug#21422).
        ('cl-defmethod (push (cadr x) provides))
        ;; FIXME: Add extension point (bug#72616).
	(_ (let ((sym (or (cdr-safe x) x)))
	     (and sym (symbolp sym)
	          (push sym symbols))))))
    (let ((apropos-pattern "") ;Dummy binding for apropos-symbols-internal.
          (text
           (concat
            (format-message
             "Library `%s' provides: %s\nand requires: %s"
             file
             (mapconcat #'apropos-library-button
                        (or provides '(nil)) " and ")
             (mapconcat #'apropos-library-button
                        (or requires '(nil)) " and ")))))
      (if (null symbols)
          (with-output-to-temp-buffer "*Apropos*"
	    (with-current-buffer standard-output
	      (apropos-mode)
              (apropos--preamble text)))
        (apropos-symbols-internal symbols apropos-do-all text)))))

(defun apropos-symbols-internal (symbols keys &optional text)
  ;; Filter out entries that are marked as apropos-inhibit.
  (let ((all nil))
    (dolist (symbol symbols)
      (unless (get symbol 'apropos-inhibit)
	(push symbol all)))
    (setq symbols all))
  (let ((apropos-accumulator
	 (mapcar
	  (lambda (symbol)
	    (let (doc properties)
	      (list
	       symbol
	       (apropos-score-symbol symbol)
	       (when (fboundp symbol)
		 (if (setq doc (condition-case nil
				   (documentation symbol t)
				 (void-function
				  "(alias for undefined function)")
				 (error
				  "(can't retrieve function documentation)")))
		     (substring doc 0 (string-search "\n" doc))
		   "(not documented)"))
	       (when (boundp symbol)
		 (apropos-documentation-property
		  symbol 'variable-documentation t))
	       (when (setq properties (symbol-plist symbol))
		 (setq doc (list (car properties)))
		 (while (setq properties (cdr (cdr properties)))
		   (setq doc (cons (car properties) doc)))
		 (mapconcat (lambda (p) (format "%s" p)) (nreverse doc) " "))
	       (when (get symbol 'widget-type)
		 (apropos-documentation-property
		  symbol 'widget-documentation t))
	       (when (facep symbol)
		 (let ((alias (get symbol 'face-alias)))
		   (if alias
		       (if (facep alias)
			   (format-message
			    "%slias for the face `%s'."
			    (if (get symbol 'obsolete-face) "Obsolete a" "A")
			    alias)
			 ;; Never happens in practice because fails
			 ;; (facep symbol) test.
			 "(alias for undefined face)")
		     (apropos-documentation-property
		      symbol 'face-documentation t))))
	       (when (get symbol 'custom-group)
		 (apropos-documentation-property
		  symbol 'group-documentation t)))))
	  symbols)))
    (apropos-print keys nil text)))


;;;###autoload
(defun apropos-value (pattern &optional do-all)
  "Show all symbols whose value's printed representation matches PATTERN.
PATTERN can be a word, a list of words (separated by spaces),
or a regexp (using some regexp special characters).  If it is a word,
search for matches for that word as a substring.  If it is a list of words,
search for matches for any two (or more) of those words.

With \\[universal-argument] prefix, or if `apropos-do-all' is non-nil, also looks
at function definitions (arguments, documentation and body) and at the
names and values of properties.

Returns list of symbols and values found."
  (interactive (list (apropos-read-pattern "value")
		     current-prefix-arg))
  (setq apropos--current (list #'apropos-value pattern do-all))
  (apropos-parse-pattern pattern t)
  (or do-all (setq do-all apropos-do-all))
  (setq apropos-accumulator ())
  (let (f v p)
    (mapatoms
     (lambda (symbol)
       (setq f nil v nil p nil)
       (or (memq symbol '(apropos-regexp
                          apropos--current apropos-pattern-quoted pattern
		          apropos-pattern apropos-all-words-regexp
		          apropos-words apropos-all-words
		          apropos-accumulator))
           (setq v (apropos-value-internal #'boundp symbol #'symbol-value)))
       (if do-all
           (setq f (apropos-value-internal #'fboundp symbol #'symbol-function)
	         p (apropos-format-plist symbol "\n    " t)))
       (if (apropos-false-hit-str v)
           (setq v nil))
       (if (apropos-false-hit-str f)
           (setq f nil))
       (if (apropos-false-hit-str p)
           (setq p nil))
       (if (or f v p)
           (setq apropos-accumulator (cons (list symbol
					         (+ (apropos-score-str f)
					            (apropos-score-str v)
					            (apropos-score-str p))
					         f v p)
				           apropos-accumulator))))))
  (let ((apropos-multi-type do-all))
    (apropos-print nil "\n")))

;;;###autoload
(defun apropos-local-value (pattern &optional buffer)
  "Show buffer-local variables whose values match PATTERN.
This is like `apropos-value', but only for buffer-local variables.
Optional arg BUFFER (default: current buffer) is the buffer to check."
  (interactive (list (apropos-read-pattern "value of buffer-local variable")))
  (unless buffer (setq buffer  (current-buffer)))
  (setq apropos--current (list #'apropos-local-value pattern buffer))
  (apropos-parse-pattern pattern t)
  (setq apropos-accumulator  ())
  (let ((var             nil))
    (mapatoms
     (lambda (symb)
       (unless (memq symb '(apropos-regexp apropos-pattern
                            apropos-all-words-regexp apropos-words
                            apropos-all-words apropos-accumulator))
         (setq var  (apropos-value-internal #'local-variable-if-set-p symb
                                            #'symbol-value)))
       (when (apropos-false-hit-str var)
         (setq var nil))
       (when var
         (setq apropos-accumulator (cons (list symb (apropos-score-str var) nil var)
                                         apropos-accumulator))))))
  (let ((apropos-multi-type  nil))
    (apropos-print
     nil "\n----------------\n"
     (format "Buffer `%s' has the following local variables\nmatching %s`%s':"
             (buffer-name buffer)
             (if (consp pattern) "keywords " "")
             pattern))))

(defun apropos--map-preloaded-atoms (f)
  "Like `mapatoms' but only enumerates functions&vars that are predefined."
  (let ((preloaded-regexp
         (concat "\\`"
                 (regexp-quote lisp-directory)
                 (regexp-opt preloaded-file-list)
                 "\\.elc?\\'")))
    ;; FIXME: I find this regexp approach brittle.  Maybe a better
    ;; option would be find/record the nthcdr of `load-history' which
    ;; corresponds to the `load-history' state when we dumped.
    ;; (Then again, maybe an even better approach would be to record the
    ;; state of the `obarray' when we dumped, which we may also be able to
    ;; use in `bytecomp' to provide a clean initial environment?)
    (dolist (x load-history)
      (when (let ((elt (car x)))
              (and (stringp elt) (string-match preloaded-regexp elt)))
        (dolist (def (cdr x))
          (cond
           ((symbolp def) (funcall f def))
           ((eq 'defun (car-safe def)) (funcall f (cdr def)))))))))

(defun apropos--documentation-add (symbol doc pos)
  (when (setq doc (apropos-documentation-internal doc))
    (let ((score (apropos-score-doc doc))
          (item (cdr (assq symbol apropos-accumulator))))
      (unless item
        (push (cons symbol
                    (setq item (list (apropos-score-symbol symbol 2)
                                     nil nil)))
              apropos-accumulator))
      (setf (nth pos item) doc)
      (setcar item (+ (car item) score)))))

;;;###autoload
(defun apropos-documentation (pattern &optional do-all)
  "Show symbols whose documentation contains matches for PATTERN.
PATTERN can be a word, a list of words (separated by spaces),
or a regexp (using some regexp special characters).  If it is a word,
search for matches for that word as a substring.  If it is a list of words,
search for matches for any two (or more) of those words.

Note that by default this command only searches in the functions predefined
at Emacs startup, i.e., the primitives implemented in C or preloaded in the
Emacs dump image.
With \\[universal-argument] prefix, or if `apropos-do-all' is non-nil, it searches
all currently defined documentation strings.

Returns list of symbols and documentation found."
  ;; The doc used to say that DO-ALL includes key-bindings info in the
  ;; output, but I cannot see that that is true.
  (interactive (list (apropos-read-pattern "documentation")
		     current-prefix-arg))
  (setq apropos--current (list #'apropos-documentation pattern do-all))
  (apropos-parse-pattern pattern t)
  (or do-all (setq do-all apropos-do-all))
  (let ((apropos-accumulator ())
        (apropos-files-scanned ())
        (delayed (make-hash-table :test #'equal)))
    (with-temp-buffer
      (let ((standard-input (current-buffer))
            (apropos-sort-by-scores apropos-documentation-sort-by-scores)
            f v)
        (apropos-documentation-check-doc-file)
        (funcall
         (if do-all #'mapatoms #'apropos--map-preloaded-atoms)
         (lambda (symbol)
           (setq f (apropos-safe-documentation symbol)
                 v (get symbol 'variable-documentation))
           (if (integerp v) (setq v nil))
           (if (consp f)
               (push (list symbol (cdr f) 1) (gethash (car f) delayed))
             (apropos--documentation-add symbol f 1))
           (if (consp v)
               (push (list symbol (cdr v) 2) (gethash (car v) delayed))
             (apropos--documentation-add symbol v 2))))
        (maphash #'apropos--documentation-add-from-elc delayed)
        (apropos-print nil "\n----------------\n" nil t)))))


(defun apropos-value-internal (predicate symbol function)
  (when (funcall predicate symbol)
    (let ((print-escape-newlines t))
      (setq symbol (prin1-to-string
                    (if (memq symbol '(command-history minibuffer-history))
                        ;; The value we're looking for will always be in
                        ;; the first element of these two lists, so skip
                        ;; that value.
                        (cdr (funcall function symbol))
                      (funcall function symbol)))))
    (when (string-match apropos-regexp symbol)
      (if apropos-match-face
          (put-text-property (match-beginning 0) (match-end 0)
                             'face apropos-match-face
                             symbol))
      symbol)))

(defun apropos-documentation-internal (doc)
  ;; By the time we get here, refs to DOC or to .elc files should have
  ;; been converted into actual strings.
  (cl-assert (not (or (consp doc) (integerp doc))))
  (cond
   ((and ;; Sanity check in case bad data sneaked into the
         ;; documentation slot.
         (stringp doc)
         (string-match apropos-all-words-regexp doc)
         (apropos-true-hit-doc doc))
    (when apropos-match-face
      (setq doc (substitute-command-keys (copy-sequence doc)))
      (if (or (string-match apropos-pattern-quoted doc)
              (string-match apropos-all-words-regexp doc))
          (put-text-property (match-beginning 0)
                             (match-end 0)
                             'face apropos-match-face doc))
      doc))))

(defun apropos-format-plist (pl sep &optional compare)
  "Return a string representation of the plist PL.
Paired elements are separated by the string SEP.  Only include
properties matching the current `apropos-regexp' when COMPARE is
non-nil."
  (setq pl (symbol-plist pl))
  (let (p p-out)
    (while pl
      (setq p (format "%s %S" (car pl) (nth 1 pl)))
      (if (or (not compare) (string-match apropos-regexp p))
	  (put-text-property 0 (length (symbol-name (car pl)))
			     'face 'apropos-property p)
	(setq p nil))
      (when p
        (and compare apropos-match-face
             (put-text-property (match-beginning 0) (match-end 0)
                                'face apropos-match-face
                                p))
        (setq p-out (concat p-out (if p-out sep) p)))
      (setq pl (nthcdr 2 pl)))
    p-out))


;; Finds all documentation related to APROPOS-REGEXP in internal-doc-file-name.

(defun apropos-documentation-check-doc-file ()
  (let (type symbol (sepa 2) sepb doc)
    (insert ?\^_)
    (backward-char)
    (insert-file-contents (concat doc-directory internal-doc-file-name))
    (forward-char)
    (while (save-excursion
	     (setq sepb (search-forward "\^_"))
	     (not (eobp)))
      (beginning-of-line 2)
      (if (save-restriction
	    (narrow-to-region (point) (1- sepb))
	    (re-search-forward apropos-all-words-regexp nil t))
	  (progn
	    (goto-char (1+ sepa))
	    (setq type (if (eq ?F (preceding-char))
			   2	; function documentation
			 3)		; variable documentation
		  symbol (read)
		  doc (buffer-substring (1+ (point)) (1- sepb)))
	    (when (and (apropos-true-hit-doc doc)
                       ;; The DOC file lists all built-in funcs and vars.
                       ;; If any are not currently bound, they can
                       ;; only be platform-specific stuff (eg NS) not
                       ;; in use on the current platform.
                       ;; So we exclude them.
                       (cond ((= 3 type) (boundp symbol))
                             ((= 2 type) (fboundp symbol))))
              (let ((apropos-item (assq symbol apropos-accumulator)))
		(or (and apropos-item
			 (setcar (cdr apropos-item)
			         (apropos-score-doc doc)))
		    (setq apropos-item (list symbol
					     (+ (apropos-score-symbol symbol 2)
					        (apropos-score-doc doc))
					     nil nil)
			  apropos-accumulator (cons apropos-item
						    apropos-accumulator)))
		(when apropos-match-face
		  (setq doc (substitute-command-keys doc))
		  (if (or (string-match apropos-pattern-quoted doc)
			  (string-match apropos-all-words-regexp doc))
		      (put-text-property (match-beginning 0)
				         (match-end 0)
				         'face apropos-match-face doc)))
		(setcar (nthcdr type apropos-item) doc)))))
      (setq sepa (goto-char sepb)))))

(defun apropos--documentation-add-from-elc (file defs)
  (erase-buffer)
  (insert-file-contents
   (if (file-name-absolute-p file) file
     (expand-file-name file lisp-directory)))
  (pcase-dolist (`(,symbol ,begbyte ,pos) defs)
    ;; We presume the file-bytes are the same as the buffer bytes,
    ;; which should indeed be the case because .elc files use the
    ;; `emacs-internal' encoding.
    (let* ((beg (byte-to-position (+ (point-min) begbyte)))
           (sizeend (1- beg))
           (size (save-excursion
                   (goto-char beg)
                   (skip-chars-backward " 0-9")
                   (cl-assert (looking-back "#@" (- (point) 2)))
                   (string-to-number (buffer-substring (point) sizeend))))
           (end (byte-to-position (+ begbyte size -1))))
      (when (save-restriction
	      ;; match ^ and $ relative to doc string
	      (narrow-to-region beg end)
	      (goto-char (point-min))
	      (re-search-forward apropos-all-words-regexp nil t))
	(let ((doc (buffer-substring beg end)))
	  (when (apropos-true-hit-doc doc)
	    (apropos--documentation-add symbol doc pos)))))))

(defun apropos-safe-documentation (function)
  "Like `documentation', except it avoids calling `get_doc_string'.
Will return nil instead."
  (when (setq function (indirect-function function))
    ;; FIXME: `function-documentation' says not to call it, but `documentation'
    ;; would turn (FILE . POS) references into strings too eagerly, so
    ;; we do want to use the lower-level function.
    (let ((doc (function-documentation function)))
      ;; Docstrings from the DOC file are handled elsewhere.
      (if (integerp doc) nil doc))))

(defcustom apropos-compact-layout nil
  "If non-nil, use a single line per binding."
  :type 'boolean)

(defun apropos-print (do-keys spacing &optional text nosubst)
  "Output result of apropos searching into buffer `*Apropos*'.
The value of `apropos-accumulator' is the list of items to output.
Each element should have the format
 (SYMBOL SCORE FN-DOC VAR-DOC [PLIST-DOC WIDGET-DOC FACE-DOC GROUP-DOC]).
The return value is the list that was in `apropos-accumulator', sorted
alphabetically by symbol name; but this function also sets
`apropos-accumulator' to nil before returning.
If DO-KEYS is non-nil, output the key bindings.  If NOSUBST is
nil, substitute \"ASCII quotes\" (i.e., grace accent and
apostrophe) with curly quotes), and if non-nil, leave them alone.
If SPACING is non-nil, it should be a string; separate items with
that string.  If non-nil, TEXT is a string that will be printed
as a heading."
  (if (null apropos-accumulator)
      (message "No apropos matches for `%s'" apropos-pattern)
    (setq apropos-accumulator
	  (sort apropos-accumulator
		(lambda (a b)
		  (if apropos-sort-by-scores
		      (or (> (cadr a) (cadr b))
			  (and (= (cadr a) (cadr b))
			       (string-lessp (car a) (car b))))
		    (string-lessp (car a) (car b))))))
    (with-output-to-temp-buffer "*Apropos*"
      (let ((p apropos-accumulator)
	    (old-buffer (current-buffer))
	    (inhibit-read-only t)
	    (button-end 0)
            (first t)
	    symbol item)
	(set-buffer standard-output)
	(apropos-mode)
        (apropos--preamble text)
	(dolist (apropos-item p)
	  (if (and spacing (not first))
	      (princ spacing)
            (setq first nil))
	  (setq symbol (car apropos-item))
	  ;; Insert dummy score element for backwards compatibility with 21.x
	  ;; apropos-item format.
	  (if (not (numberp (cadr apropos-item)))
	      (setq apropos-item
		    (cons (car apropos-item)
			  (cons nil (cdr apropos-item)))))
	  (when (= (point) button-end) (terpri))
	  (insert-text-button (symbol-name symbol)
			      'type 'apropos-symbol
			      'skip apropos-multi-type
			      'face 'apropos-symbol
			      'outline-level 1)
	  (setq button-end (point))
	  (if (and (eq apropos-sort-by-scores 'verbose)
		   (cadr apropos-item))
	      (insert " (" (number-to-string (cadr apropos-item)) ") "))
	  ;; Calculate key-bindings if we want them.
          (unless apropos-compact-layout
            (and do-keys
                 (commandp symbol)
                 (not (eq symbol 'self-insert-command))
                 (indent-to 30 1)
                 (if (let ((keys
                            (with-current-buffer old-buffer
                              (where-is-internal symbol)))
                           filtered)
                       ;; Copy over the list of key sequences,
                       ;; omitting any that contain a buffer or a frame.
                       ;; FIXME: Why omit keys that contain buffers and
                       ;; frames?  This looks like a bad workaround rather
                       ;; than a proper fix.  Does anybody know what problem
                       ;; this is trying to address?  --Stef
                       (dolist (key keys)
                         (let ((i 0)
                               loser)
                           (while (< i (length key))
                             (if (or (framep (aref key i))
                                     (bufferp (aref key i)))
                                 (setq loser t))
                             (setq i (1+ i)))
                           (or loser
                               (push key filtered))))
                       (setq item filtered))
                     ;; Convert the remaining keys to a string and insert.
                     (insert
                      (mapconcat
                       (lambda (key)
                         (setq key (condition-case ()
                                       (key-description key)
                                     (error)))
			 (put-text-property 0 (length key)
					    'face 'apropos-keybinding
					    key)
                         key)
                       item ", "))
                   (insert "M-x ... RET")
		   (put-text-property (- (point) 11) (- (point) 8)
				      'face 'apropos-keybinding)
		   (put-text-property (- (point) 3) (point)
				      'face 'apropos-keybinding)))
            (terpri))
	  (apropos-print-doc apropos-item
			     2
			     (if (commandp symbol)
				 'apropos-command
			       (if (macrop symbol)
				   'apropos-macro
				 'apropos-function))
			     (not nosubst))
	  (apropos-print-doc apropos-item
			     3
			     (if (custom-variable-p symbol)
				 'apropos-user-option
			       'apropos-variable)
			     (not nosubst))
          ;; Insert an excerpt of variable values.
          (when (boundp symbol)
            (insert "  Value: ")
            (let* ((print-escape-newlines t)
                   (value (prin1-to-string (symbol-value symbol)))
                   (truncated (truncate-string-to-width
                               value (- (window-width) 20) nil nil t)))
              (insert truncated)
              (unless (equal value truncated)
                (buttonize-region (1- (point)) (point)
                                  (lambda (_)
                                    (message "Value: %s" value))))
              (insert "\n")))
	  (apropos-print-doc apropos-item 7 'apropos-group t)
	  (apropos-print-doc apropos-item 6 'apropos-face t)
	  (apropos-print-doc apropos-item 5 'apropos-widget t)
	  (apropos-print-doc apropos-item 4 'apropos-plist nil))
        (setq-local truncate-partial-width-windows t)
        (setq-local truncate-lines t)))
    (when help-window-select
      (select-window (get-buffer-window "*Apropos*"))))
  (prog1 apropos-accumulator
    (setq apropos-accumulator ())))	; permit gc

(defun apropos-print-doc (apropos-item i type do-keys)
  (let ((doc (nth i apropos-item)))
    (when (stringp doc)
      (if apropos-compact-layout
          (insert (propertize "\t" 'display '(space :align-to 32)))
        (insert " "))
      (if apropos-multi-type
	  (let ((button-face (button-type-get type 'face)))
	    (unless (consp button-face)
	      (setq button-face (list button-face)))
            (insert " ")
	    (insert-text-button
	     (if apropos-compact-layout
		 (format "<%s>" (button-type-get type 'apropos-short-label))
	       (button-type-get type 'apropos-label))
	     'type type
	     'apropos-symbol (car apropos-item))
	    (insert (if apropos-compact-layout " " ": ")))

	;; If the query is only for a single type, there's no point
	;; writing it over and over again.  Insert a blank button, and
	;; put the 'apropos-label property there (needed by
	;; apropos-symbol-button-display-help).
	(insert-text-button
	 " " 'type type 'skip t
	 'face 'default 'apropos-symbol (car apropos-item)))

      (let ((opoint (point))
	    (ocol (current-column)))
	(cond ((equal doc "")
	       (setq doc "(not documented)"))
	      (do-keys
	       (setq doc (or (ignore-errors
                               (substitute-command-keys doc))
                             doc))))
	(insert doc)
	(if (equal doc "(not documented)")
	    (put-text-property opoint (point) 'font-lock-face 'shadow))
	;; The labeling buttons might make the line too long, so fill it if
	;; necessary.
	(let ((fill-column (+ 5 (if (integerp emacs-lisp-docstring-fill-column)
                                    emacs-lisp-docstring-fill-column
                                  fill-column)))
	      (fill-prefix (make-string ocol ?\s)))
	  (fill-region opoint (point) nil t)))
      (or (bolp) (terpri)))))

(defun apropos--preamble (text)
  (let ((inhibit-read-only t))
    (insert (substitute-command-keys "Type \\[apropos-follow] on ")
	    (if apropos-multi-type "a type label" "an entry")
	    " to view its full documentation.\n\n")
    (when text
      (insert text "\n\n"))))

(defun apropos-follow ()
  "Invokes any button at point, otherwise invokes the nearest label button."
  (interactive nil apropos-mode)
  (button-activate
   (or (apropos-next-label-button (line-beginning-position))
       (error "There is nothing to follow here"))))

(defun apropos-next-symbol ()
  "Move cursor down to the next symbol in an `apropos-mode' buffer."
  (interactive nil apropos-mode)
  (forward-line)
  (while (and (not (eq (face-at-point) 'apropos-symbol))
              (< (point) (point-max)))
    (forward-line)))

(defun apropos-previous-symbol ()
  "Move cursor back to the last symbol in an `apropos-mode' buffer."
  (interactive nil apropos-mode)
  (forward-line -1)
  (while (and (not (eq (face-at-point) 'apropos-symbol))
              (> (point) (point-min)))
    (forward-line -1)))

(defun apropos-describe-plist (symbol)
  "Display a pretty listing of SYMBOL's plist."
  (let ((help-buffer-under-preparation t))
    (help-setup-xref (list 'apropos-describe-plist symbol)
		     (called-interactively-p 'interactive))
    (with-help-window (help-buffer)
      (set-buffer standard-output)
      (princ "Symbol ")
      (prin1 symbol)
      (princ (substitute-command-keys "'s plist is\n ("))
      (put-text-property (+ (point-min) 7) (- (point) 14)
		         'face 'apropos-symbol)
      (insert (apropos-format-plist symbol "\n  "))
      (princ ")"))))


(provide 'apropos)

;;; apropos.el ends here
