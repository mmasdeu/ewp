;;; vpt.el --- Variable Pitch Tables -*- lexical-binding: t -*-
;; Copyright (C) 2018 Lars Magne Ingebrigtsen

;; Author: Lars Magne Ingebrigtsen <larsi@gnus.org>
;; Keywords: tables

;; vpt is free software; you can redistribute it and/or modify it
;; under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2, or (at your option)
;; any later version.

;; vpt is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
;; or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public
;; License for more details.

;;; Commentary:

;; This package makes it possible to make tabular buffers that uses a
;; variable-pitch face.

;; Usage:

;; (variable-pitch-table '((:name "First" :width 10)
;;                         (:name "Second" :width 5))
;;                       '(("A thing" "Yes")
;;                         ("A wide thing that needs chopping" "And more")
;;                         ("And the last one" "Foo")))

;; but you'd normally pass in strings that are made with something like

;; (propertize "At thing" 'face 'variable-pitch)

;; or

;; (propertize "At thing" 'face '(variable-pitch :background "red"))

;; or whatever face and font you want to use.

;;; Code:

(require 'cl)

(defvar variable-pitch-table-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map special-mode-map)
    (define-key map "\r" 'variable-pitch-table-sort-by-column)
    map))

(defun variable-pitch-table (heading lines &optional data separator-width)
  "Display a table using a variable pitch font.
HEADING is a list of header names and possibly widths; LINES is a
list of list of strings, and DATA is a list of data to be put on
the lines as the `data' property.  (The fourth element of DATA is
put on the fourth line, etc.)

SEPARATOR-WIDTH says how many pixels to separate columns width.
The default is 10.

Usage example:

 (variable-pitch-table '((:name \"First\" :width 10)
                         (:name \"Second\" :width 5))
                       '((\"A thing\" \"Yes\")
                         (\"A wide thing that needs chopping\" \"And more\")
                         (\"And the last one\" \"Foo\"))
                       '(thing1 thing2 thing3))"
  (save-excursion
    (save-restriction
      (narrow-to-region (point) (point))
      (loop for i from 0
	    for spec in heading
	    do (goto-char (point-min))
	    (vpt--column i spec lines data (or separator-width 10))))))

(defun vpt--limit-string (string pixels)
  (if (not pixels)
      string
    (with-temp-buffer
      (insert string)
      (if (< (vpt--pixel-column) pixels)
	  string
	;; Iterate to find appropriate length.
	(while (and (> (vpt--pixel-column) pixels)
		    (not (bobp)))
	  (forward-char -1))
	;; Return at least one character.
	(buffer-substring (point-min)
			  (max (point) (1+ (point-min))))))))

(defun vpt--pixel-column ()
  (if (not (get-buffer-window (current-buffer)))
      (save-window-excursion
        ;; Avoid errors if the selected window is a dedicated one,
        ;; and they just want to insert a document into it.
        (set-window-dedicated-p nil nil)
	(set-window-buffer nil (current-buffer))
	(car (window-text-pixel-size nil (line-beginning-position) (point))))
    (car (window-text-pixel-size nil (line-beginning-position) (point)))))

(defun vpt--pixel-width (length)
  (when length
    (with-temp-buffer
      ;; We use an "8" to get the typical character width, because
      ;; this means that we won't chop off numbers if we're doing
      ;; number columns.
      (insert (propertize (make-string length ?8) 'face 'variable-pitch))
      (vpt--pixel-column))))

(defun vpt--column (i spec lines data separator-width)
  (let ((pixel-width (vpt--pixel-width (getf spec :width)))
	(name (getf spec :name))
	(max 0)
	header-item-start)
    (end-of-line)
    (setq header-item-start (point))
    (insert (vpt--limit-string (propertize name 'vpt-index i) pixel-width))
    (when (zerop i)
      (insert "\n"))
    ;; Insert the column.
    (loop for line in lines
	  for elem = (elt line i)
	  do (forward-line 1)
	  (end-of-line)
	  (insert (propertize (vpt--limit-string elem pixel-width)
			      'vpt-value elem))
	  (when (zerop i)
	    (insert "\n")))
    ;; Figure out the max width.
    (goto-char (point-min))
    (while (not (eobp))
      (end-of-line)
      (setq max (max max (vpt--pixel-column)))
      (forward-line 1))
    ;; Indent to the max width (but not on the final item on the line).
    (unless (= i (1- (length (car lines))))
      (goto-char (point-min))
      (while (not (eobp))
	(end-of-line)
	(insert (propertize
		 " " 'display `(space :align-to (,(+ max separator-width)))
		 ;; Extend the background colour from the string to
		 ;; the space.
		 'face (get-text-property (max (1- (point)) (point-min))
					  'face)))
	(forward-line 1)))
    ;; Insert the data.
    (goto-char (point-min))
    (forward-line 1)
    (dolist (elem lines)
      (put-text-property (point) (line-end-position) 'vpt-data elem)
      (forward-line 1))
    ;; And metadata.
    (goto-char (point-min))
    (forward-line 1)
    (dolist (elem data)
      (put-text-property (point) (progn
				   (forward-line 1)
				   (point))
			 'data elem))
    ;; Fix up the header line.
    (goto-char (point-min))
    (end-of-line)
    (insert (propertize
	     " " 'display `(space :align-to (,(+ max separator-width)))))
    (add-text-properties header-item-start (point)
			 `(face (variable-pitch :background "#808080")
				keymap ,variable-pitch-table-map))))

(defun variable-pitch-table-sort-by-column (&optional reverse)
  "Sort the table by the column under point.
If REVERSE (the prefix), sort in reverse order."
  (interactive "P")
  (let ((column (get-text-property (point) 'vpt-index))
	(inhibit-read-only t))
    (save-excursion
      (save-restriction
	(narrow-to-region
	 (progn
	   (forward-line 1)
	   (point))
	 (loop while (get-text-property (point) 'vpt-data)
	       do (forward-line 1)
	       finally (return (point))))
	(goto-char (point-min))
	(vpt--sort-lines column reverse)))))

(defun vpt--sort-lines (column reverse)
  "Sort the lines in the buffer based on the values in COLUMN."
  (let ((lines nil))
    (while (not (eobp))
      (push (buffer-substring (point) (progn
					(forward-line 1)
					(point)))
	    lines))
    (delete-region (point-min) (point-max))
    (setq lines (sort (nreverse lines)
		      (lambda (l1 l2)
			(string<
			 (elt (get-text-property 1 'vpt-data l1) column)
			 (elt (get-text-property 1 'vpt-data l2) column)))))
    (when reverse
      (setq lines (nreverse lines)))
    (dolist (line lines)
      (insert line))))

(provide 'vpt)

;;; vpt.el ends here
