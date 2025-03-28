;;; chart.el --- Draw charts (bar charts, etc)  -*- lexical-binding: t -*-

;; Copyright (C) 1996-2025 Free Software Foundation, Inc.

;; Author: Eric M. Ludlam <zappo@gnu.org>
;; Old-Version: 0.2
;; Keywords: OO, chart, graph

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
;;   This package is an experiment of mine aiding in the debugging of
;; eieio, and proved to be neat enough that others may like to use
;; it.  To quickly see what you can do with chart, run the command
;; `chart-test-it-all'.
;;
;;   Chart current can display bar-charts in either of two
;; directions.  It also supports ranged (integer) axis, and axis
;; defined by some set of strings or names.  These name can be
;; automatically derived from data sequences, which are just lists of
;; anything encapsulated in a nice eieio object.
;;
;;   Current example apps for chart can be accessed via these commands:
;; `chart-file-count'     - count files with matching extensions
;; `chart-space-usage'    - display space used by files/directories
;; `chart-emacs-storage'  - Emacs storage units used/free (garbage-collect)
;; `chart-emacs-lists'    - length of Emacs lists
;; `chart-rmail-from'     - who sends you the most mail (in -summary only)
;;
;; Customization:
;;
;;   If you find the default colors and pixmaps unpleasant, or too
;; short, you can change them.  The variable `chart-face-color-list'
;; contains a list of colors, and `chart-face-pixmap-list' contains
;; all the pixmaps to use.  The current pixmaps are those found on
;; several systems I found.  The two lists should be the same length,
;; as the long list will just be truncated.
;;
;;   If you would like to draw your own stipples, simply create some
;; xbm's and put them in a directory, then you can add:
;;
;; (setq x-bitmap-file-path (cons "~/mybitmaps" x-bitmap-file-path))
;;
;; to your .emacs (or wherever) and load the `chart-face-pixmap-list'
;; with all the bitmaps you want to use.

(require 'eieio)
(eval-when-compile (require 'cl-lib))
(eval-when-compile (require 'cl-generic))

;;; Code:
(defvar-keymap chart-mode-map :doc "Keymap used in chart mode.")

(defvar-local chart-local-object nil
  "Local variable containing the locally displayed chart object.")

(defvar chart-face-color-list '("red" "green" "blue"
				"cyan" "yellow" "purple")
  "Colors to use when generating `chart-face-list'.
Colors will be the background color.")

