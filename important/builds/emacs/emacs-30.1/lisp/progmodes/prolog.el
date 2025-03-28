;;; prolog.el --- major mode for Prolog (and Mercury) -*- lexical-binding:t -*-

;; Copyright (C) 1986-1987, 1997-1999, 2002-2003, 2011-2025 Free
;; Software Foundation, Inc.

;; Authors: Emil Åström <emil_astrom(at)hotmail(dot)com>
;;          Milan Zamazal <pdm(at)freesoft(dot)cz>
;;          Stefan Bruda <stefan(at)bruda(dot)ca>
;;          * See below for more details
;; Maintainer: Stefan Bruda <stefan(at)bruda(dot)ca>
;; Keywords: prolog major mode sicstus swi mercury

(defvar prolog-mode-version "1.22"
  "Prolog mode version number.")

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

;; Original author: Masanobu UMEDA <umerin(at)mse(dot)kyutech(dot)ac(dot)jp>
;; Parts of this file was taken from a modified version of the original
;; by Johan Andersson, Peter Olin, Mats Carlsson, Johan Bevemyr, Stefan
;; Andersson, and Per Danielsson (all SICS people), and Henrik Båkman
;; at Uppsala University, Sweden.
;;
;; Some ideas and also a few lines of code have been borrowed (not stolen ;-)
;; from Oz.el, the Emacs major mode for the Oz programming language,
;; Copyright (C) 1993 DFKI GmbH, Germany, with permission.
;; Authored by Ralf Scheidhauer and Michael Mehl
;;   ([scheidhr|mehl](at)dfki(dot)uni-sb(dot)de)
;;
;; More ideas and code have been taken from the SICStus debugger mode
;; (http://www.csd.uu.se/~perm/source_debug/index.shtml -- broken link
;; as of Mon May 5 08:23:48 EDT 2003) by Per Mildner.
;;
;; Additions for ECLiPSe and other helpful suggestions: Stephan Heuel
;; <heuel(at)ipb(dot)uni-bonn(dot)de>

;;; Commentary:
;;
;; This package provides a major mode for editing Prolog code, with
;; all the bells and whistles one would expect, including syntax
;; highlighting and auto indentation.  It can also send regions to an
;; inferior Prolog process.

;; Some settings you may wish to use:

;; (setq prolog-system 'swi)  ; optional, the system you are using;
;;                            ; see `prolog-system' below for possible values
;; (setq auto-mode-alist (append '(("\\.pl\\'" . prolog-mode)
;;                                 ("\\.m\\'" . mercury-mode))
;;                                auto-mode-alist))
;;
;; The last expression above makes sure that files ending with .pl
;; are assumed to be Prolog files and not Perl, which is the default
;; Emacs setting.  If this is not wanted, remove this line.  It is then
;; necessary to either
;;
;;  o  insert in your Prolog files the following comment as the first line:
;;
;;       % -*- Mode: Prolog -*-
;;
;;     and then the file will be open in Prolog mode no matter its
;;     extension, or
;;
;;  o  manually switch to prolog mode after opening a Prolog file, by typing
;;     M-x prolog-mode.
;;
;; If the command to start the prolog process ('sicstus', 'pl' or
;; 'swipl' for SWI prolog, etc.) is not available in the default path,
;; then it is necessary to set the value of the environment variable
;; EPROLOG to a shell command to invoke the prolog process.
;; You can also customize the variable
;; `prolog-program-name' (in the group `prolog-inferior') and provide
;; a full path for your Prolog system (swi, scitus, etc.).

;; Changelog:

;; Version 1.22:
;;  o  Allowed both 'swipl' and 'pl' as names for the SWI Prolog
;;     interpreter.
;;  o  Atoms that start a line are not blindly colored as
;;     predicates.  Instead we check that they are followed by ( or
;;     :- first.  Patch suggested by Guy Wiener.
;; Version 1.21:
;;  o  Cleaned up the code that defines faces.  The missing face
;;     warnings on some Emacsen should disappear.
;; Version 1.20:
;;  o  Improved the handling of clause start detection and multi-line
;;     comments: `prolog-clause-start' no longer finds non-predicate
;;     (e.g., capitalized strings) beginning of clauses.
;;     `prolog-tokenize' recognizes when the end point is within a
;;     multi-line comment.
;; Version 1.19:
;;  o  Minimal changes for Aquamacs inclusion and in general for
;;     better coping with finding the Prolog executable.  Patch
;;     provided by David Reitter
;; Version 1.18:
;;  o  Fixed syntax highlighting for clause heads that do not begin at
;;     the beginning of the line.
;;  o  Fixed compilation warnings under Emacs.
;;  o  Updated the email address of the current maintainer.
;; Version 1.17:
;;  o  Minor indentation fix (patch by Markus Triska)
;;  o  `prolog-underscore-wordchar-flag' defaults now to nil (more
;;     consistent to other Emacs modes)
;; Version 1.16:
;;  o  Eliminated a possible compilation warning.
;; Version 1.15:
;;  o  Introduced three new customizable variables: electric colon
;;     (`prolog-electric-colon-flag', default nil), electric dash
;;     (`prolog-electric-dash-flag', default nil), and a possibility
;;     to prevent the predicate template insertion from adding commas
;;     (`prolog-electric-dot-full-predicate-template', defaults to t
;;     since it seems quicker to me to just type those commas).  A
;;     trivial adaptation of a patch by Markus Triska.
;;  o  Improved the behavior of electric if-then-else to only skip
;;     forward if the parenthesis/semicolon is preceded by
;;     whitespace.  Once more a trivial adaptation of a patch by
;;     Markus Triska.
;; Version 1.14:
;;  o  Cleaned up align code.  `prolog-align-flag' is eliminated (since
;;     on a second thought it does not do anything useful).  Added key
;;     binding (C-c C-a) and menu entry for alignment.
;;  o  Condensed regular expressions for lower and upper case
;;     characters (GNU Emacs seems to go over the regexp length limit
;;     with the original form).  My code on the matter was improved
;;     considerably by Markus Triska.
;;  o  Fixed `prolog-insert-spaces-after-paren' (which used an
;;     uninitialized variable).
;;  o  Minor changes to clean up the code and avoid some implicit
;;     package requirements.
;; Version 1.13:
;;  o  Removed the use of `map-char-table' in `prolog-build-case-strings'
;;     which appears to cause problems in (at least) Emacs 23.0.0.1.
;;  o  Added if-then-else indentation + corresponding electric
;;     characters.  New customization: `prolog-electric-if-then-else-flag'
;;  o  Align support (requires `align').  New customization:
;;     `prolog-align-flag'.
;;  o  Temporary consult files have now the same name throughout the
;;     session.  This prevents issues with reconsulting a buffer
;;     (this event is no longer passed to Prolog as a request to
;;     consult a new file).
;;  o  Adaptive fill mode is now turned on.  Comment indentation is
;;     still worse than it could be though, I am working on it.
;;  o  Improved filling and auto-filling capabilities.  Now block
;;     comments should be [auto-]filled correctly most of the time;
;;     the following pattern in particular is worth noting as being
;;     filled correctly:
;;         <some code here> % some comment here that goes beyond the
;;                          % rightmost column, possibly combined with
;;                          % subsequent comment lines
;;  o  `prolog-char-quote-workaround' now defaults to nil.
;;  o  Note: Many of the above improvements have been suggested by
;;     Markus Triska, who also provided useful patches on the matter
;;     when he realized that I was slow in responding.  Many thanks.
;; Version 1.11 / 1.12
;;  o  GNU Emacs compatibility fix for paragraph filling (fixed
;;     incorrectly in 1.11, fix fixed in 1.12).
;; Version 1.10
;;  o  Added paragraph filling in comment blocks and also correct auto
;;     filling for comments.
;;  o  Fixed the possible "Regular expression too big" error in
;;     `prolog-electric-dot'.
;; Version 1.9
;;  o  Parenthesis expressions are now indented by default so that
;;     components go one underneath the other, just as for compound
;;     terms.  You can use the old style (the second and subsequent
;;     lines being indented to the right in a parenthesis expression)
;;     by setting the customizable variable `prolog-paren-indent-p'
;;     (group "Prolog Indentation") to t.
;;  o  (Somehow awkward) handling of the 0' character escape
;;     sequence.  I am looking into a better way of doing it but
;;     prospects look bleak.  If this breaks things for you please let
;;     me know and also set the `prolog-char-quote-workaround' (group
;;     "Prolog Other") to nil.
;; Version 1.8
;;  o  Key binding fix.
;; Version 1.7
;;  o  Fixed a number of issues with the syntax of single quotes,
;;     including Debian bug #324520.
;; Version 1.6
;;  o  Fixed mercury mode menu initialization (Debian bug #226121).
;;  o  Fixed (i.e., eliminated) Delete remapping (Debian bug #229636).
;;  o  Corrected indentation for clauses defining quoted atoms.
;; Version 1.5:
;;  o  Keywords fontifying should work in console mode so this is
;;     enabled everywhere.
;; Version 1.4:
;;  o  Now supports GNU Prolog--minor adaptation of a patch by Stefan
;;     Moeding.
;; Version 1.3:
;;  o  Info-follow-nearest-node now called correctly under Emacs too
;;     (thanks to Nicolas Pelletier).  Should be implemented more
;;     elegantly (i.e., without compilation warnings) in the future.
;; Version 1.2:
;;  o  Another prompt fix, still in SWI mode (people seem to have
;;     changed the prompt of SWI Prolog).
;; Version 1.1:
;;  o  Fixed dots in the end of line comments causing indentation
;;     problems.  The following code is now correctly indented (note
;;     the dot terminating the comment):
;;        a(X) :- b(X),
;;            c(X).                  % comment here.
;;        a(X).
;;     and so is this (and variants):
;;        a(X) :- b(X),
;;            c(X).                  /* comment here.  */
;;        a(X).
;; Version 1.0:
;;  o  Revamped the menu system.
;;  o  Yet another prompt recognition fix (SWI mode).
;;  o  This is more of a renumbering than a new edition.  I promoted
;;     the mode to version 1.0 to emphasize the fact that it is now
;;     mature and stable enough to be considered production (in my
;;     opinion anyway).
;; Version 0.1.41:
;;  o  GNU Emacs compatibility fixes.
;; Version 0.1.40:
;;  o  prolog-get-predspec is now suitable to be called as
;;     imenu-extract-index-name-function.  The predicate index works.
;;  o  Since imenu works now as advertised, prolog-imenu-flag is t
;;     by default.
;;  o  Eliminated prolog-create-predicate-index since the imenu
;;     utilities now work well.  Actually, this function is also
;;     buggy, and I see no reason to fix it since we do not need it
;;     anyway.
;;  o  Fixed prolog-pred-start, prolog-clause-start, prolog-clause-info.
;;  o  Fix for prolog-build-case-strings; now prolog-upper-case-string
;;     and prolog-lower-case-string are correctly initialized,
;;  o  Various font-lock changes; most importantly, block comments (/*
;;     ... */) are now correctly fontified in XEmacs even when they
;;     extend on multiple lines.
;; Version 0.1.36:
;;  o  The debug prompt of SWI Prolog is now correctly recognized.
;; Version 0.1.35:
;;  o  Minor font-lock bug fixes.


;;; Code:

(require 'comint)

(eval-when-compile
  ;; We need imenu everywhere because of the predicate index!
  (require 'imenu)
  ;)
  (require 'shell)
  )

(require 'align)

(defgroup prolog nil
  "Editing and running Prolog and Mercury files."
  :group 'languages)

(defgroup prolog-faces nil
  "Prolog mode specific faces."
  :group 'font-lock)

(defgroup prolog-indentation nil
  "Prolog mode indentation configuration."
  :group 'prolog)

(defgroup prolog-font-lock nil
  "Prolog mode font locking patterns."
  :group 'prolog)

(defgroup prolog-keyboard nil
  "Prolog mode keyboard flags."
  :group 'prolog)

(defgroup prolog-inferior nil
  "Inferior Prolog mode options."
  :group 'prolog)

(defgroup prolog-other nil
  "Other Prolog mode options."
  :group 'prolog)


;;-------------------------------------------------------------------
;; User configurable variables
;;-------------------------------------------------------------------

;; General configuration

(defcustom prolog-system nil
  "Prolog interpreter/compiler used.
The value of this variable is nil or a symbol.
If it is a symbol, it determines default values of other configuration
variables with respect to properties of the specified Prolog
interpreter/compiler.

Currently recognized symbol values are:
eclipse - Eclipse Prolog
mercury - Mercury
sicstus - SICStus Prolog
swi     - SWI Prolog
gnu     - GNU Prolog"
  :version "24.1"
  :group 'prolog
  :type '(choice (const :tag "SICStus" :value sicstus)
                 (const :tag "SWI Prolog" :value swi)
                 (const :tag "GNU Prolog" :value gnu)
                 (const :tag "ECLiPSe Prolog" :value eclipse)
                 ;; Mercury shouldn't be needed since we have a separate
                 ;; major mode for it.
                 (const :tag "Default" :value nil)))
(make-variable-buffer-local 'prolog-system)

;; NB: This alist can not be processed in prolog-mode-variables to
;; create a prolog-system-version-i variable since it is needed
;; prior to the call to prolog-mode-variables.
(defcustom prolog-system-version
  '((sicstus  (3 . 6))
    (swi      (0 . 0))
    (mercury  (0 . 0))
    (eclipse  (3 . 7))
    (gnu      (0 . 0)))
  ;; FIXME: This should be auto-detected instead of user-provided.
  "Alist of Prolog system versions.
The version numbers are of the format (Major . Minor)."
  :version "24.1"
  :type '(repeat (list (symbol :tag "System")
                       (cons :tag "Version numbers" (integer :tag "Major")
                             (integer :tag "Minor"))))
  :risky t
  :group 'prolog)

;; Indentation

(defcustom prolog-indent-width 4
  "The indentation width used by the editing buffer."
  :group 'prolog-indentation
  :type 'integer
  :safe 'integerp)

(defcustom prolog-left-indent-regexp "\\(;\\|\\*?->\\)"
  "Regexp for `prolog-electric-if-then-else-flag'."
  :version "24.1"
  :group 'prolog-indentation
  :type 'regexp
  :safe 'stringp)

