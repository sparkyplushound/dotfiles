;;; erc-track.el --- Track modified channel buffers  -*- lexical-binding:t -*-

;; Copyright (C) 2002-2025 Free Software Foundation, Inc.

;; Author: Mario Lang <mlang@delysid.org>
;; Maintainer: Amin Bandali <bandali@gnu.org>, F. Jason Park <jp@neverwas.me>
;; Keywords: comm
;; URL: https://www.emacswiki.org/emacs/ErcChannelTracking

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

;; Highlights keywords and pals (friends), and hides or highlights fools
;; (using a dark color).  Add to your init file:

;; (require 'erc-track)
;; (erc-track-mode 1)

;; Todo:
;; * Add extensibility so that custom functions can track
;;   custom modification types.

(eval-when-compile (require 'cl-lib))
(require 'erc)
(require 'erc-match)

;;; Code:

(defgroup erc-track nil
  "Track active buffers and show activity in the mode line."
  :group 'erc)

(defcustom erc-track-enable-keybindings 'ask
  "Whether to enable the ERC track keybindings, namely:
\\`C-c C-SPC' and \\`C-c C-@', which both do the same thing.

The default is to check to see whether these keys are used
already: if not, then enable the ERC track minor mode, which
provides these keys.  Otherwise, do not touch the keys.

This can alternatively be set to either t or nil, which indicate
respectively always to enable ERC track minor mode or never to
enable ERC track minor mode.

The reason for using this default value is to both (1) adhere to
the Emacs development guidelines which say not to touch keys of
the form C-c C-<something> and also (2) to meet the expectations
of long-time ERC users, many of whom rely on these keybindings."
  :type '(choice (const :tag "Ask, if used already" ask)
		 (const :tag "Enable" t)
		 (const :tag "Disable" nil)))

(defcustom erc-track-visibility t
  "Where do we look for buffers to determine their visibility?
The value of this variable determines, when a buffer is considered
visible or invisible.  New messages in invisible buffers are tracked,
while switching to visible buffers when they are tracked removes them
from the list.  See also `erc-track-when-inactive'.

Possible values are:

t                - all frames
visible          - all visible frames
nil              - only the selected frame
selected-visible - only the selected frame if it is visible

Activity means that there was no user input in the last 10 seconds."
  :type  '(choice (const :tag "All frames" t)
		  (const :tag "All visible frames" visible)
		  (const :tag "Only the selected frame" nil)
		  (const :tag "Only the selected frame if it is visible"
			 selected-visible)))

(defcustom erc-track-exclude nil
  "A list targets (channel names or query targets) which should not be tracked."
  :type '(repeat string))

(defcustom erc-track-remove-disconnected-buffers nil
  "If true, remove buffers associated with a server that is
disconnected from `erc-modified-channels-alist'."
  :type 'boolean)

(defcustom erc-track-exclude-types '("NICK" "333" "353")
  "List of message types to be ignored.
This list could look like (\"JOIN\" \"PART\").

By default, exclude changes of nicknames (NICK), display of who
set the channel topic (333), and listing of users on the current
channel (353)."
  :type 'erc-message-type)

(defcustom erc-track-exclude-server-buffer nil
  "If true, don't perform tracking on the server buffer.
This is useful for excluding all the things like MOTDs from the
server and other miscellaneous functions."
  :type 'boolean)

(defcustom erc-track-shorten-start 1
  "Minimum number of characters for a channel name in the mode-line."
  :type 'number)

(defcustom erc-track-shorten-cutoff 4
  "All channel names longer than this value will be shortened."
  :type 'number)

(defcustom erc-track-shorten-aggressively nil
  "If non-nil, channel names will be shortened more aggressively.
Usually, names are not shortened if this will save only one character.
Example: If there are two channels, #linux-de and #linux-fr, then
normally these will not be shortened.  When shortening aggressively,
however, these will be shortened to #linux-d and #linux-f.

If this variable is set to `max', then channel names will be shortened
to the max.  Usually, shortened channel names will remain unique for a
given set of existing channels.  When shortening to the max, the shortened
channel names will be unique for the set of active channels only.
Example: If there are two active channels #emacs and #vi, and two inactive
channels #electronica and #folk, then usually the active channels are
shortened to #em and #v.  When shortening to the max, however, #emacs is
not compared to #electronica -- only to #vi, therefore it can be shortened
even more and the result is #e and #v.

This setting is used by `erc-track-shorten-names'."
  :type '(choice (const :tag "No" nil)
		 (const :tag "Yes" t)
		 (const :tag "Max" max)))

(defcustom erc-track-shorten-function 'erc-track-shorten-names
  "Function used to reduce the channel names before display.
It takes one argument, CHANNEL-NAMES which is a list of strings.
It should return a list of strings of the same number of elements.
If nil instead of a function, shortening is disabled."
  :type '(choice (const :tag "Disabled")
		 function))

(defcustom erc-track-list-changed-hook nil
  "Hook run when the contents of `erc-modified-channels-alist' changes.

This is useful for people that don't use the default mode-line
notification but instead use a separate mechanism to provide
notification of channel activity."
  :type 'hook)

(defcustom erc-track-use-faces t
  "Use faces in the mode-line.
The faces used are the same as used for text in the buffers.
\(e.g. `erc-pal-face' is used if a pal sent a message to that channel.)"
  :type 'boolean)

(defun erc-track--massage-nick-button-faces (sym val &optional set-fn)
  "Transform VAL of face-list option SYM to have new defaults.
Use `set'-compatible SET-FN when given.  If an update was
performed, set the symbol property `erc-track--obsolete-faces' of
SYM to t."
  (let* ((changedp nil)
         (new (mapcar
               (lambda (f)
                 (if (and (eq (car-safe f) 'erc-nick-default-face)
                          (equal f '(erc-nick-default-face erc-default-face)))
                     (progn
                       (setq changedp t)
                       (put sym 'erc-track--obsolete-faces t)
                       (cons 'erc-button-nick-default-face (cdr f)))
                   f))
               val)))
    (if set-fn
        (funcall set-fn sym (if changedp new val))
      (set-default sym (if changedp new val)))))

(defcustom erc-track-faces-priority-list
  '(erc-error-face
    erc-current-nick-face
    erc-keyword-face
    erc-pal-face
    erc-nick-msg-face
    erc-direct-msg-face
    (erc-button erc-default-face)
    erc-dangerous-host-face
    erc-nick-default-face
    (erc-button-nick-default-face erc-default-face)
    erc-default-face
    erc-action-face
    erc-fool-face
    erc-notice-face
    erc-input-face
    erc-prompt-face)
  "A list of faces used to highlight active buffer names in the mode line.
If a message contains one of the faces in this list, the buffer name will
be highlighted using that face.  The first matching face is used.

Note that ERC prioritizes certain faces reserved for critical
messages regardless of this option's value."
  :package-version '(ERC . "5.6")
  :set #'erc-track--massage-nick-button-faces
  :type (erc--with-dependent-type-match
         (repeat (choice face (repeat :tag "Combination" face)))
         erc-button))

(defcustom erc-track-priority-faces-only nil
  "Only track text highlighted with a priority face.
If you would like to ignore changes in certain channels where there
are no faces corresponding to your `erc-track-faces-priority-list', set
this variable.  You can set a list of channel name strings, so those
will be ignored while all other channels will be tracked as normal.
Other options are `all', to apply this to all channels or nil, to disable
this feature.

Note: If you have a lot of faces listed in `erc-track-faces-priority-list',
setting this variable might not be very useful."
  :type '(choice (const nil)
		 (repeat string)
		 (const all)))

(defcustom erc-track-faces-normal-list
  '((erc-button erc-default-face)
    erc-dangerous-host-face
    erc-nick-default-face
    (erc-button-nick-default-face erc-default-face)
    erc-default-face
    erc-action-face)
  "A list of faces considered to be part of normal conversations.
This list is used to highlight active buffer names in the mode line.

If a message contains one of the faces in this list, and the
previous mode line face for this buffer is also in this list, then
the buffer name will be highlighted using the face from the
message.  This gives a rough indication that active conversations
are occurring in these channels.

Note that ERC makes a copy of this option when initializing the
module.  To see your changes reflected mid-session, cycle
\\[erc-track-mode].

The effect may be disabled by setting this variable to nil."
  :package-version '(ERC . "5.6")
  :set #'erc-track--massage-nick-button-faces
  :type (erc--with-dependent-type-match
         (repeat (choice face (repeat :tag "Combination" face)))
         erc-button))

(defvar erc-track-ignore-normal-contenders-p nil
  "Compatibility flag to promote only exclusively new \"normal\" faces.
When non-nil, revert to pre-5.6 behavior in which only a current
mode-line face that both outranks and is absent from the current
message is eligible for replacement by a fellow face from
`erc-track-faces-normal-list' that does appear in the message.
By extension, when enabled, never replace the current, reigning
mode-line face if it's present in the current message.  May be
incompatible with modules introduced after ERC 5.5.")

(defcustom erc-track-position-in-mode-line 'before-modes
  "Where to show modified channel information in the mode-line.

Choices are:
`before-modes' - add to the beginning of `mode-line-modes',
`after-modes'  - add to the end of `mode-line-modes',
t              - add to the end of `global-mode-string',
nil            - don't add to mode line."
  :type '(choice (const :tag "Just before mode information" before-modes)
		 (const :tag "Just after mode information" after-modes)
		 (const :tag "After all other information" t)
		 (const :tag "Don't display in mode line" nil))
  :set (lambda (sym val)
	 (set sym val)
	 (when (and (boundp 'erc-track-mode)
		    erc-track-mode)
	   (erc-track-remove-from-mode-line)
	   (erc-track-add-to-mode-line val))))

(defun erc-modified-channels-object (strings)
  "Generate a new `erc-modified-channels-object' based on STRINGS."
  (if strings
      (concat (if (eq erc-track-position-in-mode-line 'after-modes)
		  "[" " [")
	      (mapconcat #'identity (nreverse strings) ",")
	      (if (eq erc-track-position-in-mode-line 'before-modes)
		  "] " "]"))
    ""))

(defvar erc-modified-channels-object (erc-modified-channels-object nil)
  "Internal object used for displaying modified channels in the mode line.")

(put 'erc-modified-channels-object 'risky-local-variable t); allow properties

(defvar erc-modified-channels-alist nil
  "An ALIST used for tracking channel modification activity.
Each element is a list of the form (BUFFER COUNT . FACE) where
BUFFER is a buffer object of the channel the entry corresponds
to, COUNT is a number indicating how often activity was noticed,
and FACE is a face (or a list of faces, combined as usual) to use
when displaying the buffer's name in the mode line.

Entries in this list are only added/updated for buffers that were
not visible when activity occurred in them, and are removed for
each buffer as soon as it becomes visible again (or if the server
is disconnected, provided `erc-track-remove-disconnected-buffers'
is true).

For how the face is chosen for a buffer, see
`erc-track-select-mode-line-face' and
`erc-track-priority-faces-only'.  For how buffers are then
displayed in the mode line, see `erc-modified-channels-display'.")

(defcustom erc-track-showcount nil
  "If non-nil, count of unseen messages will be shown for each channel."
  :type 'boolean)

(defcustom erc-track-showcount-string ":"
  "The string to display between buffer name and the count in the mode line.
The default is a colon, resulting in \"#emacs:9\"."
  :type 'string)

(defcustom erc-track-switch-from-erc t
  "If non-nil, `erc-track-switch-buffer' will return to the last non-erc buffer
when there are no more active channels."
  :type 'boolean)

(defcustom erc-track-switch-direction 'oldest
  "Direction `erc-track-switch-buffer' should switch.

  importance  -  find buffer with the most important message
  oldest      -  find oldest active buffer
  newest      -  find newest active buffer
  leastactive -  find buffer with least unseen messages
  mostactive  -  find buffer with most unseen messages.

If set to `importance', the importance is determined by position
in `erc-track-faces-priority-list', where first is most
important."
  :type '(choice (const importance)
		 (const oldest)
		 (const newest)
		 (const leastactive)
		 (const mostactive)))

(defconst erc-track--attn-faces '((erc-error-face erc-notice-face))
  "Faces whose presence always triggers mode-line inclusion.")

(defun erc-track-remove-from-mode-line ()
  "Remove `erc-track-modified-channels' from the mode-line."
  (setq mode-line-modes
	(remove '(t erc-modified-channels-object) mode-line-modes))
  (when (consp global-mode-string)
    (setq global-mode-string
	  (delq 'erc-modified-channels-object global-mode-string))))

(defun erc-track-add-to-mode-line (position)
  "Add `erc-track-modified-channels' to POSITION in the mode-line.
See `erc-track-position-in-mode-line' for possible values."
  ;; CVS Emacs has a new format string, and global-mode-string
  ;; is very far to the right.
  (cond ((eq position 'before-modes)
	 (add-to-list 'mode-line-modes
		      '(t erc-modified-channels-object)))
	((eq position 'after-modes)
	 (add-to-list 'mode-line-modes
		      '(t erc-modified-channels-object) t))
	((eq position t)
	 (when (not global-mode-string)
	   (setq global-mode-string '(""))) ; Padding for mode-line wart
	 (add-to-list 'global-mode-string
		      'erc-modified-channels-object
		      t))))

;;; Shortening of names

(defvar erc-track--shortened-names nil
  "A cons of the last novel name-shortening params and the result.
The CAR is a hash of environmental inputs such as options and
parameters passed to `erc-track-shorten-function'.  Its effect is
only really noticeable during batch processing.")

(defvar erc-track--shortened-names-current-hash nil)

(defun erc-track--shortened-names-set (_ shortened)
  "Remember SHORTENED names with hash of contextual params."
  (cl-assert erc-track--shortened-names-current-hash)
  (setq erc-track--shortened-names
        (cons erc-track--shortened-names-current-hash shortened)))

(defun erc-track--shortened-names-get (channel-names)
  "Cache CHANNEL-NAMES with various contextual parameters.
For now, omit relevant options like `erc-track-shorten-start' and
friends, even though they do affect the outcome, because they
likely change too infrequently to matter over sub-second
intervals and are unlikely to be let-bound or set locally."
  (when-let ((hash (setq erc-track--shortened-names-current-hash
                         (sxhash-equal (list channel-names
                                             (buffer-list)
                                             erc-track-shorten-function))))
             (erc-track--shortened-names)
             ((= hash (car erc-track--shortened-names))))
    (cdr erc-track--shortened-names)))

(gv-define-simple-setter erc-track--shortened-names-get
                         erc-track--shortened-names-set)

(defun erc-track-shorten-names (channel-names)
  "Call `erc-unique-channel-names' with the correct parameters.
This function is a good value for `erc-track-shorten-function'.
The list of all channels is returned by `erc-all-buffer-names'.
CHANNEL-NAMES is the list of active channel names.
Only channel names longer than `erc-track-shorten-cutoff' are
actually shortened, and they are only shortened to a minimum
of `erc-track-shorten-start' characters."
  (erc-unique-channel-names
   (erc-all-buffer-names)
   channel-names
   (lambda (s)
     (> (length s) erc-track-shorten-cutoff))
   erc-track-shorten-start))

(defun erc-all-buffer-names ()
  "Return all channel or query buffer names.
Note that we cannot use `erc-channel-list' with a nil argument,
because that does not return query buffers."
  (save-excursion
    (let (result)
      (dolist (buf (buffer-list))
	(set-buffer buf)
	(when (or (eq major-mode 'erc-mode) (eq major-mode 'erc-dcc-chat-mode))
	  (setq result (cons (buffer-name) result))))
      result)))

(defun erc-unique-channel-names (all active &optional predicate start)
  "Return a list of unique channel names.
ALL is the list of all channel and query buffer names.
ACTIVE is the list of active buffer names.
PREDICATE is a predicate that should return non-nil if a name needs
  no shortening.
START is the minimum length of the name used."
  (if (eq 'max erc-track-shorten-aggressively)
      ;; Return the unique substrings of all active channels.
      (erc-unique-substrings active predicate start)
    ;; Otherwise, determine the unique substrings of all channels, and
    ;; for every active channel, return the corresponding substring.
    ;; Given the names of the active channels, we now need to find the
    ;; corresponding short name from the list of all substrings.  To
    ;; avoid problems when there are two channels and one is a
    ;; substring of the other (notorious examples are #hurd and
    ;; #hurd-bunny), every candidate gets the longest possible
    ;; substring.
    (let ((all-substrings (sort
			   (erc-unique-substrings all predicate start)
			   (lambda (a b) (> (length a) (length b)))))
	  result)
      (dolist (channel active)
	(let ((substrings all-substrings)
	      candidate
	      winner)
	  (while (and substrings (not winner))
	    (setq candidate (car substrings)
		  substrings (cdr substrings))
	    (when (and (string= candidate
				(substring channel
					   0
					   (min (length candidate)
						(length channel))))
		       (not (member candidate result)))
	      (setq winner candidate)))
	  (setq result (cons winner result))))
      (nreverse result))))

(defun erc-unique-substrings (strings &optional predicate start)
  "Return a list of unique substrings of STRINGS."
  (if (or (not (numberp start))
	  (< start 0))
      (setq start 2))
  (mapcar
   (lambda (str)
     (let* ((others (delete str (copy-sequence strings)))
	    (maxlen (length str))
	    (i (min start
		    (length str)))
	    candidate
	    done)
       (if (and (functionp predicate) (not (funcall predicate str)))
	   ;; do not shorten if a predicate exists and it returns nil
	   str
	 ;; Start with smallest substring candidate, ie. length 1.
	 ;; Then check all the others and see whether any of them starts
	 ;; with the same substring.  While there is such another
	 ;; element in the list, increase the length of the candidate.
	 (while (not done)
	   (if (> i maxlen)
	       (setq done t)
	     (setq candidate (substring str 0 i)
		   done (not (erc-unique-substring-1 candidate others))))
	   (setq i (1+ i)))
	 (if (and (= (length candidate) (1- maxlen))
		  (not erc-track-shorten-aggressively))
	     str
	   candidate))))
   strings))

(defun erc-unique-substring-1 (candidate others)
  "Return non-nil when any string in OTHERS starts with CANDIDATE."
  (let (result other (maxlen (length candidate)))
    (while (and others
		(not result))
      (setq other (car others)
	    others (cdr others))
      (when (and (>= (length other) maxlen)
		 (string= candidate (substring other 0 maxlen)))
	(setq result other)))
    result))

;;; Minor mode

;; Play nice with other IRC clients (and Emacs development rules) by
;; making this a minor mode

(defvar erc-track-minor-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-@")   #'erc-track-switch-buffer)
    (define-key map (kbd "C-c C-SPC") #'erc-track-switch-buffer)
    map)
  "Keymap for ERC track minor mode.")

;;;###autoload
(define-minor-mode erc-track-minor-mode
  "Toggle mode line display of ERC activity (ERC Track minor mode).

ERC Track minor mode is a global minor mode.  It exists for the
sole purpose of providing the C-c C-SPC and C-c C-@ keybindings.
Make sure that you have enabled the track module, otherwise the
keybindings will not do anything useful."
  :global t)

(defun erc-track-minor-mode-maybe (&optional buffer)
  "Enable `erc-track-minor-mode', depending on `erc-track-enable-keybindings'."
  (when (and (not erc-track-minor-mode)
	     ;; don't start the minor mode until we have an ERC
	     ;; process running, because we don't want to prompt the
	     ;; user while starting Emacs
	     (or (and (buffer-live-p buffer)
		      (with-current-buffer buffer (eq major-mode 'erc-mode)))
		 (erc-buffer-list)))
    (cond ((eq erc-track-enable-keybindings 'ask)
	   (let ((key (or (and (key-binding (kbd "C-c C-SPC")) "C-SPC")
			  (and (key-binding (kbd "C-c C-@")) "C-@"))))
	     (if key
		 (if (y-or-n-p
		      (concat "The C-c " key " binding is in use;"
			      " override it for tracking? "))
		     (progn
		       (message (concat "Will change it; set"
					" `erc-track-enable-keybindings'"
					" to disable this message"))
		       (sleep-for 3)
		       (erc-track-minor-mode 1))
		   (message (concat "Not changing it; set"
				    " `erc-track-enable-keybindings'"
				    " to disable this message"))
		   (sleep-for 3))
	       (erc-track-minor-mode 1))))
	  ((eq erc-track-enable-keybindings t)
	   (erc-track-minor-mode 1))
	  (t nil))))

;;; Module

;;;###autoload(autoload 'erc-track-mode "erc-track" nil t)
(define-erc-module track nil
  "This mode tracks ERC channel buffers with activity."
  ;; Enable:
  ((when (boundp 'erc-track-when-inactive)
     (if erc-track-when-inactive
	 (progn
	   (add-hook 'window-configuration-change-hook #'erc-user-is-active)
	   (add-hook 'erc-send-completed-hook #'erc-user-is-active)
           ;; FIXME find out why this uses `erc-server-001-functions'.
           ;; `erc-user-is-active' runs when `erc-server-connected' is
           ;; non-nil.  But this hook usually only runs when it's nil.
	   (add-hook 'erc-server-001-functions #'erc-user-is-active))
       (erc-track-add-to-mode-line erc-track-position-in-mode-line)
       (erc-update-mode-line)
       (add-hook 'window-configuration-change-hook
		 #'erc-window-configuration-change)
       (add-hook 'erc-insert-post-hook #'erc-track-modified-channels)
       (add-hook 'erc-disconnected-hook #'erc-modified-channels-update))
     ;; enable the tracking keybindings
     (add-hook 'erc-connect-pre-hook #'erc-track-minor-mode-maybe)
     (erc-track-minor-mode-maybe))
   (add-hook 'erc-mode-hook #'erc-track--setup)
   (unless erc--updating-modules-p (erc-buffer-do #'erc-track--setup))
   (add-hook 'erc-networks--copy-server-buffer-functions
             #'erc-track--replace-killed-buffer))
  ;; Disable:
  ((when (boundp 'erc-track-when-inactive)
     (erc-track-remove-from-mode-line)
     (if erc-track-when-inactive
	 (progn
	   (remove-hook 'window-configuration-change-hook
			#'erc-user-is-active)
	   (remove-hook 'erc-send-completed-hook #'erc-user-is-active)
	   (remove-hook 'erc-server-001-functions #'erc-user-is-active)
           ;; FIXME remove this if unused.
	   (remove-hook 'erc-timer-hook #'erc-user-is-active))
       (remove-hook 'window-configuration-change-hook
		    #'erc-window-configuration-change)
       (remove-hook 'erc-disconnected-hook #'erc-modified-channels-update)
       (remove-hook 'erc-insert-post-hook #'erc-track-modified-channels))
     ;; disable the tracking keybindings
     (remove-hook 'erc-connect-pre-hook #'erc-track-minor-mode-maybe)
     (when erc-track-minor-mode
       (erc-track-minor-mode -1)))
   (remove-hook 'erc-mode-hook #'erc-track--setup)
   (erc-buffer-do #'erc-track--setup)
   (remove-hook 'erc-networks--copy-server-buffer-functions
                #'erc-track--replace-killed-buffer)))

;; FIXME move this above the module definition.
(defcustom erc-track-when-inactive nil
  "Enable channel tracking even for visible buffers, if you are inactive."
  :type 'boolean
  :set (lambda (sym val)
	 (if erc-track-mode
	     (progn
	       (erc-track-disable)
	       (set sym val)
	       (erc-track-enable))
	   (set sym val))))

(defvar-local erc-track--normal-faces nil
  "Local copy of `erc-track-faces-normal-list' as a hash table.")

(defun erc-track--setup ()
  "Initialize a buffer for use with the `track' module.
If this is a server buffer or `erc-track-faces-normal-list' is
locally bound, create a new `erc-track--normal-faces' for the
current buffer.  Otherwise, set the local value to the server
buffer's."
  (if erc-track-mode
      (let ((existing (erc-with-server-buffer erc-track--normal-faces))
            (localp (and erc--target
                         (local-variable-p 'erc-track-faces-normal-list)))
            (opts '(erc-track-faces-normal-list erc-track-faces-priority-list))
            warnp table)
        ;; Don't bother warning users who've disabled `button'.
        (unless (or erc--target (not (or (bound-and-true-p erc-button-mode)
                                         (memq 'button erc-modules))))
          (when (or localp (local-variable-p 'erc-track-faces-priority-list))
            (dolist (opt opts)
              (erc-track--massage-nick-button-faces opt (symbol-value opt)
                                                    #'set)))
          (dolist (opt opts)
            (when (get opt 'erc-track--obsolete-faces)
              (push opt warnp)
              (put opt 'erc-track--obsolete-faces nil)))
          (when warnp
            (erc--warn-once-before-connect 'erc-track-mode
              (if (cdr warnp) "Options " "Option ")
              (mapconcat (lambda (o) (format "`%S'" o)) warnp " and ")
              (if (cdr warnp) " contain" " contains")
              " an obsolete item, %S, intended to match buttonized nicknames."
              " ERC has changed it to %S for the current session."
              " Please save the current value to silence this message."
              '(erc-nick-default-face erc-default-face)
              '(erc-button-nick-default-face erc-default-face))))
        (when (or (null existing) localp)
          (setq table (map-into (mapcar (lambda (f) (cons f f))
                                        erc-track-faces-normal-list)
                                '(hash-table :test equal :weakness value))))
        (setq erc-track--normal-faces (or table existing))
        (unless (or localp existing)
          (erc-with-server-buffer (setq erc-track--normal-faces table))))
    (kill-local-variable 'erc-track--normal-faces)))

;;; Visibility

(defvar erc-buffer-activity nil
  "Last time the user sent something.")

(defvar erc-buffer-activity-timeout 10
  "How many seconds of inactivity by the user
to consider when `erc-track-visibility' is set to
only consider active buffers visible.")

(defun erc-user-is-active (&rest _ignore)
  "Set `erc-buffer-activity'."
  (when erc-server-connected
    (setq erc-buffer-activity (erc-current-time))
    (erc-track-modified-channels)))

(defun erc-track-get-buffer-window (buffer frame-param)
  (if (eq frame-param 'selected-visible)
      (if (eq (frame-visible-p (selected-frame)) t)
	  (get-buffer-window buffer nil)
	nil)
    (get-buffer-window buffer frame-param)))

(defun erc-buffer-visible (buffer)
  "Return non-nil when the buffer is visible."
  (if erc-track-when-inactive
      (when erc-buffer-activity; could be nil
	(and (erc-track-get-buffer-window buffer erc-track-visibility)
	     (not (time-less-p erc-buffer-activity-timeout
			       (erc-time-diff erc-buffer-activity nil)))))
    (erc-track-get-buffer-window buffer erc-track-visibility)))

;;; Tracking the channel modifications

(defun erc-window-configuration-change ()
  (unless (minibuffer-window-active-p (minibuffer-window))
    ;; delay this until command has finished to make sure window is
    ;; actually visible before clearing activity
    (erc-modified-channels-update)))

(defvar erc-modified-channels-update-inside nil
  "Variable to prevent running `erc-modified-channels-update' multiple times.
Without it, you cannot debug `erc-modified-channels-display',
because the debugger also causes changes to the
window-configuration.")

(defun erc-modified-channels-update (&rest _args)
  "Update `erc-modified-channels-alist' according to buffer visibility.
It calls `erc-modified-channels-display' at the end.  This should
usually be called via `window-configuration-change-hook'.
ARGS are ignored."
  (interactive)
  (unless erc-modified-channels-update-inside
    (let ((erc-modified-channels-update-inside t)
	  (removed-channel nil))
      (mapc (lambda (elt)
	      (let ((buffer (car elt)))
		(when (or (not (bufferp buffer))
			  (not (buffer-live-p buffer))
			  (erc-buffer-visible buffer)
			  (and erc-track-remove-disconnected-buffers
			       (not (with-current-buffer buffer
				      erc-server-connected))))
		  (setq removed-channel t)
		  (erc-modified-channels-remove-buffer buffer))))
	    erc-modified-channels-alist)
      (when removed-channel
	(erc-modified-channels-display)))))

(defvar erc-track-mouse-face 'mode-line-highlight
  "The face to use when mouse is over channel names in the mode line.")

(defun erc-make-mode-line-buffer-name (string buffer &optional faces count)
  "Return a button that switches to BUFFER when clicked.
STRING is the string in the button.  It is possibly suffixed with
the number of unread messages, according to variables
`erc-track-showcount' and `erc-track-showcount-string'.

If `erc-track-use-faces' is true and FACES are provided, format
STRING with them.  When the mouse hovers above the button, STRING
is displayed according to `erc-track-mouse-face'."
  ;; We define a new sparse keymap every time, because 1. this data
  ;; structure is very small, the alternative would require us to
  ;; defvar a keymap, 2. the user is not interested in customizing it
  ;; (really?), 3. the defun needs to switch to BUFFER, so we would
  ;; need to save that value somewhere.
  (let ((map (make-sparse-keymap))
	(name (if erc-track-showcount
		  (concat string
			  erc-track-showcount-string
			  (int-to-string count))
		(copy-sequence string))))
    (define-key map (vector 'mode-line 'mouse-2)
      (lambda (e)
	(interactive "e")
	(save-selected-window
	  (select-window
	   (posn-window (event-start e)))
	  (switch-to-buffer buffer))))
    (define-key map (vector 'mode-line 'mouse-3)
      (lambda (e)
	(interactive "e")
	(save-selected-window
	  (select-window
	   (posn-window (event-start e)))
	  (switch-to-buffer-other-window buffer))))
    (put-text-property 0 (length name) 'local-map map name)
    (put-text-property
     0 (length name)
     'help-echo (concat "mouse-2: switch to buffer, "
			"mouse-3: switch to buffer in other window")
     name)
    (put-text-property 0 (length name) 'mouse-face erc-track-mouse-face name)
    (when (and faces erc-track-use-faces)
      (put-text-property 0 (length name) 'face faces name))
    name))

(defun erc-modified-channels-display ()
  "Set `erc-modified-channels-object' according to `erc-modified-channels-alist'.
Use `erc-make-mode-line-buffer-name' to create buttons."
  (cond ((or (eq 'mostactive erc-track-switch-direction)
	     (eq 'leastactive erc-track-switch-direction))
	 (erc-track-sort-by-activest))
	((eq 'importance erc-track-switch-direction)
	 (erc-track-sort-by-importance)))
  (run-hooks 'erc-track-list-changed-hook)
  (when erc-track-position-in-mode-line
    (let* ((oldobject erc-modified-channels-object)
	   (strings
	    (when erc-modified-channels-alist
	      ;; erc-modified-channels-alist contains all the data we need.  To
	      ;; better understand what is going on, we split things up into
	      ;; four lists: BUFFERS, COUNTS, SHORT-NAMES, and FACES.  These
	      ;; four lists we use to create a new
	      ;; `erc-modified-channels-object' using
	      ;; `erc-make-mode-line-buffer-name'.
	      (let* ((buffers (mapcar #'car erc-modified-channels-alist))
		     (counts (mapcar #'cadr erc-modified-channels-alist))
		     (faces (mapcar #'cddr erc-modified-channels-alist))
                     (long-names (mapcar (lambda (buf)
                                           (or (buffer-name buf)
                                               ""))
					 buffers))
                     (erc-track--shortened-names-current-hash nil)
                     (short-names
                      (if (functionp erc-track-shorten-function)
                          (with-memoization
                              (erc-track--shortened-names-get long-names)
                            (funcall erc-track-shorten-function long-names))
                        long-names))
		     strings)
		(while buffers
		  (when (car short-names)
		    (setq strings (cons (erc-make-mode-line-buffer-name
					 (car short-names)
					 (car buffers)
					 (car faces)
					 (car counts))
					strings)))
		  (setq short-names (cdr short-names)
			buffers (cdr buffers)
			counts (cdr counts)
			faces (cdr faces)))
		strings)))
	   (newobject (erc-modified-channels-object strings)))
      (unless (equal-including-properties oldobject newobject)
	(setq erc-modified-channels-object newobject)
	(force-mode-line-update t)))))

(defun erc-modified-channels-remove-buffer (buffer)
  "Remove BUFFER from `erc-modified-channels-alist'."
  (interactive "bBuffer: ")
  (setq erc-modified-channels-alist
	(delete (assq buffer erc-modified-channels-alist)
		erc-modified-channels-alist))
  (when (called-interactively-p 'interactive)
    (erc-modified-channels-display)))

(defun erc-track-find-face (faces)
  "Return the face to use in the mode line."
  (declare (obsolete erc-track-select-mode-line-face "28.1"))
  (erc-track-select-mode-line-face (car faces) (cdr faces)))

;; Note that unless called by `erc-track-modified-channels',
;; `erc-track-faces-priority-list' will not begin with
;; `erc-track--attn-faces'.
(defun erc-track-select-mode-line-face (cur-face new-faces)
  "Return the face to use in the mode line.

CUR-FACE is the face currently used in the mode line (for the
current buffer).  NEW-FACES is the list of new faces that have
just been seen (in the current buffer).

Initially, the selected face is the one with highest priority in
`erc-track-faces-priority-list' (i.e., the one closest to the
front of the list) among CUR-FACE and NEW-FACES.  If nothing
matches (including if `erc-track-faces-priority-list' is not
set), the default mode-line faces will be used (NIL is returned).

If the selected face is still CUR-FACE (highest priority), and
the highest priority face in NEW-FACES alone is different (which
necessarily means it has lower priority than CUR-FACE), and both
are in `erc-track-faces-normal-list', then the latter is selected
instead.  This has the effect of allowing the current mode line
face, if a member of `erc-track-faces-normal-list', to be
replaced with another with lower priority face from NEW-FACES, if
that face with highest priority in NEW-FACES is also a member of
`erc-track-faces-normal-list'.

To put it another way, when CUR-FACE outranks all NEW-FACES and
doesn't appear among them, it's eligible to be replaced with a
fellow \"normal\" from NEW-FACES.  But if it does appear among
them, it can't be replaced."
  (let ((choice (catch 'face
                  (dolist (candidate erc-track-faces-priority-list)
                    (when (or (equal candidate cur-face)
                              (member candidate new-faces))
                      (throw 'face candidate))))))
    (when choice
      (if (and (equal choice cur-face)
               (member choice erc-track-faces-normal-list))
          (let ((only-in-new
                 (catch 'face
                   (dolist (candidate erc-track-faces-priority-list)
                     (when (member candidate new-faces)
                       (throw 'face candidate))))))
            (if (member only-in-new erc-track-faces-normal-list)
                only-in-new
              choice))
        choice))))

(defvar erc-track--alt-normals-function nil
  "A function to possibly elect a \"normal\" face.
Called with the current incumbent and the worthiest new contender
followed by all new contending faces and so-called \"normal\"
faces.  See `erc-track--select-mode-line-face' for their meanings
and expected types.  This function should return a face or nil.")

(defun erc-track--select-mode-line-face (cur-face new-faces ranks normals)
  "Return CUR-FACE or a replacement for displaying in the mode-line, or nil.
Expect RANKS to be a list of faces and both NORMALS and the car
of NEW-FACES to be hash tables mapping faces to non-nil values.
Assume the latter's makeup and that of RANKS to resemble
`erc-track-faces-normal-list' and `erc-track-faces-priority-list'.
If NEW-FACES has a cdr, expect it to be its car's contents
ordered from most recently seen (later in the buffer) to
earliest.  In general, act like `erc-track-select-mode-line-face'
except appeal to `erc-track--alt-normals-function' if it's
non-nil, falling back on reconsidering NEW-FACES when CUR-FACE
outranks all its members.  That is, choose the first among RANKS
in NEW-FACES not equal to CUR-FACE.  Failing that, choose the
first face in NEW-FACES that's also in NORMALS, assuming
NEW-FACES has a cdr."
  (cl-check-type erc-track-ignore-normal-contenders-p null)
  (cl-check-type new-faces cons)
  (when-let ((choice (catch 'face
                       (dolist (candidate ranks)
                         (when (or (equal candidate cur-face)
                                   (gethash candidate (car new-faces)))
                           (throw 'face candidate))))))
    (or (and erc-track--alt-normals-function
             (funcall erc-track--alt-normals-function
                      cur-face choice new-faces normals))
        (and (equal choice cur-face)
             (gethash choice normals)
             (catch 'face
               (progn
                 (dolist (candidate ranks)
                   (when (and (not (equal candidate choice))
                              (gethash candidate (car new-faces))
                              (gethash choice normals))
                     (throw 'face candidate)))
                 (dolist (candidate (cdr new-faces))
                   (when (and (not (equal candidate choice))
                              (gethash candidate normals))
                     (throw 'face candidate))))))
        choice)))

(defun erc-track-modified-channels ()
  "Hook function for `erc-insert-post-hook'.
Check if the current buffer should be added to the mode line as a
hidden, modified channel.  Assumes it will only be called when
the current buffer is in `erc-mode'."
  (let ((this-channel (or (erc-default-target)
			  (buffer-name (current-buffer)))))
    (if (and (not (erc-buffer-visible (current-buffer)))
	     (not (member this-channel erc-track-exclude))
	     (not (and erc-track-exclude-server-buffer
                       ;; FIXME either use `erc--server-buffer-p' or
                       ;; explain why that's unwise.
                       (erc-server-or-unjoined-channel-buffer-p)))
             (not (let ((parsed (erc-find-parsed-property)))
                    (or (erc-message-type-member (or parsed (point-min))
                                                 erc-track-exclude-types)
                        ;; Skip certain non-server-sent messages.
                        (and (not parsed)
                             (erc--memq-msg-prop 'erc--skip 'track))))))
	;; If the active buffer is not visible (not shown in a
	;; window), and not to be excluded, determine the kinds of
	;; faces used in the current message, and unless the user
	;; wants to ignore changes in certain channels where there
	;; are no faces corresponding to `erc-track-faces-priority-list',
	;; and the faces in the current message are found in said
	;; priority list, add the buffer to the erc-modified-channels-alist,
	;; if it is not already there.  If the buffer is already on the list
	;; (in the car), change its face attribute (in the cddr) if
	;; necessary.  See `erc-modified-channels-alist' for the
	;; exact data structure used.
        (when-let
            ((faces (if erc-track-ignore-normal-contenders-p
                        (erc-faces-in (buffer-string))
                      (erc-track--get-faces-in-current-message)))
             (normals erc-track--normal-faces)
             (erc-track-faces-priority-list
              `(,@erc-track--attn-faces ,@erc-track-faces-priority-list))
             (ranks erc-track-faces-priority-list)
             ((not (and
                    (or (eq erc-track-priority-faces-only 'all)
                        (member this-channel erc-track-priority-faces-only))
                    (not (catch 'found
                           (dolist (f ranks)
                             (when (gethash f (or (car-safe faces) faces))
                               (throw 'found t)))))))))
          (progn ; FIXME remove `progn' on next major edit
	    (if (not (assq (current-buffer) erc-modified-channels-alist))
		;; Add buffer, faces and counts
		(setq erc-modified-channels-alist
		      (cons (cons (current-buffer)
				  (cons
                                   1 (if erc-track-ignore-normal-contenders-p
                                         (erc-track-select-mode-line-face
                                          nil faces)
                                       (erc-track--select-mode-line-face
                                        nil faces ranks normals))))
			    erc-modified-channels-alist))
	      ;; Else modify the face for the buffer, if necessary.
	      (when faces
		(let* ((cell (assq (current-buffer)
				   erc-modified-channels-alist))
		       (old-face (cddr cell))
                       (new-face (if erc-track-ignore-normal-contenders-p
                                     (erc-track-select-mode-line-face
                                      old-face faces)
                                   (erc-track--select-mode-line-face
                                    old-face faces ranks normals))))
		  (setcdr cell (cons (1+ (cadr cell)) new-face)))))
	    ;; And display it
	    (erc-modified-channels-display)))
      ;; Else if the active buffer is the current buffer, remove it
      ;; from our list.
      (when (and (or (erc-buffer-visible (current-buffer))
		(and this-channel
		     (member this-channel erc-track-exclude)))
		 (assq (current-buffer) erc-modified-channels-alist))
	;; Remove it from mode-line if buffer is visible or
	;; channel was added to erc-track-exclude recently.
	(erc-modified-channels-remove-buffer (current-buffer))
	(erc-modified-channels-display)))))

(defun erc-faces-in (str)
  "Return a list of all faces used in STR."
  (let ((i 0)
	(m (length str))
	(faces (let ((face1 (get-text-property 0 'face str)))
		 (when face1 (list face1))))
	cur)
    (while (and (setq i (next-single-property-change i 'face str m))
		(not (= i m)))
      (and (setq cur (get-text-property i 'face str))
	   (not (member cur faces))
	   (push cur faces)))
    faces))

(defvar erc-track--face-reject-function nil
  "Function called with face in current buffer to massage or reject.")

(defun erc-track--get-faces-in-current-message ()
  "Collect all faces in the narrowed buffer.
Return a cons of a hash table and a list ordered from most
recently seen to earliest seen."
  (let ((i (text-property-not-all (point-min) (point-max) 'font-lock-face nil))
        (seen (make-hash-table :test #'equal))
        ;;
        (rfaces ())
        (faces (make-hash-table :test #'equal)))
    (while-let ((i)
                (cur (get-text-property i 'face)))
      (unless (gethash cur seen)
        (puthash cur t seen)
        (when erc-track--face-reject-function
          (setq cur (funcall erc-track--face-reject-function cur)))
        (when cur
          (push cur rfaces)
          (puthash cur t faces)))
      (setq i (next-single-property-change i 'font-lock-face)))
    (cons faces rfaces)))

;;; Buffer switching

(defvar erc-track-last-non-erc-buffer nil
  "Name of the last buffer before activating `erc-track-switch-buffer'.")

(defun erc-track-sort-by-activest ()
  "Sort erc-modified-channels-alist by activity.
That means the number of unseen messages in a channel."
  (setq erc-modified-channels-alist
	(sort erc-modified-channels-alist
	      (lambda (a b) (> (nth 1 a) (nth 1 b))))))

(defun erc-track-face-priority (face)
  "Return priority (a number) of FACE in `erc-track-faces-priority-list'.
Lower number means higher priority.

If face is not in `erc-track-faces-priority-list', it will have a
higher number than any other face in that list."
  (let ((count 0))
    (catch 'done
      (dolist (item `(,@erc-track--attn-faces ,@erc-track-faces-priority-list))
	(if (equal item face)
	    (throw 'done t)
	  (setq count (1+ count)))))
    count))

(defun erc-track-sort-by-importance ()
  "Sort `erc-modified-channels-alist' by importance.
That means the position of the face in `erc-track-faces-priority-list'."
  (setq erc-modified-channels-alist
	(sort erc-modified-channels-alist
	      (lambda (a b) (< (erc-track-face-priority (cddr a))
			       (erc-track-face-priority (cddr b)))))))

(defun erc-track-get-active-buffer (arg)
  "Return the buffer name of ARG in `erc-modified-channels-alist'.
Negative arguments index in the opposite direction.  This direction
is relative to `erc-track-switch-direction'."
  (let ((dir erc-track-switch-direction)
	offset)
    (when (< arg 0)
      (setq dir (pcase dir
		  ('oldest      'newest)
		  ('newest      'oldest)
		  ('mostactive  'leastactive)
		  ('leastactive 'mostactive)
		  ('importance  'oldest)))
      (setq arg (- arg)))
    (setq offset (pcase dir
		   ((or 'oldest 'leastactive)
		    (- (length erc-modified-channels-alist) arg))
		   (_ (1- arg))))
    ;; normalize out of range user input
    (cond ((>= offset (length erc-modified-channels-alist))
	   (setq offset (1- (length erc-modified-channels-alist))))
	  ((< offset 0)
	   (setq offset 0)))
    (car (nth offset erc-modified-channels-alist))))

(defvar erc-track--switch-fallback-blockers '((derived-mode . erc-mode))
  "List of `buffer-match-p' conditions OR'd together.
ERC sets `erc-track-last-non-erc-buffer' to the current buffer
unless any passes.")

(defun erc-track--switch-buffer (fun arg)
  (if (not erc-track-mode)
      (message (concat "Enable the ERC track module if you want to use the"
		       " tracking minor mode"))
    (cond (erc-modified-channels-alist
	   ;; if we're not in erc-mode, set this buffer to return to
           (unless (buffer-match-p (cons 'or
                                         erc-track--switch-fallback-blockers)
                                   (current-buffer))
	     (setq erc-track-last-non-erc-buffer (current-buffer)))
	   ;; and jump to the next active channel
           (if-let ((buf (erc-track-get-active-buffer arg))
                    ((buffer-live-p buf)))
               (funcall fun buf)
             (erc-modified-channels-update)
             (erc-track--switch-buffer fun arg)))
	  ;; if no active channels, switch back to what we were doing before
	  ((and erc-track-last-non-erc-buffer
	        erc-track-switch-from-erc
	        (buffer-live-p erc-track-last-non-erc-buffer))
	   (funcall fun erc-track-last-non-erc-buffer)))))

(defun erc-track-switch-buffer (arg)
  "Switch to the next active ERC buffer.
If there are no active ERC buffers, switch back to the last
non-ERC buffer visited.  The order of buffers is defined by
`erc-track-switch-direction', and a negative argument will
reverse it."
  (interactive "p")
  (erc-track--switch-buffer 'switch-to-buffer arg))

(defun erc-track-switch-buffer-other-window (arg)
  "Switch to the next active ERC buffer in another window.
If there are no active ERC buffers, switch back to the last
non-ERC buffer visited.  The order of buffers is defined by
`erc-track-switch-direction', and a negative argument will
reverse it."
  (interactive "p")
  (erc-track--switch-buffer 'switch-to-buffer-other-window arg))

(defun erc-track--replace-killed-buffer (existing)
  (when-let ((found (assq existing erc-modified-channels-alist)))
    (setcar found (current-buffer))))

(provide 'erc-track)

;;; erc-track.el ends here
;;
;; Local Variables:
;; generated-autoload-file: "erc-loaddefs.el"
;; End:
