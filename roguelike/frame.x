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
(import x/core/doors int+ int- int* int/ int% int< int= str-make str->ptr ptr-set! ptr-ref ptr->int int->ptr str-byte-ref char->int mem-copy mem-cmp)
(import roguelike/data data-all data-glyph)
(import roguelike/items items-glyph)
(import roguelike/map map-terrain map-kinds map-rows map-cols map-tile map-seen? map-visible? map-in? map-opaque? map-chart
  tile-rock tile-roof tile-door tile-water tile-shallow map-shown map-covered? map-roofed? map-roof-pitch map-roof-at
  map-roof-off map-drawn-buffers)
(import roguelike/state game-map game-player game-floor game-creatures game-traps
  player-r player-c player-conditions item-r item-c item-class creature-r creature-c creature-name creature-glyph
  creature-state creature-condition game-set game-blows game-over)
(import roguelike/draw draw-hunger)
(import roguelike/game game-glow)
(import roguelike/creatures creatures-shown?)
(import roguelike/traps trap-r trap-c trap-found?)

(def frame-tile-size 16)
; The view, [ROWS COLS DR DC] in cells: drawn at the tile's size and
; shown at the painter's zoom (paint.x), which sets it to fill the
; screen; DR DC how far it is moved off the player, by a drag.
(def %fr-view (Vector of 10 20 0 0))
(def frame-view-rows (fn (_) (Vector ref 0 %fr-view)))
(def frame-view-cols (fn (_) (Vector ref 1 %fr-view)))
(def frame-view! (fn (_ rows cols) (do (Vector set! 0 rows %fr-view) (Vector set! 1 cols %fr-view) ())))
(def frame-pan (fn (_) (pair (Vector ref 2 %fr-view) (Vector ref 3 %fr-view))))
; V held to 0 .. N - 1.
(def %fr-held (fn (_ v n) (if (int< v 0) 0 (if (int< v n) v (int- n 1)))))
; The view of game G moved DR DC cells off the player, no further than
; puts its middle on the map's edge.
(def frame-pan!
  (fn (_ g dr dc)
    (def m (game-map g))
    (def p (game-player g))
    (Vector set! 2 (int- (%fr-held (int+ (player-r p) dr) (map-rows m)) (player-r p)) %fr-view)
    (Vector set! 3 (int- (%fr-held (int+ (player-c p) dc) (map-cols m)) (player-c p)) %fr-view)
    ()))
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