(defvar chart-face-pixmap-list
  (if (display-graphic-p)
      '("dimple1" "scales" "dot" "cross_weave" "boxes" "dimple3"))
  "If pixmaps are allowed, display these background pixmaps.
Useful if new Emacs is used on B&W display.")

(defcustom chart-face-use-pixmaps nil
  "Non-nil to use fancy pixmaps in the background of chart face colors."
  :group 'eieio
  :type 'boolean)

(declare-function x-display-color-cells "xfns.c" (&optional terminal))

(defvar chart-face-list #'chart--face-list
  "Faces used to colorize charts.
This should either be a list of faces, or a function that returns
a list of faces.

List is limited currently, which is ok since you really can't display
too much in text characters anyways.")

(defun chart--face-list ()
  (and
   (display-color-p)
   (let ((cl chart-face-color-list)
         (pl chart-face-pixmap-list)
         (faces ())
         nf)
     (while cl
       (setq nf (make-face
                 (intern (concat "chart-" (car cl) "-" (car pl)))))
       (set-face-background nf (if (condition-case nil
                                       (> (x-display-color-cells) 4)
                                     (error t))
                                   (car cl)
                                 "white"))
       (set-face-foreground nf "black")
       (if (and chart-face-use-pixmaps pl)
           (condition-case nil
               (set-face-stipple nf (car pl))
             (error (message "Cannot set background pixmap %s" (car pl)))))
       (push nf faces)
       (setq cl (cdr cl)
             pl (cdr pl)))
     faces)))

(define-derived-mode chart-mode special-mode "Chart"
  "Define a mode in Emacs for displaying a chart."
  (buffer-disable-undo)
  (setq-local font-lock-global-modes nil)
  (font-lock-mode -1)                   ;Isn't it off already?  --Stef
  )

(defclass chart ()
  ((title :initarg :title
	  :initform "Emacs Chart")
   (title-face :initarg :title-face
	       :initform 'bold-italic)
   (x-axis :initarg :x-axis
	   :initform nil )
   (x-margin :initarg :x-margin
	     :initform 5)
   (x-width :initarg :x-width
	    )
   (y-axis :initarg :y-axis
	   :initform nil)
   (y-margin :initarg :y-margin
	     :initform 5)
   (y-width :initarg :y-width
	    )
   (key-label :initarg :key-label
	      :initform "Key")
   (sequences :initarg :sequences
	      :initform nil)
   )
  "Superclass for all charts to be displayed in an Emacs buffer.")

(defun chart-new-buffer (obj)
  "Create a new buffer NAME in which the chart OBJ is displayed.
Returns the newly created buffer."
  (with-current-buffer (get-buffer-create (format "*%s*" (oref obj title)))
    (chart-mode)
    (setq chart-local-object obj)
    (current-buffer)))

(cl-defmethod initialize-instance :after ((obj chart) &rest _fields)
  "Initialize the chart OBJ being created with FIELDS.
Make sure the width/height is correct."
  (oset obj x-width (- (window-width) 10))
  (oset obj y-width (- (window-height) 12)))

(defclass chart-axis ()
  ((name :initarg :name
	 :initform "Generic Axis")
   (loweredge :initarg :loweredge
	      :initform t)
   (name-face :initarg :name-face
	      :initform 'bold)
   (labels-face :initarg :labels-face
		:initform 'italic)
   (chart :initarg :chart
	  :initform nil)
   )
  "Superclass used for display of an axis.")

(defclass chart-axis-range (chart-axis)
  ((bounds :initarg :bounds
	   :initform '(0.0 . 50.0))
   )
  "Class used to display an axis defined by a range of values.")

(defclass chart-axis-names (chart-axis)
  ((items :initarg :items
	  :initform nil)
   )
  "Class used to display an axis which represents different named items.")

(defclass chart-sequence ()
  ((data :initarg :data
	 :initform nil)
   (name :initarg :name
	 :initform "Data")
   )
  "Class used for all data in different charts.")

(defclass chart-bar (chart)
  ((direction :initarg :direction
	      :initform 'vertical))
  "Subclass for bar charts (vertical or horizontal).")

(cl-defmethod chart-draw ((c chart) &optional buff)
  "Start drawing a chart object C in optional BUFF.
Erases current contents of buffer."
  (with-silent-modifications
    (save-excursion
      (if buff (set-buffer buff))
      (erase-buffer)
      (insert (make-string (window-height (selected-window)) ?\n))
      ;; Start by displaying the axis
      (chart-draw-axis c)
      ;; Display title
      (chart-draw-title c)
      ;; Display data
      (message "Rendering chart...")
      (sit-for 0)
      (chart-draw-data c)
      ;; Display key
                                        ; (chart-draw-key c)
      (message "Rendering chart...done")
      )))

(cl-defmethod chart-draw-title ((c chart))
  "Draw a title upon the chart.
Argument C is the chart object."
  (chart-display-label (oref c title) 'horizontal 0 0 (window-width)
		       (oref c title-face)))

(cl-defmethod chart-size-in-dir ((c chart) dir)
  "Return the physical size of chart C in direction DIR."
  (if (eq dir 'vertical)
      (oref c y-width)
    (oref c x-width)))

(cl-defmethod chart-draw-axis ((c chart))
  "Draw axis into the current buffer defined by chart C."
  (let ((ymarg (oref c y-margin))
	(xmarg (oref c x-margin))
	(ylen (oref c y-width))
	(xlen (oref c x-width)))
    (chart-axis-draw (oref c y-axis) 'vertical ymarg
		     (if (oref (oref c y-axis) loweredge) nil xlen)
		     xmarg (+ xmarg ylen))
    (chart-axis-draw (oref c x-axis) 'horizontal xmarg
		     (if (oref (oref c x-axis) loweredge) nil ylen)
		     ymarg (+ ymarg xlen)))
  )

(cl-defmethod chart-axis-draw ((a chart-axis) &optional dir margin zone start end)
  "Draw some axis for A in direction DIR with MARGIN in boundary.
ZONE is a zone specification.
START and END represent the boundary."
  (chart-draw-line dir (+ margin (if zone zone 0)) start end)
  (chart-display-label (oref a name) dir (if zone (+ zone margin 3)
					   (if (eq dir 'horizontal)
					       1 0))
		       start end (oref a name-face)))

(cl-defmethod chart-translate-xpos ((c chart) x)
  "Translate in chart C the coordinate X into a screen column."
  (let ((range (oref (oref c x-axis) bounds)))
    (+ (oref c x-margin)
       (round (* (float (- x (car range)))
		 (/ (float (oref c x-width))
		    (float (- (cdr range) (car range))))))))
  )

(cl-defmethod chart-translate-ypos ((c chart) y)
  "Translate in chart C the coordinate Y into a screen row."
  (let ((range (oref (oref c y-axis) bounds)))
    (+ (oref c x-margin)
       (- (oref c y-width)
	  (round (* (float (- y (car range)))
		    (/ (float (oref c y-width))
		       (float (- (cdr range) (car range)))))))))
  )

(cl-defmethod chart-axis-draw ((a chart-axis-range) &optional dir margin zone _start _end)
  "Draw axis information based upon a range to be spread along the edge.
A is the chart to draw.  DIR is the direction.
MARGIN, ZONE, START, and END specify restrictions in chart space."
  (cl-call-next-method)
  ;; We prefer about 5 spaces between each value
  (let* ((i (car (oref a bounds)))
	 (e (cdr (oref a bounds)))
	 (z (if zone zone 0))
	 (s nil)
	 (rng (- e i))
	 ;; want to jump by units of 5 spaces or so
	 (j (/ rng (/  (chart-size-in-dir (oref a chart) dir) 4)))
	 p1)
    (if (= j 0) (setq j 1))
    (while (<= i e)
      (setq s
	    (cond ((> i 999999)
		   (format "%dM" (/ i 1000000)))
		  ((> i 999)
		   (format "%dK" (/ i 1000)))
		  (t
		   (format "%d" i))))
      (if (eq dir 'vertical)
	  (let ((x (+ (+ margin z) (if (oref a loweredge)
				       (- (length s)) 1))))
	    (if (< x 1) (setq x 1))
	    (chart-goto-xy x (chart-translate-ypos (oref a chart) i)))
	(chart-goto-xy (chart-translate-xpos (oref a chart) i)
		       (+ margin z (if (oref a loweredge) -1 1))))
      (setq p1 (point))
      (insert s)
      (chart-zap-chars (length s))
      (put-text-property p1 (point) 'face (oref a labels-face))
      (setq i (+ i j))))
)

(cl-defmethod chart-translate-namezone ((c chart) n)
  "Return a dot-pair representing a positional range for a name.
The name in chart C of the Nth name resides.
Automatically compensates for direction."
  (let* ((dir (oref c direction))
	 (w (if (eq dir 'vertical) (oref c x-width) (oref c y-width)))
	 (m (if (eq dir 'vertical) (oref c y-margin) (oref c x-margin)))
	 (ns (length
	      (oref (if (eq dir 'vertical) (oref c x-axis) (oref c y-axis))
		    items)))
	 (lpn (/ (+ 1.0 (float w)) (float ns)))
	 )
    (cons (+ m (round (* lpn (float n))))
	  (+ m -1 (round (* lpn (+ 1.0 (float n))))))
    ))

(cl-defmethod chart-axis-draw ((a chart-axis-names) &optional dir margin zone _start _end)
  "Draw axis information based upon A range to be spread along the edge.
Optional argument DIR is the direction of the chart.
Optional arguments MARGIN, ZONE, START and END specify boundaries
of the drawing."
  (cl-call-next-method)
  ;; We prefer about 5 spaces between each value
  (let* ((i 0)
	 (s (oref a items))
	 (z (if zone zone 0))
	 (r nil)
	 (p nil)
	 (odd nil)
	 p1)
    (while s
      (setq odd (= (% (length s) 2) 1))
      (setq r (chart-translate-namezone (oref a chart) i))
      (if (eq dir 'vertical)
	  (setq p (/ (+ (car r) (cdr r)) 2))
	(setq p (- (+ (car r) (/ (- (cdr r) (car r)) 2))
		   (/ (length (car s)) 2))))
      (if (eq dir 'vertical)
	  (let ((x (+ (+ margin z) (if (oref a loweredge)
				       (- (length (car s)))
				     (length (car s))))))
	    (if (< x 1) (setq x 1))
	    (if (> (length (car s)) (1- margin))
		(setq x (+ x margin)))
	    (chart-goto-xy x p))
	(chart-goto-xy p (+ (+ margin z) (if (oref a loweredge)
					     (if odd -2 -1)
					   (if odd 2 1)))))
      (setq p1 (point))
      (insert (car s))
      (chart-zap-chars (length (car s)))
      (put-text-property p1 (point) 'face (oref a labels-face))
      (setq i (+ i 1)
	    s (cdr s))))
)

(cl-defmethod chart-draw-data ((c chart-bar))
  "Display the data available in a bar chart C."
  (let* ((data (oref c sequences))
	 (dir (oref c direction))
	 (odir (if (eq dir 'vertical) 'horizontal 'vertical))
         (faces
          (if (functionp chart-face-list)
              (funcall chart-face-list)
            chart-face-list)))
    (while data
      (if (stringp (car (oref (car data) data)))
	  ;; skip string lists...
	  nil
	;; display number lists...
	(let ((i 0)
	      (seq (oref (car data) data)))
	  (while seq
	    (let* ((rng (chart-translate-namezone c i))
		   (dp (if (eq dir 'vertical)
			   (chart-translate-ypos c (car seq))
			 (chart-translate-xpos c (car seq))))
		  (zp (if (eq dir 'vertical)
			  (chart-translate-ypos c 0)
			(chart-translate-xpos c 0)))
		  (fc (if faces
			  (nth (% i (length faces)) faces)
			'default)))
	      (if (< dp zp)
		  (progn
		    (chart-draw-line dir (car rng) dp zp)
		    (chart-draw-line dir (cdr rng) dp zp))
		(chart-draw-line dir (car rng) zp (1+ dp))
		(chart-draw-line dir (cdr rng) zp (1+ dp)))
	      (if (= (car rng) (cdr rng)) nil
		(chart-draw-line odir dp (1+ (car rng)) (cdr rng))
		(chart-draw-line odir zp (car rng) (1+ (cdr rng))))
	      (if (< dp zp)
		  (chart-deface-rectangle dir rng (cons dp zp) fc)
		(chart-deface-rectangle dir rng (cons zp dp) fc))
	      )
	    ;; find the bounds, and chart it!
	    ;; for now, only do one!
	    (setq i (1+ i)
		  seq (cdr seq)))))
      (setq data (cdr data))))
  )

(cl-defmethod chart-add-sequence ((c chart) &optional seq axis-label)
  "Add to chart object C the sequence object SEQ.
If AXIS-LABEL, then the axis stored in C is updated with the bounds of SEQ,
or is created with the bounds of SEQ."
  (if axis-label
      (let ((axis (eieio-oref c axis-label)))
	(if (stringp (car (oref seq data)))
	    (let ((labels (oref seq data)))
	      (if (not axis)
		  (setq axis (make-instance 'chart-axis-names
					    :name (oref seq name)
					    :items labels
					    :chart c))
		(oset axis items labels)))
	  (let ((range (cons 0 1))
		(l (oref seq data)))
	    (if (not axis)
		(setq axis (make-instance 'chart-axis-range
					  :name (oref seq name)
					  :chart c)))
            (dolist (x l)
              (if (< x (car range)) (setcar range x))
              (if (> x (cdr range)) (setcdr range x)))
            (oset axis bounds range)))
	(if (eq axis-label 'x-axis) (oset axis loweredge nil))
	(eieio-oset c axis-label axis)
	))
  (oset c sequences (append (oref c sequences) (list seq))))

;;; Charting optimizers

(cl-defmethod chart-trim ((c chart) max)
  "Trim all sequences in chart C to be at most MAX elements long."
  (let ((s (oref c sequences)))
    (dolist (x s)
      (let ((sl (oref x data)))
	(if (> (length sl) max)
            (setcdr (nthcdr (1- max) sl) nil)))))
  )

(cl-defmethod chart-sort ((c chart) pred)
  "Sort the data in chart C using predicate PRED.
See `chart-sort-matchlist' for more details."
  (let* ((sl (oref c sequences))
	 (s1 (car sl))
	 (s2 (car (cdr sl)))
	 (s nil))
    (if (stringp (car (oref s1 data)))
	(progn
	  (chart-sort-matchlist s1 s2 pred)
	  (setq s (oref s1 data)))
      (if (stringp (car (oref s2 data)))
	  (progn
	    (chart-sort-matchlist s2 s1 pred)
	    (setq s (oref s2 data)))
	(error "Sorting of chart %s not supported" (eieio-object-name c))))
    (if (eq (oref c direction) 'horizontal)
	(oset (oref c y-axis) items s)
      (oset (oref c x-axis) items s)
	))
  )

(defun chart-sort-matchlist (namelst numlst pred)
  "Sort NAMELST and NUMLST (both sequence objects) based on predicate PRED.
PRED should be the equivalent of `<', except it must expect two
cons cells of the form (NAME . NUM).  See `sort' for more details."
  ;; 1 - create 1 list of cons cells
  (let ((newlist nil)
	(alst (oref namelst data))
	(ulst (oref numlst data)))
    (while alst
      ;; this is reversed, but were are sorting anyway
      (setq newlist (cons (cons (car alst) (car ulst)) newlist))
      (setq alst (cdr alst)
	    ulst (cdr ulst)))
    ;; 2 - Run sort routine on it
    (setq newlist (sort newlist pred)
	  alst nil
	  ulst nil)
    ;; 3 - Separate the lists
    (while newlist
      (setq alst (cons (car (car newlist)) alst)
	    ulst (cons (cdr (car newlist)) ulst))
      (setq newlist (cdr newlist)))
    ;; 4 - Store them back
    (oset namelst data (reverse alst))
    (oset numlst data (reverse ulst))))

;;; Utilities

(defun chart-goto-xy (x y)
  "Move cursor to position X Y in buffer, and add spaces and CRs if needed."
  (let ((indent-tabs-mode nil)
	(num (progn (goto-char (point-min)) (forward-line y))))
    (if (and (= 0 num) (/= 0 (current-column))) (newline 1))
    (if (eobp) (newline num))
    (if (< x 0) (setq x 0))
    (if (< y 0) (setq y 0))
    ;; Now, a quickie column moveto/forceto method.
    (or (= (move-to-column x) x)
	(let ((p (point)))
	  (indent-to x)
          (remove-text-properties p (point) '(face nil))))))

(defun chart-zap-chars (n)
  "Zap up to N chars without deleting EOLs."
  (if (not (eobp))
      (if (< n (- (line-end-position) (point)))
	  (delete-char n)
        (delete-region (point) (line-end-position)))))

(defun chart-display-label (label dir zone start end &optional face)
  "Display LABEL in direction DIR in column/row ZONE between START and END.
Optional argument FACE is the property we wish to place on this text."
  (if (eq dir 'horizontal)
      (let (p1)
	(chart-goto-xy (+ start (- (/ (- end start) 2) (/ (length label) 2)))
		       zone)
	(setq p1 (point))
	(insert label)
	(chart-zap-chars (length label))
	(put-text-property p1 (point) 'face face)
	)
    (let ((i 0)
	  (stz (+ start (- (/ (- end start) 2) (/ (length label) 2)))))
      (while (< i (length label))
	(chart-goto-xy zone (+ stz i))
	(insert (aref label i))
	(chart-zap-chars 1)
	(put-text-property (1- (point)) (point) 'face face)
	(setq i (1+ i))))))

(defun chart-draw-line (dir zone start end)
  "Draw a line using line-drawing characters in direction DIR.
Use column or row ZONE between START and END."
  (chart-display-label
   (make-string (- end start) (if (eq dir 'vertical) ?| ?\-))
   dir zone start end))

(defun chart-deface-rectangle (dir r1 r2 face)
  "Colorize a rectangle in direction DIR across range R1 by range R2.
R1 and R2 are dotted pairs.  Colorize it with FACE."
  (let* ((range1 (if (eq dir 'vertical) r1 r2))
	 (range2 (if (eq dir 'vertical) r2 r1))
	 (y (car range2)))
    (while (<= y (cdr range2))
      (chart-goto-xy (car range1) y)
      (put-text-property (point) (+ (point) (1+ (- (cdr range1) (car range1))))
			 'face face)
      (setq y (1+ y)))))

;;; Helpful `I don't want to learn eieio just now' washover functions

(defun chart-bar-quickie (dir title namelst nametitle numlst numtitle
			      &optional max sort-pred)
  "Create a bar chart named TITLE in direction DIR [`horizontal' `vertical'].
NAMELST is the list of bar names and NAMETITLE is the name the of axis
containing them.
NUMLST is the list of values and NUMTITLE is the name of the value
axis.
Optional argument MAX limits the chart's max element display to MAX by
passing it as second argument to `chart-trim', otherwise the chart's
display is unlimited.
Optional argument SORT-PRED is a predicate function passed as second
argument to `chart-sort' to sort the lists if desired."
  (let ((nc (make-instance 'chart-bar
			   :title title
			   :key-label "8-m"  ; This is a text key pic
			   :direction dir
			   ))
	(iv (eq dir 'vertical)))
    (chart-add-sequence nc
			(make-instance 'chart-sequence
				       :data namelst
				       :name nametitle)
			(if iv 'x-axis 'y-axis))
    (chart-add-sequence nc
			(make-instance 'chart-sequence
				       :data numlst
				       :name numtitle)
			(if iv 'y-axis 'x-axis))
    (if sort-pred (chart-sort nc sort-pred))
    (if (integerp max) (chart-trim nc max))
    (switch-to-buffer (chart-new-buffer nc))
    (chart-draw nc)))

;;; Test code

(defun chart-test-it-all ()
  "Test out various charting features."
  (interactive)
  (chart-bar-quickie 'vertical "Test Bar Chart"
		     '( "U1" "ME2" "C3" "B4" "QT" "EZ") "Items"
		     '( 5 -10 23 20 30 -3) "Values")
  (if (not (called-interactively-p 'any))
      (kill-buffer "*Test Bar Chart*"))
  )

;;; Sample utility function

(defun chart-file-count (dir)
  "Draw a chart displaying the number of different file extensions in DIR."
  (interactive "DDirectory: ")
  (message "Collecting statistics...")
  (let ((flst (directory-files dir nil nil t))
	(extlst (list "<dir>"))
	(cntlst (list 0)))
    (dolist (f flst)
      (let* ((x (file-name-extension f))
             (s (if (file-accessible-directory-p (expand-file-name f dir))
                    "<dir>" x))
	     (m (member s extlst)))
	(unless (null s)
	  (if m
              (cl-incf (car (nthcdr (- (length extlst) (length m)) cntlst)))
	    (setq extlst (cons s extlst)
                  cntlst (cons 1 cntlst))))))
    ;; Let's create the chart!
    (chart-bar-quickie 'vertical "Files Extension Distribution"
		       extlst "File Extensions"
		       cntlst "# of occurrences"
		       10
		       (lambda (a b) (> (cdr a) (cdr b))))
    ))

;; This assumes 4KB blocks
(defun chart--file-size (size)
  (* (/ (+ size 4095) 4096) 4096))

(defun chart--directory-size (dir)
  "Compute total size of files in directory DIR and its subdirectories.
DIR is assumed to be a directory, verified by the caller."
  (let ((size 0))
    (dolist (file (directory-files-recursively dir "." t))
      (let ((fsize (nth 7 (file-attributes file))))
        (if (> fsize 0)
            (setq size
                  (+ size (chart--file-size fsize))))))
    size))

(defun chart-space-usage (d)
  "Display a top usage chart for directory D."
  (interactive "DDirectory: ")
  (message "Collecting statistics...")
  (let ((nmlst nil)
	(cntlst nil)
        b)
    (if (executable-find "du")
        (progn
	  (setq b (get-buffer-create " *du-tmp*"))
          (set-buffer b)
          (erase-buffer)
          (if (and (memq system-type '(windows-nt ms-dos))
                   (fboundp 'w32-shell-dos-semantics)
                   (w32-shell-dos-semantics))
              (progn
                ;; With Windows shells, 'cd' does not change the drive,
                ;; and ';' is not reliable for running multiple
                ;; commands, so use alternatives.  We quote the
                ;; directory because otherwise pushd will barf on a
                ;; directory with forward slashes.  Note that * will not
                ;; skip dotfiles with Windows shells, unlike on Unix.
                (insert "pushd \"" d "\" && du -sk * \n")
                (message "Running `pushd \"%s\" && du -sk *'..." d))
            (insert "cd " d ";du -sk * \n")
            (message "Running `cd %s;du -sk *'..." d))
          (call-process-region (point-min) (point-max) shell-file-name t
			       (current-buffer) nil)
          (goto-char (point-min))
          (message "Scanning output ...")
          (while (re-search-forward "^\\([0-9]+\\)[ \t]+\\([^ \n]+\\)$" nil t)
            (let* ((nam (buffer-substring (match-beginning 2) (match-end 2)))
	           (num (buffer-substring (match-beginning 1) (match-end 1))))
	      (setq nmlst (cons nam nmlst)
	            ;; * 1000 to put it into bytes
	            cntlst (cons (* (string-to-number num) 1000) cntlst)))))
      (dolist (file (directory-files d t directory-files-no-dot-files-regexp))
        (let ((fbase (file-name-nondirectory file)))
          ;; Typical shells exclude files and subdirectories whose names
          ;; begin with a period when it expands *, so we do the same.
          (unless (string-match-p "\\`\\." fbase)
            (setq nmlst (cons fbase nmlst))
            (if (file-regular-p file)
                (setq cntlst (cons (chart--file-size
                                    (nth 7 (file-attributes file)))
                                   cntlst))
              (setq cntlst (cons (chart--directory-size file) cntlst)))))))
    (if (not nmlst)
	(error "No files found!"))
    (chart-bar-quickie 'vertical (format "Largest files in %s" d)
		       nmlst "File Name"
		       cntlst "File Size"
		       10
		       (lambda (a b) (> (cdr a) (cdr b))))
    ))

(defun chart-emacs-storage ()
  "Chart the current storage requirements of Emacs."
  (interactive)
  (let* ((data (garbage-collect)))
    ;; Let's create the chart!
    (chart-bar-quickie 'vertical "Emacs Runtime Storage Usage"
		       (mapcar (lambda (x) (symbol-name (car x))) data)
                       "Storage Items"
		       (mapcar (lambda (x) (* (nth 1 x) (nth 2 x)))
                               data)
                       "Bytes")))

(defun chart-emacs-lists ()
  "Chart out the size of various important lists."
  (interactive)
  (let* ((names '("buffers" "frames" "processes" "faces"))
	 (nums (list (length (buffer-list))
		     (length (frame-list))
		     (length (process-list))
		     (length (face-list))
		     )))
    (if (fboundp 'x-display-list)
	(setq names (append names '("x-displays"))
	      nums (append nums (list (length (x-display-list))))))
    ;; Let's create the chart!
    (chart-bar-quickie 'vertical "Emacs List Size Chart"
		       names "Various Lists"
		       nums "Objects")))

(defun chart-rmail-from ()
  "If we are in an rmail summary buffer, then chart out the froms."
  (interactive)
  (if (not (eq major-mode 'rmail-summary-mode))
      (error "You must invoke chart-rmail-from in an rmail summary buffer"))
  (let ((nmlst nil)
	(cntlst nil))
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward "-[A-Z][a-z][a-z] +\\(\\w+\\)@\\w+" nil t)
	(let* ((nam (buffer-substring (match-beginning 1) (match-end 1)))
	       (m (member nam nmlst)))
	  (message "Scanned username %s" nam)
	  (if m
	      (let ((cell (nthcdr (- (length nmlst) (length m)) cntlst)))
		(setcar cell (1+ (car cell))))
	    (setq nmlst (cons nam nmlst)
		  cntlst (cons 1 cntlst))))))
    (chart-bar-quickie 'vertical "Username Occurrence in RMAIL box"
		       nmlst "User Names"
		       cntlst "# of occurrences"
		       10
		       (lambda (a b) (> (cdr a) (cdr b))))
    ))


(provide 'chart)

;;; chart.el ends here
