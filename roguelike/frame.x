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
(import x/core/doors int+ int- int* int/ int% int< int= str-make str->ptr ptr-set! ptr-ref str-byte-ref char->int)
(import roguelike/data data-all data-glyph)
(import roguelike/items items-glyph)
(import roguelike/map map-terrain map-kinds map-rows map-cols map-tile map-seen? map-visible? map-in? map-opaque? tile-rock)
(import roguelike/state game-map game-player game-floor game-creatures game-traps
  player-r player-c item-r item-c item-class creature-r creature-c creature-name creature-glyph game-set)
(import roguelike/creatures creatures-shown?)
(import roguelike/traps trap-r trap-c trap-found?)

(def frame-tile-size 16)
; The view, [ROWS COLS] in cells: drawn at the tile's size and shown
; at the painter's zoom (paint.x), which sets it to fill the screen.
(def %fr-view (Vector of 10 20))
(def frame-view-rows (fn (_) (Vector ref 0 %fr-view)))
(def frame-view-cols (fn (_) (Vector ref 1 %fr-view)))
(def frame-view! (fn (_ rows cols) (do (Vector set! 0 rows %fr-view) (Vector set! 1 cols %fr-view) ())))
(def frame-level-y 24)

; --- the art ----------------------------------------------------------------

; The per-cell paths walk lists with first and rest: a List send costs
; a few hundred objects, and a turn makes thousands of these calls.
(def %fr-keyed
  (fn (self l key)
    (match ((null? l) ()) ((if (pair? (first l)) (eq? (first (first l)) key) #f) (first l)) (#t (self (rest l) key)))))
(def %fr-prop (fn (_ t key) (%fr-keyed (rest t) key)))
; L's elements in front of ACC.
(def %fr-onto (fn (self l acc) (if (null? l) acc (pair (first l) (self (rest l) acc)))))
(def %fr-prop1 (fn (_ t key) ((fn (_ p) (if (null? p) () (first (rest p)))) (%fr-prop t key))))
(def %fr-same? (fn (_ a b) (if (str? a) (if (str? b) (str=? a b) #f) (eq? a b))))
(def %fr-weight (fn (_ t) ((fn (_ w) (if (null? w) 1 w)) (%fr-prop1 t (lit weight)))))

; The art's tiles by name, ((NAME . TILES) ...), read in one pass.
(def %fr-group
  (fn (_ tiles)
    (def names (List fold (fn (_ ns t) (if (List any? (fn (_ n) (%fr-same? n (first t))) ns) ns (pair (first t) ns))) () tiles))
    (List map (fn (_ n) (pair n (List filter (fn (_ t) (%fr-same? (first t) n)) tiles))) names)))
(def %fr-named (fn (_ groups name) ((fn (_ g) (if (null? g) () (rest g))) (List find (fn (_ g) (%fr-same? (first g) name)) groups))))

; Of TILES, one name's, those with part PART (nil for none), the band's
; own when it has any, else the set's: (TOTAL-WEIGHT . TILES), or nil.
(def %fr-variants
  (fn (_ tiles part band)
    (def mine (List filter (fn (_ t) (eq? (%fr-prop1 t (lit part)) part)) tiles))
    (def own (if (null? band) () (List filter (fn (_ t) ((fn (_ b) (if (null? b) #f (str=? b band))) (%fr-prop1 t (lit band)))) mine)))
    (def vs (if (null? own) (List filter (fn (_ t) (null? (%fr-prop t (lit band)))) mine) own))
    (if (null? vs) () (pair (List fold (fn (_ n t) (+ n (%fr-weight t))) 0 vs) vs))))

(def %fr-parts (list () (lit top) (lit face) (lit n) (lit e) (lit w) (lit ne) (lit nw) (lit se) (lit sw)
                     (lit face-w) (lit face-e) (lit shade)))

; A kind's pictures: ((PART . VARIANTS) ...) for each part it has.
(def %fr-kind
  (fn (_ groups name band)
    (def tiles (%fr-named groups name))
    (if (null? tiles) ()
      (List filter (fn (_ p) (not (null? (rest p))))
        (List map (fn (_ part) (pair part (%fr-variants tiles part band))) %fr-parts)))))

; The art of ART-FORMS for band BAND (a name, or nil): a vector by
; terrain code of each kind's pictures, the kind it is a sort of
; standing in where it has none; then the art's tiles, for names that
; are not terrain.
(def frame-art
  (fn (_ art-forms band)
    (def groups (%fr-group (data-all art-forms (lit tile))))
    (def kinds (Vector make map-kinds ()))
    (def named (fn (self name) (List find (fn (_ t) (eq? (List ref 1 t) name)) map-terrain)))
    (def own
      (fn (self t)
        ((fn (_ k) (match ((not (null? k)) k) ((null? (List ref 2 t)) ()) (#t (self (named (List ref 2 t))))))
         (%fr-kind groups (List ref 1 t) band))))
    (List for-each (fn (_ t) (Vector set! (first t) (own t) kinds)) map-terrain)
    (list kinds groups band)))
(def frame-art-band (fn (_ a) (List ref 2 a)))

; The picture for a cell at SEED of a kind's pictures PICS, part PART,
; or nil.
(def %fr-pick
  (fn (_ pics part seed)
    (def vs ((fn (self l) (match ((null? l) ()) ((eq? (first (first l)) part) (first l)) (#t (self (rest l))))) pics))
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
     ((fn (_ tiles) (if (null? tiles) () (%fr-variants tiles () (List ref 2 a)))) (%fr-named (List ref 1 a) name)))))

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
    (def vr (frame-view-rows))
    (def vc (frame-view-cols))
    (pair (clamp (- r (int/ vr 2)) (- rows vr))
          (clamp (- c (int/ vc 2)) (- cols vc)))))

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
    ; The parts PARTS put, in order, in front of ACC.
    (def puts
      (fn (self parts acc)
        (if (null? parts) acc
          ((fn (_ p) (if (null? p) (self (rest parts) acc) (pair (list (lit tile) x y p) (self (rest parts) acc))))
           (%fr-pick pics (first parts) seed)))))
    (match ((not (map-seen? m r c)) (list (list (lit fill) x y frame-tile-size frame-tile-size)))
           ((= t tile-rock) (list (list (lit fill) x y frame-tile-size frame-tile-size)))
           ((map-opaque? t) (puts (frame-wall-parts (fn (_ dr dc) (%fr-solid? m (+ r dr) (+ c dc)))) ()))
           ((%fr-solid? m (- r 1) c) (puts (list () (lit shade)) ()))
           (#t (puts (list ()) ())))))

; The level's cells in view of camera CAM, (R0 . C0), with art A, in
; the order to draw them: built from the last cell back.
(def frame-level
  (fn (_ a m cam)
    (def r0 (first cam))
    (def c0 (rest cam))
    (def cols (frame-view-cols))
    ((fn (self i acc)
       (if (int< i 0) acc
         (do (def r (int+ r0 (int/ i cols)))
             (def c (int+ c0 (int% i cols)))
             (self (int- i 1)
               (%fr-onto (frame-cell a m r c (int* frame-tile-size (int- c c0)) (int+ frame-level-y (int* frame-tile-size (int- r r0)))) acc)))))
     (int- (* (frame-view-rows) cols) 1) ())))

; --- what stands on it --------------------------------------------------------

; The pixel place of the cell at R C under camera CAM, (X . Y), or nil
; when it is out of view.
(def frame-place
  (fn (_ cam r c)
    (def vr (- r (first cam)))
    (def vc (- c (rest cam)))
    (if (if (< vr 0) #t (if (< vc 0) #t (if (< vr (frame-view-rows)) (not (< vc (frame-view-cols))) #t))) ()
      (pair (* frame-tile-size vc) (+ frame-level-y (* frame-tile-size vr))))))

; The picture named NAME put at R C, over its shadow when SHADOW; where
; the art has no picture of it, its GLYPH, (glyph X Y GLYPH), as the
; terminal shows it; nothing out of view.
(def %fr-put
  (fn (_ a cam r c name shadow glyph)
    (def at (frame-place cam r c))
    (def p (frame-named a name (+ (* r 80) c)))
    (def s (if shadow (frame-named a (lit shadow) 0) ()))
    (match
      ((null? at) ())
      ((null? p) (list (list (lit glyph) (first at) (rest at) glyph)))
      (#t (List append (if (null? s) () (list (list (lit tile) (first at) (rest at) s)))
                       (list (list (lit tile) (first at) (rest at) p)))))))

; What stands on G's level under camera CAM with art A, in the order
; the terminal draws it: found traps and items where they were seen,
; creatures in view over their shadows, the player last.
(def frame-things
  (fn (_ g a cam)
    (def m (game-map g))
    (def p (game-player g))
    (def set (game-set g))
    (List append
      (List flat-map (fn (_ t) (if (if (trap-found? t) (map-seen? m (trap-r t) (trap-c t)) #f)
                                 (%fr-put a cam (trap-r t) (trap-c t) (lit trap) #f (data-glyph set (lit trap) "^")) ()))
        (game-traps g))
      (List flat-map (fn (_ it) (if (map-seen? m (item-r it) (item-c it))
                                  (%fr-put a cam (item-r it) (item-c it) (item-class it) #f (items-glyph g it)) ()))
        (game-floor g))
      (List flat-map (fn (_ cr) (if (creatures-shown? g cr)
                                  (%fr-put a cam (creature-r cr) (creature-c cr) (creature-name cr) #t (creature-glyph cr)) ()))
        (game-creatures g))
      (%fr-put a cam (player-r p) (player-c p) (lit player) #t (data-glyph set (lit player) "@")))))

; --- what is lit ----------------------------------------------------------------

; The view of M under camera CAM as one op, (view X Y COLS ROWS
; BYTES): a byte a cell, row by row, 0 dark, 1 seen before, 2 in view.
(def frame-view
  (fn (_ m cam)
    (def rows (frame-view-rows))
    (def cols (frame-view-cols))
    (def n (* rows cols))
    (def bytes (str-make n))
    (def bp (str->ptr bytes))
    ((fn (self i)
       (when (int< i n)
         (do (def r (int+ (first cam) (int/ i cols)))
             (def c (int+ (rest cam) (int% i cols)))
             (ptr-set! bp i (match ((map-visible? m r c) 2) ((map-seen? m r c) 1) (#t 0)) 1)
             (self (int+ i 1)))))
     0)
    (list (lit view) 0 frame-level-y cols rows bytes)))

; The lights of OPS, the tiles drawn, whose cells are in view on M
; under camera CAM: (light X Y R G B REACH FLICKER), X Y the cell's
; middle, REACH in cells, FLICKER the waver in percent (0 for none).
(def frame-lights
  (fn (self m cam ops)
    (if (null? ops) ()
      (do (def op (first ops))
          (def l (if (eq? (first op) (lit tile)) (%fr-prop (first (rest (rest (rest op)))) (lit light)) ()))
          (if (null? l) (self m cam (rest ops))
            (do (def x (first (rest op)))
                (def y (first (rest (rest op))))
                (def form (first (rest (rest (rest op)))))
                (if (not (map-visible? m (int+ (first cam) (int/ (int- y frame-level-y) frame-tile-size))
                                         (int+ (rest cam) (int/ x frame-tile-size))))
                  (self m cam (rest ops))
                  (pair (List append (list (lit light) (int+ x 8) (int+ y 8)) (rest l)
                          (list ((fn (_ f) (if (null? f) 0 f)) (%fr-prop1 form (lit flicker)))))
                        (self m cam (rest ops))))))))))

; --- the light map ---------------------------------------------------------------

; A flame's waver: one wave of sixteen steps, out of a hundred.
(def %fr-wave (Vector of 0 38 70 92 100 92 70 38 0 -38 -70 -92 -100 -92 -70 -38))
(def %fr-wave-at (fn (_ i) (Vector ref (int% (if (int< i 0) (int- 0 i) i) 16) %fr-wave)))

; A light's strength at TICK, out of a hundred: three waves, slow and
; quick, each light out of step with the rest by its place.
(def frame-flicker
  (fn (_ l tick)
    (def f (List ref 7 l))
    (def s (int/ (int+ (int* (List ref 1 l) 37) (int* (List ref 2 l) 71)) 16))
    (if (int= f 0) 100
      (int+ 100 (int/ (int* f (int/ (int+ (int* 45 (%fr-wave-at (int+ (int* tick 3) s)))
                                         (int+ (int* 30 (%fr-wave-at (int+ (int* tick 7) (int* s 2))))
                                               (int* 25 (%fr-wave-at (int+ tick (int/ s 3))))))
                                    100))
                      100)))))

; The light map is worked in a region of four words a cell: the dark
; left and each channel's tint, out of 256.  Each light touches only
; the cells within its reach.
(def %fr-get (fn (_ w i k) (ptr-ref w (int+ (int* i 16) (int* k 4)) 4)))
(def %fr-put! (fn (_ w i k v) (ptr-set! w (int+ (int* i 16) (int* k 4)) (if (int< v 0) 0 v) 4)))

; Cell I of the map, COLS wide, lit by a light at LX LY reaching RAD
; pixels, its colour R G B at tint weight W0: the dark lifted by the
; square of the distance, the tint taken toward its colour.
(def %fr-light-cell!
  (fn (_ w i cols ox oy lx ly r2 r g b w0)
    (def dx (int- (int+ ox (int+ (int* (int% i cols) 16) 8)) lx))
    (def dy (int- (int+ oy (int+ (int* (int/ i cols) 16) 8)) ly))
    (def d2 (int+ (int* dx dx) (int* dy dy)))
    (when (int< d2 r2)
      (do (def c (int- 256 (int/ (int* d2 256) r2)))
          (def wt (int/ (int* w0 c) 256))
          (%fr-put! w i 0 (int/ (int* (%fr-get w i 0) (int- 256 c)) 256))
          (%fr-put! w i 1 (int- (%fr-get w i 1) (int/ (int* wt (int- 255 r)) 255)))
          (%fr-put! w i 2 (int- (%fr-get w i 2) (int/ (int* wt (int- 255 g)) 255)))
          (%fr-put! w i 3 (int- (%fr-get w i 3) (int/ (int* wt (int- 255 b)) 255)))))))

; Light L at strength K over the cells of its reach.
(def %fr-light!
  (fn (_ w cols rows ox oy l k)
    (def lx (List ref 1 l))
    (def ly (List ref 2 l))
    (def rad (int/ (int* (int* (List ref 6 l) 16) k) 100))
    (def r2 (int* rad rad))
    (def w0 (int/ (int* 56 k) 100))
    (def c0 (int/ (int- (int- lx ox) rad) 16))
    (def c1 (int/ (int+ (int- lx ox) rad) 16))
    (def r0 (int/ (int- (int- ly oy) rad) 16))
    (def r1 (int/ (int+ (int- ly oy) rad) 16))
    (def lo (fn (_ v) (if (int< v 0) 0 v)))
    (def hi (fn (_ v n) (if (int< v n) v (int- n 1))))
    (def cl (lo c0))
    (def ch (hi c1 cols))
    (def rl (lo r0))
    (def rh (hi r1 rows))
    (def r (List ref 3 l))
    (def g (List ref 4 l))
    (def b (List ref 5 l))
    ((fn (self y x)
       (if (int< rh y) #t
         (if (int< ch x) (self (int+ y 1) cl)
           (do (%fr-light-cell! w (int+ (int* y cols) x) cols ox oy lx ly r2 r g b w0)
               (self y (int+ x 1))))))
     rl cl)))

; How much of a cell in view the dark takes where no light reaches, and
; how much of that a cell seen before and out of view keeps, out of 256.
(def %fr-dark 100)
(def %fr-seen 150)
; What of red and green a cell seen before keeps, out of 256: its blue
; all, so the remembered level is cool.
(def %fr-cool-r 190)
(def %fr-cool-g 215)

; The light map of VIEW, the view op, and LIGHTS, the light ops, at
; TICK: a canvas, (COLS ROWS REGION), a pixel a cell, its R G B what
; the cell's pixels are multiplied by out of 255.  The level is dark
; but for the lights: each lifts the dark round it and tints it its
; colour; a cell seen before and out of view is dimmer still and
; cool, as the lights are warm; a cell never seen is black.
(def frame-light-map
  (fn (_ view lights tick)
    (def ox (List ref 1 view))
    (def oy (List ref 2 view))
    (def cols (List ref 3 view))
    (def rows (List ref 4 view))
    (def seen (List ref 5 view))
    (def n (int* cols rows))
    (def work (str-make (int* n 16)))
    (def w (str->ptr work))
    (def region (str-make (int* n 4)))
    (def rp (str->ptr region))
    ((fn (self i) (when (int< i n) (do (%fr-put! w i 0 256) (%fr-put! w i 1 256) (%fr-put! w i 2 256) (%fr-put! w i 3 256) (self (int+ i 1))))) 0)
    (List for-each (fn (_ l) (%fr-light! w cols rows ox oy l (frame-flicker l tick))) lights)
    ((fn (self i)
       (when (int< i n)
         (do (def v (char->int (str-byte-ref seen i)))
             (def m (int- 256 (int/ (int* %fr-dark (%fr-get w i 0)) 256)))
             (def m2 (if (int= v 2) m (if (int= v 1) (int/ (int* m %fr-seen) 256) 0)))
             (def o (int* i 4))
             (def cool (fn (_ x k) (if (int= v 1) (int/ (int* x k) 256) x)))
             (ptr-set! rp o (%fr-byte (cool (int/ (int* m2 (%fr-get w i 1)) 256) %fr-cool-r)) 1)
             (ptr-set! rp (int+ o 1) (%fr-byte (cool (int/ (int* m2 (%fr-get w i 2)) 256) %fr-cool-g)) 1)
             (ptr-set! rp (int+ o 2) (%fr-byte (int/ (int* m2 (%fr-get w i 3)) 256)) 1)
             (ptr-set! rp (int+ o 3) 255 1)
             (self (int+ i 1)))))
     0)
    (list cols rows region)))
(def %fr-byte (fn (_ x) (if (int< 255 x) 255 (if (int< x 0) 0 x))))

; G's level with art A, the camera on the player, as (CAM LEVEL .
; OVER): the ground's ops, which change only when the camera or the
; map does and so are drawn once into a layer of their own; then the
; cells of the ground with a tile that moves, (frames ...), what stands
; on it, the view and the lights, drawn over that every frame.
(def frame-scene
  (fn (_ g a)
    (def m (game-map g))
    (def p (game-player g))
    (def cam (frame-camera (map-rows m) (map-cols m) (player-r p) (player-c p)))
    (def level (frame-level a m cam))
    (def moving (%fr-moving-cells level))
    (def in? (fn (_ op) (%fr-at? moving (first (rest op)) (first (rest (rest op))))))
    (def things (frame-things g a cam))
    (def at (frame-place cam (player-r p) (player-c p)))
    (pair cam (pair (if (null? moving) level (List filter (fn (_ op) (not (in? op))) level))
      (List append (if (null? moving) () (List filter in? level))
        things (list (frame-view m cam)) (frame-lights m cam (List append level things))
        (if (null? at) () (list (List append (list (lit light) (int+ (first at) 8) (int+ (rest at) 8)) %fr-lantern)))
        (frame-glints g cam))))))

; The places, (X . Y), of the cells of OPS with a tile that moves.
(def %fr-moving-cells
  (fn (self ops)
    (match ((null? ops) ())
           ((if (eq? (first (first ops)) (lit tile)) (not (null? (%fr-prop (first (rest (rest (rest (first ops))))) (lit frames)))) #f)
             (pair (pair (first (rest (first ops))) (first (rest (rest (first ops))))) (self (rest ops))))
           (#t (self (rest ops))))))
; Whether X Y is one of PLACES.
(def %fr-at?
  (fn (self places x y)
    (match ((null? places) #f) ((if (int= (first (first places)) x) (int= (rest (first places)) y) #f) #t)
           (#t (self (rest places) x y)))))

; The hero's lantern, as a light's (R G B REACH FLICKER): warm, and
; wavering a little.
(def %fr-lantern (list 255 222 170 5 4))

; A glint on each item in view, (glint X Y SEED GOLD?): a star that
; comes and goes on it, drawn over the light (paint.x).  SEED puts each
; out of step with the rest.
(def frame-glints
  (fn (_ g cam)
    (def m (game-map g))
    (List flat-map
      (fn (_ it)
        (def at (if (map-visible? m (item-r it) (item-c it)) (frame-place cam (item-r it) (item-c it)) ()))
        (if (null? at) ()
          (list (list (lit glint) (first at) (rest at) (int+ (int* (item-r it) 7) (int* (item-c it) 13))
                      (eq? (item-class it) (lit gold))))))
      (game-floor g))))

(provide roguelike/frame
  frame-tile-size frame-view-rows frame-view-cols frame-view! frame-level-y
  frame-art frame-art-band frame-named frame-seed frame-wall-parts frame-camera frame-cell frame-level
  frame-place frame-things frame-view frame-lights frame-glints frame-flicker frame-light-map frame-scene)
