;;; image-mode.el --- support for visiting image files  -*- lexical-binding: t -*-
;;
;; Copyright (C) 2005-2025 Free Software Foundation, Inc.
;;
;; Author: Richard Stallman <rms@gnu.org>
;; Keywords: multimedia
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

;; Defines `image-mode', a major mode for visiting image files.  Displaying
;; images only works if Emacs was built with support for displaying
;; such images.  See Info node `(emacs) Image Mode' for more
;; information.
;;
;; There is support for switching between viewing the text of the
;; file, the hex of the file and viewing the file as an image.
;; Viewing the image works by putting a `display' text-property on the
;; image data, with the image-data still present underneath; if the
;; resulting buffer file is saved to another name it will correctly save
;; the image data to the new file.

;; Todo:

;; Consolidate with doc-view to make them work on directories of images or on
;; image files containing various "pages".

;;; Code:

(require 'image)
(require 'exif)
(require 'dired)
(eval-when-compile (require 'cl-lib))

;;; Image mode window-info management.

(defvar-local image-mode-winprops-alist t
  "Alist of windows to window properties.
Each element has the form (WINDOW . ALIST).
See `image-mode-winprops'.")

(defvar image-mode-new-window-functions nil
  "Special hook run when image data is requested in a new window.
It is called with one argument, the initial WINPROPS.")

(defcustom image-auto-resize t
  "Non-nil to resize the image upon first display.
Its value should be one of the following:
 - nil, meaning no resizing.
 - t, meaning to scale the image down to fit in the window.
 - `fit-window', meaning to fit the image to the window.
 - A number, which is a scale factor (the default size is 1).

Resizing will always preserve the aspect ratio of the image."
  :type '(choice (const :tag "No resizing" nil)
                 (const :tag "Fit to window" fit-window)
                 (number :tag "Scale factor" 1)
                 (other :tag "Scale down to fit window" t))
  :version "29.1"
  :group 'image)

(defcustom image-auto-resize-max-scale-percent nil
  "Max size (in percent) to scale up to when `image-auto-resize' is `fit-window'.
Can be either a number larger than 100, or nil, which means no
max size."
  :type '(choice (const :tag "No max" nil)
                 natnum)
  :version "29.1"
  :group 'image)

(defcustom image-auto-resize-on-window-resize 1
  "Non-nil to resize the image whenever the window's dimensions change.
This will always keep the image fit to the window.
When non-nil, the value should be a number of seconds to wait before
resizing according to the value specified in `image-auto-resize'."
  :type '(choice (const :tag "No auto-resize on window size change" nil)
                 (number :tag "Wait for number of seconds before resize" 1))
  :version "27.1"
  :group 'image)

(defvar-local image-transform-resize nil
  "The image resize operation.
Non-nil to resize the image upon first display.
Its value should be one of the following:
 - nil, meaning no resizing.
 - t, meaning to scale the image down to fit in the window.
 - `fit-window', meaning to fit the image to the window.
 - A number, which is a scale factor (the default size is 1).

There is also support for these values, obsolete since Emacs 29.1:
 - `fit-height', meaning to fit the image to the window height.
 - `fit-width', meaning to fit the image to the window width.

Resizing will always preserve the aspect ratio of the image.")

(defvar-local image-transform-scale 1.0
  "The scale factor of the image being displayed.")

(defvar-local image-transform-rotation 0.0
  "Rotation angle for the image in the current Image mode buffer.")

(defvar-local image--transform-smoothing nil
  "Whether to use transform smoothing.")

(defvar image-transform-right-angle-fudge 0.0001
  "Snap distance to a multiple of a right angle.
There's no deep theory behind the default value, it should just
be somewhat larger than ImageMagick's MagickEpsilon.")

(defun image-mode-winprops (&optional window cleanup)
  "Return winprops of WINDOW.
A winprops object has the shape (WINDOW . ALIST).
WINDOW defaults to `selected-window' if it displays the current buffer, and
otherwise it defaults to t, used for times when the buffer is not displayed."
  (cond ((null window)
         (setq window
               (if (eq (current-buffer) (window-buffer)) (selected-window) t)))
        ((eq window t))
	((not (windowp window))
	 (error "Not a window: %s" window)))
  (when cleanup
    (setq image-mode-winprops-alist
  	  (delq nil (mapcar (lambda (winprop)
			      (let ((w (car-safe winprop)))
				(if (or (not (windowp w)) (window-live-p w))
				    winprop)))
  			    image-mode-winprops-alist))))
  (let ((winprops (assq window image-mode-winprops-alist)))
    ;; For new windows, set defaults from the latest.
    (if winprops
        ;; Move window to front.
        (setq image-mode-winprops-alist
              (cons winprops (delq winprops image-mode-winprops-alist)))
      (setq winprops (cons window
                           (copy-alist (cdar image-mode-winprops-alist))))
      ;; Add winprops before running the hook, to avoid inf-loops if the hook
      ;; triggers window-configuration-change-hook.
      (setq image-mode-winprops-alist
            (cons winprops image-mode-winprops-alist))
      (run-hook-with-args 'image-mode-new-window-functions winprops))
    winprops))

(defun image-mode-window-get (prop &optional winprops)
  (declare (gv-setter (lambda (val)
                        `(image-mode-window-put ,prop ,val ,winprops))))
  (unless (consp winprops) (setq winprops (image-mode-winprops winprops)))
  (cdr (assq prop (cdr winprops))))

(defun image-mode-window-put (prop val &optional winprops)
  (unless (consp winprops) (setq winprops (image-mode-winprops winprops)))
  (unless (eq t (car winprops))
    (image-mode-window-put prop val t))
  (setcdr winprops (cons (cons prop val)
                         (delq (assq prop (cdr winprops)) (cdr winprops)))))

