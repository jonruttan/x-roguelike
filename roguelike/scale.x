; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/scale.x -- how much ground a cell is
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A place is drawn at a scale, (scale N): each cell N metres across and
; the number after N in the Fibonacci sequence, 1 2 3 5 8 13 21 34 ...,
; down.  A terminal cell is about that shape, so ground keeps its shape
; drawn.  At 1 a cell is a metre by two, a person a cell; at 21 it is a
; field's corner.  Sizes are given in metres and come out in cells:
; across, down, or as ground covered; never less than a cell.

(module roguelike/scale)

(import x/core/doors int/ int+ int*)

; Scale N as (ACROSS . DOWN) metres, or #f when N is not on the ladder.
(def scale-rung
  (fn (_ n)
    ((fn (self a b) (match ((< a n) (self b (int+ a b))) ((= a n) (pair a b)) (#t #f))) 1 2)))

; M metres in cells of F metres, to the nearest, a cell at least.
(def %sc-cells (fn (_ m f) ((fn (_ c) (if (< c 1) 1 c)) (int/ (int+ m (int/ f 2)) f))))

; M metres across, M metres down, and M square metres, in cells at SC.
(def scale-across (fn (_ sc m) (%sc-cells m (first sc))))
(def scale-down (fn (_ sc m) (%sc-cells m (rest sc))))
(def scale-area (fn (_ sc m) (%sc-cells m (int* (first sc) (rest sc)))))

; Every (scale N) among FORMS, at any depth, is on the ladder, or this
; raises, naming the form.
(def scale-check!
  (fn (self forms)
    (List for-each
      (fn (_ f)
        (when (pair? f)
          (do (when (eq? (first f) (lit scale))
                (unless (if (pair? (rest f)) (if (number? (first (rest f))) (scale-rung (first (rest f))) #f) #f)
                  (Err raise (lit arg) "a scale is one of 1 2 3 5 8 13 21 34 ..." f)))
              (self (rest f)))))
      forms)))

(provide roguelike/scale scale-rung scale-across scale-down scale-area scale-check!)