(defcustom prolog-paren-indent-p nil
  "If non-nil, increase indentation for parenthesis expressions.
The second and subsequent line in a parenthesis expression other than
a compound term can either be indented `prolog-paren-indent' to the
right (if this variable is non-nil) or in the same way as for compound
terms (if this variable is nil, default)."
  :version "24.1"
  :group 'prolog-indentation
  :type 'boolean
  :safe 'booleanp)

(defcustom prolog-paren-indent 4
  "The indentation increase for parenthesis expressions.
Only used in ( If -> Then ; Else ) and ( Disj1 ; Disj2 ) style expressions."
  :version "24.1"
  :group 'prolog-indentation
  :type 'integer
  :safe 'integerp)

(defcustom prolog-parse-mode 'beg-of-clause
  "The parse mode used (decides from which point parsing is done).
Legal values:
`beg-of-line'   - starts parsing at the beginning of a line, unless the
                  previous line ends with a backslash.  Fast, but has
                  problems detecting multiline /* */ comments.
`beg-of-clause' - starts parsing at the beginning of the current clause.
                  Slow, but copes better with /* */ comments."
  :version "24.1"
  :group 'prolog-indentation
  :type '(choice (const :value beg-of-line)
                 (const :value beg-of-clause)))

;; Font locking

(defcustom prolog-keywords
  '((eclipse
     ("use_module" "begin_module" "module_interface" "dynamic"
      "external" "export" "dbgcomp" "nodbgcomp" "compile"))
    (mercury
     ("all" "else" "end_module" "equality" "external" "fail" "func" "if"
      "implementation" "import_module" "include_module" "inst" "instance"
      "interface" "mode" "module" "not" "pragma" "pred" "some" "then" "true"
      "type" "typeclass" "use_module" "where"))
    (sicstus
     ("block" "dynamic" "mode" "module" "multifile" "meta_predicate"
      "parallel" "public" "sequential" "volatile"))
    (swi
     ("discontiguous" "dynamic" "ensure_loaded" "export" "export_list" "import"
      "meta_predicate" "module" "module_transparent" "multifile" "require"
      "use_module" "volatile"))
    (gnu
     ("built_in" "char_conversion" "discontiguous" "dynamic" "ensure_linked"
      "ensure_loaded" "foreign" "include" "initialization" "multifile" "op"
      "public" "set_prolog_flag"))
    (t
     ;; FIXME: Shouldn't we just use the union of all the above here?
     ("dynamic" "module")))
  "Alist of Prolog keywords which is used for font locking of directives."
  :version "24.1"
  :group 'prolog-font-lock
  ;; Note that "(repeat string)" also allows "nil" (repeat-count 0).
  ;; This gets processed by prolog-find-value-by-system, which
  ;; allows both the car and the cdr to be a list to eval.
  ;; Though the latter must have the form '(eval ...)'.
  ;; Of course, none of this is documented...
  :type '(repeat (list (choice symbol sexp) (choice (repeat string) sexp)))
  :risky t)

(defcustom prolog-types
  '((mercury
     ("char" "float" "int" "io__state" "string" "univ"))
    (t nil))
  "Alist of Prolog types used by font locking."
  :version "24.1"
  :group 'prolog-font-lock
  :type '(repeat (list (choice symbol sexp) (choice (repeat string) sexp)))
  :risky t)

(defcustom prolog-mode-specificators
  '((mercury
     ("bound" "di" "free" "ground" "in" "mdi" "mui" "muo" "out" "ui" "uo"))
    (t nil))
  "Alist of Prolog mode specificators used by font locking."
  :version "24.1"
  :group 'prolog-font-lock
  :type '(repeat (list (choice symbol sexp) (choice (repeat string) sexp)))
  :risky t)

(defcustom prolog-determinism-specificators
  '((mercury
     ("cc_multi" "cc_nondet" "det" "erroneous" "failure" "multi" "nondet"
      "semidet"))
    (t nil))
  "Alist of Prolog determinism specificators used by font locking."
  :version "24.1"
  :group 'prolog-font-lock
  :type '(repeat (list (choice symbol sexp) (choice (repeat string) sexp)))
  :risky t)

(defcustom prolog-directives
  '((mercury
     ("^#[0-9]+"))
    (t nil))
  "Alist of Prolog source code directives used by font locking."
  :version "24.1"
  :group 'prolog-font-lock
  :type '(repeat (list (choice symbol sexp) (choice (repeat string) sexp)))
  :risky t)


;; Keyboard

(defcustom prolog-electric-dot-flag nil
  "Non-nil means make dot key electric.
Electric dot appends newline or inserts head of a new clause.
If dot is pressed at the end of a line where at least one white space
precedes the point, it inserts a recursive call to the current predicate.
If dot is pressed at the beginning of an empty line, it inserts the head
of a new clause for the current predicate.  It does not apply in strings
and comments.
It does not apply in strings and comments."
  :version "24.1"
  :group 'prolog-keyboard
  :type 'boolean)

(defcustom prolog-electric-dot-full-predicate-template nil
  "If nil, electric dot inserts only the current predicate's name and `('
for recursive calls or new clause heads.  Non-nil means to also
insert enough commas to cover the predicate's arity and `)',
and dot and newline for recursive calls."
  :version "24.1"
  :group 'prolog-keyboard
  :type 'boolean)

(defcustom prolog-electric-underscore-flag nil
  "Non-nil means make underscore key electric.
Electric underscore replaces the current variable with underscore.
If underscore is pressed not on a variable then it behaves as usual."
  :version "24.1"
  :group 'prolog-keyboard
  :type 'boolean)

(defcustom prolog-electric-if-then-else-flag nil
  "Non-nil makes `(', `>' and `;' electric
to automatically indent if-then-else constructs."
  :version "24.1"
  :group 'prolog-keyboard
  :type 'boolean)

(defcustom prolog-electric-colon-flag nil
  "Non-nil means make `:' electric (inserts `:-' on a new line).
If non-nil, pressing `:' at the end of a line that starts in
the first column (i.e., clause heads) inserts ` :-' and newline."
  :version "24.1"
  :group 'prolog-keyboard
  :type 'boolean)

(defcustom prolog-electric-dash-flag nil
  "Non-nil means make `-' electric (inserts a `-->' on a new line).
If non-nil, pressing `-' at the end of a line that starts in
the first column (i.e., DCG heads) inserts ` -->' and newline."
  :version "24.1"
  :group 'prolog-keyboard
  :type 'boolean)

(defcustom prolog-old-sicstus-keys-flag nil
  "Non-nil means old SICStus Prolog mode keybindings are used."
  :version "24.1"
  :group 'prolog-keyboard
  :type 'boolean)

;; Inferior mode

(defcustom prolog-program-name
  `(((getenv "EPROLOG") (eval (getenv "EPROLOG")))
    (eclipse "eclipse")
    (mercury nil)
    (sicstus "sicstus")
    (swi ,(if (not (executable-find "swipl")) "pl" "swipl"))
    (gnu "gprolog")
    (t ,(let ((names '("prolog" "gprolog" "swipl" "pl")))
 	  (while (and names
 		      (not (executable-find (car names))))
 	    (setq names (cdr names)))
 	  (or (car names) "prolog"))))
  "Alist of program names for invoking an inferior Prolog with `run-prolog'."
  :group 'prolog-inferior
  :type '(alist :key-type (choice symbol sexp)
                :value-type (group (choice string (const nil) sexp)))
  :risky t)
(defun prolog-program-name ()
  (prolog-find-value-by-system prolog-program-name))

(defcustom prolog-program-switches
  '((sicstus ("-i"))
    (t nil))
  "Alist of switches given to inferior Prolog run with `run-prolog'."
  :version "24.1"
  :group 'prolog-inferior
  :type '(repeat (list (choice symbol sexp) (choice (repeat string) sexp)))
  :risky t)
(defun prolog-program-switches ()
  (prolog-find-value-by-system prolog-program-switches))

(defcustom prolog-consult-string
  '((eclipse "[%f].")
    (mercury nil)
    (sicstus (eval (if (prolog-atleast-version '(3 . 7))
                       "prolog:zap_file(%m,%b,consult,%l)."
                     "prolog:zap_file(%m,%b,consult).")))
    (swi "[%f].")
    (gnu     "[%f].")
    (t "reconsult(%f)."))
  "Alist of strings defining predicate for reconsulting.

Some parts of the string are replaced:
`%f' by the name of the consulted file (can be a temporary file)
`%b' by the file name of the buffer to consult
`%m' by the module name and name of the consulted file separated by colon
`%l' by the line offset into the file.  This is 0 unless consulting a
     region of a buffer, in which case it is the number of lines before
     the region."
  :group 'prolog-inferior
  :type '(alist :key-type (choice symbol sexp)
                :value-type (group (choice string (const nil) sexp)))
  :risky t)

(defun prolog-consult-string ()
  (prolog-find-value-by-system prolog-consult-string))

(defcustom prolog-compile-string
  '((eclipse "[%f].")
    (mercury "mmake ")
    (sicstus (eval (if (prolog-atleast-version '(3 . 7))
                       "prolog:zap_file(%m,%b,compile,%l)."
                     "prolog:zap_file(%m,%b,compile).")))
    (swi "[%f].")
    (t "compile(%f)."))
  "Alist of strings and lists defining predicate for recompilation.

Some parts of the string are replaced:
`%f' by the name of the compiled file (can be a temporary file)
`%b' by the file name of the buffer to compile
`%m' by the module name and name of the compiled file separated by colon
`%l' by the line offset into the file.  This is 0 unless compiling a
     region of a buffer, in which case it is the number of lines before
     the region.

If `prolog-program-name' is non-nil, it is a string sent to a Prolog process.
If `prolog-program-name' is nil, it is an argument to the `compile' function."
  :group 'prolog-inferior
  :type '(alist :key-type (choice symbol sexp)
                :value-type (group (choice string (const nil) sexp)))
  :risky t)

(defun prolog-compile-string ()
  (prolog-find-value-by-system prolog-compile-string))

(defcustom prolog-eof-string "end_of_file.\n"
  "String or alist of strings that represent end of file for prolog.
If nil, send actual operating system end of file."
  :group 'prolog-inferior
  :type '(choice string
                 (const nil)
                 (alist :key-type (choice symbol sexp)
                        :value-type (group (choice string (const nil) sexp))))
  :risky t)

(defcustom prolog-prompt-regexp
  '((eclipse "^[a-zA-Z0-9()]* *\\?- \\|^\\[[a-zA-Z]* [0-9]*\\]:")
    (sicstus "| [ ?][- ] *")
    (swi "^\\(\\[[a-zA-Z]*\\] \\)?[1-9]?[0-9]*[ ]?\\?- \\|^| +")
    (gnu "^| \\?-")
    (t "^|? *\\?-"))
  "Alist of prompts of the prolog system command line."
  :version "24.1"
  :group 'prolog-inferior
  :type '(alist :key-type (choice symbol sexp)
                :value-type (group (choice string (const nil) sexp)))
  :risky t)

(defun prolog-prompt-regexp ()
  (prolog-find-value-by-system prolog-prompt-regexp))

;; (defcustom prolog-continued-prompt-regexp
;;   '((sicstus "^\\(| +\\|     +\\)")
;;     (t "^|: +"))
;;   "Alist of regexps matching the prompt when consulting `user'."
;;   :group 'prolog-inferior
;;   :type '(alist :key-type (choice symbol sexp)
;;                :value-type (group (choice string (const nil) sexp)))
;;   :risky t)

