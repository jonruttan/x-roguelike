# The level as pictures
# @weight 1

What the windowed front-end draws for the level, as a list, before any
pixel is touched (see `docs/graphics.md`): which picture each cell
takes, a wall in parts by its neighbours, and the camera on the player.


## walls

### a wall's parts by its open neighbours

```roguelike
(import roguelike/frame frame-art frame-art-band frame-named frame-wall-parts frame-camera frame-cell frame-level
  frame-view-rows frame-view-cols frame-level-y frame-tile-size)
(def spec-solid (fn (_ open) (fn (_ dr dc) (not (List any? (fn (_ d) (if (= (first d) dr) (= (rest d) dc) #f)) open)))))
(def spec-delve-art (data-load "data/delve/art"))
(def spec-fa (frame-art spec-delve-art ()))
(def spec-tile-prop (fn (_ t key) ((fn (_ p) (if (null? p) () (List ref 1 p))) (List find (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) (rest t)))))
(write (List map (fn (_ open) (frame-wall-parts (spec-solid open)))
  (list ()
        (list '(1 . 0))
        (list '(1 . 0) '(0 . -1) '(0 . 1))
        (list '(-1 . 0))
        (list '(1 . 1))
        (list '(-1 . -1) '(-1 . 1))
        (list '(-1 . 0) '(0 . 1)))))
```
---
    (('top) ('face) ('face 'face-w 'face-e) ('top 'n) ('top 'se) ('top 'ne 'nw) ('top 'n 'e))


## the camera

### the player in the middle, always: the view runs past the map's edge

```roguelike
(write (list (frame-camera 22 80 0 0) (frame-camera 22 80 11 40) (frame-camera 22 80 21 79) (frame-camera 10 30 5 5)))
```
---
    ((-5 . -10) (6 . 30) (16 . 69) (0 . -5))


## the art

### each kind's parts; a kind with no pictures takes its sort's

```roguelike
(def a spec-fa)
(write (List map (fn (_ t) (List map first (Vector ref t (first a)))) (list tile-floor tile-wall tile-pillar tile-door tile-rock)))
```
---
    ((() 'shade) ('top 'face 'n 'e 'w 'ne 'nw 'se 'sw 'face-w 'face-e) ('top 'face 'n 'e 'w 'ne 'nw 'se 'sw 'face-w 'face-e) (()) ())

### a band's pictures in front of the set's

```roguelike
(import roguelike/map map-make map-set! map-seen!)
(def flood (frame-art spec-delve-art "The Flood"))
(def m (map-make 3 3))
(List for-each (fn (_ rc) (do (map-set! m (first rc) (rest rc) tile-wall) (map-seen! m (first rc) (rest rc)))) '((0 . 0) (0 . 1) (0 . 2) (1 . 0) (1 . 1) (1 . 2) (2 . 0) (2 . 1) (2 . 2)))
(map-set! m 2 1 tile-floor)
(write (List map (fn (_ op) (spec-tile-prop (List ref 3 op) 'band)) (frame-cell flood m 1 1 0 24)))
```
---
    ("The Flood")

### a named picture: a creature, the player, the shadow

```roguelike
(write (List map (fn (_ n) ((fn (_ t) (if (null? t) () (first t))) (frame-named spec-fa n 7))) (list "mine rat" 'player 'shadow "nobody")))
```
---
    ("mine rat" 'player 'shadow ())

### a pose is never the player's picture at a place

```roguelike
(write (List any? (fn (_ at) (not (null? (spec-tile-prop (frame-named spec-fa 'player at) 'pose)))) (List range 0 40)))
```
---
    #f


## the level

### every cell in view drawn, inside the level's rows

```roguelike
(def g (spec-game-on (spec-set-named "delve") 3 ()))
(def m (game-map g))
(def p (game-player g))
(def cam (frame-camera (map-rows m) (map-cols m) (player-r p) (player-c p)))
(def fa spec-fa)
(def ops (frame-level fa m cam))
(write (list (<= (* (frame-view-rows) (frame-view-cols)) (List length ops))
             (List all? (fn (_ op) (if (eq? (first op) 'tile) #t (eq? (first op) 'fill))) ops)
             (List all? (fn (_ op) (if (eq? (first op) 'tile) (pair? (List ref 3 op)) #t)) ops)
             (List all? (fn (_ op) (if (<= 0 (List ref 1 op)) (< (List ref 1 op) (* (frame-view-cols) 16)) #f)) ops)
             (List all? (fn (_ op) (if (<= frame-level-y (List ref 2 op)) (< (List ref 2 op) (+ frame-level-y (* (frame-view-rows) 16))) #f)) ops)
             (List any? (fn (_ op) (if (eq? (first op) 'tile)
                                     (if (= (List ref 1 op) (* 16 (- (player-c p) (rest cam))))
                                       (= (List ref 2 op) (+ frame-level-y (* 16 (- (player-r p) (first cam))))) #f) #f)) ops)))
```
---
    (#t #t #t #t #t #t)

### a view past the map's corner: the cells off the map dark fills, their view bytes 0

```roguelike
(import roguelike/frame frame-view)
(import x/core/doors str-byte-ref char->int)
(def off (frame-level fa m (pair -3 -5)))
(def first-op (List find (fn (_ op) (if (= (List ref 1 op) 0) (= (List ref 2 op) frame-level-y) #f)) off))
(def bytes (List ref 5 (frame-view m (pair -3 -5))))
(write (list (first first-op) (char->int (str-byte-ref bytes 0))
             (<= (* (frame-view-rows) (frame-view-cols)) (List length off))))
```
---
    ('fill 0 #t)

### what stands on it, the player last over a shadow; the view; the lights

```roguelike
(import roguelike/frame frame-things frame-view frame-lights frame-scene frame-place)
(import x/core/doors str-byte-ref char->int)
(def scene ((fn (_ s) (List append (List ref 1 s) (rest (rest s)))) (frame-scene g fa)))
(def tiles (List filter (fn (_ op) (eq? (first op) 'tile)) scene))
(def view (List find (fn (_ op) (eq? (first op) 'view)) scene))
(def cam (frame-camera (map-rows m) (map-cols m) (player-r p) (player-c p)))
(def at (frame-place cam (player-r p) (player-c p)))
(def cell (+ (* (- (player-r p) (first cam)) (frame-view-cols)) (- (player-c p) (rest cam))))
(write (list (first (List ref 3 (List ref (- (List length tiles) 2) tiles)))
             (first (List ref 3 (List ref (- (List length tiles) 1) tiles)))
             (List drop 1 (List take 5 view))
             (char->int (str-byte-ref (List ref 5 view) cell))
             (List find (fn (_ op) (if (eq? (first op) 'light) (= (List ref 1 op) (+ 8 (first at))) #f)) scene)))
```
---
    ('shadow 'player (0 24 20 10) 2 ('light 168 112 255 196 118 5 10))

### the light map: the player's cell lit and warm, a seen cell dimmer, a dark one black

```roguelike
(import roguelike/frame frame-light-map frame-flicker)
(import x/core/doors ptr-ref str->ptr)
(def lmap (frame-light-map view (List filter (fn (_ op) (eq? (first op) 'light)) scene) 0))
(def px (fn (_ i) (if (null? i) () (List map (fn (_ k) (ptr-ref (str->ptr (List ref 2 lmap)) (+ (* i 4) k) 1)) '(0 1 2 3)))))
(def first-of (fn (_ v) (List find (fn (_ i) (= v (char->int (str-byte-ref (List ref 5 view) i)))) (List range 0 (* (frame-view-rows) (frame-view-cols))))))
(def lit-beside (px (- cell 1)))
(import x/core/doors ptr-set!)
(ptr-set! (str->ptr (List ref 5 view)) (- cell 1) 1 1)
(def lmap (frame-light-map view (List filter (fn (_ op) (eq? (first op) 'light)) scene) 0))
(write (list (List take 2 lmap) (px cell) lit-beside (px (- cell 1)) (px (first-of 0))
             (List map (fn (_ t) (frame-flicker '(light 100 100 0 0 0 3 25) t)) '(0 1 2 3))
             ))
```
---
    ((20 10) (255 236 208 255) (255 238 210 255) (148 155 164 255) (0 0 0 255) (117 105 108 89))

### a set with no art: what stands on the level is its glyph

```roguelike
(def bare (frame-things g (frame-art () ()) cam))
(write (list (List all? (fn (_ op) (eq? (first op) 'glyph)) bare)
             (List ref 3 (List ref (- (List length bare) 1) bare))))
```
---
    (#t "@")