(defun image-set-window-vscroll (vscroll)
  (setf (image-mode-window-get 'vscroll) vscroll)
  (set-window-vscroll (selected-window) vscroll t))

(defun image-set-window-hscroll (ncol)
  (setf (image-mode-window-get 'hscroll) ncol)
  (set-window-hscroll (selected-window) ncol))

(defun image-mode-reapply-winprops ()
  ;; When set-window-buffer, set hscroll and vscroll to what they were
  ;; last time the image was displayed in this window.
  (when (listp image-mode-winprops-alist)
    ;; Beware: this call to image-mode-winprops can't be optimized away,
    ;; because it not only gets the winprops data but sets it up if needed
    ;; (e.g. it's used by doc-view to display the image in a new window).
    (let* ((winprops (image-mode-winprops nil t))
           (hscroll (image-mode-window-get 'hscroll winprops))
           (vscroll (image-mode-window-get 'vscroll winprops)))
      (when (image-get-display-property) ;Only do it if we display an image!
	(if hscroll (set-window-hscroll (selected-window) hscroll))
	(if vscroll (set-window-vscroll (selected-window) vscroll t))))))

(defun image-mode-setup-winprops ()
  ;; Record current scroll settings.
  (unless (listp image-mode-winprops-alist)
    (setq image-mode-winprops-alist nil))
  (add-hook 'window-configuration-change-hook
	    #'image-mode-reapply-winprops nil t))

;;; Image scrolling functions

(defun image-get-display-property ()
  (get-char-property (point-min) 'display
                     ;; There might be different images for different displays.
                     (if (eq (window-buffer) (current-buffer))
                         (selected-window))))

(declare-function image-size "image.c" (spec &optional pixels frame))
(declare-function xwidget-info "xwidget.c" (xwidget))
(declare-function xwidget-at "xwidget.el" (pos))

(defun image-display-size (spec &optional pixels frame)
  "Wrapper around `image-size', handling slice display properties.
Like `image-size', the return value is (WIDTH . HEIGHT).
WIDTH and HEIGHT are in canonical character units if PIXELS is
nil, and in pixel units if PIXELS is non-nil.

If SPEC is an image display property, this function is equivalent to
`image-size'.  If SPEC represents an xwidget object, defer to `xwidget-info'.
If SPEC is a list of properties containing `image' and `slice' properties,
return the display size taking the slice property into account.  If the list
contains `image' but not `slice', return the `image-size' of the specified
image."
  (cond ((eq (car spec) 'xwidget)
         (let ((xwi (xwidget-info (xwidget-at (point-min)))))
           (cons (aref xwi 2) (aref xwi 3))))
        ((eq (car spec) 'image)
         (image-size spec pixels frame))
        (t (let ((image (assoc 'image spec))
                 (slice (assoc 'slice spec)))
             (cond ((and image slice)
                    (if pixels
                        (cons (nth 3 slice) (nth 4 slice))
                      (cons (/ (float (nth 3 slice)) (frame-char-width frame))
                            (/ (float (nth 4 slice))
                               (frame-char-height frame)))))
                   (image
                    (image-size image pixels frame))
                   (t
                    (error "Invalid image specification: %s" spec)))))))

(defun image-forward-hscroll (&optional n)
  "Scroll image in current window to the left by N character widths.
Stop if the right edge of the image is reached."
  (interactive "p" image-mode)
  (cond ((= n 0) nil)
	((< n 0)
	 (image-set-window-hscroll (max 0 (+ (window-hscroll) n))))
	(t
	 (let* ((image (image-get-display-property))
		(edges (window-edges nil t nil t))
		(win-width (- (/ (nth 2 edges) (frame-char-width))
                              (/ (nth 0 edges) (frame-char-width))))
		(img-width (ceiling (car (image-display-size image)))))
	   (image-set-window-hscroll (min (max 0 (- img-width win-width))
					  (+ n (window-hscroll))))))))

(defun image-backward-hscroll (&optional n)
  "Scroll image in current window to the right by N character widths.
Stop if the left edge of the image is reached."
  (interactive "p" image-mode)
  (image-forward-hscroll (- n)))

(defun image-next-line (n)
  "Scroll image in current window upward by N lines.
Stop if the bottom edge of the image is reached."
  (interactive "p" image-mode)
  ;; Convert N to pixels.
  (setq n (* n (frame-char-height)))
  (cond ((= n 0) nil)
	((< n 0)
	 (image-set-window-vscroll (max 0 (+ (window-vscroll nil t) n))))
	(t
	 (let* ((image (image-get-display-property))
		(edges (window-edges nil t t))
		(win-height (- (nth 3 edges) (nth 1 edges)))
		(img-height (ceiling (cdr (image-display-size image t)))))
	   (image-set-window-vscroll (min (max 0 (- img-height win-height))
					  (+ n (window-vscroll nil t))))))))

(defun image-previous-line (&optional n)
  "Scroll image in current window downward by N lines.
Stop if the top edge of the image is reached."
  (interactive "p" image-mode)
  (image-next-line (- n)))

(defun image-scroll-up (&optional n)
  "Scroll image in current window upward by N lines.
Stop if the bottom edge of the image is reached.

Interactively, giving this command a numerical prefix will scroll
up by that many lines (and down by that many lines if the number
is negative).  Without a prefix, scroll up by a full screen.
If given a \\`C-u -' prefix, scroll a full page down instead.

If N is omitted or nil, scroll upward by a near full screen.
A near full screen is `next-screen-context-lines' less than a full screen.
A negative N means scroll downward.

If N is the atom `-', scroll downward by nearly full screen.
When calling from a program, supply as argument a number, nil, or `-'."
  (interactive "P" image-mode)
  (cond ((null n)
	 (let* ((edges (window-inside-edges))
		(win-height (- (nth 3 edges) (nth 1 edges))))
	   (image-next-line
	    (max 0 (- win-height next-screen-context-lines)))))
	((eq n '-)
	 (let* ((edges (window-inside-edges))
		(win-height (- (nth 3 edges) (nth 1 edges))))
	   (image-next-line
	    (min 0 (- next-screen-context-lines win-height)))))
	(t (image-next-line (prefix-numeric-value n)))))

(defun image-scroll-down (&optional n)
  "Scroll image in current window downward by N lines.
Stop if the top edge of the image is reached.

Interactively, giving this command a numerical prefix will scroll
down by that many lines (and up by that many lines if the number
is negative).  Without a prefix, scroll down by a full screen.
If given a \\`C-u -' prefix, scroll a full page up instead.

If N is omitted or nil, scroll downward by a near full screen.
A near full screen is `next-screen-context-lines' less than a full screen.
A negative N means scroll upward.

If N is the atom `-', scroll upward by nearly full screen.
When calling from a program, supply as argument a number, nil, or `-'."
  (interactive "P" image-mode)
  (cond ((null n)
	 (let* ((edges (window-inside-edges))
		(win-height (- (nth 3 edges) (nth 1 edges))))
	   (image-next-line
	    (min 0 (- next-screen-context-lines win-height)))))
	((eq n '-)
	 (let* ((edges (window-inside-edges))
		(win-height (- (nth 3 edges) (nth 1 edges))))
	   (image-next-line
	    (max 0 (- win-height next-screen-context-lines)))))
	(t (image-next-line (- (prefix-numeric-value n))))))

(defun image-scroll-left (&optional n)
  "Scroll image in current window leftward by N character widths.
Stop if the right edge of the image is reached.
If ARG is omitted or nil, scroll leftward by a near full screen.
A near full screen is 2 columns less than a full screen.
Negative ARG means scroll rightward.
If ARG is the atom `-', scroll rightward by nearly full screen.
When calling from a program, supply as argument a number, nil, or `-'."
  (interactive "P" image-mode)
  (cond ((null n)
	 (let* ((edges (window-inside-edges))
		(win-width (- (nth 2 edges) (nth 0 edges))))
	   (image-forward-hscroll
	    (max 0 (- win-width 2)))))
	((eq n '-)
	 (let* ((edges (window-inside-edges))
		(win-width (- (nth 2 edges) (nth 0 edges))))
	   (image-forward-hscroll
	    (min 0 (- 2 win-width)))))
	(t (image-forward-hscroll (prefix-numeric-value n)))))

(defun image-scroll-right (&optional n)
  "Scroll image in current window rightward by N character widths.
Stop if the left edge of the image is reached.
If ARG is omitted or nil, scroll downward by a near full screen.
A near full screen is 2 less than a full screen.
Negative ARG means scroll leftward.
If ARG is the atom `-', scroll leftward by nearly full screen.
When calling from a program, supply as argument a number, nil, or `-'."
  (interactive "P" image-mode)
  (cond ((null n)
	 (let* ((edges (window-inside-edges))
		(win-width (- (nth 2 edges) (nth 0 edges))))
	   (image-forward-hscroll
	    (min 0 (- 2 win-width)))))
	((eq n '-)
	 (let* ((edges (window-inside-edges))
		(win-width (- (nth 2 edges) (nth 0 edges))))
	   (image-forward-hscroll
	    (max 0 (- win-width 2)))))
	(t (image-forward-hscroll (- (prefix-numeric-value n))))))

(defun image-bol (arg)
  "Scroll horizontally to the left edge of the image in the current window.
With argument ARG not nil or 1, move forward ARG - 1 lines first,
stopping if the top or bottom edge of the image is reached."
  (interactive "p" image-mode)
  (and arg
       (/= (setq arg (prefix-numeric-value arg)) 1)
       (image-next-line (- arg 1)))
  (image-set-window-hscroll 0))

(defun image-eol (arg)
  "Scroll horizontally to the right edge of the image in the current window.
With argument ARG not nil or 1, move forward ARG - 1 lines first,
stopping if the top or bottom edge of the image is reached."
  (interactive "p" image-mode)
  (and arg
       (/= (setq arg (prefix-numeric-value arg)) 1)
       (image-next-line (- arg 1)))
  (let* ((image (image-get-display-property))
	 (edges (window-inside-edges))
	 (win-width (- (nth 2 edges) (nth 0 edges)))
	 (img-width (ceiling (car (image-display-size image)))))
    (image-set-window-hscroll (max 0 (- img-width win-width)))))

(defun image-bob ()
  "Scroll to the top-left corner of the image in the current window."
  (interactive nil image-mode)
  (image-set-window-hscroll 0)
  (image-set-window-vscroll 0))

(defun image-eob ()
  "Scroll to the bottom-right corner of the image in the current window."
  (interactive nil image-mode)
  (let* ((image (image-get-display-property))
	 (edges (window-inside-edges))
	 (pixel-edges (window-edges nil t t))
	 (win-width (- (nth 2 edges) (nth 0 edges)))
	 (img-width (ceiling (car (image-display-size image))))
	 (win-height (- (nth 3 pixel-edges) (nth 1 pixel-edges)))
	 (img-height (ceiling (cdr (image-display-size image t)))))
    (image-set-window-hscroll (max 0 (- img-width win-width)))
    (image-set-window-vscroll (max 0 (- img-height win-height)))))

;; Adjust frame and image size.

(defun image-mode-fit-frame (&optional frame toggle)
  "Fit FRAME to the current image.
If FRAME is omitted or nil, it defaults to the selected frame.
All other windows on the frame are deleted.

If called interactively, or if TOGGLE is non-nil, toggle between
fitting FRAME to the current image and restoring the size and
window configuration prior to the last `image-mode-fit-frame'
call."
  (interactive (list nil t) image-mode)
  (let* ((buffer (current-buffer))
	 (saved (frame-parameter frame 'image-mode-saved-params))
	 (window-configuration (current-window-configuration frame))
	 (frame-width (frame-text-width frame))
	 (frame-height (frame-text-height frame)))
    (with-selected-frame (or frame (selected-frame))
      (if (and toggle saved
	       (= (caar saved) frame-width)
	       (= (cdar saved) frame-height))
	  (progn
	    (set-frame-width frame (car (nth 1 saved)) nil t)
	    (set-frame-height frame (cdr (nth 1 saved)) nil t)
	    (set-window-configuration (nth 2 saved))
	    (set-frame-parameter frame 'image-mode-saved-params nil))
	(delete-other-windows)
	(switch-to-buffer buffer t t)
        (fit-frame-to-buffer frame)
	;; The frame size after the above `set-frame-*' calls may
	;; differ from what we specified, due to window manager
	;; interference.  We have to call `frame-width' and
	;; `frame-height' to get the actual results.
	(set-frame-parameter frame 'image-mode-saved-params
			     (list (cons (frame-text-width frame)
					 (frame-text-height frame))
				   (cons frame-width frame-height)
				   window-configuration))))))

;;; Image Mode setup

(defcustom image-text-based-formats '(svg xpm)
  "List of image formats that use a plain text format.
For such formats, display a message that explains how to edit the
image as text, when opening such images in `image-mode'."
  :type '(choice (const :tag "Disable completely" nil)
                 (repeat :tag "List of formats" sexp))
  :version "29.1"
  :group 'image)

(defvar-local image-type nil
  "The image type for the current Image mode buffer.")

(defvar-local image-multi-frame nil
  "Non-nil if image for the current Image mode buffer has multiple frames.")

(defvar-keymap image-mode-map
  :doc "Mode keymap for `image-mode'."
  :parent (make-composed-keymap image-map special-mode-map)

  ;; Toggling keys
  "C-c C-c" #'image-toggle-display
  "C-c C-x" #'image-toggle-hex-display

  ;; Transformation keys
  "s f"     #'image-mode-fit-frame
  "s w"     #'image-transform-fit-to-window
  "s h"     #'image-transform-fit-to-height
  "s i"     #'image-transform-fit-to-width
  "s b"     #'image-transform-fit-both
  "s p"     #'image-transform-set-percent
  "s s"     #'image-transform-set-scale
  "s r"     #'image-transform-set-rotation
  "s m"     #'image-transform-set-smoothing
  "s o"     #'image-transform-reset-to-original
  "s 0"     #'image-transform-reset-to-initial

  ;; Multi-frame keys
  "RET"     #'image-toggle-animation
  "F"       #'image-goto-frame
  "f"       #'image-next-frame
  "b"       #'image-previous-frame
  "a +"     #'image-increase-speed
  "a -"     #'image-decrease-speed
  "a 0"     #'image-reset-speed
  "a r"     #'image-reverse-speed

  ;; File keys
  "n"       #'image-next-file
  "p"       #'image-previous-file
  "w"       #'image-mode-copy-file-name-as-kill
  "m"       #'image-mode-mark-file
  "u"       #'image-mode-unmark-file

  ;; Scrolling keys
  "SPC"     #'image-scroll-up
  "S-SPC"   #'image-scroll-down
  "DEL"     #'image-scroll-down

  ;; Misc
  "W"       #'image-mode-wallpaper-set

  ;; Remapped
  "<remap> <forward-char>"           #'image-forward-hscroll
  "<remap> <backward-char>"          #'image-backward-hscroll
  "<remap> <right-char>"             #'image-forward-hscroll
  "<remap> <left-char>"              #'image-backward-hscroll
  "<remap> <previous-line>"          #'image-previous-line
  "<remap> <next-line>"              #'image-next-line
  "<remap> <scroll-up>"              #'image-scroll-up
  "<remap> <scroll-down>"            #'image-scroll-down
  "<remap> <scroll-up-command>"      #'image-scroll-up
  "<remap> <scroll-down-command>"    #'image-scroll-down
  "<remap> <scroll-left>"            #'image-scroll-left
  "<remap> <scroll-right>"           #'image-scroll-right
  "<remap> <move-beginning-of-line>" #'image-bol
  "<remap> <move-end-of-line>"       #'image-eol
  "<remap> <beginning-of-buffer>"    #'image-bob
  "<remap> <end-of-buffer>"          #'image-eob)

(easy-menu-define image-mode-menu image-mode-map
  "Menu for Image mode."
  '("Image"
    ["Show as Text" image-toggle-display :active t
     :help "Show image as text"]
    ["Show as Hex" image-toggle-hex-display :active t
     :help "Show image as hex"]
    "--"
    ["Fit Frame to Image" image-mode-fit-frame :active t
     :help "Resize frame to match image"]
    ["Fit Image to Window" image-transform-fit-to-window
     :help "Resize image to match the window height and width"]
    ["Fit Image to Window (Scale down only)" image-transform-fit-both
     :help "Scale image down to match the window height and width"]
    ["Fill Window with Image" image-transform-fill-window
     :help "Resize image to fill either width or height of the window"]
    ["Zoom In" image-increase-size
     :help "Enlarge the image"]
    ["Zoom Out" image-decrease-size
     :help "Shrink the image"]
    ["Set Scale..." image-transform-set-scale
     :help "Resize image by specified scale factor"]
    ["Rotate Clockwise" image-rotate
     :help "Rotate the image"]
    ["Set Rotation..." image-transform-set-rotation
     :help "Set rotation angle of the image"]
    ["Set Smoothing..." image-transform-set-smoothing
     :help "Toggle smoothing"]
    ["Original Size" image-transform-reset-to-original
     :help "Reset image to actual size"]
    ["Reset to Default Size" image-transform-reset-to-initial
     :help "Reset all image transformations to initial size"]
    "--"
    ["Show Thumbnails"
     (lambda ()
       (interactive)
       (image-dired default-directory))
     :active default-directory
     :help "Show thumbnails for all images in this directory"]
    ["Previous Image" image-previous-file :active buffer-file-name
     :help "Move to previous image in this directory"]
    ["Next Image" image-next-file :active buffer-file-name
     :help "Move to next image in this directory"]
    ["Copy File Name" image-mode-copy-file-name-as-kill
     :active buffer-file-name
     :help "Copy the current file name to the kill ring"]
    "--"
    ["Animate Image" image-toggle-animation :style toggle
     :selected (let ((image (image-get-display-property)))
                 (and image (image-animate-timer image)))
     :active image-multi-frame
     :help "Toggle image animation"]
    ["Loop Animation"
     (lambda () (interactive)
       (setq image-animate-loop (not image-animate-loop))
       ;; FIXME this is a hacky way to make it affect a currently
       ;; animating image.
       (when (let ((image (image-get-display-property)))
               (and image (image-animate-timer image)))
         (image-toggle-animation)
         (image-toggle-animation)))
     :style toggle :selected image-animate-loop
     :active image-multi-frame
     :help "Animate images once, or forever?"]
    ["Reverse Animation" image-reverse-speed
     :style toggle :selected (let ((image (image-get-display-property)))
                               (and image (<
                                           (image-animate-get-speed image)
                                           0)))
     :active image-multi-frame
     :help "Reverse direction of this image's animation?"]
    ["Speed Up Animation" image-increase-speed
     :active image-multi-frame
     :help "Speed up this image's animation"]
    ["Slow Down Animation" image-decrease-speed
     :active image-multi-frame
     :help "Slow down this image's animation"]
    ["Reset Animation Speed" image-reset-speed
     :active image-multi-frame
     :help "Reset the speed of this image's animation"]
    ["Previous Frame" image-previous-frame :active image-multi-frame
     :help "Show the previous frame of this image"]
    ["Next Frame" image-next-frame :active image-multi-frame
     :help "Show the next frame of this image"]
    ["Goto Frame..." image-goto-frame :active image-multi-frame
     :help "Show a specific frame of this image"]))

(defvar-keymap image-minor-mode-map
  :doc "Mode keymap for `image-minor-mode'."
  "C-c C-c" #'image-toggle-display
  "C-c C-x" #'image-toggle-hex-display)

(defvar bookmark-make-record-function)

(put 'image-mode 'mode-class 'special)

(declare-function image-converter-initialize "image-converter.el")

;;;###autoload
(defun image-mode ()
  "Major mode for image files.
You can use \\<image-mode-map>\\[image-toggle-display] or \
\\[image-toggle-hex-display] to toggle between display
as an image and display as text or hex.

Key bindings:
\\{image-mode-map}"
  (interactive)
  (unless (display-images-p)
    (error "Display does not support images"))

  (unless (eq major-mode 'image-mode)
    (major-mode-suspend)
    (setq major-mode 'image-mode))
  (setq image-transform-resize image-auto-resize)

  ;; Bail out early if we have no image data.
  (if (zerop (buffer-size))
      (funcall (if (called-interactively-p 'any) 'error 'message)
               (if (stringp buffer-file-name)
                   (if (file-exists-p buffer-file-name)
                       "Empty file"
                     "(New file)")
                 "Empty buffer"))
    (image-mode--display)
    (setq-local image-crop-buffer-text-function
                ;; Use the binary image data directly for the buffer text.
                (lambda (_text image) image))
    ;; Ensure that we recognize externally parsed image formats in
    ;; commands like `n'.
    (when image-use-external-converter
      (require 'image-converter)
      (image-converter-initialize))))

(defun image-mode--display ()
  (if (not (image-get-display-property))
      (progn
        (when (condition-case err
                  (progn
	            (image-toggle-display-image)
                    t)
                (unknown-image-type
                 (image-mode-as-text)
                 (funcall
                  (if (called-interactively-p 'any) 'error 'message)
                  (if image-use-external-converter
                      "Unknown image type"
                    "Unknown image type; consider switching `image-use-external-converter' on"))
                 nil)
                (error
                 (image-mode-as-text)
                 (funcall
                  (if (called-interactively-p 'any) 'error 'message)
                  "Cannot display image: %s" (cdr err))
                 nil))
	  ;; If attempt to display the image fails.
	  (if (not (image-get-display-property))
	      (error "Invalid image"))
          (image-mode--setup-mode)))
    ;; Set next vars when image is already displayed but local
    ;; variables were cleared by kill-all-local-variables
    (setq cursor-type nil truncate-lines t
	  image-type (plist-get (cdr (image-get-display-property)) :type))
    (image-mode--setup-mode)))

(defun image-mode--setup-mode ()
  (setq mode-name (if image-type (format "Image[%s]" image-type) "Image"))
  (use-local-map image-mode-map)

  ;; Use our own bookmarking function for images.
  (setq-local bookmark-make-record-function
              #'image-bookmark-make-record)

  ;; Keep track of [vh]scroll when switching buffers
  (image-mode-setup-winprops)

  (add-hook 'change-major-mode-hook #'image-toggle-display-text nil t)
  (add-hook 'after-revert-hook #'image-after-revert-hook nil t)
  (when image-auto-resize-on-window-resize
    (add-hook 'window-state-change-functions #'image--window-state-change nil t))

  (add-function :before-while (local 'isearch-filter-predicate)
                #'image-mode-isearch-filter)

  (run-mode-hooks 'image-mode-hook)
  (let ((image (image-get-display-property))
        msg animated)
    (cond
     ((null image)
      (setq msg "an image"))
     ((setq animated (image-multi-frame-p image))
      (setq image-multi-frame t
	    mode-line-process
	    `(:eval
	      (concat " "
		      (propertize
		       (format "[%s/%s]"
			       (1+ (image-current-frame ',image))
			       ,(car animated))
		       'help-echo "Frames\nmouse-1: Next frame\nmouse-3: Previous frame"
		       'mouse-face 'mode-line-highlight
		       'local-map
		       '(keymap
			 (mode-line
			  keymap
			  (down-mouse-1 . image-next-frame)
			  (down-mouse-3 . image-previous-frame)))))))
      (setq msg "text.  This image has multiple frames"))
     (t
      (setq msg "text")))
    (when (memq (plist-get (cdr image) :type) image-text-based-formats)
      (message (substitute-command-keys
                "Type \\[image-toggle-display] to view the image as %s")
               msg))))

;;;###autoload
(define-minor-mode image-minor-mode
  "Toggle Image minor mode in this buffer.

Image minor mode provides the key \\<image-mode-map>\\[image-toggle-display], \
to switch back to
`image-mode' and display an image file as the actual image."
  :lighter (:eval (if image-type (format " Image[%s]" image-type) " Image"))
  :group 'image
  :version "22.1"
  (if image-minor-mode
      (add-hook 'change-major-mode-hook (lambda () (image-minor-mode -1)) nil t)))

;;;###autoload
(defun image-mode-to-text ()
  "Set current buffer's modes be a non-image major mode, plus `image-minor-mode'.
A non-image major mode displays an image file as text."
  ;; image-mode-as-text = normal-mode + image-minor-mode
  (let ((previous-image-type image-type)) ; preserve `image-type'
    (major-mode-restore '(image-mode image-mode-as-text))
    ;; Restore `image-type' after `kill-all-local-variables' in `normal-mode'.
    (setq image-type previous-image-type)
    (unless (image-get-display-property)
      ;; Show the image file as text.
      (image-toggle-display-text))))

(defun image-mode-as-hex ()
  "Set current buffer's modes be `hexl-mode' major mode, plus `image-minor-mode'.
This will by default display an image file as hex.  `image-minor-mode'
provides the key sequence \\<image-mode-map>\\[image-toggle-hex-display] to \
switch back to `image-mode' to display
an image file's buffer as an image.

You can use `image-mode-as-hex' in `auto-mode-alist' when you want to
display image files as hex by default.

See commands `image-mode' and `image-minor-mode' for more information
on these modes."
  (interactive)
  (image-mode-to-text)
  (hexl-mode)
  (image-minor-mode 1)
  (message (substitute-command-keys
            "Type \\[image-toggle-display] or \
\\[image-toggle-hex-display] to view the image as an image")))

(defun image-mode-as-text ()
  "Set a non-image mode as major mode in combination with image minor mode.
A non-image major mode found from `auto-mode-alist' or Fundamental mode
displays an image file as text.  `image-minor-mode' provides the key
\\<image-mode-map>\\[image-toggle-display] to switch back to `image-mode'
to display an image file as the actual image.

You can use `image-mode-as-text' in `auto-mode-alist' when you want
to display an image file as text initially.

See commands `image-mode' and `image-minor-mode' for more information
on these modes."
  (interactive)
  (image-mode-to-text)
  (image-minor-mode 1)
  (message (substitute-command-keys
            "Type \\[image-toggle-display] to view the image as %s")
           (if (image-get-display-property)
               "text" "an image")))

(defun image-toggle-display-text ()
  "Show the image file as text.
Remove text properties that display the image."
  (let ((inhibit-read-only t)
	(buffer-undo-list t)
	(create-lockfiles nil) ; avoid changing dir mtime by lock_file
	(modified (buffer-modified-p)))
    (remove-list-of-text-properties (point-min) (point-max)
				    '(display read-nonsticky ;; intangible
					      read-only front-sticky))
    (set-buffer-modified-p modified)
    (if (called-interactively-p 'any)
	(message "Repeat this command to go back to displaying the image"))))

(defun image-mode-isearch-filter (_beg _end)
  "Show image as text when trying to search/replace in the image buffer."
  (save-match-data
    (when (and (derived-mode-p 'image-mode)
               (image-get-display-property))
      (image-mode-as-text)))
  t)

(defvar archive-superior-buffer)
(defvar tar-superior-buffer)
(declare-function image-flush "image.c" (spec &optional frame))

(defun image--scale-within-limits-p (image)
  "Return t if `fit-window' will scale image within the customized limits.
The limits are given by the user option
`image-auto-resize-max-scale-percent'."
  (or (not image-auto-resize-max-scale-percent)
      (let ((scale (/ image-auto-resize-max-scale-percent 100))
            (mw (plist-get (cdr image) :max-width))
            (mh (plist-get (cdr image) :max-height))
            ;; Note: `image-size' looks up and thus caches the
            ;; untransformed image.  There's no easy way to
            ;; prevent that.
            (size (image-size image t)))
        (or (<= mw (* (car size) scale))
            (<= mh (* (cdr size) scale))))))

(defun image-toggle-display-image ()
  "Show the image of the image file.
Turn the image data into a real image, but only if the whole file
was inserted."
  (unless (derived-mode-p 'image-mode)
    (error "The buffer is not in Image mode"))
  (let* ((filename (buffer-file-name))
	 (data-p (not (and filename
			   (file-readable-p filename)
			   (not (file-remote-p filename))
			   (not (buffer-modified-p))
			   (not (and (boundp 'archive-superior-buffer)
				     archive-superior-buffer))
			   (not (and (boundp 'tar-superior-buffer)
				     tar-superior-buffer))
                           ;; This means the buffer holds the contents
                           ;; of a file uncompressed by jka-compr.el.
                           (not (and (local-variable-p
                                      'jka-compr-really-do-compress)
                                     jka-compr-really-do-compress))
                           ;; This means the buffer holds the
                           ;; decrypted content (bug#21870).
                           (not (local-variable-p
                                 'epa-file-encrypt-to)))))
	 (file-or-data
          (if data-p
	      (let ((str
		     (buffer-substring-no-properties (point-min) (point-max))))
                (if enable-multibyte-characters
                    (encode-coding-string str buffer-file-coding-system)
                  str))
	    filename))
	 ;; If we have a `fit-width' or a `fit-height', don't limit
	 ;; the size of the image to the window size.
         (edges (when (or (eq image-transform-resize t)
                          (eq image-transform-resize 'fit-window))
		  (window-inside-pixel-edges (get-buffer-window))))
	 (max-width (when edges
		      (- (nth 2 edges) (nth 0 edges))))
	 (max-height (when edges
		       (- (nth 3 edges) (nth 1 edges))))
	 (inhibit-read-only t)
	 (buffer-undo-list t)
	 (modified (buffer-modified-p))
	 props image type)

    ;; If the data in the current buffer isn't from an existing file,
    ;; but we have a file name (this happens when visiting images from
    ;; a zip file, for instance), provide a type hint based on the
    ;; suffix.
    (when (and data-p filename)
      (setq data-p (intern (format "image/%s"
                                   (file-name-extension filename)))))
    (setq type (if (image--imagemagick-wanted-p filename)
		   'imagemagick
		 (image-type file-or-data nil data-p)))

    ;; Get the rotation data from the file, if any.
    (when (zerop image-transform-rotation) ; don't reset modified value
      (setq image-transform-rotation
            (or (exif-orientation
                 (ignore-error exif-error
                   ;; exif-parse-buffer can move point, so preserve it.
                   (save-excursion
                     (exif-parse-buffer))))
                0.0)))
    ;; Swap width and height when changing orientation
    ;; between portrait and landscape.
    (when (and edges (zerop (mod (+ image-transform-rotation 90) 180)))
      (setq max-width (prog1 max-height (setq max-height max-width))))

    ;; :scale 1: If we do not set this, create-image will apply
    ;; default scaling based on font size.
    (setq image (if (not edges)
		    (create-image file-or-data type data-p :scale 1
                                  :format (and filename data-p))
		  (create-image file-or-data type data-p :scale 1
				:max-width max-width
				:max-height max-height
                                ;; Type hint.
                                :format (and filename data-p))))

    ;; Handle `fit-window'.
    (when (and (eq image-transform-resize 'fit-window)
               (image--scale-within-limits-p image))
      (setq image
            (cons (car image)
                  (plist-put (cdr image) :width
                             (plist-get (cdr image) :max-width)))))

    ;; Discard any stale image data before looking it up again.
    (image-flush image)
    (setq image (append image (image-transform-properties image)))
    (setq props
	  `(display ,image
		    ;; intangible ,image
		    rear-nonsticky (display) ;; intangible
		    read-only t front-sticky (read-only)))

    (let ((create-lockfiles nil)) ; avoid changing dir mtime by lock_file
      (add-text-properties (point-min) (point-max) props)
      (restore-buffer-modified-p modified))
    ;; Inhibit the cursor when the buffer contains only an image,
    ;; because cursors look very strange on top of images.
    (setq cursor-type nil)
    ;; This just makes the arrow displayed in the right fringe
    ;; area look correct when the image is wider than the window.
    (setq truncate-lines t)
    ;; Disable adding a newline at the end of the image file when it
    ;; is written with, e.g., C-x C-w.
    (if (coding-system-equal (coding-system-base buffer-file-coding-system)
			     'no-conversion)
	(setq-local find-file-literally t))
    ;; Allow navigation of large images.
    (setq-local auto-hscroll-mode nil)
    (setq image-type type)
    (if (eq major-mode 'image-mode)
	(setq mode-name (format "Image[%s]" type)))
    (image-transform-check-size)
    (if (called-interactively-p 'any)
	(message "Repeat this command to go back to displaying the file as text"))))

(defun image--imagemagick-wanted-p (filename)
  (and (fboundp 'imagemagick-types)
       (not (eq imagemagick-types-inhibit t))
       (not (and filename (file-name-extension filename)
                 (memq (intern (upcase (file-name-extension filename)) obarray)
                       imagemagick-types-inhibit)))))

(declare-function hexl-mode-exit "hexl" (&optional arg))

(defun image-toggle-hex-display ()
  "Toggle between image and hex display."
  (interactive)
  (cond ((or (image-get-display-property) ; in `image-mode'
             (eq major-mode 'fundamental-mode))
         (image-mode-as-hex))
        ((eq major-mode 'hexl-mode)
         (hexl-mode-exit))
        (t (error "That command is invalid here"))))

(defun image-toggle-display ()
  "Toggle between image and text display.

If the current buffer is displaying an image file as an image,
call `image-mode-as-text' to switch to text or hex display.
Otherwise, display the image by calling `image-mode'."
  (interactive)
  (cond ((image-get-display-property) ; in `image-mode'
         (image-mode-as-text))
        ((eq major-mode 'hexl-mode)
         (hexl-mode-exit))
        ((image-mode))))

(defun image-kill-buffer ()
  "Kill the current buffer."
  (interactive nil image-mode)
  (kill-buffer (current-buffer)))

(defun image-after-revert-hook ()
  ;; Fixes bug#21598
  (when (not (image-get-display-property))
    (image-toggle-display-image))
  (when (image-get-display-property)
    (image-toggle-display-text)
    ;; Update image display.
    (mapc (lambda (window) (redraw-frame (window-frame window)))
          (get-buffer-window-list (current-buffer) 'nomini 'visible))
    (image-toggle-display-image)))

(defvar image-auto-resize-timer nil
  "Timer for `image-auto-resize-on-window-resize' option.")

(defun image--window-state-change (window)
  ;; Wait for a bit of idle-time before actually performing the change,
  ;; so as to batch together sequences of closely consecutive size changes.
  ;; `image-fit-to-window' just changes one value in a plist.  The actual
  ;; image resizing happens later during redisplay.  So if those
  ;; consecutive calls happen without any redisplay between them,
  ;; the costly operation of image resizing should happen only once.
  (when (numberp image-auto-resize-on-window-resize)
    (when image-auto-resize-timer
      (cancel-timer image-auto-resize-timer))
    (setq image-auto-resize-timer
          (run-with-idle-timer image-auto-resize-on-window-resize nil
                               #'image-fit-to-window window))))

(defvar image-fit-to-window-lock nil
  "Lock for `image-fit-to-window' timer function.")

(defun image-fit-to-window (window)
  "Adjust size of image to display it exactly in WINDOW boundaries."
  (when (and (window-live-p window)
             ;; Don't resize anything if we're in the minibuffer
             ;; (which may transitively change the window sizes if you
             ;; hit TAB, for instance).
             (not (minibuffer-window-active-p (selected-window)))
             ;; Don't resize if there's a message in the echo area.
             (not (current-message)))
    (with-current-buffer (window-buffer window)
      (when (derived-mode-p 'image-mode)
        (let ((spec (image-get-display-property)))
          (when (eq (car-safe spec) 'image)
            (let* ((image-width  (plist-get (cdr spec) :max-width))
                   (image-height (plist-get (cdr spec) :max-height))
                   (edges (window-inside-pixel-edges window))
                   (window-width  (- (nth 2 edges) (nth 0 edges)))
                   (window-height (- (nth 3 edges) (nth 1 edges))))
              ;; If the size has been changed manually (with `+'/`-'),
              ;; then :max-width/:max-height is nil.  In that case, do
              ;; no automatic resizing.
              (when (and image-width image-height
                         ;; Don't do resizing if we have a manual
                         ;; rotation (from the `r' command), either.
                         (not (plist-get (cdr spec) :rotation))
                         (or (not (= image-width  window-width))
                             (not (= image-height window-height))))
                (unless image-fit-to-window-lock
                  (unwind-protect
                      (progn
                        (setq-local image-fit-to-window-lock t)
                        (ignore-error remote-file-error
                          (image-toggle-display-image)))
                    (setq image-fit-to-window-lock nil)))))))))))


;;; Animated images

(defcustom image-animate-loop nil
  "Non-nil means animated images loop forever, rather than playing once."
  :type 'boolean
  :version "24.1"
  :group 'image)

(defun image-toggle-animation ()
  "Start or stop animating the current image.
If `image-animate-loop' is non-nil, animation loops forever.
Otherwise it plays once, then stops."
  (interactive)
  (let ((image (image-get-display-property))
	animation)
    (cond
     ((null image)
      (error "No image is present"))
     ((null (setq animation (image-multi-frame-p image)))
      (message "No image animation."))
     (t
      (let ((timer (image-animate-timer image)))
	(if timer
	    (cancel-timer timer)
	  (let ((index (plist-get (cdr image) :index)))
	    ;; If we're at the end, restart.
	    (and index
		 (>= index (1- (car animation)))
		 (setq index nil))
	    (image-animate image index
			   (if image-animate-loop t)))))))))

(defun image--set-speed (speed &optional multiply)
  "Set speed of an animated image to SPEED.
If MULTIPLY is non-nil, treat SPEED as a multiplication factor.
If SPEED is `reset', reset the magnitude of the speed to 1."
  (let ((image (image-get-display-property)))
    (cond
     ((null image)
      (error "No image is present"))
     ((null image-multi-frame)
      (message "No image animation."))
     (t
      (if (eq speed 'reset)
	  (setq speed (if (< (image-animate-get-speed image) 0)
			  -1 1)
		multiply nil))
      (image-animate-set-speed image speed multiply)
      ;; FIXME Hack to refresh an active image.
      (when (image-animate-timer image)
	(image-toggle-animation)
	(image-toggle-animation))
      (message "Image speed is now %s" (image-animate-get-speed image))))))

(defun image-increase-speed ()
  "Increase the speed of current animated image by a factor of 2."
  (interactive)
  (image--set-speed 2 t))

(defun image-decrease-speed ()
  "Decrease the speed of current animated image by a factor of 2."
  (interactive)
  (image--set-speed 0.5 t))

(defun image-reverse-speed ()
  "Reverse the animation of the current image."
  (interactive)
  (image--set-speed -1 t))

(defun image-reset-speed ()
  "Reset the animation speed of the current image."
  (interactive)
  (image--set-speed 'reset))

(defun image-goto-frame (n &optional relative)
  "Show frame N of a multi-frame image.
Optional argument OFFSET non-nil means interpret N as relative to the
current frame.  Frames are indexed from 1."
  (interactive
   (list (or current-prefix-arg
	     (read-number "Show frame number: "))))
  (let ((image (image-get-display-property)))
    (cond
     ((null image)
      (error "No image is present"))
     ((null image-multi-frame)
      (message "No image animation."))
     (t
      (image-show-frame image
			(if relative
			    (+ n (image-current-frame image))
			  (1- n)))))))

(defun image-next-frame (&optional n)
  "Switch to the next frame of a multi-frame image.
With optional argument N, switch to the Nth frame after the current one.
If N is negative, switch to the Nth frame before the current one."
  (interactive "p")
  (image-goto-frame n t))

(defun image-previous-frame (&optional n)
  "Switch to the previous frame of a multi-frame image.
With optional argument N, switch to the Nth frame before the current one.
If N is negative, switch to the Nth frame after the current one."
  (interactive "p")
  (image-next-frame (- n)))


;;; Switching to the next/previous image

(defun image-next-file (&optional n)
  "Visit the next image in the same directory as the current image file.
With optional argument N, visit the Nth image file after the
current one, in cyclic alphabetical order.

This command visits the specified file via `find-alternate-file',
replacing the current Image mode buffer."
  (interactive "p" image-mode)
  (unless (derived-mode-p 'image-mode)
    (error "The buffer is not in Image mode"))
  (unless buffer-file-name
    (error "The current image is not associated with a file"))
  (let ((next (image-mode--next-file buffer-file-name n)))
    (unless next
      (user-error "No %s file in this directory"
                  (if (> n 0)
                      "next"
                    "prev")))
    (if (stringp next)
        (find-alternate-file next)
      (funcall next))))

(defun image-mode--directory-buffers (file)
  "Return an alist of type/buffer for all \"parent\" buffers to image FILE.
This is normally a list of Dired buffers, but can also be archive and
tar mode buffers."
  (let* ((non-essential t) ; Do not block for remote buffers.
         (buffers nil)
         (dir (file-name-directory file)))
    (cond
     ((and (boundp 'tar-superior-buffer)
	   tar-superior-buffer)
      (when (buffer-live-p tar-superior-buffer)
        (push (cons 'tar tar-superior-buffer) buffers)))
     ((and (boundp 'archive-superior-buffer)
	   archive-superior-buffer)
      (when (buffer-live-p archive-superior-buffer)
        (push (cons 'archive archive-superior-buffer) buffers)))
     (t
      ;; Find a Dired buffer.
      (dolist (buffer (buffer-list))
        (with-current-buffer buffer
          (when (and (derived-mode-p 'dired-mode)
	             (equal (file-remote-p dir)
		            (file-remote-p default-directory))
	             (equal (file-truename dir)
		            (file-truename default-directory)))
            (push (cons 'dired (current-buffer)) buffers))))
      ;; If we can't find any buffers to navigate in, we open a Dired
      ;; buffer.
      (unless buffers
        (push (cons 'dired (find-file-noselect dir)) buffers)
        (message "Opened a dired buffer on %s" dir))))
    buffers))

(declare-function archive-next-file-displayer "arc-mode")
(declare-function tar-next-file-displayer "tar-mode")

(defun image-mode--next-file (file n)
  "Go to the next image file in the parent buffer of FILE.
This is typically a Dired buffer, but may also be a tar/archive buffer.
Return the next image file from that buffer.
If N is negative, go to the previous file."
  (let ((regexp (image-file-name-regexp))
        (buffers (image-mode--directory-buffers file))
        next)
    (dolist (buffer buffers)
      ;; We do this traversal for all the Dired buffers open on this
      ;; directory.  There probably is just one, but we want to move
      ;; point in all of them.
      (save-window-excursion
        (switch-to-buffer (cdr buffer) t t)
        (cl-case (car buffer)
          (dired
           (dired-goto-file file)
           (let (found)
             (while (and (not found)
                         ;; Stop if we reach the end/start of the buffer.
                         (if (> n 0)
                             (not (eobp))
                           (not (bobp))))
               (dired-next-line n)
               (let ((candidate (dired-get-filename nil t)))
                 (when (and candidate
                            (string-match-p regexp candidate))
                   (setq found candidate))))
             (if found
                 (setq next found)
               ;; If we didn't find a next/prev file, then restore
               ;; point.
               (dired-goto-file file))))
          (archive
           (setq next (archive-next-file-displayer file regexp n)))
          (tar
           (setq next (tar-next-file-displayer file regexp n))))))
    next))

(defun image-previous-file (&optional n)
  "Visit the preceding image in the same directory as the current file.
With optional argument N, visit the Nth image file preceding the
current one, in cyclic alphabetical order.

This command visits the specified file via `find-alternate-file',
replacing the current Image mode buffer."
  (interactive "p" image-mode)
  (image-next-file (- n)))

(defun image-mode-copy-file-name-as-kill ()
  "Push the currently visited file name onto the kill ring."
  (interactive nil image-mode)
  (unless buffer-file-name
    (error "The current buffer doesn't visit a file"))
  (kill-new buffer-file-name)
  (message "Copied %s" buffer-file-name))

(defun image-mode-mark-file ()
  "Mark the current file in the appropriate Dired buffer(s).
Any Dired buffer that's opened to the current file's directory
will have the line where the image appears (if any) marked.

If no such buffer exists, it will be opened."
  (interactive nil image-mode)
  (unless buffer-file-name
    (error "Current buffer is not visiting a file"))
  (image-mode--mark-file buffer-file-name #'dired-mark "marked"))

(defun image-mode-unmark-file ()
  "Unmark the current file in the appropriate Dired buffer(s).
Any Dired buffer that's opened to the current file's directory
will remove the mark from the line where the image appears (if
any).

If no such buffer exists, it will be opened."
  (interactive nil image-mode)
  (unless buffer-file-name
    (error "Current buffer is not visiting a file"))
  (image-mode--mark-file buffer-file-name #'dired-unmark "unmarked"))

(declare-function dired-mark "dired" (arg &optional interactive))
(declare-function dired-unmark "dired" (arg &optional interactive))
(declare-function dired-goto-file "dired" (file))

(defun image-mode--mark-file (file function message)
  (require 'dired)
  (let* ((dir (file-name-directory file))
	 (buffers
          (cl-loop for buffer in (buffer-list)
		   when (with-current-buffer buffer
			  (and (eq major-mode 'dired-mode)
			       (equal (file-truename dir)
				      (file-truename default-directory))))
		   collect buffer))
         results)
    (unless buffers
      (save-excursion
        (setq buffers (list (find-file-noselect dir)))))
    (dolist (buffer buffers)
      (with-current-buffer buffer
	(if (not (dired-goto-file file))
            (push (format "couldn't find in %s" (directory-file-name dir))
                  results)
	  (funcall function 1)
          (push (format "%s in %s" message (directory-file-name dir))
                results))))
    ;; Capitalize first character.
    (let ((string (mapconcat #'identity results "; ")))
      (message "%s%s" (capitalize (substring string 0 1))
               (substring string 1)))))


;;; Support for bookmark.el
(declare-function bookmark-make-record-default
                  "bookmark" (&optional no-file no-context posn))
(declare-function bookmark-prop-get "bookmark" (bookmark prop))
(declare-function bookmark-default-handler "bookmark" (bmk))

(defun image-bookmark-make-record ()
  `(,@(bookmark-make-record-default nil 'no-context 0)
      (image-type . ,image-type)
      (handler    . image-bookmark-jump)))

;;;###autoload
(defun image-bookmark-jump (bmk)
  ;; This implements the `handler' function interface for record type
  ;; returned by `bookmark-make-record-function', which see.
  (prog1 (bookmark-default-handler bmk)
    (when (not (string= image-type (bookmark-prop-get bmk 'image-type)))
      (image-toggle-display))))


;;; Setting the wallpaper

(defun image-mode-wallpaper-set ()
  "Set the desktop background to the current image.
This uses `wallpaper-set' (which see)."
  (interactive nil image-mode)
  (wallpaper-set buffer-file-name))


;;; Image transformation

(defsubst image-transform-width (width height)
  "Return the bounding box width of a rotated WIDTH x HEIGHT rectangle.
The rotation angle is the value of `image-transform-rotation' in degrees."
  (let ((angle (degrees-to-radians image-transform-rotation)))
    ;; Assume, w.l.o.g., that the vertices of the rectangle have the
    ;; coordinates (+-w/2, +-h/2) and that (0, 0) is the center of the
    ;; rotation by the angle A.  The projections onto the first axis
    ;; of the vertices of the rotated rectangle are +- (w/2) cos A +-
    ;; (h/2) sin A, and the difference between the largest and the
    ;; smallest of the four values is the expression below.
    (+ (* width (abs (cos angle))) (* height (abs (sin angle))))))

;; The following comment and code snippet are from
;; ImageMagick-6.7.4-4/magick/distort.c

;;    /* Set the output image geometry to calculated 'best fit'.
;;       Yes this tends to 'over do' the file image size, ON PURPOSE!
;;       Do not do this for DePolar which needs to be exact for virtual tiling.
;;    */
;;    if ( fix_bounds ) {
;;      geometry.x = (ssize_t) floor(min.x-0.5);
;;      geometry.y = (ssize_t) floor(min.y-0.5);
;;      geometry.width=(size_t) ceil(max.x-geometry.x+0.5);
;;      geometry.height=(size_t) ceil(max.y-geometry.y+0.5);
;;    }

;; Other parts of the same file show that here the origin is in the
;; left lower corner of the image rectangle, the center of the
;; rotation is the center of the rectangle and min.x and max.x
;; (resp. min.y and max.y) are the smallest and the largest of the
;; projections of the vertices onto the first (resp. second) axis.

(defun image-transform-fit-width (width height length)
  "Return (w . h) so that a rotated w x h image has exactly width LENGTH.
The rotation angle is the value of `image-transform-rotation'.
Write W for WIDTH and H for HEIGHT.  Then the w x h rectangle is
an \"approximately uniformly\" scaled W x H rectangle, which
currently means that w is one of floor(s W) + {0, 1, -1} and h is
floor(s H), where s can be recovered as the value of `image-transform-scale'.
The value of `image-transform-rotation' may be replaced by
a slightly different angle.  Currently this is done for values
close to a multiple of 90, see `image-transform-right-angle-fudge'."
  (cond ((< (abs (- (mod (+ image-transform-rotation 90) 180) 90))
	    image-transform-right-angle-fudge)
	 (cl-assert (not (zerop width)) t)
	 (setq image-transform-rotation
	       (float (round image-transform-rotation))
	       image-transform-scale (/ (float length) width))
	 (cons length nil))
	((< (abs (- (mod (+ image-transform-rotation 45) 90) 45))
	    image-transform-right-angle-fudge)
	 (cl-assert (not (zerop height)) t)
	 (setq image-transform-rotation
	       (float (round image-transform-rotation))
	       image-transform-scale (/ (float length) height))
	 (cons nil length))
	(t
	 (cl-assert (not (and (zerop width) (zerop height))) t)
	 (setq image-transform-scale
	       (/ (float (1- length)) (image-transform-width width height)))
	 ;; Assume we have a w x h image and an angle A, and let l =
	 ;; l(w, h) = w |cos A| + h |sin A|, which is the actual width
	 ;; of the bounding box of the rotated image, as calculated by
	 ;; `image-transform-width'.  The code snippet quoted above
	 ;; means that ImageMagick puts the rotated image in
	 ;; a bounding box of width L = 2 ceil((w+l+1)/2) - w.
	 ;; Elementary considerations show that this is equivalent to
	 ;; L - w being even and L-3 < l(w, h) <= L-1.  In our case, L is
	 ;; the given `length' parameter and our job is to determine
	 ;; reasonable values for w and h which satisfy these
	 ;; conditions.
	 (let ((w (floor (* image-transform-scale width)))
	       (h (floor (* image-transform-scale height))))
	   ;; Let w and h as bound above.  Then l(w, h) <= l(s W, s H)
	   ;; = L-1 < l(w+1, h+1) = l(w, h) + l(1, 1) <= l(w, h) + 2,
	   ;; hence l(w, h) > (L-1) - 2 = L-3.
	   (cons
	    (cond ((= (mod w 2) (mod length 2))
		   w)
		  ;; l(w+1, h) >= l(w, h) > L-3, but does l(w+1, h) <=
		  ;; L-1 hold?
		  ((<= (image-transform-width (1+ w) h) (1- length))
		   (1+ w))
		  ;; No, it doesn't, but this implies that l(w-1, h) =
		  ;; l(w+1, h) - l(2, 0) >= l(w+1, h) - 2 > (L-1) -
		  ;; 2 = L-3.  Clearly, l(w-1, h) <= l(w, h) <= L-1.
		  (t
		   (1- w)))
	    h)))))

(defun image-transform-check-size ()
  "Check that the image exactly fits the width/height of the window.

Do this for an image of type `imagemagick' to make sure that the
elisp code matches the way ImageMagick computes the bounding box
of a rotated image."
  (when (and (not (numberp image-transform-resize))
	     (boundp 'image-type))
    (let ((size (image-display-size (image-get-display-property) t)))
      (cond ((eq image-transform-resize 'fit-width)
	     (cl-assert (= (car size)
			(- (nth 2 (window-inside-pixel-edges))
			   (nth 0 (window-inside-pixel-edges))))
		     t))
	    ((eq image-transform-resize 'fit-height)
	     (cl-assert (= (cdr size)
			(- (nth 3 (window-inside-pixel-edges))
			   (nth 1 (window-inside-pixel-edges))))
		     t))))))

(defun image-transform-properties (spec)
  "Return rescaling/rotation properties for image SPEC.
These properties are determined by the Image mode variables
`image-transform-resize' and `image-transform-rotation'.  The
return value is suitable for appending to an image spec."
  (setq image-transform-scale 1.0)
  (when (or (not (memq image-transform-resize '(nil t)))
	    (/= image-transform-rotation 0.0))
    ;; Note: `image-size' looks up and thus caches the untransformed
    ;; image.  There's no easy way to prevent that.
    (let* ((size (image-size spec t))
           (edges (window-inside-pixel-edges (get-buffer-window)))
	   (resized
	    (cond
	     ((numberp image-transform-resize)
	      (unless (= image-transform-resize 1)
		(setq image-transform-scale image-transform-resize)
		(cons nil (floor (* image-transform-resize (cdr size))))))
	     ((eq image-transform-resize 'fit-width)
	      (image-transform-fit-width
	       (car size) (cdr size)
	       (- (nth 2 edges) (nth 0 edges))))
	     ((eq image-transform-resize 'fit-height)
	      (let ((res (image-transform-fit-width
			  (cdr size) (car size)
			  (- (nth 3 edges) (nth 1 edges)))))
		(cons (cdr res) (car res)))))))
      `(,@(when (car resized)
	    (list :width (car resized)))
	,@(when (cdr resized)
	    (list :height (cdr resized)))
	,@(unless (= 0.0 image-transform-rotation)
	    (list :rotation image-transform-rotation))
        ,@(when image--transform-smoothing
            (list :transform-smoothing
                  (string= image--transform-smoothing "smooth")))))))

(defun image-transform-set-percent (scale)
  "Prompt for a percentage, and resize the current image to that size.
The percentage is in relation to the original size of the image."
  (interactive (list (read-number "Scale (% of original): " 100
                                  'read-number-history))
               image-mode)
  (unless (cl-plusp scale)
    (error "Not a positive number: %s" scale))
  (setq image-transform-resize (/ scale 100.0))
  (image-toggle-display-image))

(defun image-transform-set-scale (scale)
  "Prompt for a number, and resize the current image by that amount."
  (interactive "nScale: " image-mode)
  (setq image-transform-resize scale)
  (image-toggle-display-image))

(defun image-transform-fit-to-height ()
  "Fit the current image to the height of the current window."
  (declare (obsolete image-transform-fit-to-window "29.1"))
  (interactive nil image-mode)
  (setq image-transform-resize 'fit-height)
  (image-toggle-display-image))

(defun image-transform-fit-to-width ()
  "Fit the current image to the width of the current window."
  (declare (obsolete image-transform-fit-to-window "29.1"))
  (interactive nil image-mode)
  (setq image-transform-resize 'fit-width)
  (image-toggle-display-image))

(defun image-transform-fit-both ()
  "Scale the current image down to fit in the current window."
  (interactive nil image-mode)
  (setq image-transform-resize t)
  (image-toggle-display-image))

(defun image-transform-fit-to-window ()
  "Fit the current image to the height and width of the current window."
  (interactive nil image-mode)
  (setq image-transform-resize 'fit-window)
  (image-toggle-display-image))

(defun image-transform-fill-window ()
  "Fill the window with the image while keeping image proportions.
This means filling the window with the image as much as possible
without leaving empty space around image edges.  Then you can use
either horizontal or vertical scrolling to see the remaining parts
of the image."
  (interactive nil image-mode)
  (let ((size (image-display-size (image-get-display-property) t)))
    (setq image-transform-resize
          (if (> (car size) (cdr size)) 'fit-height 'fit-width)))
  (image-toggle-display-image))

(defun image-transform-set-rotation (rotation)
  "Prompt for an angle ROTATION, and rotate the image by that amount.
ROTATION should be in degrees."
  (interactive "nRotation angle (in degrees): " image-mode)
  (setq image-transform-rotation (float (mod rotation 360)))
  (image-toggle-display-image))

(defun image-transform-set-smoothing (smoothing)
  (interactive (list (completing-read "Smoothing: "
                                      '("none" "smooth") nil t))
               image-mode)
  (setq image--transform-smoothing smoothing)
  (image-toggle-display-image))

(defun image-transform-reset-to-original ()
  "Display the current image with the original (actual) size and rotation."
  (interactive nil image-mode)
  (setq image-transform-resize nil
	image-transform-scale 1)
  (image-toggle-display-image))

(defun image-transform-reset-to-initial ()
  "Display the current image with the default (initial) size and rotation."
  (interactive nil image-mode)
  (setq image-transform-resize image-auto-resize
	image-transform-rotation 0.0
	image-transform-scale 1
        image--transform-smoothing nil)
  (image-toggle-display-image))

(defun image-mode--images-in-directory (file)
  (declare (obsolete nil "29.1"))
  (let* ((dir (file-name-directory buffer-file-name))
         (files (directory-files dir nil
                                 (image-file-name-regexp) t)))
    ;; Add the current file to the list of images if necessary, in
    ;; case it does not match `image-file-name-regexp'.
    (unless (member file files)
      (push file files))
    (sort files 'string-lessp)))

(define-obsolete-function-alias 'image-transform-original #'image-transform-reset-to-original "29.1")
(define-obsolete-function-alias 'image-transform-reset #'image-transform-reset-to-initial "29.1")

(provide 'image-mode)

;;; image-mode.el ends here
