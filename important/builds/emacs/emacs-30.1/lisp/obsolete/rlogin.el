;;; rlogin.el --- remote login interface  -*- lexical-binding:t -*-

;; Copyright (C) 1992-2025 Free Software Foundation, Inc.

;; Author: Noah Friedman <friedman@splode.com>
;; Keywords: unix, comm
;; Obsolete-since: 29.1

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

;; This library is obsolete.
;; See: https://debbugs.gnu.org/56461

;; Support for remote logins using `rlogin'.
;; This program is layered on top of shell.el; the code here only accounts
;; for the variations needed to handle a remote process, e.g. directory
;; tracking and the sending of some special characters.

;; If you wish for rlogin mode to prompt you in the minibuffer for
;; passwords when a password prompt appears, just enter
;; M-x comint-send-invisible and type in your line (or tweak
;; `comint-password-prompt-regexp' to match your password prompt).

;;; Code:

(require 'comint)
(require 'shell)

(defgroup rlogin nil
  "Remote login interface."
  :group 'processes
  :group 'unix)

(defcustom rlogin-program "ssh"
  "Name of program to invoke remote login."
  :version "24.4"                       ; rlogin -> ssh
  :type 'string
  :group 'rlogin)

(defcustom rlogin-explicit-args '("-t" "-t")
  "List of arguments to pass to `rlogin-program' on the command line."
  :version "24.4"                       ; nil -> -t -t
  :type '(repeat (string :tag "Argument"))
  :group 'rlogin)

(defcustom rlogin-mode-hook nil
  "Hooks to run after setting current buffer to rlogin-mode."
  :type 'hook
  :group 'rlogin)

(defcustom rlogin-process-connection-type
  ;; Solaris 2.x `rlogin' will spew a bunch of ioctl error messages if
  ;; stdin isn't a tty.
  (and (string-match "rlogin" rlogin-program)
       (string-match-p "-solaris2" system-configuration) t)
  "If non-nil, use a pty for the local rlogin process.
If nil, use a pipe (if pipes are supported on the local system).

Generally it is better not to waste ptys on systems which have a static
number of them.  On the other hand, some implementations of `rlogin' assume
a pty is being used, and errors will result from using a pipe instead."
  :set-after '(rlogin-program)
  :type '(choice (const :tag "pipes" nil)
		 (other :tag "ptys" t))
  :group 'rlogin)

(defcustom rlogin-directory-tracking-mode 'local
  "Control whether and how to do directory tracking in an rlogin buffer.

nil means don't do directory tracking.

t means do so using an ftp remote file name.

Any other value means do directory tracking using local file names.
This works only if the remote machine and the local one
share the same directories (through NFS).  This is the default.

This variable becomes local to a buffer when set in any fashion for it.

It is better to use the function of the same name to change the behavior of
directory tracking in an rlogin session once it has begun, rather than
simply setting this variable, since the function does the necessary
re-syncing of directories."
  :type '(choice (const :tag "off" nil)
		 (const :tag "ftp" t)
		 (other :tag "local" local))
  :group 'rlogin)

(make-variable-buffer-local 'rlogin-directory-tracking-mode)

(defcustom rlogin-host nil
  "The name of the default remote host.  This variable is buffer-local."
  :type '(choice (const nil) string)
  :group 'rlogin)

(defcustom rlogin-remote-user nil
  "The username used on the remote host.
This variable is buffer-local and defaults to your local user name.
If rlogin is invoked with the `-l' option to specify the remote username,
this variable is set from that."
  :type '(choice (const nil) string)
  :group 'rlogin)

(defvar-keymap rlogin-mode-map
  :doc "Keymap for `rlogin-mode'."
  :parent shell-mode-map
  "C-c C-c"  #'rlogin-send-Ctrl-C
  "C-c C-d"  #'rlogin-send-Ctrl-D
  "C-c C-z"  #'rlogin-send-Ctrl-Z
  "C-c C-\\" #'rlogin-send-Ctrl-backslash
  "C-d"      #'rlogin-delchar-or-send-Ctrl-D
  "TAB"      #'rlogin-tab-or-complete)


(defvar rlogin-history nil)

;;;###autoload
(defun rlogin (input-args &optional buffer)
  "Open a network login connection via `rlogin' with args INPUT-ARGS.
INPUT-ARGS should start with a host name; it may also contain
other arguments for `rlogin'.

Input is sent line-at-a-time to the remote connection.

Communication with the remote host is recorded in a buffer `*rlogin-HOST*'
\(or `*rlogin-USER@HOST*' if the remote username differs).
If a prefix argument is given and the buffer `*rlogin-HOST*' already exists,
a new buffer with a different connection will be made.

When called from a program, if the optional second argument BUFFER is
a string or buffer, it specifies the buffer to use.

The variable `rlogin-program' contains the name of the actual program to
run.  It can be a relative or absolute path.

The variable `rlogin-explicit-args' is a list of arguments to give to
the rlogin when starting.  They are added after any arguments given in
INPUT-ARGS.

If the default value of `rlogin-directory-tracking-mode' is t, then the
default directory in that buffer is set to a remote (FTP) file name to
access your home directory on the remote machine.  Occasionally this causes
an error, if you cannot access the home directory on that machine.  This
error is harmless as long as you don't try to use that default directory.

If `rlogin-directory-tracking-mode' is neither t nor nil, then the default
directory is initially set up to your (local) home directory.
This is useful if the remote machine and your local machine
share the same files via NFS.  This is the default.

If you wish to change directory tracking styles during a session, use the
function `rlogin-directory-tracking-mode' rather than simply setting the
variable."
  (interactive (list
		(read-from-minibuffer (format-message
                                       "Arguments for `%s' (hostname first): "
                                       (file-name-nondirectory rlogin-program))
				      nil nil nil 'rlogin-history)
		current-prefix-arg))
  (let* ((process-connection-type rlogin-process-connection-type)
         (args (if rlogin-explicit-args
                   (append (split-string input-args)
                           rlogin-explicit-args)
                 (split-string input-args)))
         (host (let ((tail args))
                 ;; Find first arg that doesn't look like an option.
                 ;; This still loses for args that take values, feh.
                 (while (and tail (= ?- (aref (car tail) 0)))
                   (setq tail (cdr tail)))
                 (car tail)))
	 (user (or (car (cdr (member "-l" args)))
                   (user-login-name)))
         (buffer-name (if (string= user (user-login-name))
                          (format "*rlogin-%s*" host)
                        (format "*rlogin-%s@%s*" user host))))
    (cond ((null buffer))
	  ((stringp buffer)
	   (setq buffer-name buffer))
          ((bufferp buffer)
           (setq buffer-name (buffer-name buffer)))
          ((numberp buffer)
           (setq buffer-name (format "%s<%d>" buffer-name buffer)))
          (t
           (setq buffer-name (generate-new-buffer-name buffer-name))))
    (setq buffer (get-buffer-create buffer-name))
    (switch-to-buffer buffer-name)
    (unless (comint-check-proc buffer-name)
      (comint-exec buffer buffer-name rlogin-program nil args)
      (rlogin-mode)
      (setq-local rlogin-host host)
      (setq-local rlogin-remote-user user)
      (ignore-errors
        (cond ((eq rlogin-directory-tracking-mode t)
               ;; Do this here, rather than calling the tracking mode
               ;; function, to avoid a gratuitous resync check; the default
               ;; should be the user's home directory, be it local or remote.
               (setq comint-file-name-prefix
                     (concat "/-:" rlogin-remote-user "@" rlogin-host ":"))
               (cd-absolute comint-file-name-prefix))
              ((null rlogin-directory-tracking-mode))
              (t
               (cd-absolute (concat comint-file-name-prefix "~/"))))))))

(put 'rlogin-mode 'mode-class 'special)

(define-derived-mode rlogin-mode shell-mode "Rlogin"
  (setq shell-dirtrackp rlogin-directory-tracking-mode)
  (make-local-variable 'comint-file-name-prefix))

(defun rlogin-directory-tracking-mode (&optional prefix)
  "Do remote or local directory tracking, or disable entirely.

If called with no prefix argument or a unspecified prefix argument (just
`\\[universal-argument]' with no number) do remote directory tracking via
ange-ftp.  If called as a function, give it no argument.

If called with a negative prefix argument, disable directory tracking
entirely.

If called with a positive, numeric prefix argument, for example
\\[universal-argument] 1 \\[rlogin-directory-tracking-mode],
then do directory tracking but assume the remote filesystem is the same as
the local system.  This only works in general if the remote machine and the
local one share the same directories (e.g. through NFS)."
  (interactive "P")
  (cond
   ((or (null prefix)
        (consp prefix))
    (setq rlogin-directory-tracking-mode t)
    (setq shell-dirtrackp t)
    (setq comint-file-name-prefix
          (concat "/-:" rlogin-remote-user "@" rlogin-host ":")))
   ((< prefix 0)
    (setq rlogin-directory-tracking-mode nil)
    (setq shell-dirtrackp nil))
   (t
    (setq rlogin-directory-tracking-mode 'local)
    (setq comint-file-name-prefix "")
    (setq shell-dirtrackp t)))
  (cond
   (shell-dirtrackp
    (let* ((proc (get-buffer-process (current-buffer)))
           (proc-mark (process-mark proc))
           (current-input (buffer-substring proc-mark (point-max)))
           (orig-point (point))
           (offset (and (>= orig-point proc-mark)
                        (- (point-max) orig-point))))
      (unwind-protect
          (progn
            (delete-region proc-mark (point-max))
            (goto-char (point-max))
            (shell-resync-dirs))
        (goto-char proc-mark)
        (insert current-input)
        (if offset
            (goto-char (- (point-max) offset))
          (goto-char orig-point)))))))


(defun rlogin-send-Ctrl-C ()
  (interactive)
  (process-send-string nil "\C-c"))

(defun rlogin-send-Ctrl-D ()
  (interactive)
  (process-send-string nil "\C-d"))

(defun rlogin-send-Ctrl-Z ()
  (interactive)
  (process-send-string nil "\C-z"))

(defun rlogin-send-Ctrl-backslash ()
  (interactive)
  (process-send-string nil "\C-\\"))

(defun rlogin-delchar-or-send-Ctrl-D (arg)
  "Delete ARG characters forward, or send a C-d to process if at end of buffer."
  (interactive "p")
  (if (eobp)
      (rlogin-send-Ctrl-D)
    (delete-char arg)))

(defun rlogin-tab-or-complete ()
  "Complete file name if doing directory tracking, or just insert TAB."
  (interactive)
  (if rlogin-directory-tracking-mode
      (completion-at-point)
    (insert "\C-i")))

(provide 'rlogin)

;;; rlogin.el ends here
