; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/frame.x -- the level as pictures: what goes where
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The windowed front-end's half that knows the game (docs/graphics.md):
; which picture each cell takes and where it goes.  It draws nothing;
; it answers a list of what to draw, (tile X Y FORM) or (fill X Y W H),
; in the order to draw it, for the raster library to carry out.
;
; A set's art is read once into a table by the terrain's codes: each
; kind's pictures by part, a kind with none of its own taking those of
; the kind it is a sort of, a band's in front of the set's.  A cell
; takes one of a part's variants by its place, the same every frame.

(module roguelike/frame)

(import x/type/vector)
(import x/core/doors int/ int%)
(import roguelike/data data-all)
(import roguelike/map map-terrain map-kinds map-rows map-cols map-tile map-seen? map-in? map-opaque? tile-rock)

(def frame-tile-size 16)
(def frame-view-rows 19)
(def frame-view-cols 40)
(def frame-level-y 24)

; --- the art ----------------------------------------------------------------

(def %fr-prop (fn (_ t key) (List find (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) (rest t))))
(def %fr-prop1 (fn (_ t key) ((fn (_ p) (if (null? p) () (List ref 1 p))) (%fr-prop t key))))
(def %fr-same? (fn (_ a b) (if (str? a) (if (str? b) (str=? a b) #f) (eq? a b))))
(def %fr-weight (fn (_ t) ((fn (_ w) (if (null? w) 1 w)) (%fr-prop1 t (lit weight)))))

; The tiles of ART named NAME with part PART (nil for none), the band's
; own when it has any, else the set's: (TOTAL-WEIGHT . TILES), or nil.
(def %fr-variants
  (fn (_ tiles name part band)
    (def mine (List filter (fn (_ t) (if (%fr-same? (first t) name) (eq? (%fr-prop1 t (lit part)) part) #f)) tiles))
    (def own (if (null? band) () (List filter (fn (_ t) ((fn (_ b) (if (null? b) #f (str=? b band))) (%fr-prop1 t (lit band)))) mine)))
    (def vs (if (null? own) (List filter (fn (_ t) (null? (%fr-prop t (lit band)))) mine) own))
    (if (null? vs) () (pair (List fold (fn (_ n t) (+ n (%fr-weight t))) 0 vs) vs))))

(def %fr-parts (list () (lit top) (lit face) (lit n) (lit e) (lit w) (lit ne) (lit nw) (lit se) (lit sw)
                     (lit face-w) (lit face-e) (lit shade)))

; A kind's pictures: ((PART . VARIANTS) ...) for each part it has.
(def %fr-kind
  (fn (_ tiles name band)
    (List filter (fn (_ p) (not (null? (rest p))))
      (List map (fn (_ part) (pair part (%fr-variants tiles name part band))) %fr-parts))))

; The art of ART-FORMS for band BAND (a name, or nil): a vector by
; terrain code of each kind's pictures, the kind it is a sort of
; standing in where it has none; then the art's tiles, for names that
; are not terrain.
(def frame-art
  (fn (_ art-forms band)
    (def tiles (data-all art-forms (lit tile)))
    (def kinds (Vector make map-kinds ()))
    (def named (fn (self name) (List find (fn (_ t) (eq? (List ref 1 t) name)) map-terrain)))
    (def own
      (fn (self t)
        ((fn (_ k) (match ((not (null? k)) k) ((null? (List ref 2 t)) ()) (#t (self (named (List ref 2 t))))))
         (%fr-kind tiles (List ref 1 t) band))))
    (List for-each (fn (_ t) (Vector set! (first t) (own t) kinds)) map-terrain)
    (list kinds tiles band)))
(def frame-art-band (fn (_ a) (List ref 2 a)))

; The picture for a cell at SEED of a kind's pictures PICS, part PART,
; or nil.
(def %fr-pick
  (fn (_ pics part seed)
    (def vs (List find (fn (_ p) (eq? (first p) part)) pics))
    (if (null? vs) ()
      ((fn (self h l) (if (< h (%fr-weight (first l))) (first l) (self (- h (%fr-weight (first l))) (rest l))))
       (int% (frame-seed seed) (first (rest vs))) (rest (rest vs))))))

; A cell's place stirred into a number, the same every frame.
(def frame-seed (fn (_ s) (>> (& (+ (* s 2654435761) 40503) 4294967295) 7)))

; The picture named NAME (a creature's name, an item class, player,
; shadow, panel) at SEED, the band's before the set's, or nil.
(def frame-named
  (fn (_ a name seed)
    ((fn (_ vs) (if (null? vs) () (%fr-pick (list (pair () vs)) () seed)))
     (%fr-variants (List ref 1 a) name () (List ref 2 a)))))

; --- the walls --------------------------------------------------------------

; The parts a wall cell is drawn in, in order, from SOLID?, (fn (_ dr
; dc)) whether the neighbour that way is solid: its face where the
; ground lies south of it, its top with rims and corners elsewhere.
(def frame-wall-parts
  (fn (_ solid?)
    (if (not (solid? 1 0))
      (List append (list (lit face))
        (if (solid? 0 -1) () (list (lit face-w)))
        (if (solid? 0 1) () (list (lit face-e))))
      (List append (list (lit top))
        (if (solid? -1 0) () (list (lit n)))
        (if (solid? 0 1) () (list (lit e)))
        (if (solid? 0 -1) () (list (lit w)))
        (if (if (solid? -1 0) (if (solid? 0 1) (not (solid? -1 1)) #f) #f) (list (lit ne)) ())
        (if (if (solid? -1 0) (if (solid? 0 -1) (not (solid? -1 -1)) #f) #f) (list (lit nw)) ())
        (if (if (solid? 1 0) (if (solid? 0 1) (not (solid? 1 1)) #f) #f) (list (lit se)) ())
        (if (if (solid? 1 0) (if (solid? 0 -1) (not (solid? 1 -1)) #f) #f) (list (lit sw)) ())))))

; --- the camera -------------------------------------------------------------

; The view's top-left cell, (R0 . C0): the player at R C in the middle,
; the view held inside the map's ROWS by COLS.
(def frame-camera
  (fn (_ rows cols r c)
    (def clamp (fn (_ v hi) (match ((< v 0) 0) ((< hi v) (if (< hi 0) 0 hi)) (#t v))))
    (pair (clamp (- r (int/ frame-view-rows 2)) (- rows frame-view-rows))
          (clamp (- c (int/ frame-view-cols 2)) (- cols frame-view-cols)))))

; --- the level --------------------------------------------------------------

; Whether the cell at R C of M is solid to the walls beside it: opaque,
; off the map, or not yet seen.
(def %fr-solid?
  (fn (_ m r c) (if (map-in? m r c) (if (map-seen? m r c) (map-opaque? (map-tile m r c)) #t) #t)))

; What to draw for the cell at R C of M with art A, at X Y: the
; ground's picture, or a wall's parts, or the shade a wall's face
; casts; a cell not seen is a fill of the dark.
(def frame-cell
  (fn (_ a m r c x y)
    (def t (map-tile m r c))
    (def pics (Vector ref t (first a)))
    (def seed (+ (* r 80) c))
    (def put (fn (_ part) ((fn (_ p) (if (null? p) () (list (list (lit tile) x y p)))) (%fr-pick pics part seed))))
    (match ((not (map-seen? m r c)) (list (list (lit fill) x y frame-tile-size frame-tile-size)))
           ((= t tile-rock) (list (list (lit fill) x y frame-tile-size frame-tile-size)))
           ((map-opaque? t)
             (List flat-map put (frame-wall-parts (fn (_ dr dc) (%fr-solid? m (+ r dr) (+ c dc))))))
           ((%fr-solid? m (- r 1) c) (List append (put ()) (put (lit shade))))
           (#t (put ())))))

; The level's cells in view of camera CAM, (R0 . C0), with art A, in
; the order to draw them.
(def frame-level
  (fn (_ a m cam)
    (def r0 (first cam))
    (def c0 (rest cam))
    (List flat-map
      (fn (_ i)
        (def r (+ r0 (int/ i frame-view-cols)))
        (def c (+ c0 (int% i frame-view-cols)))
        (frame-cell a m r c (* frame-tile-size (- c c0)) (+ frame-level-y (* frame-tile-size (- r r0)))))
      (List range 0 (* frame-view-rows frame-view-cols)))))

(provide roguelike/frame
  frame-tile-size frame-view-rows frame-view-cols frame-level-y
  frame-art frame-art-band frame-named frame-seed frame-wall-parts frame-camera frame-cell frame-level)