; Of TILES, one name's, those with part PART (nil for none) and no pose
; (a pose is drawn only for its moment, never as a variant), the band's
; own when it has any, else the set's: (TOTAL-WEIGHT . TILES), or nil.
(def %fr-variants
  (fn (_ tiles part band)
    (def mine (List filter (fn (_ t) (if (eq? (%fr-prop1 t (lit part)) part) (null? (%fr-prop t (lit pose))) #f)) tiles))
    (def own (if (null? band) () (List filter (fn (_ t) ((fn (_ b) (if (null? b) #f (str=? b band))) (%fr-prop1 t (lit band)))) mine)))
    (def vs (if (null? own) (List filter (fn (_ t) (null? (%fr-prop t (lit band)))) mine) own))
    (if (null? vs) () (pair (List fold (fn (_ n t) (+ n (%fr-weight t))) 0 vs) vs))))

(def %fr-parts (list () (lit top) (lit face) (lit n) (lit e) (lit s) (lit w) (lit ne) (lit nw) (lit se) (lit sw)
                     (lit out-ne) (lit out-nw) (lit out-se) (lit out-sw) (lit face-w) (lit face-e) (lit shade)
                     (lit north) (lit ridge) (lit west) (lit ridge-ns) (lit east)
                     (lit gable) (lit gable-w) (lit gable-e) (lit gable-ww) (lit gable-ee) (lit doorway) (lit stoop-n) (lit stoop-e) (lit stoop-s) (lit stoop-w)
                     (lit dormer) (lit dormer-n) (lit dormer-e) (lit dormer-w)))

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

; --- ground that joins ------------------------------------------------------

; The parts a joined ground cell (water, shallows: a kind drawn with
; rims) is drawn in, in order, from SAME?, (fn (_ dr dc)) whether the
; neighbour that way runs on from it: the whole; a rim on each side
; that does not; a rounded corner where both sides of it do not; and
; a notch where both sides do and the diagonal between does not.  So
; cells of a kind side by side are drawn as one pool.
(def frame-join-parts
  (fn (_ same?)
    (def n (same? -1 0))
    (def e (same? 0 1))
    (def s (same? 1 0))
    (def w (same? 0 -1))
    (def corner (fn (_ a b dr dc out in) (match ((not (if a #t b)) (list out)) ((if a (if b (not (same? dr dc)) #f) #f) (list in)) (#t ()))))
    (List append (list ())
      (if n () (list (lit n))) (if e () (list (lit e))) (if s () (list (lit s))) (if w () (list (lit w)))
      (corner n e -1 1 (lit out-ne) (lit ne)) (corner n w -1 -1 (lit out-nw) (lit nw))
      (corner s e 1 1 (lit out-se) (lit se)) (corner s w 1 -1 (lit out-sw) (lit sw)))))

; --- the camera -------------------------------------------------------------

; The view's top-left cell, (R0 . C0): the player at R C in the middle,
; so the screen is never half empty beside a map's edge, or moved off
; the player by the pan, its middle kept on the map of ROWS by COLS.
; What lies past the edge is drawn as rock.
(def frame-camera
  (fn (_ rows cols r c)
    (pair (- (%fr-held (+ r (Vector ref 2 %fr-view)) rows) (int/ (frame-view-rows) 2))
          (- (%fr-held (+ c (Vector ref 3 %fr-view)) cols) (int/ (frame-view-cols) 2)))))

; --- the level --------------------------------------------------------------

; Whether the cell at R C of M is solid to the walls beside it: opaque
; as it is drawn, off the map, or not yet seen.
(def %fr-solid?
  (fn (_ m r c) (if (map-in? m r c) (if (map-seen? m r c) (map-opaque? (map-shown m r c)) #t) #t)))
; Whether the cell at R C of M is solid to the roof beside it: under a
; roof that is on, its door too.
(def %fr-covered? (fn (_ m r c) (if (map-in? m r c) (map-covered? m r c) #f)))
; The parts the roofed cell at R C of M is drawn in, from the roof's
; pictures PICS: its front where the street lies south, the gable where
; the roof runs north and south, and a door there its doorway over it;
; elsewhere the slope it is on (map.x, map-roof-pitch), a door too,
; then the rims where the roof ends north, east and west.  A door is
; found by the stoop outside it (%fr-stoops).  Where PICS has no
; picture of a gable or a slope, the roof's face or its top.
(def %fr-slopes (list (lit top) (lit north) (lit ridge) (lit top) (lit west) (lit ridge-ns) (lit east)))
; The gable's part at R C, a cell of pitch P: the peak under the ridge,
; a rake in the cell beside the ridge, a low end beyond; face where the
; roof runs east and west.
(def %fr-gable
  (fn (_ m r c p)
    (match ((= p 5) (lit gable))
           ((= p 4) (if (= (map-roof-pitch m r (+ c 1)) 5) (lit gable-w) (lit gable-ww)))
           ((= p 6) (if (= (map-roof-pitch m r (- c 1)) 5) (lit gable-e) (lit gable-ee)))
           (#t (lit face)))))
(def %fr-roof-parts
  (fn (_ pics m r c seed)
    (def on? (fn (_ dr dc) (%fr-covered? m (+ r dr) (+ c dc))))
    (def p (map-roof-pitch m r c))
    (def have (fn (_ part other) (if (null? (%fr-pick pics part seed)) other part)))
    (def slope (List ref p %fr-slopes))
    (if (not (on? 1 0))
      (pair (have (%fr-gable m r c p) (lit face)) (if (= (map-tile m r c) tile-door) (list (lit doorway)) ()))
      (List append (list (have slope (lit top)))
        (if (on? -1 0) () (list (lit n)))
        (if (on? 0 1) () (list (lit e)))
        (if (on? 0 -1) () (list (lit w)))
        ((fn (_ d) (if (null? (%fr-pick pics d seed)) () (list d))) (%fr-dormer m r c on?))))))
; The dormer over a door at R C of M, ON? whether the cell that far off
; is under a roof: facing the street from the cell behind a front door,
; facing east, west or north from a door in those walls; nil where no
; door is.
(def %fr-dormer
  (fn (_ m r c on?)
    (def door? (fn (_ dr) (= (map-tile m (+ r dr) c) tile-door)))
    (match ((if (door? 1) (if (not (on? 2 0)) (= (map-roof-at m (+ r 1) c) (map-roof-at m r c)) #f) #f) (lit dormer))
           ((not (door? 0)) ())
           ((not (on? 0 1)) (lit dormer-e))
           ((not (on? 0 -1)) (lit dormer-w))
           ((not (on? -1 0)) (lit dormer-n))
           (#t ()))))
; Whether what lies at R C of M is drawn: seen, and under no roof.
(def %fr-seen? (fn (_ m r c) (if (map-seen? m r c) (not (map-roofed? m r c)) #f)))

; What to draw for the cell at R C of M with art A, at X Y: the
; ground's picture, or a wall's parts, or the shade a wall's face
; casts; under a roof that is on, the roof's parts, put together as a
; wall's are, by the roofed cells beside it; a cell not seen, or off
; the map, is a fill of the dark.
(def frame-cell
  (fn (_ a m r c x y) (%fr-cell-ops (%fr-cell-pics a m r c) x y)))
; The pictures the cell at R C of M is drawn in, in order, or dark for
; a fill of the dark.
(def %fr-cell-pics
  (fn (_ a m r c) (if (map-in? m r c) (%fr-cell a m r c) (lit dark))))
; The ops drawing a cell's pictures PICS at X Y.
(def %fr-cell-ops
  (fn (self pics x y)
    (match ((null? pics) ())
           ((pair? pics) (pair (list (lit tile) x y (first pics)) (self (rest pics) x y)))
           (#t (list (list (lit fill) x y frame-tile-size frame-tile-size))))))
(def %fr-cell
  (fn (_ a m r c)
    (def t ((fn (_ k) (if (= k tile-door) (if (map-covered? m r c) tile-roof k) k)) (map-shown m r c)))
    (def pics (Vector ref t (first a)))
    (def seed (+ (* r 80) c))
    ; The pictures of the parts PARTS, in order, in front of ACC.
    (def puts
      (fn (self parts acc)
        (if (null? parts) acc
          ((fn (_ p) (if (null? p) (self (rest parts) acc) (pair p (self (rest parts) acc))))
           (%fr-pick pics (first parts) seed)))))
    ; The ground's parts: joined to its neighbours where its kind has rims.
    (def ground
      (fn (_)
        (if (List any? (fn (_ p) (eq? (first p) (lit n))) pics)
          (frame-join-parts (fn (_ dr dc) (%fr-joins? m t (+ r dr) (+ c dc))))
          (list ()))))
    (match ((not (map-seen? m r c)) (lit dark))
           ((= t tile-rock) (lit dark))
           ((= t tile-roof) (puts (%fr-roof-parts pics m r c seed) ()))
           ((map-opaque? t) (puts (frame-wall-parts (fn (_ dr dc) (%fr-solid? m (+ r dr) (+ c dc)))) ()))
           ((%fr-solid? m (- r 1) c) (puts (List append (ground) (list (lit shade))) (%fr-stoops a m r c)))
           (#t (puts (ground) (%fr-stoops a m r c))))))

; The stoops on the ground at R C of M, art A, their pictures: one from the
; roof's pictures for each door beside it into a building it is not
; part of, on the side the door is, so a door is found from the street
; whether its roof is on or off: stoop-s below a door to the north,
; stoop-n above one to the south, stoop-e and stoop-w beside one to the
; west and east.
(def %fr-stoop-sides
  (list (list -1 0 (lit stoop-s)) (list 1 0 (lit stoop-n)) (list 0 -1 (lit stoop-e)) (list 0 1 (lit stoop-w))))
(def %fr-stoops
  (fn (_ a m r c)
    (def here (map-roof-at m r c))
    (def pics (Vector ref tile-roof (first a)))
    (List flat-map
      (fn (_ s)
        (def dr (first s))
        (def dc (first (rest s)))
        (def id (map-roof-at m (+ r dr) (+ c dc)))
        (if (if (= (map-tile m (+ r dr) (+ c dc)) tile-door) (if (< 0 id) (not (= id here)) #f) #f)
          ((fn (_ p) (if (null? p) () (list p)))
           (%fr-pick pics (List ref 2 s) (+ (* r 80) c)))
          ()))
      %fr-stoop-sides)))

; Whether kind T is water, deep or shallow.
(def %fr-wet? (fn (_ t) (if (= t tile-water) #t (= t tile-shallow))))
; Whether the cell at R C of M runs on from ground of kind T, with no
; rim between: the same kind, water beside water, a wall, or a cell not
; seen or off the map.
(def %fr-joins?
  (fn (_ m t r c)
    (if (if (map-in? m r c) (map-seen? m r c) #f)
      ((fn (_ u) (match ((= u t) #t) ((map-opaque? u) #t) (#t (if (%fr-wet? t) (%fr-wet? u) #f)))) (map-tile m r c))
      #t)))

; A cell's pictures turn only on the tiles, the seen flags and the roofs
; of it and the cells beside it, so they are kept from turn to turn and
; worked again only around a cell whose tile or seen flag has changed;
; all of them when a roof has changed, or the roof that is off.
;
; A level's cache, [MAP ART OFF TILES SEEN ROOFS CELLS]: the map and art
; its cells were worked for, OFF the roof that was off then, TILES SEEN
; and ROOFS copies of the map's buffers then, CELLS each cell's pictures
; (%fr-cell-pics), or unset.  The painter keeps one.
(def frame-level-cache (fn (_) (Vector of () () -1 () () () ())))
(def %fr-copy (fn (_ s n) (def d (str-make n)) (mem-copy (str->ptr d) (str->ptr s) n) d))
(def %fr-same-buffer?
  (fn (_ a b n) (if (null? a) (null? b) (if (null? b) #f (int= 0 (mem-cmp (str->ptr a) (str->ptr b) n))))))
; CACHE brought up to map M with art A.
(def %fr-level-kept!
  (fn (_ cache a m)
    (def n (int* (map-rows m) (map-cols m)))
    (def bufs (map-drawn-buffers m))
    (def roofs (List ref 2 bufs))
    (if (if (same? m (Vector ref 0 cache))
          (if (same? a (Vector ref 1 cache))
            (if (int= (map-roof-off m) (Vector ref 2 cache)) (%fr-same-buffer? roofs (Vector ref 5 cache) n) #f) #f) #f)
      (do (%fr-changed! cache m (first bufs) 3)
          (%fr-changed! cache m (List ref 1 bufs) 4))
      (do (Vector set! 0 m cache)
          (Vector set! 1 a cache)
          (Vector set! 2 (map-roof-off m) cache)
          (Vector set! 3 (%fr-copy (first bufs) n) cache)
          (Vector set! 4 (%fr-copy (List ref 1 bufs) n) cache)
          (Vector set! 5 (if (null? roofs) () (%fr-copy roofs n)) cache)
          (Vector set! 6 (Vector make n (lit unset)) cache)))))
; The cells of CACHE around each cell whose byte in the map M's buffer
; NOW differs from its copy in CACHE's slot K unset, row by row, and
; the copy brought up to NOW.
(def %fr-changed!
  (fn (_ cache m now k)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def np (str->ptr now))
    (def wp (str->ptr (Vector ref k cache)))
    (def cells (Vector ref 6 cache))
    (def at (fn (_ p o) (int->ptr (int+ (ptr->int p) o))))
    (def unset!
      (fn (_ r c)
        (List for-each
          (fn (_ d)
            (def r2 (int+ r (first d)))
            (def c2 (int+ c (rest d)))
            (when (map-in? m r2 c2) (Vector set! (int+ (int* r2 cols) c2) (lit unset) cells)))
          %fr-around)))
    (unless (int= 0 (mem-cmp np wp (int* rows cols)))
      ((fn (self r)
         (when (int< r rows)
           (do (def o (int* r cols))
               (unless (int= 0 (mem-cmp (at np o) (at wp o) cols))
                 ((fn (self c)
                    (when (int< c cols)
                      (do (unless (int= (ptr-ref np (int+ o c) 1) (ptr-ref wp (int+ o c) 1)) (unset! r c))
                          (self (int+ c 1)))))
                  0))
               (self (int+ r 1)))))
       0)
      (mem-copy wp np (int* rows cols)))))
(def %fr-around (list (pair -1 -1) (pair -1 0) (pair -1 1) (pair 0 -1) (pair 0 0) (pair 0 1) (pair 1 -1) (pair 1 0) (pair 1 1)))
; Cell R C's pictures from CACHE, worked and kept when unset.
(def %fr-kept-pics
  (fn (_ cache a m r c)
    (if (map-in? m r c)
      ((fn (_ cells i)
         ((fn (_ pics) (if (eq? pics (lit unset)) ((fn (_ new) (Vector set! i new cells) new) (%fr-cell a m r c)) pics))
          (Vector ref i cells)))
       (Vector ref 6 cache) (int+ (int* r (map-cols m)) c))
      (lit dark))))

; The level's cells in view of camera CAM, (R0 . C0), with art A, in
; the order to draw them, their pictures kept in CACHE
; (frame-level-cache): built from the last cell back.
(def frame-level
  (fn (_ cache a m cam)
    (%fr-level-kept! cache a m)
    (def r0 (first cam))
    (def c0 (rest cam))
    (def cols (frame-view-cols))
    ((fn (self i acc)
       (if (int< i 0) acc
         (do (def r (int+ r0 (int/ i cols)))
             (def c (int+ c0 (int% i cols)))
             (self (int- i 1)
               (%fr-onto (%fr-cell-ops (%fr-kept-pics cache a m r c) (int* frame-tile-size (int- c c0)) (int+ frame-level-y (int* frame-tile-size (int- r r0)))) acc)))))
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
; terminal shows it; nothing out of view.  A thing that walks, WHO (a
; creature, or player), has its tile op, and its shadow's, as (tile X Y
; PICTURE (WHO R . C)), so the painter can tell whether it moved since
; the last turn and move the two together.
(def %fr-put
  (fn (_ a cam r c name shadow glyph who)
    (def at (frame-place cam r c))
    (def p (frame-named a name (+ (* r 80) c)))
    (def s (if shadow (frame-named a (lit shadow) 0) ()))
    (def put (fn (_ pic) (if (null? who) (list (lit tile) (first at) (rest at) pic) (list (lit tile) (first at) (rest at) pic (pair who (pair r c))))))
    (match
      ((null? at) ())
      ((null? p) (list (list (lit glyph) (first at) (rest at) glyph)))
      (#t (List append (if (null? s) () (list (put s))) (list (put p)))))))
; What stands on G's level under camera CAM with art A, in the order
; the terminal draws it: found traps and items where they were seen,
; creatures in view over their shadows, the player last.
(def frame-things
  (fn (_ g a cam)
    (def m (game-map g))
    (def p (game-player g))
    (def set (game-set g))
    (List append
      (List flat-map (fn (_ t) (if (if (trap-found? t) (%fr-seen? m (trap-r t) (trap-c t)) #f)
                                 (%fr-put a cam (trap-r t) (trap-c t) (lit trap) #f (data-glyph set (lit trap) "^") ()) ()))
        (game-traps g))
      (List flat-map (fn (_ it) (if (%fr-seen? m (item-r it) (item-c it))
                                  (%fr-put a cam (item-r it) (item-c it) (item-class it) #f (items-glyph g it) ()) ()))
        (game-floor g))
      (List flat-map (fn (_ cr) (if (creatures-shown? g cr)
                                  (List append
                                    (%fr-put a cam (creature-r cr) (creature-c cr) (creature-name cr) #t (creature-glyph cr) cr)
                                    (%fr-marks a cam (creature-r cr) (creature-c cr) cr (%fr-creature-states cr)))
                                  ()))
        (game-creatures g))
      (%fr-posed a (%fr-put a cam (player-r p) (player-c p) (lit player) #t (data-glyph set (lit player) "@") (lit player))
                 (%fr-player-pose g))
      (%fr-marks a cam (player-r p) (player-c p) (lit player) (%fr-player-states g)))))

; --- poses ----------------------------------------------------------------------

; The picture of NAME in POSE, (tile NAME (pose POSE) ...), or nil.
(def frame-pose
  (fn (_ a name pose)
    (List find (fn (_ t) (eq? (%fr-prop1 t (lit pose)) pose)) (%fr-named (List ref 1 a) name))))

; The player's pose in game G: dead when the game ended in its death;
; else hit when a blow landed on it this turn, attack when it struck
; one; else nil.
(def %fr-player-pose
  (fn (_ g)
    (def p (game-player g))
    (def at? (fn (_ r c) (if (= r (player-r p)) (= c (player-c p)) #f)))
    (def blows (game-blows g))
    (match
      ((eq? (game-over g) (lit dead)) (lit dead))
      ((List any? (fn (_ b) (if (at? (List ref 3 b) (List ref 4 b)) (not (eq? (List ref 5 b) (lit miss))) #f)) blows) (lit hit))
      ((List any? (fn (_ b) (at? (List ref 1 b) (List ref 2 b))) blows) (lit attack))
      (#t ()))))

; OPS, the player's from %fr-put, posed POSE from art A: dead drawn in
; place of its picture; any other pose, a blow's, carried on its tile
; op, (tile X Y PICTURE (WHO R . C) (pose PICTURE)), for the front-end
; to draw while the turn's blows are shown.  A pose the art has none of
; is no pose.
(def %fr-posed
  (fn (_ a ops pose)
    (def pic (if (null? pose) () (frame-pose a (lit player) pose)))
    (if (null? pic) ops
      (List map
        (fn (_ op)
          (if (if (eq? (first op) (lit tile)) (if (< 4 (List length op)) (eq? (first (List ref 3 op)) (lit player)) #f) #f)
            (if (eq? pose (lit dead))
              (list (lit tile) (List ref 1 op) (List ref 2 op) pic (List ref 4 op))
              (list (lit tile) (List ref 1 op) (List ref 2 op) (List ref 3 op) (List ref 4 op) (list (lit pose) pic)))
            op))
        ops))))

; --- marks ----------------------------------------------------------------------

; The states a mark is drawn for over a creature: asleep, and the
; conditions it is under.
(def %fr-creature-marks (list (lit held) (lit slowed)))
(def %fr-creature-states
  (fn (_ cr)
    (List append (if (eq? (creature-state cr) (lit asleep)) (list (lit asleep)) ())
                 (List filter (fn (_ name) (< 0 (creature-condition cr name))) %fr-creature-marks))))
; The player's: each condition it is under, and its hunger.
(def %fr-player-states
  (fn (_ g)
    (def hunger (draw-hunger g))
    (List append (List map first (List filter (fn (_ c) (< 0 (rest c))) (player-conditions (game-player g))))
                 (match ((str=? hunger "Hungry") (list (lit hungry)) )
                        ((str=? hunger "Weak") (list (lit weak)))
                        ((str=? hunger "") ())
                        (#t (list (lit fainting)))))))

; The marks over the thing WHO at R C under camera CAM for STATES, from
; art A: each state's mark-STATE picture as a tile op, (tile X Y PICTURE
; (WHO R . C) mark), that moves with WHO and goes round its pictures
; whatever WHO does; asleep, where the art has no mark-asleep, as (sleep
; X Y SEED), drawn by the front-end; a state with neither, nothing.
(def %fr-marks
  (fn (_ a cam r c who states)
    (def at (frame-place cam r c))
    (if (null? at) ()
      (List flat-map
        (fn (_ name)
          (def pic (frame-named a (Str8 ->sym (Str8 append "mark-" (symbol->str name))) 0))
          (match ((not (null? pic)) (list (list (lit tile) (first at) (rest at) pic (pair who (pair r c)) (lit mark))))
                 ((eq? name (lit asleep)) (list (list (lit sleep) (first at) (rest at) (+ (* r 7) (* c 13)))))
                 (#t ())))
        states))))

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
             (ptr-set! bp i (match ((not (map-in? m r c)) 0) ((map-visible? m r c) 2) ((map-seen? m r c) 1) (#t 0)) 1)
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

; The reach of light L at strength K in a map COLS by ROWS whose first
; cell is at OX OY: (RL RH CL CH K), its rows and columns held to the
; map, and K.
(def %fr-reach
  (fn (_ cols rows ox oy l k)
    (def lx (List ref 1 l))
    (def ly (List ref 2 l))
    (def rad (int/ (int* (int* (List ref 6 l) 16) k) 100))
    (def lo (fn (_ v) (if (int< v 0) 0 v)))
    (def hi (fn (_ v n) (if (int< v n) v (int- n 1))))
    (list (lo (int/ (int- (int- ly oy) rad) 16)) (hi (int/ (int+ (int- ly oy) rad) 16) rows)
          (lo (int/ (int- (int- lx ox) rad) 16)) (hi (int/ (int+ (int- lx ox) rad) 16) cols)
          k)))

; F called with each cell of REACH in a map COLS wide.
(def %fr-each-cell
  (fn (_ reach cols f)
    (def rh (List ref 1 reach))
    (def cl (List ref 2 reach))
    (def ch (List ref 3 reach))
    ((fn (self y x)
       (if (int< rh y) #t
         (if (int< ch x) (self (int+ y 1) cl)
           (do (f (int+ (int* y cols) x)) (self y (int+ x 1))))))
     (first reach) cl)))

; Light L over the cells of REACH, its strength there.
(def %fr-light!
  (fn (_ w cols ox oy l reach)
    (def k (List ref 4 reach))
    (def lx (List ref 1 l))
    (def ly (List ref 2 l))
    (def rad (int/ (int* (int* (List ref 6 l) 16) k) 100))
    (def r2 (int* rad rad))
    (def w0 (int/ (int* 56 k) 100))
    (def r (List ref 3 l))
    (def g (List ref 4 l))
    (def b (List ref 5 l))
    (%fr-each-cell reach cols (fn (_ i) (%fr-light-cell! w i cols ox oy lx ly r2 r g b w0)))))

; How much of a cell in view the dark takes where no light reaches, and
; how much of that a cell seen before and out of view keeps, out of 256.
(def %fr-dark 72)
(def %fr-seen 200)
; What of red and green a cell seen before keeps, out of 256: its blue
; all, so the remembered level is cool.
(def %fr-cool-r 190)
(def %fr-cool-g 215)

; The light map of VIEW, the view op, and LIGHTS, the light ops, at
; TICK, worked in CACHE (frame-light-cache): a canvas, (COLS ROWS
; REGION), a pixel a cell, its R G B what
; the cell's pixels are multiplied by out of 255.  The level is dark
; but for the lights: each lifts the dark round it and tints it its
; colour; a cell seen before and out of view is dimmer still and
; cool, as the lights are warm; a cell never seen is black.
;
; A cell no light reaches has a colour that only its being in view, seen
; before or never seen decides, so the map with no light on it is made
; once a view and copied each frame; only the cells within a light's
; reach are worked, in a region kept at no light between frames.
(def frame-light-map
  (fn (_ cache view lights tick)
    (def cols (List ref 3 view))
    (def rows (List ref 4 view))
    (def n (int* cols rows))
    (unless (same? view (Vector ref 0 cache)) (%fr-unlit! cache view n))
    (def w (str->ptr (Vector ref 2 cache)))
    (def seen (List ref 5 view))
    (def region (str-make (int* n 4)))
    (def rp (str->ptr region))
    (mem-copy rp (str->ptr (Vector ref 1 cache)) (int* n 4))
    (def reaches (List map (fn (_ l) (pair l (%fr-reach cols rows (List ref 1 view) (List ref 2 view) l (frame-flicker l tick)))) lights))
    (List for-each (fn (_ lr) (%fr-light! w cols (List ref 1 view) (List ref 2 view) (first lr) (rest lr))) reaches)
    (List for-each (fn (_ lr) (%fr-each-cell (rest lr) cols (fn (_ i) (%fr-shade! rp (int* i 4) (char->int (str-byte-ref seen i)) w i)))) reaches)
    (List for-each (fn (_ lr) (%fr-each-cell (rest lr) cols (fn (_ i) (%fr-clear! w i)))) reaches)
    (list cols rows region)))

; A light map's cache, [VIEW UNLIT WORK N]: the view the map with no
; light was last made for, UNLIT that map, WORK a region of N cells at
; no light.  The painter keeps one.
(def frame-light-cache (fn (_) (Vector of () () () 0)))
(def %fr-clear! (fn (_ w i) (%fr-put! w i 0 256) (%fr-put! w i 1 256) (%fr-put! w i 2 256) (%fr-put! w i 3 256)))
(def %fr-unlit!
  (fn (_ cache view n)
    (unless (int= n (Vector ref 3 cache))
      (do (def work (str-make (int* n 16)))
          ((fn (self i) (when (int< i n) (do (%fr-clear! (str->ptr work) i) (self (int+ i 1))))) 0)
          (Vector set! 2 work cache)
          (Vector set! 3 n cache)))
    (def unlit (str-make (int* n 4)))
    (def seen (List ref 5 view))
    (def w (str->ptr (Vector ref 2 cache)))
    ((fn (self i) (when (int< i n) (do (%fr-shade! (str->ptr unlit) (int* i 4) (char->int (str-byte-ref seen i)) w i) (self (int+ i 1))))) 0)
    (Vector set! 1 unlit cache)
    (Vector set! 0 view cache)))

; Cell I's colour in the map at RP offset O from its dark and tints in
; the region W, V whether it is in view (2), seen before (1) or not (0).
(def %fr-shade!
  (fn (_ rp o v w i)
    (def m (int- 256 (int/ (int* %fr-dark (%fr-get w i 0)) 256)))
    (def m2 (if (int= v 2) m (if (int= v 1) (int/ (int* m %fr-seen) 256) 0)))
    (def r (int/ (int* m2 (%fr-get w i 1)) 256))
    (def g (int/ (int* m2 (%fr-get w i 2)) 256))
    (ptr-set! rp o (%fr-byte (if (int= v 1) (int/ (int* r %fr-cool-r) 256) r)) 1)
    (ptr-set! rp (int+ o 1) (%fr-byte (if (int= v 1) (int/ (int* g %fr-cool-g) 256) g)) 1)
    (ptr-set! rp (int+ o 2) (%fr-byte (int/ (int* m2 (%fr-get w i 3)) 256)) 1)
    (ptr-set! rp (int+ o 3) 255 1)))
(def %fr-byte (fn (_ x) (if (int< 255 x) 255 (if (int< x 0) 0 x))))

; G's level with art A, its cells' pictures kept in CACHE
; (frame-level-cache), the camera on the player, as (CAM LEVEL .
; OVER): the ground's ops, which change only when the camera or the
; map does and so are drawn once into a layer of their own; then the
; cells of the ground with a tile that moves, (frames ...), what stands
; on it, the view and the lights, drawn over that every frame, and the
; chart of the whole level.
(def frame-scene
  (fn (_ cache g a)
    (def m (game-map g))
    (def p (game-player g))
    (def cam (frame-camera (map-rows m) (map-cols m) (player-r p) (player-c p)))
    (def level (frame-level cache a m cam))
    (def moving (%fr-moving-cells level))
    (def in? (fn (_ op) (%fr-at? moving (first (rest op)) (first (rest (rest op))))))
    (def things (frame-things g a cam))
    (def at (frame-place cam (player-r p) (player-c p)))
    (pair cam (pair (if (null? moving) level (List filter (fn (_ op) (not (in? op))) level))
      (List append (if (null? moving) () (List filter in? level))
        things (list (frame-view m cam))
        (frame-lights m cam ((fn (_ ops) (if (int< 0 (game-glow g)) (List reject %fr-player-op? ops) ops)) (List append level things)))
        (if (null? at) () (list (List append (list (lit light) (int+ (first at) 8) (int+ (rest at) 8)) (%fr-carried g))))
        (frame-glints g cam) (frame-blows g cam) (list (frame-chart g)))))))

; The turn's blows whose target is in view under camera CAM, oldest
; first, each (blow FX FY TX TY HOW N BY-PLAYER? WHAT UNSEEN?): the
; pixel places of who struck (the target's when the striker is out of
; view) and of whom, HOW hit, miss, kill or touch, N the damage, whether
; the player struck, what flew, or nil, and whether it was struck from a
; cell in view with no one drawn there.
(def frame-blows
  (fn (_ g cam)
    (def p (game-player g))
    (List flat-map
      (fn (_ b)
        (def to (frame-place cam (List ref 3 b) (List ref 4 b)))
        (def from ((fn (_ f) (if (null? f) to f)) (frame-place cam (List ref 1 b) (List ref 2 b))))
        (def mine (if (= (List ref 1 b) (player-r p)) (= (List ref 2 b) (player-c p)) #f))
        (if (null? to) ()
          (list (list (lit blow) (first from) (rest from) (first to) (rest to) (List ref 5 b) (List ref 6 b)
                      mine (List ref 7 b) (if mine #f (%fr-unseen-at? g (List ref 1 b) (List ref 2 b)))))))
      (List reverse (game-blows g)))))
; Whether the cell at R C is in view with no one drawn there who stands
; on it: the striker from it is not seen.
(def %fr-unseen-at?
  (fn (_ g r c)
    (if (map-visible? (game-map g) r c)
      (not (List any? (fn (_ cr) (if (if (= (creature-r cr) r) (= (creature-c cr) c) #f) (creatures-shown? g cr) #f))
             (game-creatures g)))
      #f)))


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
; The light the player carries: with the lamp out and a ring's light
; (game-glow), a cold sea-green out as far as it reaches, steady, and
; the player's own picture's light left out; else the lantern.
(def %fr-player-op?
  (fn (_ op)
    (match ((not (eq? (first op) (lit tile))) #f) ((null? (rest (rest (rest (rest op))))) #f)
           (#t (eq? (first (List ref 4 op)) (lit player))))))
(def %fr-carried
  (fn (_ g)
    (def reach (game-glow g))
    (if (int< 0 reach) (list 110 235 190 reach 0) %fr-lantern)))

; A glint on each item in view, (glint X Y SEED GOLD?): a star that
; comes and goes on it, drawn over the light (paint.x).  SEED puts each
; out of step with the rest.
(def frame-glints
  (fn (_ g cam)
    (def m (game-map g))
    (List flat-map
      (fn (_ it)
        (def at (if (if (map-visible? m (item-r it) (item-c it)) (not (map-roofed? m (item-r it) (item-c it))) #f)
                  (frame-place cam (item-r it) (item-c it)) ()))
        (if (null? at) ()
          (list (list (lit glint) (first at) (rest at) (int+ (int* (item-r it) 7) (int* (item-c it) 13))
                      (eq? (item-class it) (lit gold))))))
      (game-floor g))))

; --- the chart -----------------------------------------------------------------

; The whole of G's level, small, as one op, (chart ROWS COLS BYTES (PR
; . PC) ((R . C) ...)): a byte a cell, row by row, as map-chart has it;
; where the player stands; and where each creature shown stands, on the
; screen or off it.
(def frame-chart
  (fn (_ g)
    (def m (game-map g))
    (def p (game-player g))
    (list (lit chart) (map-rows m) (map-cols m) (map-chart m) (pair (player-r p) (player-c p))
          (List flat-map (fn (_ cr) (if (creatures-shown? g cr) (list (pair (creature-r cr) (creature-c cr))) ()))
            (game-creatures g)))))

(provide roguelike/frame
  frame-tile-size frame-view-rows frame-view-cols frame-view! frame-pan frame-pan! frame-level-y
  frame-art frame-art-band frame-named frame-seed frame-wall-parts frame-join-parts frame-camera frame-cell frame-level
  frame-place frame-things frame-view frame-lights frame-glints frame-blows frame-flicker frame-light-map frame-light-cache frame-level-cache frame-scene
  frame-chart)