(defcustom prolog-debug-on-string "debug.\n"
  "Predicate for enabling debug mode."
  :version "24.1"
  :group 'prolog-inferior
  :type 'string)

(defcustom prolog-debug-off-string "nodebug.\n"
  "Predicate for disabling debug mode."
  :version "24.1"
  :group 'prolog-inferior
  :type 'string)

(defcustom prolog-trace-on-string "trace.\n"
  "Predicate for enabling tracing."
  :version "24.1"
  :group 'prolog-inferior
  :type 'string)

(defcustom prolog-trace-off-string "notrace.\n"
  "Predicate for disabling tracing."
  :version "24.1"
  :group 'prolog-inferior
  :type 'string)

(defcustom prolog-zip-on-string "zip.\n"
  "Predicate for enabling zip mode for SICStus."
  :version "24.1"
  :group 'prolog-inferior
  :type 'string)

(defcustom prolog-zip-off-string "nozip.\n"
  "Predicate for disabling zip mode for SICStus."
  :version "24.1"
  :group 'prolog-inferior
  :type 'string)

(defcustom prolog-use-standard-consult-compile-method-flag t
  "Non-nil means use the standard compilation method.
Otherwise the new compilation method will be used.  This
utilizes a special compilation buffer with the associated
features such as parsing of error messages and automatically
jumping to the source code responsible for the error.

Warning: the new method is so far only experimental and
does contain bugs.  The recommended setting for the novice user
is non-nil for this variable."
  :version "24.1"
  :group 'prolog-inferior
  :type 'boolean)


;; Miscellaneous

(defcustom prolog-imenu-flag t
  "Non-nil means add a clause index menu for all prolog files."
  :version "24.1"
  :group 'prolog-other
  :type 'boolean)

(defcustom prolog-imenu-max-lines 3000
  "The maximum number of lines of the file for imenu to be enabled.
Relevant only when `prolog-imenu-flag' is non-nil."
  :version "24.1"
  :group 'prolog-other
  :type 'integer)

(defcustom prolog-info-predicate-index
  "(sicstus)Predicate Index"
  "The info node for the SICStus predicate index."
  :version "24.1"
  :group 'prolog-other
  :type 'string)

(defcustom prolog-underscore-wordchar-flag nil
  "Non-nil means underscore (_) is a word-constituent character."
  :version "24.1"
  :group 'prolog-other
  :type 'boolean)
(make-obsolete-variable 'prolog-underscore-wordchar-flag
                        'superword-mode "24.4")

(defcustom prolog-use-sicstus-sd nil
  "If non-nil, use the source level debugger of SICStus 3#7 and later."
  :version "24.1"
  :group 'prolog-other
  :type 'boolean)


;;-------------------------------------------------------------------
;; Internal variables
;;-------------------------------------------------------------------

;;(defvar prolog-temp-filename "")   ; Later set by `prolog-temporary-file'

(defvar prolog-mode-syntax-table
  ;; The syntax accepted varies depending on the implementation used.
  ;; Here are some of the differences:
  ;; - SWI-Prolog accepts nested /*..*/ comments.
  ;; - Edinburgh-style Prologs take <radix>'<number> for non-decimal number,
  ;;   whereas ISO-style Prologs use 0[obx]<number> instead.
  ;; - In atoms \x<hex> sometimes needs a terminating \ (ISO-style)
  ;;   and sometimes not.
  (let ((table (make-syntax-table)))
    (modify-syntax-entry ?_ (if prolog-underscore-wordchar-flag "w" "_") table)
    (modify-syntax-entry ?+ "." table)
    (modify-syntax-entry ?- "." table)
    (modify-syntax-entry ?= "." table)
    (modify-syntax-entry ?< "." table)
    (modify-syntax-entry ?> "." table)
    (modify-syntax-entry ?| "." table)
    (modify-syntax-entry ?\' "\"" table)
    (modify-syntax-entry ?% "<" table)
    (modify-syntax-entry ?\n ">" table)
    (modify-syntax-entry ?* ". 23b" table)
    (modify-syntax-entry ?/ ". 14" table)
    table))

(defconst prolog-atom-char-regexp
  "[[:alnum:]_$]"
  "Regexp specifying characters which constitute atoms without quoting.")
(defconst prolog-atom-regexp
  (format "[[:lower:]$]%s*" prolog-atom-char-regexp))

(defconst prolog-left-paren "[[({]"     ;FIXME: Why not \\s(?
  "The characters used as left parentheses for the indentation code.")
(defconst prolog-right-paren "[])}]"    ;FIXME: Why not \\s)?
  "The characters used as right parentheses for the indentation code.")

(defconst prolog-quoted-atom-regexp
  "\\(^\\|[^0-9]\\)\\('\\([^\n']\\|\\\\'\\)*'\\)"
  "Regexp matching a quoted atom.")
(defconst prolog-string-regexp
  "\\(\"\\([^\n\"]\\|\\\\\"\\)*\"\\)"
  "Regexp matching a string.")
(defconst prolog-head-delimiter "\\(:-\\|\\+:\\|-:\\|\\+\\?\\|-\\?\\|-->\\)"
  "A regexp for matching on the end delimiter of a head (e.g. \":-\").")

(defvar prolog-compilation-buffer "*prolog-compilation*"
  "Name of the output buffer for Prolog compilation/consulting.")

(defvar prolog-temporary-file-name nil)
(defvar prolog-keywords-i nil)
(defvar prolog-types-i nil)
(defvar prolog-mode-specificators-i nil)
(defvar prolog-determinism-specificators-i nil)
(defvar prolog-directives-i nil)
(defvar prolog-eof-string-i nil)
;; (defvar prolog-continued-prompt-regexp-i nil)
(defvar prolog-help-function-i nil)

(defvar prolog-align-rules
  (eval-when-compile
    (mapcar
     (lambda (x)
       (let ((name (car x))
             (sym  (cdr x)))
         `(,(intern (format "prolog-%s" name))
           (regexp . ,(format "\\(\\s-*\\)%s\\(\\s-*\\)" sym))
           (tab-stop . nil)
           (modes . '(prolog-mode))
           (group . (1 2)))))
     '(("dcg" . "-->") ("rule" . ":-") ("simplification" . "<=>")
       ("propagation" . "==>")))))

;; SMIE support

(require 'smie)

(defconst prolog-operator-chars "-\\\\#&*+./:<=>?@\\^`~")

(defun prolog-smie-forward-token ()
  ;; FIXME: Add support for 0'<char>, if needed after adding it to
  ;; syntax-propertize-functions.
  (forward-comment (point-max))
  (buffer-substring-no-properties
   (point)
   (progn (cond
           ((looking-at "[!;]") (forward-char 1))
           ((not (zerop (skip-chars-forward prolog-operator-chars))))
           ((not (zerop (skip-syntax-forward "w_'"))))
           ;; In case of non-ASCII punctuation.
           (t (skip-syntax-forward ".")))
          (point))))

(defun prolog-smie-backward-token ()
  ;; FIXME: Add support for 0'<char>, if needed after adding it to
  ;; syntax-propertize-functions.
  (forward-comment (- (point-max)))
  (buffer-substring-no-properties
   (point)
   (progn (cond
           ((memq (char-before) '(?! ?\; ?\,)) (forward-char -1))
           ((not (zerop (skip-chars-backward prolog-operator-chars))))
           ((not (zerop (skip-syntax-backward "w_'"))))
           ;; In case of non-ASCII punctuation.
           (t (skip-syntax-backward ".")))
          (point))))

(defconst prolog-smie-grammar
  ;; Rather than construct the operator levels table from the BNF,
  ;; we directly provide the operator precedences from GNU Prolog's
  ;; manual (7.14.10 op/3).  The only problem is that GNU Prolog's
  ;; manual uses precedence levels in the opposite sense (higher
  ;; numbers bind less tightly) than SMIE, so we use negative numbers.
  '(("." -10000 -10000)
    ("?-" nil -1200)
    (":-" -1200 -1200)
    ("-->" -1200 -1200)
    ("discontiguous" nil -1150)
    ("dynamic" nil -1150)
    ("meta_predicate" nil -1150)
    ("module_transparent" nil -1150)
    ("multifile" nil -1150)
    ("public" nil -1150)
    ("|" -1105 -1105)
    (";" -1100 -1100)
    ("*->" -1050 -1050)
    ("->" -1050 -1050)
    ("," -1000 -1000)
    ("\\+" nil -900)
    ("=" -700 -700)
    ("\\=" -700 -700)
    ("=.." -700 -700)
    ("==" -700 -700)
    ("\\==" -700 -700)
    ("@<" -700 -700)
    ("@=<" -700 -700)
    ("@>" -700 -700)
    ("@>=" -700 -700)
    ("is" -700 -700)
    ("=:=" -700 -700)
    ("=\\=" -700 -700)
    ("<" -700 -700)
    ("=<" -700 -700)
    (">" -700 -700)
    (">=" -700 -700)
    (":" -600 -600)
    ("+" -500 -500)
    ("-" -500 -500)
    ("/\\" -500 -500)
    ("\\/" -500 -500)
    ("*" -400 -400)
    ("/" -400 -400)
    ("//" -400 -400)
    ("rem" -400 -400)
    ("mod" -400 -400)
    ("<<" -400 -400)
    (">>" -400 -400)
    ("**" -200 -200)
    ("^" -200 -200)
    ;; Prefix
    ;; ("+" 200 200)
    ;; ("-" 200 200)
    ;; ("\\" 200 200)
    (:smie-closer-alist (t . "."))
    )
  "Precedence levels of infix operators.")

(defun prolog-smie-rules (kind token)
  (pcase (cons kind token)
    ('(:elem . basic) prolog-indent-width)
    ;; The list of arguments can never be on a separate line!
    (`(:list-intro . ,_) t)
    ;; When we don't know how to indent an empty line, assume the most
    ;; likely token will be ";".
    ('(:elem . empty-line-token) ";")
    ('(:after . ".") '(column . 0)) ;; To work around smie-closer-alist.
    ;; Allow indentation of if-then-else as:
    ;;    (   test
    ;;    ->  thenrule
    ;;    ;   elserule
    ;;    )
    (`(:before . ,(or "->" ";"))
     (and (smie-rule-bolp) (smie-rule-parent-p "(") (smie-rule-parent 0)))
    (`(:after . ,(or "->" "*->"))
     ;; We distinguish
     ;;
     ;;     (a ->
     ;;          b;
     ;;      c)
     ;; and
     ;;     (    a ->
     ;;          b
     ;;     ;    c)
     ;;
     ;; based on the space between the open paren and the "a".
     (unless (and (smie-rule-parent-p "(" ";")
                  (save-excursion
                    (smie-indent-forward-token)
                    (smie-backward-sexp 'halfsexp)
                    (if (smie-rule-parent-p "(")
                        (not (eq (char-before) ?\())
                      (smie-indent-backward-token)
                      (smie-rule-bolp))))
       prolog-indent-width))
    ('(:after . ";")
     ;; Align with same-line comment as in:
     ;;   ;   %% Toto
     ;;       foo
     (and (smie-rule-bolp)
          (looking-at ";[ \t]*\\(%\\)")
          (let ((offset (- (save-excursion (goto-char (match-beginning 1))
                                           (current-column))
                           (current-column))))
            ;; Only do it for small offsets, since the comment may actually be
            ;; an "end-of-line" comment at comment-column!
            (if (<= offset prolog-indent-width) offset))))
    ('(:after . ",")
     ;; Special indent for:
     ;;    foopredicate(x) :- !,
     ;;        toto.
     (and (eq (char-before) ?!)
          (save-excursion
            (smie-indent-backward-token) ;Skip !
            (equal ":-" (car (smie-indent-backward-token))))
          (smie-rule-parent prolog-indent-width)))
    ('(:after . ":-")
     (if (bolp)
         (save-excursion
           (smie-indent-forward-token)
           (skip-chars-forward " \t")
           (if (eolp)
               prolog-indent-width
             (min prolog-indent-width (current-column))))
       prolog-indent-width))
    ('(:after . "-->") prolog-indent-width)))


;;-------------------------------------------------------------------
;; Prolog mode
;;-------------------------------------------------------------------

;; Example: (prolog-atleast-version '(3 . 6))
(defun prolog-atleast-version (version)
  "Return t if the version of the current prolog system is VERSION or later.
VERSION is of the format (Major . Minor)"
  ;; Version.major < major or
  ;; Version.major = major and Version.minor <= minor
  (let* ((thisversion (prolog-find-value-by-system prolog-system-version))
         (thismajor (car thisversion))
         (thisminor (cdr thisversion)))
    (or (< (car version) thismajor)
        (and (= (car version) thismajor)
             (<= (cdr version) thisminor)))
    ))

(define-abbrev-table 'prolog-mode-abbrev-table ())

;; Because this can `eval' its arguments, any variable that gets
;; processed by it should be marked as :risky.
(defun prolog-find-value-by-system (alist)
  "Get value from ALIST according to `prolog-system'."
  (let ((system (or prolog-system
                    (let ((infbuf (prolog-inferior-buffer 'dont-run)))
                      (when infbuf
                        (buffer-local-value 'prolog-system infbuf))))))
    (if (listp alist)
        (let (result
              id)
          (while alist
            (setq id (car (car alist)))
            (if (or (eq id system)
                    (eq id t)
                    (and (listp id)
                         (eval id)))
                (progn
                  (setq result (car (cdr (car alist))))
                  (if (and (listp result)
                           (eq (car result) 'eval))
                      (setq result (eval (car (cdr result)))))
                  (setq alist nil))
              (setq alist (cdr alist))))
          result)
      alist)))

(defconst prolog-syntax-propertize-function
  (syntax-propertize-rules
   ;; GNU Prolog only accepts 0'\' rather than 0'', but the only
   ;; possible meaning of 0'' is rather clear.
   ("\\<0\\(''?\\)"
    (1 (unless (save-excursion (nth 8 (syntax-ppss (match-beginning 0))))
         (string-to-syntax "_"))))
   ;; We could check that we're not inside an atom, but I don't think
   ;; that 'foo 8'z could be a valid syntax anyway, so why bother?
   ("\\<[1-9][0-9]*\\('\\)[0-9a-zA-Z]" (1 "_"))
   ;; Supposedly, ISO-Prolog wants \NNN\ for octal and \xNNN\ for hexadecimal
   ;; escape sequences in atoms, so be careful not to let the terminating \
   ;; escape a subsequent quote.
   ("\\\\[x0-7][[:xdigit:]]*\\(\\\\\\)" (1 "_"))))

(defun prolog-mode-variables ()
  "Set some common variables to Prolog code specific values."
  (setq-local local-abbrev-table prolog-mode-abbrev-table)
  (setq-local paragraph-start (concat "[ \t]*$\\|" page-delimiter)) ;'%%..'
  (setq-local paragraph-separate paragraph-start)
  (setq-local paragraph-ignore-fill-prefix t)
  (setq-local normal-auto-fill-function 'prolog-do-auto-fill)
  (setq-local comment-start "%")
  (setq-local comment-end "")
  (setq-local comment-add 1)
  (setq-local comment-start-skip "\\(?:/\\*+ *\\|%+ *\\)")
  (setq-local parens-require-spaces nil)
  ;; Initialize Prolog system specific variables
  (dolist (var '(prolog-keywords prolog-types prolog-mode-specificators
                 prolog-determinism-specificators prolog-directives
                 prolog-eof-string
                 ;; prolog-continued-prompt-regexp
                 prolog-help-function))
    (set (intern (concat (symbol-name var) "-i"))
         (prolog-find-value-by-system (symbol-value var))))
  (when (null (prolog-program-name))
    (setq-local compile-command (prolog-compile-string)))
  (setq-local font-lock-defaults
              '(prolog-font-lock-keywords nil nil ((?_ . "w"))))
  (setq-local syntax-propertize-function prolog-syntax-propertize-function)

  (smie-setup prolog-smie-grammar #'prolog-smie-rules
              :forward-token #'prolog-smie-forward-token
              :backward-token #'prolog-smie-backward-token))

(defun prolog-mode-keybindings-common (map)
  "Define keybindings common to both Prolog modes in MAP."
  (define-key map "\C-c?" 'prolog-help-on-predicate)
  (define-key map "\C-c/" 'prolog-help-apropos)
  (define-key map "\C-c\C-d" 'prolog-debug-on)
  (define-key map "\C-c\C-t" 'prolog-trace-on)
  (define-key map "\C-c\C-z" 'prolog-zip-on)
  (define-key map "\C-c\r" 'run-prolog))

(defun prolog-mode-keybindings-edit (map)
  "Define keybindings for Prolog mode in MAP."
  (define-key map "\M-a" 'prolog-beginning-of-clause)
  (define-key map "\M-e" 'prolog-end-of-clause)
  (define-key map "\M-q" 'prolog-fill-paragraph)
  (define-key map "\C-c\C-a" 'align)
  (define-key map "\C-\M-a" 'prolog-beginning-of-predicate)
  (define-key map "\C-\M-e" 'prolog-end-of-predicate)
  (define-key map "\M-\C-c" 'prolog-mark-clause)
  (define-key map "\M-\C-h" 'prolog-mark-predicate)
  (define-key map "\C-c\C-n" 'prolog-insert-predicate-template)
  (define-key map "\C-c\C-s" 'prolog-insert-predspec)
  (define-key map "\M-\r" 'prolog-insert-next-clause)
  (define-key map "\C-c\C-va" 'prolog-variables-to-anonymous)
  (define-key map "\C-c\C-v\C-s" 'prolog-view-predspec)

  ;; If we're running SICStus, then map C-c C-c e/d to enabling
  ;; and disabling of the source-level debugging facilities.
  ;(if (and (eq prolog-system 'sicstus)
  ;         (prolog-atleast-version '(3 . 7)))
  ;    (progn
  ;      (define-key map "\C-c\C-ce" 'prolog-enable-sicstus-sd)
  ;      (define-key map "\C-c\C-cd" 'prolog-disable-sicstus-sd)
  ;      ))

  (if prolog-old-sicstus-keys-flag
      (progn
        (define-key map "\C-c\C-c" 'prolog-consult-predicate)
        (define-key map "\C-cc" 'prolog-consult-region)
        (define-key map "\C-cC" 'prolog-consult-buffer)
        (define-key map "\C-c\C-k" 'prolog-compile-predicate)
        (define-key map "\C-ck" 'prolog-compile-region)
        (define-key map "\C-cK" 'prolog-compile-buffer))
    (define-key map "\C-c\C-p" 'prolog-consult-predicate)
    (define-key map "\C-c\C-r" 'prolog-consult-region)
    (define-key map "\C-c\C-b" 'prolog-consult-buffer)
    (define-key map "\C-c\C-f" 'prolog-consult-file)
    (define-key map "\C-c\C-cp" 'prolog-compile-predicate)
    (define-key map "\C-c\C-cr" 'prolog-compile-region)
    (define-key map "\C-c\C-cb" 'prolog-compile-buffer)
    (define-key map "\C-c\C-cf" 'prolog-compile-file))

  ;; Inherited from the old prolog.el.
  (define-key map "\e\C-x" 'prolog-consult-region)
  (define-key map "\C-c\C-l" 'prolog-consult-file)
  (define-key map "\C-c\C-z" 'run-prolog))

(defun prolog-mode-keybindings-inferior (_map)
  "Define keybindings for inferior Prolog mode in MAP."
  ;; No inferior mode specific keybindings now.
  )

(defvar prolog-mode-map
  (let ((map (make-sparse-keymap)))
    (prolog-mode-keybindings-common map)
    (prolog-mode-keybindings-edit map)
    map))


(defvar prolog-mode-hook nil
  "List of functions to call after the prolog mode has initialized.")

;;;###autoload
(define-derived-mode prolog-mode prog-mode "Prolog"
  "Major mode for editing Prolog code.

Blank lines and `%%...' separate paragraphs.  `%'s starts a comment
line and comments can also be enclosed in /* ... */.

If an optional argument SYSTEM is non-nil, set up mode for the given system.

To find out what version of Prolog mode you are running, enter
\\[prolog-mode-version].

Commands:
\\{prolog-mode-map}"
  (setq mode-name (concat "Prolog"
                          (cond
                           ((eq prolog-system 'eclipse) "[ECLiPSe]")
                           ((eq prolog-system 'sicstus) "[SICStus]")
                           ((eq prolog-system 'swi) "[SWI]")
                           ((eq prolog-system 'gnu) "[GNU]")
                           (t ""))))
  (prolog-mode-variables)
  (dolist (ar prolog-align-rules) (add-to-list 'align-rules-list ar))
  (add-hook 'post-self-insert-hook #'prolog-post-self-insert nil t)
  ;; `imenu' entry moved to the appropriate hook for consistency.
  (when prolog-electric-dot-flag
    (setq-local electric-indent-chars
                (cons ?\. electric-indent-chars)))

  ;; Load SICStus debugger if suitable
  (if (and (eq prolog-system 'sicstus)
           (prolog-atleast-version '(3 . 7))
           prolog-use-sicstus-sd)
      (prolog-enable-sicstus-sd))

  (prolog-menu))

(defvar mercury-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map prolog-mode-map)
    map))

;;;###autoload
(define-derived-mode mercury-mode prolog-mode "Prolog[Mercury]"
  "Major mode for editing Mercury programs.
Actually this is just customized `prolog-mode'."
  (setq-local prolog-system 'mercury)
  ;; Run once more to set up based on `prolog-system'
  (prolog-mode-variables))


;;-------------------------------------------------------------------
;; Inferior prolog mode
;;-------------------------------------------------------------------

(defvar prolog-inferior-mode-map
  (let ((map (make-sparse-keymap)))
    (prolog-mode-keybindings-common map)
    (prolog-mode-keybindings-inferior map)
    (define-key map [remap self-insert-command]
      'prolog-inferior-self-insert-command)
    map))

(defvar prolog-inferior-mode-hook nil
  "List of functions to call after the inferior prolog mode has initialized.")

(defvar prolog-inferior-error-regexp-alist
  '(;; GNU Prolog used to not follow the GNU standard format.
    ;; ("^\\(.*?\\):\\([0-9]+\\) error: .*(char:\\([0-9]+\\)" 1 2 3)
    ;; SWI-Prolog.
    ("^\\(?:\\?- *\\)?\\(\\(?:ERROR\\|\\(W\\)arning\\): *\\(.*?\\):\\([1-9][0-9]*\\):\\(?:\\([0-9]*\\):\\)?\\)\\(?:$\\| \\)"
     3 4 5 (2 . nil) 1)
    ;; GNU-Prolog now uses the GNU standard format.
    gnu))

(defun prolog-inferior-self-insert-command ()
  "Insert the char in the buffer or pass it directly to the process."
  (interactive)
  (let* ((proc (get-buffer-process (current-buffer)))
         (pmark (and proc (marker-position (process-mark proc)))))
    ;; FIXME: the same treatment would be needed for SWI-Prolog, but I can't
    ;; seem to find any way for Emacs to figure out when to use it because
    ;; SWI doesn't include a " ? " or some such recognizable marker.
    (if (and (eq prolog-system 'gnu)
             pmark
             (null current-prefix-arg)
             (eobp)
             (eq (point) pmark)
             (save-excursion
               (goto-char (- pmark 3))
               ;; FIXME: check this comes from the process's output, maybe?
               (looking-at " \\? ")))
        ;; This is GNU prolog waiting to know whether you want more answers
        ;; or not (or abort, etc...).  The answer is a single char, not
        ;; a line, so pass this char directly rather than wait for RET to
        ;; send a whole line.
        (comint-send-string proc (string last-command-event))
      (call-interactively 'self-insert-command))))

(declare-function compilation-shell-minor-mode "compile" (&optional arg))
(defvar compilation-error-regexp-alist)

(define-derived-mode prolog-inferior-mode comint-mode "Inferior Prolog"
  "Major mode for interacting with an inferior Prolog process.

The following commands are available:
\\{prolog-inferior-mode-map}

Entry to this mode calls the value of `prolog-mode-hook' with no arguments,
if that value is non-nil.  Likewise with the value of `comint-mode-hook'.
`prolog-mode-hook' is called after `comint-mode-hook'.

You can send text to the inferior Prolog from other buffers
using the commands `send-region', `send-string' and \\[prolog-consult-region].

Commands:
Tab indents for Prolog; with argument, shifts rest
 of expression rigidly with the current line.
Paragraphs are separated only by blank lines and `%%'.  `%'s start comments.

Return at end of buffer sends line as input.
Return not at end copies rest of line to end and sends it.
\\[comint-delchar-or-maybe-eof] sends end-of-file as input.
\\[comint-kill-input] and \\[backward-kill-word] are kill commands,
imitating normal Unix input editing.
\\[comint-interrupt-subjob] interrupts the shell or its current subjob if any.
\\[comint-stop-subjob] stops, likewise.
\\[comint-quit-subjob] sends quit signal, likewise.

To find out what version of Prolog mode you are running, enter
\\[prolog-mode-version]."
  (require 'compile)
  (setq comint-input-filter 'prolog-input-filter)
  (setq mode-line-process '(": %s"))
  (prolog-mode-variables)
  (setq comint-prompt-regexp (prolog-prompt-regexp))
  (setq-local shell-dirstack-query "pwd.")
  (setq-local compilation-error-regexp-alist
              prolog-inferior-error-regexp-alist)
  (compilation-shell-minor-mode))

(defun prolog-input-filter (str)
  (cond ((string-match "\\`\\s *\\'" str) nil) ;whitespace
        ((not (derived-mode-p 'prolog-inferior-mode)) t)
        ((= (length str) 1) nil)        ;one character
        ((string-match "\\`[rf] *[0-9]*\\'" str) nil) ;r(edo) or f(ail)
        (t t)))

;; This statement was missing in Emacs 24.1, 24.2, 24.3.
(define-obsolete-function-alias 'switch-to-prolog 'run-prolog "24.1") ; "24.4" ; for grep
;;;###autoload
(defun run-prolog (arg)
  "Run an inferior Prolog process, input and output via buffer *prolog*.
With prefix argument ARG, restart the Prolog process if running before."
  (interactive "P")
  ;; FIXME: It should be possible to interactively specify the command to use
  ;; to run prolog.
  (if (and arg (get-process "prolog"))
      (progn
        (process-send-string "prolog" "halt.\n")
        (while (get-process "prolog") (sit-for 0.1))))
  (prolog-ensure-process)
  (let ((buff (buffer-name)))
    (if (not (string= buff "*prolog*"))
        (prolog-goto-prolog-process-buffer))
    ;; Load SICStus debugger if suitable
    (if (and (eq prolog-system 'sicstus)
             (prolog-atleast-version '(3 . 7))
             prolog-use-sicstus-sd)
        (prolog-enable-sicstus-sd))
    (prolog-mode-variables)
    ))

(defun prolog-inferior-guess-flavor (&optional _ignored)
  (setq-local prolog-system
              (when (or (numberp prolog-system) (markerp prolog-system))
                (save-excursion
                  (goto-char (1+ prolog-system))
                  (cond
                   ((looking-at "GNU Prolog") 'gnu)
                   ((looking-at "Welcome to SWI-Prolog\\|%.*\\<swi_") 'swi)
                   ((looking-at ".*\n") nil) ;There's at least one line.
                   (t prolog-system)))))
  (when (symbolp prolog-system)
    (remove-hook 'comint-output-filter-functions
                 'prolog-inferior-guess-flavor t)
    (when prolog-system
      (setq comint-prompt-regexp (prolog-prompt-regexp))
      (if (eq prolog-system 'gnu)
          (setq-local comint-process-echoes t)))))

(defun prolog-ensure-process (&optional wait)
  "If Prolog process is not running, run it.
If the optional argument WAIT is non-nil, wait for Prolog prompt specified by
the variable `prolog-prompt-regexp'."
  (let ((pname (prolog-program-name))
        (pswitches (prolog-program-switches)))
    (if (null pname)
        (error "This Prolog system has defined no interpreter"))
    (unless (comint-check-proc "*prolog*")
      (with-current-buffer (get-buffer-create "*prolog*")
        ;; The "INFERIOR=yes" hack is for SWI-Prolog 7.2.3 and earlier,
        ;; which assumes it is running under Emacs if either INFERIOR=yes or
        ;; if EMACS is set to a nonempty value.  The EMACS setting is
        ;; obsolescent, so set INFERIOR.  Newer versions of SWI-Prolog should
        ;; know about INSIDE_EMACS (which replaced EMACS) and should not need
        ;; this hack.
        (let ((process-environment
	       (if (getenv "INFERIOR")
		   process-environment
	         (cons "INFERIOR=yes" process-environment))))
	  (apply 'make-comint-in-buffer "prolog" (current-buffer)
	         pname nil pswitches))
        (prolog-inferior-mode)

        (unless prolog-system
          ;; Setup auto-detection.
          (setq-local
           prolog-system
           ;; Force re-detection.
           (let* ((proc (get-buffer-process (current-buffer)))
                  (pmark (and proc (marker-position (process-mark proc)))))
             (cond
              ((null pmark) (1- (point-min)))
              ;; The use of insert-before-markers in comint.el together with
              ;; the potential use of comint-truncate-buffer in the output
              ;; filter, means that it's difficult to reliably keep track of
              ;; the buffer position where the process's output started.
              ;; If possible we use a marker at "start - 1", so that
              ;; insert-before-marker at `start' won't shift it.  And if not,
              ;; we fall back on using a plain integer.
              ((> pmark (point-min)) (copy-marker (1- pmark)))
              (t (1- pmark)))))
          (add-hook 'comint-output-filter-functions
                    'prolog-inferior-guess-flavor nil t))
        (if wait
            (progn
              (goto-char (point-max))
              (while
                  (save-excursion
                    (not
                     (re-search-backward
                      (concat "\\(" (prolog-prompt-regexp) "\\)" "\\=")
                      nil t)))
                (sit-for 0.1))))))))

(defun prolog-inferior-buffer (&optional dont-run)
  (or (get-buffer "*prolog*")
      (unless dont-run
        (prolog-ensure-process)
        (get-buffer "*prolog*"))))

(defun prolog-process-insert-string (process string)
  "Insert STRING into inferior Prolog buffer running PROCESS."
  ;; Copied from elisp manual, greek to me
  (with-current-buffer (process-buffer process)
    ;; FIXME: Use window-point-insertion-type instead.
    (let ((moving (= (point) (process-mark process))))
      (save-excursion
        ;; Insert the text, moving the process-marker.
        (goto-char (process-mark process))
        (insert string)
        (set-marker (process-mark process) (point)))
      (if moving (goto-char (process-mark process))))))

;;------------------------------------------------------------
;; Old consulting and compiling functions
;;------------------------------------------------------------

(declare-function compilation-forget-errors "compile" ())
(declare-function compilation-fake-loc "compile"
                  (marker file &optional line col))

(defun prolog-old-process-region (compilep start end)
  "Process the region limited by START and END positions.
If COMPILEP is non-nil then use compilation, otherwise consulting."
   (prolog-ensure-process)
   ;(let ((tmpfile prolog-temp-filename)
   (let ((tmpfile (prolog-temporary-file))
         ;(process (get-process "prolog"))
         (first-line (1+ (count-lines
                          (point-min)
                          (save-excursion
                            (goto-char start)
                            (point))))))
     (write-region start end tmpfile)
     (setq start (copy-marker start))
     (with-current-buffer (prolog-inferior-buffer)
       (compilation-forget-errors)
       (compilation-fake-loc start tmpfile))
     (process-send-string
      "prolog" (prolog-build-prolog-command
                compilep tmpfile (prolog-bsts buffer-file-name)
                first-line))
     (prolog-goto-prolog-process-buffer)))

(defun prolog-old-process-predicate (compilep)
  "Process the predicate around point.
If COMPILEP is non-nil then use compilation, otherwise consulting."
  (prolog-old-process-region
   compilep (prolog-pred-start) (prolog-pred-end)))

(defun prolog-old-process-buffer (compilep)
  "Process the entire buffer.
If COMPILEP is non-nil then use compilation, otherwise consulting."
  (prolog-old-process-region compilep (point-min) (point-max)))

(defun prolog-old-process-file (compilep)
  "Process the file of the current buffer.
If COMPILEP is non-nil then use compilation, otherwise consulting."
  (save-some-buffers)
  (prolog-ensure-process)
  (with-current-buffer (prolog-inferior-buffer)
    (compilation-forget-errors))
    (process-send-string
     "prolog" (prolog-build-prolog-command
             compilep buffer-file-name
             (prolog-bsts buffer-file-name)))
  (prolog-goto-prolog-process-buffer))


;;------------------------------------------------------------
;; Consulting and compiling
;;------------------------------------------------------------

;; Interactive interface functions, used by both the standard
;; and the experimental consultation and compilation functions
(defun prolog-consult-file ()
  "Consult file of current buffer."
  (interactive)
  (if prolog-use-standard-consult-compile-method-flag
      (prolog-old-process-file nil)
    (prolog-consult-compile-file nil)))

(defun prolog-consult-buffer ()
  "Consult buffer."
  (interactive)
  (if prolog-use-standard-consult-compile-method-flag
      (prolog-old-process-buffer nil)
    (prolog-consult-compile-buffer nil)))

(defun prolog-consult-region (beg end)
  "Consult region between BEG and END."
  (interactive "r")
  (if prolog-use-standard-consult-compile-method-flag
      (prolog-old-process-region nil beg end)
    (prolog-consult-compile-region nil beg end)))

(defun prolog-consult-predicate ()
  "Consult the predicate around current point."
  (interactive)
  (if prolog-use-standard-consult-compile-method-flag
      (prolog-old-process-predicate nil)
    (prolog-consult-compile-predicate nil)))

(defun prolog-compile-file ()
  "Compile file of current buffer."
  (interactive)
  (if prolog-use-standard-consult-compile-method-flag
      (prolog-old-process-file t)
    (prolog-consult-compile-file t)))

(defun prolog-compile-buffer ()
  "Compile buffer."
  (interactive)
  (if prolog-use-standard-consult-compile-method-flag
      (prolog-old-process-buffer t)
    (prolog-consult-compile-buffer t)))

(defun prolog-compile-region (beg end)
  "Compile region between BEG and END."
  (interactive "r")
  (if prolog-use-standard-consult-compile-method-flag
      (prolog-old-process-region t beg end)
    (prolog-consult-compile-region t beg end)))

(defun prolog-compile-predicate ()
  "Compile the predicate around current point."
  (interactive)
  (if prolog-use-standard-consult-compile-method-flag
      (prolog-old-process-predicate t)
    (prolog-consult-compile-predicate t)))

(defun prolog-buffer-module ()
  "Select Prolog module name appropriate for current buffer.
Bases decision on buffer contents (-*- line)."
  ;; Look for -*- ... module: MODULENAME; ... -*-
  (let (beg end)
    (save-excursion
      (goto-char (point-min))
      (skip-chars-forward " \t")
      (and (search-forward "-*-" (line-end-position) t)
           (progn
             (skip-chars-forward " \t")
             (setq beg (point))
             (search-forward "-*-" (line-end-position) t))
           (progn
             (forward-char -3)
             (skip-chars-backward " \t")
             (setq end (point))
             (goto-char beg)
             (and (let ((case-fold-search t))
                    (search-forward "module:" end t))
                  (progn
                    (skip-chars-forward " \t")
                    (setq beg (point))
                    (if (search-forward ";" end t)
                        (forward-char -1)
                      (goto-char end))
                    (skip-chars-backward " \t")
                    (buffer-substring beg (point)))))))))

(defun prolog-build-prolog-command (compilep file buffername
                                    &optional first-line)
  "Make Prolog command for FILE compilation/consulting.
If COMPILEP is non-nil, consider compilation, otherwise consulting."
  (let* ((compile-string
          ;; FIXME: If the process is not running yet, the auto-detection of
          ;; prolog-system won't help here, so we should make sure
          ;; we first run Prolog and then build the command.
          (if compilep (prolog-compile-string) (prolog-consult-string)))
         (module (prolog-buffer-module))
         (file-name (concat "'" (prolog-bsts file) "'"))
         (module-name (if module (concat "'" module "'")))
         (module-file (if module
                          (concat module-name ":" file-name)
                        file-name))
         strbeg strend
         (lineoffset (if first-line
                         (- first-line 1)
                       0)))

    ;; Assure that there is a buffer name
    (if (not buffername)
        (error "The buffer is not saved"))

    (if (not (string-match "\\`'.*'\\'" buffername)) ; Add quotes
        (setq buffername (concat "'" buffername "'")))
    (while (string-match "%m" compile-string)
      (setq strbeg (substring compile-string 0 (match-beginning 0)))
      (setq strend (substring compile-string (match-end 0)))
      (setq compile-string (concat strbeg module-file strend)))
    ;; FIXME: The code below will %-expand any %[fbl] that appears in
    ;; module-file.
    (while (string-match "%f" compile-string)
      (setq strbeg (substring compile-string 0 (match-beginning 0)))
      (setq strend (substring compile-string (match-end 0)))
      (setq compile-string (concat strbeg file-name strend)))
    (while (string-match "%b" compile-string)
      (setq strbeg (substring compile-string 0 (match-beginning 0)))
      (setq strend (substring compile-string (match-end 0)))
      (setq compile-string (concat strbeg buffername strend)))
    (while (string-match "%l" compile-string)
      (setq strbeg (substring compile-string 0 (match-beginning 0)))
      (setq strend (substring compile-string (match-end 0)))
      (setq compile-string (concat strbeg (format "%d" lineoffset) strend)))
    (concat compile-string "\n")))

;; The rest of this page is experimental code!

;; Global variables for process filter function
(defvar prolog-process-flag nil
  "Non-nil means that a prolog task (i.e. a consultation or compilation job)
is running.")
(defvar prolog-consult-compile-output ""
  "Hold the unprocessed output from the current prolog task.")
(defvar prolog-consult-compile-first-line 1
  "The number of the first line of the file to consult/compile.
Used for temporary files.")
(defvar prolog-consult-compile-file nil
  "The file to compile/consult (can be a temporary file).")
(defvar prolog-consult-compile-real-file nil
  "The file name of the buffer to compile/consult.")

(defun prolog-consult-compile (compilep file &optional first-line)
  "Consult/compile FILE.
If COMPILEP is non-nil, perform compilation, otherwise perform CONSULTING.
COMMAND is a string described by the variables `prolog-consult-string'
and `prolog-compile-string'.
Optional argument FIRST-LINE is the number of the first line in the compiled
region.

This function must be called from the source code buffer."
  (if prolog-process-flag
      (error "Another Prolog task is running"))
  (prolog-ensure-process t)
  (let* ((buffer (get-buffer-create prolog-compilation-buffer))
         (real-file buffer-file-name)
         (command-string (prolog-build-prolog-command compilep file
                                                      real-file first-line))
         (process (get-process "prolog")))
    (with-current-buffer buffer
      (delete-region (point-min) (point-max))
      ;; FIXME: Wasn't this supposed to use prolog-inferior-mode?
      (compilation-mode)
      ;; FIXME: This doesn't seem to cooperate well with new(ish) compile.el.
      ;; Setting up font-locking for this buffer
      (setq-local font-lock-defaults
                  '(prolog-font-lock-keywords nil nil ((?_ . "w"))))
      ;; (if (eq prolog-system 'sicstus)
      ;;     ;; FIXME: This looks really problematic: not only is this using
      ;;     ;; the old compilation-parse-errors-function, but
      ;;     ;; prolog-parse-sicstus-compilation-errors only accepts one
      ;;     ;; argument whereas compile.el calls it with 2 (and did so at
      ;;     ;; least since Emacs-20).
      ;;     (setq-local compilation-parse-errors-function
      ;;                 #'prolog-parse-sicstus-compilation-errors))
      (setq buffer-read-only nil)
      (insert command-string "\n"))
    (display-buffer buffer)
    (setq prolog-process-flag t
          prolog-consult-compile-output ""
          prolog-consult-compile-first-line (if first-line (1- first-line) 0)
          prolog-consult-compile-file file
          prolog-consult-compile-real-file (if (string=
                                                file buffer-file-name)
                                               nil
                                             real-file))
    (with-current-buffer buffer
      (goto-char (point-max))
      (add-function :override (process-filter process)
                    #'prolog-consult-compile-filter)
      (process-send-string "prolog" command-string)
      ;; (prolog-build-prolog-command compilep file real-file first-line))
      (while (and prolog-process-flag
                  (accept-process-output process 10)) ; 10 secs is ok?
        (sit-for 0.1)
        (unless (get-process "prolog")
          (setq prolog-process-flag nil)))
      (insert (if compilep
                  "\nCompilation finished.\n"
                "\nConsulted.\n"))
      (remove-function (process-filter process)
                       #'prolog-consult-compile-filter))))

(defvar compilation-error-list)

;; FIXME: This has been obsolete since Emacs-20!
;; (defun prolog-parse-sicstus-compilation-errors (limit)
;;   "Parse the prolog compilation buffer for errors.
;; Argument LIMIT is a buffer position limiting searching.
;; For use with the `compilation-parse-errors-function' variable."
;;   (setq compilation-error-list nil)
;;   (message "Parsing SICStus error messages...")
;;   (let (filepath dir file errorline)
;;     (while
;;         (re-search-backward
;;          "{\\([a-zA-Z ]* ERROR\\|Warning\\):.* in line[s ]*\\([0-9]+\\)"
;;          limit t)
;;       (setq errorline (string-to-number (match-string 2)))
;;       (save-excursion
;;         (re-search-backward
;;          "{\\(consulting\\|compiling\\|processing\\) \\(.*\\)\\.\\.\\.}"
;;          limit t)
;;         (setq filepath (match-string 2)))

;;       ;; ###### Does this work with SICStus under Windows
;;       ;; (i.e. backslashes and stuff?)
;;       (if (string-match "\\(.*/\\)\\([^/]*\\)$" filepath)
;;           (progn
;;             (setq dir (match-string 1 filepath))
;;             (setq file (match-string 2 filepath))))

;;       (setq compilation-error-list
;;             (cons
;;              (cons (save-excursion
;;                      (beginning-of-line)
;;                      (point-marker))
;;                    (list (list file dir) errorline))
;;              compilation-error-list)
;;             ))
;;     ))

(defun prolog-consult-compile-filter (process output)
  "Filter function for Prolog compilation PROCESS.
Argument OUTPUT is a name of the output file."
  ;;(message "start")
  (setq prolog-consult-compile-output
        (concat prolog-consult-compile-output output))
  ;;(message "pccf1: %s" prolog-consult-compile-output)
  ;; Iterate through the lines of prolog-consult-compile-output
  (let (outputtype)
    (while (and prolog-process-flag
                (or
                 ;; Trace question
                 (progn
                   (setq outputtype 'trace)
                   (and (eq prolog-system 'sicstus)
                        (string-match
                         "^[ \t]*[0-9]+[ \t]*[0-9]+[ \t]*Call:.*? "
                         prolog-consult-compile-output)))

                 ;; Match anything
                 (progn
                   (setq outputtype 'normal)
                   (string-match "^.*\n" prolog-consult-compile-output))
                   ))
      ;;(message "outputtype: %s" outputtype)

      (setq output (match-string 0 prolog-consult-compile-output))
      ;; remove the text in output from prolog-consult-compile-output
      (setq prolog-consult-compile-output
            (substring prolog-consult-compile-output (length output)))
      ;;(message "pccf2: %s" prolog-consult-compile-output)

      ;; If temporary files were used, then we change the error
      ;; messages to point to the original source file.
      ;; FIXME: Use compilation-fake-loc instead.
      (cond

       ;; If the prolog process was in trace mode then it requires
       ;; user input
       ((and (eq prolog-system 'sicstus)
             (eq outputtype 'trace))
        (let ((input (concat (read-string output) "\n")))
          (process-send-string process input)
          (setq output (concat output input))))

       ((eq prolog-system 'sicstus)
        (if (and prolog-consult-compile-real-file
                 (string-match
                  "\\({.*:.* in line[s ]*\\)\\([0-9]+\\)-\\([0-9]+\\)" output))
            (setq output (replace-match
                          ;; Adds a {processing ...} line so that
                          ;; `prolog-parse-sicstus-compilation-errors'
                          ;; finds the real file instead of the temporary one.
                          ;; Also fixes the line numbers.
                          (format "Added by Emacs: {processing %s...}\n%s%d-%d"
                                  prolog-consult-compile-real-file
                                  (match-string 1 output)
                                  (+ prolog-consult-compile-first-line
                                     (string-to-number
                                      (match-string 2 output)))
                                  (+ prolog-consult-compile-first-line
                                     (string-to-number
                                      (match-string 3 output))))
                          t t output)))
        )

       ((eq prolog-system 'swi)
        (if (and prolog-consult-compile-real-file
                 (string-match (format
                                "%s\\([ \t]*:[ \t]*\\)\\([0-9]+\\)"
                                prolog-consult-compile-file)
                               output))
            (setq output (replace-match
                          ;; Real filename + text + fixed linenum
                          (format "%s%s%d"
                                  prolog-consult-compile-real-file
                                  (match-string 1 output)
                                  (+ prolog-consult-compile-first-line
                                     (string-to-number
                                      (match-string 2 output))))
                          t t output)))
        )

       (t ())
       )
      ;; Write the output in the *prolog-compilation* buffer
      (insert output)))

  ;; If the prompt is visible, then the task is finished
  (if (string-match (prolog-prompt-regexp) prolog-consult-compile-output)
      (setq prolog-process-flag nil)))

(defun prolog-consult-compile-file (compilep)
  "Consult/compile file of current buffer.
If COMPILEP is non-nil, compile, otherwise consult."
  (let ((file buffer-file-name))
    (if file
        (progn
          (save-some-buffers)
          (prolog-consult-compile compilep file))
      (prolog-consult-compile-region compilep (point-min) (point-max)))))

(defun prolog-consult-compile-buffer (compilep)
  "Consult/compile current buffer.
If COMPILEP is non-nil, compile, otherwise consult."
  (prolog-consult-compile-region compilep (point-min) (point-max)))

(defun prolog-consult-compile-region (compilep beg end)
  "Consult/compile region between BEG and END.
If COMPILEP is non-nil, compile, otherwise consult."
  ;(let ((file prolog-temp-filename)
  (let ((file (prolog-bsts (prolog-temporary-file)))
        (lines (count-lines 1 beg)))
    (write-region beg end file nil 'no-message)
    (write-region "\n" nil file t 'no-message)
    (prolog-consult-compile compilep file
                            (if (bolp) (1+ lines) lines))
    (delete-file file)))

(defun prolog-consult-compile-predicate (compilep)
  "Consult/compile the predicate around current point.
If COMPILEP is non-nil, compile, otherwise consult."
  (prolog-consult-compile-region
   compilep (prolog-pred-start) (prolog-pred-end)))


;;-------------------------------------------------------------------
;; Font-lock stuff
;;-------------------------------------------------------------------

;; Auxiliary functions

(defun prolog-font-lock-object-matcher (bound)
  "Find SICStus objects method name for font lock.
Argument BOUND is a buffer position limiting searching."
  (let (point
        (case-fold-search nil))
    (while (and (not point)
                (re-search-forward "\\(::[ \t\n]*{\\|&\\)[ \t]*"
                                   bound t))
      (while (or (re-search-forward "\\=\n[ \t]*" bound t)
                 (re-search-forward "\\=%.*" bound t)
                 (and (re-search-forward "\\=/\\*" bound t)
                      (re-search-forward "\\*/[ \t]*" bound t))))
      (setq point (re-search-forward
                   (format "\\=\\(%s\\)" prolog-atom-regexp)
                   bound t)))
    point))

(define-obsolete-function-alias 'prolog-face-name-p 'facep "28.1")

;; Set everything up
(defun prolog-font-lock-keywords ()
  "Set up font lock keywords for the current Prolog system."

  ;; Define Prolog faces
  (defface prolog-redo-face
    '((((class grayscale)) (:italic t))
      (((class color)) (:foreground "darkorchid"))
      (t (:italic t)))
    "Prolog mode face for highlighting redo trace lines."
    :group 'prolog-faces)
  (defface prolog-exit-face
    '((((class grayscale)) (:underline t))
      (((class color) (background dark)) (:foreground "green"))
      (((class color) (background light)) (:foreground "ForestGreen"))
      (t (:underline t)))
    "Prolog mode face for highlighting exit trace lines."
    :group 'prolog-faces)
  (defface prolog-exception-face
    '((((class grayscale)) (:bold t :italic t :underline t))
      (((class color)) (:bold t :foreground "black" :background "Khaki"))
      (t (:bold t :italic t :underline t)))
    "Prolog mode face for highlighting exception trace lines."
    :group 'prolog-faces)
  (defface prolog-warning-face
    '((((class grayscale)) (:underline t))
      (((class color) (background dark)) (:foreground "blue"))
      (((class color) (background light)) (:foreground "MidnightBlue"))
      (t (:underline t)))
    "Face name to use for compiler warnings."
    :group 'prolog-faces)
  (define-obsolete-face-alias 'prolog-warning-face
    'font-lock-warning-face "28.1")
  (defface prolog-builtin-face
    '((((class color) (background light)) (:foreground "Purple"))
      (((class color) (background dark)) (:foreground "Cyan"))
      (((class grayscale) (background light))
       :foreground "LightGray" :bold t)
      (((class grayscale) (background dark)) (:foreground "DimGray" :bold t))
      (t (:bold t)))
    "Face name to use for compiler warnings."
    :group 'prolog-faces)
  (define-obsolete-face-alias 'prolog-builtin-face
    'font-lock-builtin-face "28.1")
  (defvar prolog-warning-face 'font-lock-warning-face
    "Face name to use for built in predicates.")
  (defvar prolog-builtin-face 'font-lock-builtin-face
    "Face name to use for built in predicates.")
  (defvar prolog-redo-face 'prolog-redo-face
    "Face name to use for redo trace lines.")
  (defvar prolog-exit-face 'prolog-exit-face
    "Face name to use for exit trace lines.")
  (defvar prolog-exception-face 'prolog-exception-face
    "Face name to use for exception trace lines.")

  ;; Font Lock Patterns
  (let (
        ;; "Native" Prolog patterns
        (head-predicates
         (list (format "^\\(%s\\)\\((\\|[ \t]*:-\\)" prolog-atom-regexp)
               1 font-lock-function-name-face))
                                       ;(list (format "^%s" prolog-atom-regexp)
                                       ;      0 font-lock-function-name-face))
        (head-predicates-1
         (list (format "\\.[ \t]*\\(%s\\)" prolog-atom-regexp)
               1 font-lock-function-name-face) )
        (variables
         '("\\<\\([_A-Z][a-zA-Z0-9_]*\\)"
           1 font-lock-variable-name-face))
        (important-elements
         (list (if (eq prolog-system 'mercury)
                   "[][}{;|]\\|\\\\[+=]\\|<?=>?"
                 "[][}{!;|]\\|\\*->")
               0 'font-lock-keyword-face))
        (important-elements-1
         '("[^-*]\\(->\\)" 1 font-lock-keyword-face))
        (predspecs                      ; module:predicate/cardinality
         (list (format "\\<\\(%s:\\|\\)%s/[0-9]+"
                       prolog-atom-regexp prolog-atom-regexp)
               0 font-lock-function-name-face 'prepend))
        (keywords                       ; directives (queries)
         (list
          (if (eq prolog-system 'mercury)
              (concat
               "\\<\\("
               (regexp-opt prolog-keywords-i)
               "\\|"
               (regexp-opt
                prolog-determinism-specificators-i)
               "\\)\\>")
            (concat
             "^[?:]- *\\("
             (regexp-opt prolog-keywords-i)
             "\\)\\>"))
          1 prolog-builtin-face))
        ;; SICStus specific patterns
        (sicstus-object-methods
         (if (eq prolog-system 'sicstus)
             '(prolog-font-lock-object-matcher
               1 font-lock-function-name-face)))
        ;; Mercury specific patterns
        (types
         (if (eq prolog-system 'mercury)
             (list
              (regexp-opt prolog-types-i 'words)
              0 'font-lock-type-face)))
        (modes
         (if (eq prolog-system 'mercury)
             (list
              (regexp-opt prolog-mode-specificators-i 'words)
              0 'font-lock-constant-face)))
        (directives
         (if (eq prolog-system 'mercury)
             (list
              (regexp-opt prolog-directives-i 'words)
              0 'prolog-warning-face)))
        ;; Inferior mode specific patterns
        (prompt
         ;; FIXME: Should be handled by comint already.
         (list (prolog-prompt-regexp) 0 'font-lock-keyword-face))
        (trace-exit
         ;; FIXME: Add to compilation-error-regexp-alist instead.
         (cond
          ((eq prolog-system 'sicstus)
           '("[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*\\(Exit\\):"
             1 prolog-exit-face))
          ((eq prolog-system 'swi)
           '("[ \t]*\\(Exit\\):[ \t]*([ \t0-9]*)" 1 prolog-exit-face))
          (t nil)))
        (trace-fail
         ;; FIXME: Add to compilation-error-regexp-alist instead.
         (cond
          ((eq prolog-system 'sicstus)
           '("[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*\\(Fail\\):"
             1 prolog-warning-face))
          ((eq prolog-system 'swi)
           '("[ \t]*\\(Fail\\):[ \t]*([ \t0-9]*)" 1 prolog-warning-face))
          (t nil)))
        (trace-redo
         ;; FIXME: Add to compilation-error-regexp-alist instead.
         (cond
          ((eq prolog-system 'sicstus)
           '("[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*\\(Redo\\):"
             1 prolog-redo-face))
          ((eq prolog-system 'swi)
           '("[ \t]*\\(Redo\\):[ \t]*([ \t0-9]*)" 1 prolog-redo-face))
          (t nil)))
        (trace-call
         ;; FIXME: Add to compilation-error-regexp-alist instead.
         (cond
          ((eq prolog-system 'sicstus)
           '("[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*\\(Call\\):"
             1 font-lock-function-name-face))
          ((eq prolog-system 'swi)
           '("[ \t]*\\(Call\\):[ \t]*([ \t0-9]*)"
             1 font-lock-function-name-face))
          (t nil)))
        (trace-exception
         ;; FIXME: Add to compilation-error-regexp-alist instead.
         (cond
          ((eq prolog-system 'sicstus)
           '("[ \t]*[0-9]+[ \t]+[0-9]+[ \t]*\\(Exception\\):"
             1 prolog-exception-face))
          ((eq prolog-system 'swi)
           '("[ \t]*\\(Exception\\):[ \t]*([ \t0-9]*)"
             1 prolog-exception-face))
          (t nil)))
        (error-message-identifier
         ;; FIXME: Add to compilation-error-regexp-alist instead.
         (cond
          ((eq prolog-system 'sicstus)
           '("{\\([A-Z]* ?ERROR:\\)" 1 prolog-exception-face prepend))
          ((eq prolog-system 'swi)
           '("^[[]\\(WARNING:\\)" 1 prolog-builtin-face prepend))
          (t nil)))
        (error-whole-messages
         ;; FIXME: Add to compilation-error-regexp-alist instead.
         (cond
          ((eq prolog-system 'sicstus)
           '("{\\([A-Z]* ?ERROR:.*\\)}[ \t]*$"
             1 font-lock-comment-face append))
          ((eq prolog-system 'swi)
           '("^[[]WARNING:[^]]*[]]$" 0 font-lock-comment-face append))
          (t nil)))
        (error-warning-messages
         ;; FIXME: Add to compilation-error-regexp-alist instead.
         ;; Mostly errors that SICStus asks the user about how to solve,
         ;; such as "NAME CLASH:" for example.
         (cond
          ((eq prolog-system 'sicstus)
           '("^[A-Z ]*[A-Z]+:" 0 prolog-warning-face))
          (t nil)))
        (warning-messages
         ;; FIXME: Add to compilation-error-regexp-alist instead.
         (cond
          ((eq prolog-system 'sicstus)
           '("\\({ ?\\(Warning\\|WARNING\\) ?:.*}\\)[ \t]*$"
             2 prolog-warning-face prepend))
          (t nil))))

    ;; Make font lock list
    (delq
     nil
     (cond
      ((derived-mode-p 'prolog-mode)
       (list
        head-predicates
        head-predicates-1
        variables
        important-elements
        important-elements-1
        predspecs
        keywords
        sicstus-object-methods
        types
        modes
        directives))
      ((eq major-mode 'prolog-inferior-mode)
       (list
        prompt
        error-message-identifier
        error-whole-messages
        error-warning-messages
        warning-messages
        predspecs
        trace-exit
        trace-fail
        trace-redo
        trace-call
        trace-exception))
      ((eq major-mode 'compilation-mode)
       (list
        error-message-identifier
        error-whole-messages
        error-warning-messages
        warning-messages
        predspecs))))
    ))



(defun prolog-find-unmatched-paren ()
  "Return the column of the last unmatched left parenthesis."
  (save-excursion
    (goto-char (or (nth 1 (syntax-ppss)) (point-min)))
    (current-column)))


(defun prolog-paren-balance ()
  "Return the parenthesis balance of the current line.
A return value of N means N more left parentheses than right ones."
  (save-excursion
    (car (parse-partial-sexp (line-beginning-position)
                             (line-end-position)))))

(defun prolog-electric--if-then-else ()
  "Insert spaces after the opening parenthesis.
\"then\" (->) and \"else\" (;) branches.
Spaces are inserted if all preceding objects on the line are
whitespace characters, parentheses, or then/else branches."
  (when prolog-electric-if-then-else-flag
    (save-excursion
      (let ((regexp (concat "(\\|" prolog-left-indent-regexp))
            (pos (point))
            level)
        (beginning-of-line)
        (skip-chars-forward " \t")
        ;; Treat "( If -> " lines specially.
        ;;(setq incr (if (looking-at "(.*->")
        ;;               2
        ;;             prolog-paren-indent))

        ;; work on all subsequent "->", "(", ";"
        (and (looking-at regexp)
             (= pos (match-end 0))
             (indent-according-to-mode))
        (while (looking-at regexp)
          (goto-char (match-end 0))
          (setq level (+ (prolog-find-unmatched-paren) prolog-paren-indent))

          ;; Remove old white space
          (let ((start (point)))
            (skip-chars-forward " \t")
            (delete-region start (point)))
          (indent-to level)
          (skip-chars-forward " \t"))
        ))
    (when (save-excursion
            (backward-char 2)
            (looking-at "\\s ;\\|\\s (\\|->")) ; (looking-at "\\s \\((\\|;\\)"))
      (skip-chars-forward " \t"))
    ))

;;;; Comment filling

(defun prolog-comment-limits ()
  "Return the current comment limits plus the comment type (block or line).
The comment limits are the range of a block comment or the range that
contains all adjacent line comments (i.e. all comments that starts in
the same column with no empty lines or non-whitespace characters
between them)."
  (let ((here (point))
        lit-limits-b lit-limits-e lit-type beg end
        )
    (save-restriction
      ;; Widen to catch comment limits correctly.
      (widen)
      (setq end (line-end-position)
            beg (line-beginning-position))
      (save-excursion
        (beginning-of-line)
        (setq lit-type (if (search-forward-regexp "%" end t) 'line 'block))
                        ;    (setq lit-type 'line)
                        ;(if (search-forward-regexp "^[ \t]*%" end t)
                        ;    (setq lit-type 'line)
                        ;  (if (not (search-forward-regexp "%" end t))
                        ;      (setq lit-type 'block)
                        ;    (if (not (= (forward-line 1) 0))
                        ;        (setq lit-type 'block)
                        ;      (setq done t
                        ;            ret (prolog-comment-limits)))
                        ;    ))
        (if (eq lit-type 'block)
            (progn
              (goto-char here)
              (when (looking-at "/\\*") (forward-char 2))
              (when (and (looking-at "\\*") (> (point) (point-min))
                         (forward-char -1) (looking-at "/"))
                (forward-char 1))
              (when (save-excursion (search-backward "/*" nil t))
                (list (save-excursion (search-backward "/*") (point))
                      (or (search-forward "*/" nil t) (point-max)) lit-type)))
          ;; line comment
          (setq lit-limits-b (- (point) 1)
                lit-limits-e end)
          (condition-case nil
              (if (progn (goto-char lit-limits-b)
                         (looking-at "%"))
                  (let ((col (current-column)) done)
                    (setq beg (point)
                          end lit-limits-e)
                    ;; Always at the beginning of the comment
                    ;; Go backward now
                    (beginning-of-line)
                    (while (and (zerop (setq done (forward-line -1)))
                                (search-forward-regexp "^[ \t]*%"
                                                       (line-end-position) t)
                                (= (+ 1 col) (current-column)))
                      (setq beg (- (point) 1)))
                    (when (= done 0)
                      (forward-line 1))
                    ;; We may have a line with code above...
                    (when (and (zerop (setq done (forward-line -1)))
                               (search-forward "%" (line-end-position) t)
                               (= (+ 1 col) (current-column)))
                      (setq beg (- (point) 1)))
                    (when (= done 0)
                      (forward-line 1))
                    ;; Go forward
                    (goto-char lit-limits-b)
                    (beginning-of-line)
                    (while (and (zerop (forward-line 1))
                                (search-forward-regexp "^[ \t]*%"
                                                       (line-end-position) t)
                                (= (+ 1 col) (current-column)))
                      (setq end (line-end-position)))
                    (list beg end lit-type))
                (list lit-limits-b lit-limits-e lit-type)
                )
            (error (list lit-limits-b lit-limits-e lit-type))))
        ))))

(defun prolog-guess-fill-prefix ()
  ;; fill 'txt entities?
  (when (save-excursion
          (end-of-line)
          (nth 4 (syntax-ppss)))
    (let* ((bounds (prolog-comment-limits))
           (cbeg (car bounds))
           (type (nth 2 bounds))
           beg end)
      (save-excursion
        (end-of-line)
        (setq end (point))
        (beginning-of-line)
        (setq beg (point))
        (if (and (eq type 'line)
                 (> cbeg beg)
                 (save-excursion (not (search-forward-regexp "^[ \t]*%"
                                                             cbeg t))))
            (progn
              (goto-char cbeg)
              (search-forward-regexp "%+[ \t]*" end t)
              (replace-regexp-in-string "[^ \t%]" " "
                                        (buffer-substring beg (point))))
          ;(goto-char beg)
          (if (search-forward-regexp "^[ \t]*\\(%+\\|\\*+\\|/\\*+\\)[ \t]*"
                                     end t)
              (string-replace "/" " " (buffer-substring beg (point)))
            (beginning-of-line)
            (when (search-forward-regexp "^[ \t]+" end t)
              (buffer-substring beg (point)))))))))

(defun prolog-fill-paragraph ()
  "Fill paragraph comment at or after point."
  (interactive)
  (let* ((bounds (prolog-comment-limits))
         (type (nth 2 bounds)))
    (if (eq type 'line)
        (let ((fill-prefix (prolog-guess-fill-prefix)))
          (fill-paragraph nil))
      (save-excursion
        (save-restriction
          ;; exclude surrounding lines that delimit a multiline comment
          ;; and don't contain alphabetic characters, like "/*******",
          ;; "- - - */" etc.
          (save-excursion
            (backward-paragraph)
            (unless (bobp) (forward-line))
            (if (string-match "^/\\*[^a-zA-Z]*$" (thing-at-point 'line))
                (narrow-to-region (line-end-position) (point-max))))
          (save-excursion
            (forward-paragraph)
            (forward-line -1)
            (if (string-match "^[^a-zA-Z]*\\*/$" (thing-at-point 'line))
                (narrow-to-region (point-min) (line-beginning-position))))
          (let ((fill-prefix (prolog-guess-fill-prefix)))
            (fill-paragraph nil))))
      )))

(defun prolog-do-auto-fill ()
  "Carry out Auto Fill for Prolog mode.
In effect it sets the `fill-prefix' when inside comments and then calls
`do-auto-fill'."
  (let ((fill-prefix (prolog-guess-fill-prefix)))
    (do-auto-fill)
    ))

(defun prolog-replace-in-string (str regexp newtext &optional literal)
  (declare (obsolete replace-regexp-in-string "28.1"))
  (replace-regexp-in-string regexp newtext str nil literal))


;;-------------------------------------------------------------------
;; Online help
;;-------------------------------------------------------------------

(defvar prolog-help-function
  '((mercury nil)
    (eclipse prolog-help-online)
    ;; (sicstus prolog-help-info)
    (sicstus prolog-find-documentation)
    (swi prolog-help-online)
    (t prolog-help-online))
  "Alist for the name of the function for finding help on a predicate.")
(put 'prolog-help-function 'risky-local-variable t)

(defun prolog-help-on-predicate ()
  "Invoke online help on the atom under cursor."
  (interactive)

  (cond
   ;; Redirect help for SICStus to `prolog-find-documentation'.
   ((eq prolog-help-function-i 'prolog-find-documentation)
    (prolog-find-documentation))

   ;; Otherwise, ask for the predicate name and then call the function
   ;; in prolog-help-function-i
   (t
    (let* ((word (prolog-atom-under-point))
           (predicate (read-string (format-prompt "Help on predicate" word)
                                   nil nil word))
           ;;point
           )
      (if prolog-help-function-i
          (funcall prolog-help-function-i predicate)
        (error "Sorry, no help method defined for this Prolog system"))))
   ))


(autoload 'Info-goto-node "info" nil t)
(declare-function Info-follow-nearest-node "info" (&optional FORK))

(defun prolog-help-info (predicate)
  (let ((buffer (current-buffer))
        oldp
        (str (concat "^\\* " (regexp-quote predicate) " */")))
    (pop-to-buffer nil)
    (Info-goto-node prolog-info-predicate-index)
    (if (not (re-search-forward str nil t))
        (error "Help on predicate `%s' not found" predicate))

    (setq oldp (point))
    (if (re-search-forward str nil t)
        ;; Multiple matches, ask user
        (let ((max 2)
              n)
          ;; Count matches
          (while (re-search-forward str nil t)
            (setq max (1+ max)))

          (goto-char oldp)
          (re-search-backward "[^ /]" nil t)
          (recenter 0)
          (setq n (read-string  ;; was read-input, which is obsolete
                   (format "Several matches, choose (1-%d): " max) "1"))
          (forward-line (- (string-to-number n) 1)))
      ;; Single match
      (re-search-backward "[^ /]" nil t))

    (Info-follow-nearest-node)
    (re-search-forward (concat "^`" (regexp-quote predicate)) nil t)
    (beginning-of-line)
    (recenter 0)
    (pop-to-buffer buffer)))

(define-obsolete-function-alias 'prolog-Info-follow-nearest-node
  #'Info-follow-nearest-node "27.1")

(defun prolog-help-online (predicate)
  (prolog-ensure-process)
  (process-send-string "prolog" (concat "help(" predicate ").\n"))
  (display-buffer "*prolog*"))

(defun prolog-help-apropos (string)
  "Find Prolog apropos on given STRING.
This function is only available when `prolog-system' is set to `swi'."
  (interactive "sApropos: ")
  (cond
   ((eq prolog-system 'swi)
    (prolog-ensure-process)
    (process-send-string "prolog" (concat "apropos(" string ").\n"))
    (display-buffer "*prolog*"))
   (t
    (error "Sorry, no Prolog apropos available for this Prolog system"))))

(defun prolog-atom-under-point ()
  "Return the atom under or left to the point."
  (save-excursion
    (let ((nonatom_chars "[](){},. \t\n")
          start)
      (skip-chars-forward (concat "^" nonatom_chars))
      (skip-chars-backward nonatom_chars)
      (skip-chars-backward (concat "^" nonatom_chars))
      (setq start (point))
      (skip-chars-forward (concat "^" nonatom_chars))
      (buffer-substring-no-properties start (point))
      )))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Help function with completion
;; Stolen from Per Mildner's SICStus debugger mode and modified

(defun prolog-find-documentation ()
  "Go to the Info node for a predicate in the SICStus Info manual."
  (interactive)
  (let ((pred (prolog-read-predicate)))
    (prolog-goto-predicate-info pred)))

(defvar prolog-info-alist nil
  "Alist with all builtin predicates.
Only for internal use by `prolog-find-documentation'")

;; Very similar to prolog-help-info except that that function cannot
;; cope with arity and that it asks the user if there are several
;; functors with different arity. This function also uses
;; prolog-info-alist for finding the info node, rather than parsing
;; the predicate index.
(defun prolog-goto-predicate-info (predicate)
  "Go to the info page for PREDICATE, which is a PredSpec."
  (interactive)
  (string-match "\\(.*\\)/\\([0-9]+\\).*$" predicate)
  (let ((buffer (current-buffer))
        (name (match-string 1 predicate))
        (arity (string-to-number (match-string 2 predicate)))
        ;oldp
        ;(str (regexp-quote predicate))
        )
    (pop-to-buffer nil)

    (Info-goto-node
     prolog-info-predicate-index) ;; We must be in the SICStus pages
    (Info-goto-node (car (cdr (assoc predicate prolog-info-alist))))

    (prolog-find-term (regexp-quote name) arity "^`")

    (recenter 0)
    (pop-to-buffer buffer))
)

(defun prolog-read-predicate ()
  "Read a PredSpec from the user.
Returned value is a string \"FUNCTOR/ARITY\".
Interaction supports completion."
  (let ((default (prolog-atom-under-point)))
    ;; If the predicate index is not yet built, do it now
    (if (not prolog-info-alist)
        (prolog-build-info-alist))
    ;; Test if the default string could be the base for completion.
    ;; Discard it if not.
    (if (eq (try-completion default prolog-info-alist) nil)
        (setq default nil))
    ;; Read the PredSpec from the user
    (completing-read (format-prompt "Help on predicate" default)
                     prolog-info-alist nil t nil nil default)))

(defun prolog-build-info-alist (&optional verbose)
  "Build an alist of all builtins and library predicates.
Each element is of the form (\"NAME/ARITY\" . (INFO-NODE1 INFO-NODE2 ...)).
Typically there is just one Info node associated with each name
If an optional argument VERBOSE is non-nil, print messages at the beginning
and end of list building."
  (if verbose
      (message "Building info alist..."))
  (setq prolog-info-alist
        (let ((l ())
              (last-entry (cons "" ())))
          (save-excursion
            (save-window-excursion
              ;; select any window but the minibuffer (as we cannot switch
              ;; buffers in minibuffer window.
              ;; I am not sure this is the right/best way
              (if (active-minibuffer-window)  ; nil if none active
                  (select-window (next-window)))
              ;; Do this after going away from minibuffer window
              (save-window-excursion
                (info))
              (Info-goto-node prolog-info-predicate-index)
              (goto-char (point-min))
              (while (re-search-forward
                      "^\\* \\(.+\\)/\\([0-9]+\\)\\([^\n:*]*\\):" nil t)
                (let* ((name (match-string 1))
                       (arity (string-to-number (match-string 2)))
                       (comment (match-string 3))
                       (fa (format "%s/%d%s" name arity comment))
                       info-node)
                  (beginning-of-line)
                  ;; Extract the info node name
                  (setq info-node (progn
                                    (re-search-forward ":[ \t]*\\([^:]+\\).$")
                                    (match-string 1)
                                   ))
                  ;; ###### Easier? (from Milan version 0.1.28)
                  ;; (setq info-node (Info-extract-menu-node-name))
                  (if (equal fa (car last-entry))
                      (setcdr last-entry (cons info-node (cdr last-entry)))
                    (setq last-entry (cons fa (list info-node))
                          l (cons last-entry l)))))
              (nreverse l)
              ))))
  (if verbose
      (message "Building info alist... done.")))


;;-------------------------------------------------------------------
;; Miscellaneous functions
;;-------------------------------------------------------------------

;; For Windows. Change backslash to slash. SICStus handles either
;; path separator but backslash must be doubled, therefore use slash.
(defun prolog-bsts (string)
  "Change backslashes to slashes in STRING."
  (let ((str1 (copy-sequence string))
        (len (length string))
        (i 0))
    (while (< i len)
      (if (char-equal (aref str1 i) ?\\)
          (aset str1 i ?/))
      (setq i (1+ i)))
    str1))

;;(defun prolog-temporary-file ()
;;  "Make temporary file name for compilation."
;;  (make-temp-name
;;   (concat
;;    (or
;;     (getenv "TMPDIR")
;;     (getenv "TEMP")
;;     (getenv "TMP")
;;     (getenv "SYSTEMP")
;;     "/tmp")
;;    "/prolcomp")))
;;(setq prolog-temp-filename (prolog-bsts (prolog-temporary-file)))

(defun prolog-temporary-file ()
  "Make temporary file name for compilation."
  (if prolog-temporary-file-name
      ;; We already have a file, erase content and continue
      (progn
        (write-region "" nil prolog-temporary-file-name nil 'silent)
        prolog-temporary-file-name)
    ;; Actually create the file and set `prolog-temporary-file-name'
    ;; accordingly.
    (setq prolog-temporary-file-name
          (make-temp-file "prolcomp" nil ".pl"))))

(defun prolog-goto-prolog-process-buffer ()
  "Switch to the prolog process buffer and go to its end."
  (switch-to-buffer-other-window "*prolog*")
  (goto-char (point-max))
)

(declare-function pltrace-on "ext:pltrace" ())

(defun prolog-enable-sicstus-sd ()
  "Enable the source level debugging facilities of SICStus 3.7 and later."
  (interactive)
  (require 'pltrace)  ; Load the SICStus debugger code
  ;; Turn on the source level debugging by default
  (add-hook 'prolog-inferior-mode-hook 'pltrace-on)
  (if (not prolog-use-sicstus-sd)
      (progn
        ;; If there is a *prolog* buffer, then call pltrace-on
        (if (get-buffer "*prolog*")
            (pltrace-on))
        (setq prolog-use-sicstus-sd t)
        )))

(declare-function pltrace-off "ext:pltrace" (&optional remove-process-filter))

(defun prolog-disable-sicstus-sd ()
  "Disable the source level debugging facilities of SICStus 3.7 and later."
  (interactive)
  (require 'pltrace)
  (setq prolog-use-sicstus-sd nil)
  ;; Remove the hook
  (remove-hook 'prolog-inferior-mode-hook 'pltrace-on)
  ;; If there is a *prolog* buffer, then call pltrace-off
  (if (get-buffer "*prolog*")
      (pltrace-off)))

(defun prolog-toggle-sicstus-sd ()
  ;; FIXME: Use define-minor-mode.
  "Toggle the source level debugging facilities of SICStus 3.7 and later."
  (interactive)
  (if prolog-use-sicstus-sd
      (prolog-disable-sicstus-sd)
    (prolog-enable-sicstus-sd)))

(defun prolog-debug-on (&optional arg)
  "Enable debugging.
When called with prefix argument ARG, disable debugging instead."
  (interactive "P")
  (if arg
      (prolog-debug-off)
    (prolog-process-insert-string (get-process "prolog")
                                  prolog-debug-on-string)
    (process-send-string "prolog" prolog-debug-on-string)))

(defun prolog-debug-off ()
  "Disable debugging."
  (interactive)
  (prolog-process-insert-string (get-process "prolog")
                                prolog-debug-off-string)
  (process-send-string "prolog" prolog-debug-off-string))

(defun prolog-trace-on (&optional arg)
  "Enable tracing.
When called with prefix argument ARG, disable tracing instead."
  (interactive "P")
  (if arg
      (prolog-trace-off)
    (prolog-process-insert-string (get-process "prolog")
                                  prolog-trace-on-string)
    (process-send-string "prolog" prolog-trace-on-string)))

(defun prolog-trace-off ()
  "Disable tracing."
  (interactive)
  (prolog-process-insert-string (get-process "prolog")
                                prolog-trace-off-string)
  (process-send-string "prolog" prolog-trace-off-string))

(defun prolog-zip-on (&optional arg)
  "Enable zipping (for SICStus 3.7 and later).
When called with prefix argument ARG, disable zipping instead."
  (interactive "P")
  (if (not (and (eq prolog-system 'sicstus)
                (prolog-atleast-version '(3 . 7))))
      (error "Only works for SICStus 3.7 and later"))
  (if arg
      (prolog-zip-off)
    (prolog-process-insert-string (get-process "prolog")
                                  prolog-zip-on-string)
    (process-send-string "prolog" prolog-zip-on-string)))

(defun prolog-zip-off ()
  "Disable zipping (for SICStus 3.7 and later)."
  (interactive)
  (prolog-process-insert-string (get-process "prolog")
                                prolog-zip-off-string)
  (process-send-string "prolog" prolog-zip-off-string))

;; (defun prolog-create-predicate-index ()
;;   "Create an index for all predicates in the buffer."
;;   (let ((predlist '())
;;         clauseinfo
;;         object
;;         pos
;;         )
;;     (goto-char (point-min))
;;     ;; Replace with prolog-clause-start!
;;     (while (re-search-forward "^.+:-" nil t)
;;       (setq pos (match-beginning 0))
;;       (setq clauseinfo (prolog-clause-info))
;;       (setq object (prolog-in-object))
;;       (setq predlist (append
;;                       predlist
;;                       (list (cons
;;                              (if (and (eq prolog-system 'sicstus)
;;                                       (prolog-in-object))
;;                                  (format "%s::%s/%d"
;;                                          object
;;                                          (nth 0 clauseinfo)
;;                                          (nth 1 clauseinfo))
;;                                (format "%s/%d"
;;                                        (nth 0 clauseinfo)
;;                                        (nth 1 clauseinfo)))
;;                              pos
;;                              ))))
;;       (prolog-end-of-predicate))
;;     predlist))

(defun prolog-get-predspec ()
  (save-excursion
    (let ((state (prolog-clause-info))
          (object (prolog-in-object)))
      (if (or (equal (nth 0 state) "")
              (nth 4 (syntax-ppss)))
          nil
        (if (and (eq prolog-system 'sicstus)
                 object)
            (format "%s::%s/%d"
                    object
                    (nth 0 state)
                    (nth 1 state))
          (format "%s/%d"
                  (nth 0 state)
                  (nth 1 state)))
        ))))

(defun prolog-pred-start ()
  "Return the starting point of the first clause of the current predicate."
  ;; FIXME: Use SMIE.
  (save-excursion
    (goto-char (prolog-clause-start))
    ;; Find first clause, unless it was a directive
    (if (and (not (looking-at "[:?]-"))
             (not (looking-at "[ \t]*[%/]"))  ; Comment

             )
        (let* ((pinfo (prolog-clause-info))
               (predname (nth 0 pinfo))
               (arity (nth 1 pinfo))
               (op (point)))
          (while (and (re-search-backward
                       (format "^%s\\([(\\.]\\| *%s\\)"
                               predname prolog-head-delimiter) nil t)
                      (= arity (nth 1 (prolog-clause-info)))
                      )
            (setq op (point)))
          (if (eq prolog-system 'mercury)
              ;; Skip to the beginning of declarations of the predicate
              (progn
                (goto-char (prolog-beginning-of-clause))
                (while (and (not (eq (point) op))
                            (looking-at
                             (format ":-[ \t]*\\(pred\\|mode\\)[ \t]+%s"
                                     predname)))
                  (setq op (point))
                  (goto-char (prolog-beginning-of-clause)))))
          op)
      (point))))

(defun prolog-pred-end ()
  "Return the position at the end of the last clause of the current predicate."
  ;; FIXME: Use SMIE.
  (save-excursion
    (goto-char (prolog-clause-end))     ; If we are before the first predicate.
    (goto-char (prolog-clause-start))
    (let* ((pinfo (prolog-clause-info))
          (predname (nth 0 pinfo))
          (arity (nth 1 pinfo))
          oldp
          (notdone t)
          (op (point)))
      (if (looking-at "[:?]-")
          ;; This was a directive
          (progn
            (if (and (eq prolog-system 'mercury)
                     (looking-at
                      (format ":-[ \t]*\\(pred\\|mode\\)[ \t]+\\(\\(?:%s\\)+\\)"
                              prolog-atom-regexp)))
                ;; Skip predicate declarations
                (progn
                  (setq predname (buffer-substring-no-properties
                                  (match-beginning 2) (match-end 2)))
                  (while (re-search-forward
                          (format
                           "\n*\\(:-[ \t]*\\(pred\\|mode\\)[ \t]+\\)?%s[( \t]"
                           predname)
                          nil t))))
            (goto-char (prolog-clause-end))
            (setq op (point)))
        ;; It was not a directive, find the last clause
        (while (and notdone
                    (re-search-forward
                     (format "^%s\\([(\\.]\\| *%s\\)"
                             predname prolog-head-delimiter) nil t)
                    (= arity (nth 1 (prolog-clause-info))))
          (setq oldp (point))
          (setq op (prolog-clause-end))
          (if (>= oldp op)
              ;; End of clause not found.
              (setq notdone nil)
            ;; Continue while loop
            (goto-char op))))
      op)))

(defun prolog-clause-start (&optional not-allow-methods)
  "Return the position at the start of the head of the current clause.
If NOTALLOWMETHODS is non-nil then do not match on methods in
objects (relevant only if `prolog-system' is set to `sicstus')."
  (save-excursion
    (let ((notdone t)
          (retval (point-min)))
      (end-of-line)

      ;; SICStus object?
      (if (and (not not-allow-methods)
               (eq prolog-system 'sicstus)
               (prolog-in-object))
          (while (and
                  notdone
                  ;; Search for a head or a fact
                  (re-search-backward
                   ;; If in object, then find method start.
                   ;; "^[ \t]+[a-z$].*\\(:-\\|&\\|:: {\\|,\\)"
                   "^[ \t]+[a-z$].*\\(:-\\|&\\|:: {\\)" ; The comma causes
                                        ; problems since we cannot assume
                                        ; that the line starts at column 0,
                                        ; thus we don't know if the line
                                        ; is a head or a subgoal
                   (point-min) t))
            (if (>= (prolog-paren-balance) 0) ; To no match on "   a) :-"
                ;; Start of method found
                (progn
                  (setq retval (point))
                  (setq notdone nil)))
            )                                ; End of while

        ;; Not in object
        (while (and
                notdone
                ;; Search for a text at beginning of a line
                ;; ######
                ;; (re-search-backward "^[a-z$']" nil t))
                (let ((case-fold-search nil))
                  (re-search-backward "^\\([[:lower:]$']\\|[:?]-\\)"
                                      nil t)))
          (let ((bal (prolog-paren-balance)))
            (cond
             ((> bal 0)
              ;; Start of clause found
              (progn
                (setq retval (point))
                (setq notdone nil)))
             ((and (= bal 0)
                   (looking-at
                    (format ".*\\(\\.\\|%s\\|!,\\)[ \t]*\\(%%.*\\|\\)$"
                            prolog-head-delimiter)))
              ;; Start of clause found if the line ends with a '.' or
              ;; a prolog-head-delimiter
              (progn
                (setq retval (point))
                (setq notdone nil))
              )
             (t nil) ; Do nothing
             ))))

        retval)))

(defun prolog-clause-end (&optional not-allow-methods)
  "Return the position at the end of the current clause.
If NOTALLOWMETHODS is non-nil then do not match on methods in
objects (relevant only if `prolog-system' is set to `sicstus')."
  (save-excursion
    (beginning-of-line) ; Necessary since we use "^...." for the search.
    (if (re-search-forward
         (if (and (not not-allow-methods)
                  (eq prolog-system 'sicstus)
                  (prolog-in-object))
             (format
              "^\\(%s\\|%s\\|[^\n'\"%%]\\)*&[ \t]*\\(\\|%%.*\\)$\\|[ \t]*}"
              prolog-quoted-atom-regexp prolog-string-regexp)
           (format
            "^\\(%s\\|%s\\|[^\n'\"%%]\\)*\\.[ \t]*\\(\\|%%.*\\)$"
            prolog-quoted-atom-regexp prolog-string-regexp))
         nil t)
        (if (and (nth 8 (syntax-ppss))
                 (not (eobp)))
            (progn
              (forward-char)
              (prolog-clause-end))
          (point))
      (point))))

(defun prolog-clause-info ()
  "Return a (name arity) list for the current clause."
  (save-excursion
    (goto-char (prolog-clause-start))
    (let* ((op (point))
           (predname
            (if (looking-at prolog-atom-char-regexp)
                (progn
                  (skip-chars-forward "^ (.")
                  (buffer-substring op (point)))
              ""))
           (arity 0))
      ;; Retrieve the arity.
      (if (looking-at prolog-left-paren)
          (let ((endp (save-excursion
                        (forward-list) (point))))
            (setq arity 1)
            (forward-char 1)            ; Skip the opening paren.
            (while (progn
                     (skip-chars-forward "^[({,'\"")
                     (< (point) endp))
              (if (looking-at ",")
                  (progn
                    (setq arity (1+ arity))
                    (forward-char 1)    ; Skip the comma.
                    )
                ;; We found a string, list or something else we want
                ;; to skip over.
                (forward-sexp 1))
              )))
      (list predname arity))))

(defun prolog-in-object ()
  "Return object name if the point is inside a SICStus object definition."
  ;; Return object name if the last line that starts with a character
  ;; that is neither white space nor a comment start
  (save-excursion
    (if (save-excursion
          (beginning-of-line)
          (looking-at "\\([^\n ]+\\)[ \t]*::[ \t]*{"))
        ;; We were in the head of the object
        (match-string 1)
      ;; We were not in the head
      (if (and (re-search-backward "^[a-z$'}]" nil t)
               (looking-at "\\([^\n ]+\\)[ \t]*::[ \t]*{"))
          (match-string 1)
        nil))))

(defun prolog-beginning-of-clause ()
  "Move to the beginning of current clause.
If already at the beginning of clause, move to previous clause."
  (interactive)
  (let ((point (point))
        (new-point (prolog-clause-start)))
    (if (and (>= new-point point)
             (> point 1))
        (progn
          (goto-char (1- point))
          (goto-char (prolog-clause-start)))
      (goto-char new-point)
      (skip-chars-forward " \t"))))

;; (defun prolog-previous-clause ()
;;   "Move to the beginning of the previous clause."
;;   (interactive)
;;   (forward-char -1)
;;   (prolog-beginning-of-clause))

(defun prolog-end-of-clause ()
  "Move to the end of clause.
If already at the end of clause, move to next clause."
  (interactive)
  (let ((point (point))
        (new-point (prolog-clause-end)))
    (if (and (<= new-point point)
             (not (eq new-point (point-max))))
        (progn
          (goto-char (1+ point))
          (goto-char (prolog-clause-end)))
      (goto-char new-point))))

;; (defun prolog-next-clause ()
;;   "Move to the beginning of the next clause."
;;   (interactive)
;;   (prolog-end-of-clause)
;;   (forward-char)
;;   (prolog-end-of-clause)
;;   (prolog-beginning-of-clause))

(defun prolog-beginning-of-predicate ()
  "Go to the nearest beginning of predicate before current point.
Return the final point or nil if no such a beginning was found."
  ;; FIXME: Hook into beginning-of-defun.
  (interactive)
  (let ((op (point))
        (pos (prolog-pred-start)))
    (if pos
        (if (= op pos)
            (if (not (bobp))
                (progn
                  (goto-char pos)
                  (backward-char 1)
                  (setq pos (prolog-pred-start))
                  (if pos
                      (progn
                        (goto-char pos)
                        (point)))))
          (goto-char pos)
          (point)))))

(defun prolog-end-of-predicate ()
  "Go to the end of the current predicate."
  ;; FIXME: Hook into end-of-defun.
  (interactive)
  (let ((op (point)))
    (goto-char (prolog-pred-end))
    (if (= op (point))
        (progn
          (forward-line 1)
          (prolog-end-of-predicate)))))

(defun prolog-insert-predspec ()
  "Insert the predspec for the current predicate."
  (interactive)
  (let* ((pinfo (prolog-clause-info))
         (predname (nth 0 pinfo))
         (arity (nth 1 pinfo)))
    (insert (format "%s/%d" predname arity))))

(defun prolog-view-predspec ()
  "Insert the predspec for the current predicate."
  (interactive)
  (let* ((pinfo (prolog-clause-info))
         (predname (nth 0 pinfo))
         (arity (nth 1 pinfo)))
    (message "%s/%d" predname arity)))

(defun prolog-insert-predicate-template ()
  "Insert the template for the current clause."
  (interactive)
  (let* ((n 1)
         oldp
         (pinfo (prolog-clause-info))
         (predname (nth 0 pinfo))
         (arity (nth 1 pinfo)))
    (insert predname)
    (if (> arity 0)
        (progn
          (insert "(")
 	  (when prolog-electric-dot-full-predicate-template
 	    (setq oldp (point))
 	    (while (< n arity)
 	      (insert ",")
 	      (setq n (1+ n)))
 	    (insert ")")
 	    (goto-char oldp))
          ))
  ))

(defun prolog-insert-next-clause ()
  "Insert newline and the name of the current clause."
  (interactive)
  (insert "\n")
  (prolog-insert-predicate-template))

(defun prolog-insert-module-modeline ()
  "Insert a modeline for module specification.
This line should be first in the buffer.
The module name should be written manually just before the semi-colon."
  (interactive)
  (insert "%%% -*- Module: ; -*-\n")
  (backward-char 6))

(define-obsolete-function-alias 'prolog-uncomment-region
  'uncomment-region "28.1")

(defun prolog-indent-predicate ()
  "Indent the current predicate."
  (interactive)
  (indent-region (prolog-pred-start) (prolog-pred-end) nil))

(defun prolog-indent-buffer ()
  "Indent the entire buffer."
  (interactive)
  (indent-region (point-min) (point-max) nil))

(defun prolog-mark-clause ()
  "Put mark at the end of this clause and move point to the beginning."
  (interactive)
  (let ((pos (point)))
    (goto-char (prolog-clause-end))
    (forward-line 1)
    (beginning-of-line)
    (set-mark (point))
    (goto-char pos)
    (goto-char (prolog-clause-start))))

(defun prolog-mark-predicate ()
  "Put mark at the end of this predicate and move point to the beginning."
  (interactive)
  (goto-char (prolog-pred-end))
  (let ((pos (point)))
    (forward-line 1)
    (beginning-of-line)
    (set-mark (point))
    (goto-char pos)
    (goto-char (prolog-pred-start))))

(defun prolog-electric--colon ()
  "If `prolog-electric-colon-flag' is non-nil, insert the electric `:' construct.
That is, insert space (if appropriate), `:-' and newline if colon is pressed
at the end of a line that starts in the first column (i.e., clause heads)."
  (when (and prolog-electric-colon-flag
             (eq (char-before) ?:)
             (not current-prefix-arg)
             (eolp)
             (not (memq (char-after (line-beginning-position))
                        '(?\s ?\t ?\%))))
    (unless (memq (char-before (1- (point))) '(?\s ?\t))
      (save-excursion (forward-char -1) (insert " ")))
    (insert "-\n")
    (indent-according-to-mode)))

(defun prolog-electric--dash ()
  "If `prolog-electric-dash-flag' is non-nil, insert the electric `-' construct.
that is, insert space (if appropriate), `-->' and newline if dash is pressed
at the end of a line that starts in the first column (i.e., DCG heads)."
  (when (and prolog-electric-dash-flag
             (eq (char-before) ?-)
             (not current-prefix-arg)
             (eolp)
             (not (memq (char-after (line-beginning-position))
                        '(?\s ?\t ?\%))))
    (unless (memq (char-before (1- (point))) '(?\s ?\t))
      (save-excursion (forward-char -1) (insert " ")))
    (insert "->\n")
    (indent-according-to-mode)))

(defun prolog-electric--dot ()
  "Make dot electric, if `prolog-electric-dot-flag' is non-nil.
When invoked at the end of nonempty line, insert dot and newline.
When invoked at the end of an empty line, insert a recursive call to
the current predicate.
When invoked at the beginning of line, insert a head of a new clause
of the current predicate."
  ;; Check for situations when the electricity should not be active
  (if (or (not prolog-electric-dot-flag)
          (not (eq (char-before) ?\.))
          current-prefix-arg
          (nth 8 (syntax-ppss))
          ;; Do not be electric in a floating point number or an operator
          (not
           (save-excursion
             (forward-char -1)
             (skip-chars-backward " \t")
             (let ((num (> (skip-chars-backward "0-9") 0)))
               (or (bolp)
                   (memq (char-syntax (char-before))
                         (if num '(?w ?_) '(?\) ?w ?_)))))))
          ;; Do not be electric if inside a parenthesis pair.
          (not (= (car (syntax-ppss))
                  0))
          )
      nil ;;Not electric.
    (cond
     ;; Beginning of line
     ((save-excursion (forward-char -1) (bolp))
      (delete-region (1- (point)) (point)) ;Delete the dot that called us.
      (prolog-insert-predicate-template))
     ;; At an empty line with at least one whitespace
     ((save-excursion
        (beginning-of-line)
        (looking-at "[ \t]+\\.$"))
      (delete-region (1- (point)) (point)) ;Delete the dot that called us.
      (prolog-insert-predicate-template)
      (when prolog-electric-dot-full-predicate-template
 	(save-excursion
 	  (end-of-line)
 	  (insert ".\n"))))
     ;; Default
     (t
      (insert "\n"))
     )))

(defun prolog-electric--underscore ()
  "Replace variable with an underscore.
If `prolog-electric-underscore-flag' is non-nil and the point is
on a variable then replace the variable with underscore and skip
the following comma and whitespace, if any."
  (when prolog-electric-underscore-flag
    (let ((case-fold-search nil))
      (when (and (not (nth 8 (syntax-ppss)))
                 (eq (char-before) ?_)
                 (save-excursion
                   (skip-chars-backward "[:alpha:]_")
                   (looking-at "\\_<[_[:upper:]][[:alnum:]_]*\\_>")))
        (replace-match "_")
        (skip-chars-forward ", \t\n")))))

(defun prolog-post-self-insert ()
  (pcase last-command-event
    (?_ (prolog-electric--underscore))
    (?- (prolog-electric--dash))
    (?: (prolog-electric--colon))
    ((or ?\( ?\; ?>) (prolog-electric--if-then-else))
    (?. (prolog-electric--dot))))

(defun prolog-find-term (functor arity &optional prefix)
  "Go to the position at the start of the next occurrence of a term.
The term is specified with FUNCTOR and ARITY.  The optional argument
PREFIX is the prefix of the search regexp."
  (let* (;; If prefix is not set then use the default "\\<"
         (prefix (if (not prefix)
                     "\\<"
                   prefix))
         (regexp (concat prefix functor))
         (i 1))

    ;; Build regexp for the search if the arity is > 0
    (if (= arity 0)
        ;; Add that the functor must be at the end of a word. This
        ;; does not work if the arity is > 0 since the closing )
        ;; is not a word constituent.
        (setq regexp (concat regexp "\\>"))
      ;; Arity is > 0, add parens and commas
      (setq regexp (concat regexp "("))
      (while (< i arity)
        (setq regexp (concat regexp ".+,"))
        (setq i (1+ i)))
      (setq regexp (concat regexp ".+)")))

    ;; Search, and return position
    (if (re-search-forward regexp nil t)
        (goto-char (match-beginning 0))
      (error "Term not found"))
    ))

(defun prolog-variables-to-anonymous (beg end)
  "Replace all variables within a region BEG to END by anonymous variables."
  (interactive "r")
  (save-excursion
    (let ((case-fold-search nil))
      (goto-char end)
      (while (re-search-backward "\\<[A-Z_][a-zA-Z_0-9]*\\>" beg t)
        (progn
          (replace-match "_")
          (backward-char)))
      )))

;;(defun prolog-regexp-dash-continuous-chars (chars)
;;  (let ((ints (mapcar #'prolog-char-to-int (string-to-list chars)))
;;        (beg 0)
;;        (end 0))
;;    (if (null ints)
;;        chars
;;      (while (and (< (+ beg 1) (length chars))
;;                  (not (or (= (+ (nth beg ints) 1) (nth (+ beg 1) ints))
;;                           (= (nth beg ints) (nth (+ beg 1) ints)))))
;;        (setq beg (+ beg 1)))
;;      (setq beg (+ beg 1)
;;            end beg)
;;      (while (and (< (+ end 1) (length chars))
;;                  (or (= (+ (nth end ints) 1) (nth (+ end 1) ints))
;;                      (= (nth end ints) (nth (+ end 1) ints))))
;;        (setq end (+ end 1)))
;;      (if (equal (substring chars end) "")
;;          (substring chars 0 beg)
;;        (concat (substring chars 0 beg) "-"
;;                (prolog-regexp-dash-continuous-chars (substring chars end))))
;;    )))

;;(defun prolog-condense-character-sets (regexp)
;;  "Condense adjacent characters in character sets of REGEXP."
;;  (let ((next -1))
;;    (while (setq next (string-match "\\[\\(.*?\\)\\]" regexp (1+ next)))
;;      (setq regexp (replace-match (prolog-dash-letters (match-string 1 regexp))
;;				  t t regexp 1))))
;;  regexp)

;;-------------------------------------------------------------------
;; Menu stuff (both for the editing buffer and for the inferior
;; prolog buffer)
;;-------------------------------------------------------------------

;; GNU Emacs ignores `easy-menu-add' so the order in which the menus
;; are defined _is_ important!

(easy-menu-define
  prolog-menu-help (list prolog-mode-map prolog-inferior-mode-map)
  "Help menu for the Prolog mode."
  ;; FIXME: Does it really deserve a whole menu to itself?
  `("Prolog-help"
    ["On predicate" prolog-help-on-predicate prolog-help-function-i]
    ["Apropos" prolog-help-apropos (eq prolog-system 'swi)]
    "---"
    ["Describe mode" describe-mode t]))

(easy-menu-define
  prolog-edit-menu-runtime prolog-mode-map
  "Runtime Prolog commands available from the editing buffer."
  ;; FIXME: Don't use a whole menu for just "Run Mercury".  --Stef
  `("System"
    ;; Runtime menu name.
    :label (cond ((eq prolog-system 'eclipse) "ECLiPSe")
                 ((eq prolog-system 'mercury) "Mercury")
                 (t "System"))
    ;; Consult items, NIL for mercury.
    ["Consult file" prolog-consult-file
     :included (not (eq prolog-system 'mercury))]
    ["Consult buffer" prolog-consult-buffer
     :included (not (eq prolog-system 'mercury))]
    ["Consult region" prolog-consult-region :active (use-region-p)
     :included (not (eq prolog-system 'mercury))]
    ["Consult predicate" prolog-consult-predicate
     :included (not (eq prolog-system 'mercury))]

    ;; Compile items, NIL for everything but SICSTUS.
    ["---" nil :included (eq prolog-system 'sicstus)]
    ["Compile file" prolog-compile-file
     :included (eq prolog-system 'sicstus)]
    ["Compile buffer" prolog-compile-buffer
     :included (eq prolog-system 'sicstus)]
    ["Compile region" prolog-compile-region :active (use-region-p)
     :included (eq prolog-system 'sicstus)]
    ["Compile predicate" prolog-compile-predicate
     :included (eq prolog-system 'sicstus)]

    ;; Debug items, NIL for Mercury.
    ["---" nil :included (not (eq prolog-system 'mercury))]
    ;; FIXME: Could we use toggle or radio buttons?  --Stef
    ["Debug" prolog-debug-on :included (not (eq prolog-system 'mercury))]
    ["Debug off" prolog-debug-off
     ;; In SICStus, these are pairwise disjunctive,
     ;; so it's enough with a single "off"-command
     :included (not (memq prolog-system '(mercury sicstus)))]
    ["Trace" prolog-trace-on :included (not (eq prolog-system 'mercury))]
    ["Trace off" prolog-trace-off
     :included (not (memq prolog-system '(mercury sicstus)))]
    ["Zip" prolog-zip-on :included (and (eq prolog-system 'sicstus)
                                        (prolog-atleast-version '(3 . 7)))]
    ["All debug off" prolog-debug-off
     :included (eq prolog-system 'sicstus)]
    ["Source level debugging"
     prolog-toggle-sicstus-sd
     :included (and (eq prolog-system 'sicstus)
                    (prolog-atleast-version '(3 . 7)))
     :style toggle
     :selected prolog-use-sicstus-sd]

    "---"
    ["Run" run-prolog
     :suffix (cond ((eq prolog-system 'eclipse) "ECLiPSe")
                   ((eq prolog-system 'mercury) "Mercury")
                   (t "Prolog"))]))

(easy-menu-define
  prolog-edit-menu-insert-move prolog-mode-map
  "Commands for Prolog code manipulation."
  '("Prolog"
    ["Comment region" comment-region (use-region-p)]
    ["Uncomment region" uncomment-region (use-region-p)]
    ["Add comment/move to comment" indent-for-comment t]
    ["Convert variables in region to '_'" prolog-variables-to-anonymous
     :active (use-region-p) :included (not (eq prolog-system 'mercury))]
    "---"
    ["Insert predicate template" prolog-insert-predicate-template t]
    ["Insert next clause head" prolog-insert-next-clause t]
    ["Insert predicate spec" prolog-insert-predspec t]
    ["Insert module modeline" prolog-insert-module-modeline t]
    "---"
    ["Beginning of clause" prolog-beginning-of-clause t]
    ["End of clause" prolog-end-of-clause t]
    ["Beginning of predicate" prolog-beginning-of-predicate t]
    ["End of predicate" prolog-end-of-predicate t]
    "---"
    ["Indent line" indent-according-to-mode t]
    ["Indent region" indent-region (use-region-p)]
    ["Indent predicate" prolog-indent-predicate t]
    ["Indent buffer" prolog-indent-buffer t]
    ["Align region" align (use-region-p)]
    "---"
    ["Mark clause" prolog-mark-clause t]
    ["Mark predicate" prolog-mark-predicate t]
    ["Mark paragraph" mark-paragraph t]
    ))

(defun prolog-menu ()
  "Add the menus for the Prolog editing buffers."

  ;; Add predicate index menu
  (setq-local imenu-create-index-function
              'imenu-default-create-index-function)
  ;;Milan (this has problems with object methods...)  ###### Does it? (Stefan)
  (setq-local imenu-prev-index-position-function
              #'prolog-beginning-of-predicate)
  (setq-local imenu-extract-index-name-function #'prolog-get-predspec)

  (if (and prolog-imenu-flag
           (< (count-lines (point-min) (point-max)) prolog-imenu-max-lines))
      (imenu-add-to-menubar "Predicates")))

(easy-menu-define
  prolog-inferior-menu-all prolog-inferior-mode-map
  "Menu for the inferior Prolog buffer."
  `("Prolog"
    ;; Runtime menu name.
    :label (cond ((eq prolog-system 'eclipse) "ECLiPSe")
                 ((eq prolog-system 'mercury) "Mercury")
                 (t "Prolog"))
    ;; Debug items, NIL for Mercury.
    ["---" nil :included (not (eq prolog-system 'mercury))]
    ;; FIXME: Could we use toggle or radio buttons?  --Stef
    ["Debug" prolog-debug-on :included (not (eq prolog-system 'mercury))]
    ["Debug off" prolog-debug-off
     ;; In SICStus, these are pairwise disjunctive,
     ;; so it's enough with a single "off"-command
     :included (not (memq prolog-system '(mercury sicstus)))]
    ["Trace" prolog-trace-on :included (not (eq prolog-system 'mercury))]
    ["Trace off" prolog-trace-off
     :included (not (memq prolog-system '(mercury sicstus)))]
    ["Zip" prolog-zip-on :included (and (eq prolog-system 'sicstus)
                                        (prolog-atleast-version '(3 . 7)))]
    ["All debug off" prolog-debug-off
     :included (eq prolog-system 'sicstus)]
    ["Source level debugging"
     prolog-toggle-sicstus-sd
     :included (and (eq prolog-system 'sicstus)
                    (prolog-atleast-version '(3 . 7)))
     :style toggle
     :selected prolog-use-sicstus-sd]

    ;; Runtime.
    "---"
    ["Interrupt Prolog" comint-interrupt-subjob t]
    ["Quit Prolog" comint-quit-subjob t]
    ["Kill Prolog" comint-kill-subjob t]))


(defun prolog-inferior-menu ()
  "Create the menus for the Prolog inferior buffer.
This menu is dynamically created because one may change systems during
the life of an Emacs session."
  (declare (obsolete nil "28.1"))
  nil)

(defun prolog-mode-version ()
  "Echo the current version of Prolog mode in the minibuffer."
  (interactive)
  (message "Using Prolog mode version %s" prolog-mode-version))

(provide 'prolog)

;;; prolog.el ends here
