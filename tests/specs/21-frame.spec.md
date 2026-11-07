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

### the player in the middle, the view held inside the map

```roguelike
(write (list (frame-camera 22 80 0 0) (frame-camera 22 80 11 40) (frame-camera 22 80 21 79) (frame-camera 10 30 5 5)))
```
---
    ((0 . 0) (2 . 20) (3 . 40) (0 . 0))


## the art

### each kind's parts; a kind with no pictures takes its sort's

```roguelike
(def a (frame-art spec-delve-art ()))
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
(write (List map (fn (_ n) ((fn (_ t) (if (null? t) () (first t))) (frame-named (frame-art spec-delve-art ()) n 7))) (list "mine rat" 'player 'shadow "nobody")))
```
---
    ("mine rat" 'player 'shadow ())


## the level

### every cell in view drawn, inside the level's rows

```roguelike
(def g (spec-game-on (spec-set-named "delve") 3 ()))
(def m (game-map g))
(def p (game-player g))
(def cam (frame-camera (map-rows m) (map-cols m) (player-r p) (player-c p)))
(def fa (frame-art spec-delve-art ()))
(def ops (frame-level fa m cam))
(write (list (<= (* frame-view-rows frame-view-cols) (List length ops))
             (List all? (fn (_ op) (if (eq? (first op) 'tile) #t (eq? (first op) 'fill))) ops)
             (List all? (fn (_ op) (if (eq? (first op) 'tile) (pair? (List ref 3 op)) #t)) ops)
             (List all? (fn (_ op) (if (<= 0 (List ref 1 op)) (< (List ref 1 op) 640) #f)) ops)
             (List all? (fn (_ op) (if (<= frame-level-y (List ref 2 op)) (< (List ref 2 op) (+ frame-level-y (* 19 16))) #f)) ops)
             (List any? (fn (_ op) (if (eq? (first op) 'tile)
                                     (if (= (List ref 1 op) (* 16 (- (player-c p) (rest cam))))
                                       (= (List ref 2 op) (+ frame-level-y (* 16 (- (player-r p) (first cam))))) #f) #f)) ops)))
```
---
    (#t #t #t #t #t #t)
