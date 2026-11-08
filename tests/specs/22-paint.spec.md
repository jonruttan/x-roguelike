# The frame drawn
# @weight 1

The level's pictures drawn onto the screen (see `docs/graphics.md`):
the art decoded once, the level into a layer of its own each turn, and
each frame that layer, what stands on it, the light and the text.


## the art

### every tile with rows has its picture; one drawn as another takes that one's

```roguelike
(import roguelike/paint paint-art paint-font paint-make paint-screen paint-turn! paint-frame! paint-flickers? paint-width paint-height paint-level-y)
(import roguelike/frame frame-art frame-camera frame-place frame-tile-size frame-level-y)
(import x/gfx/canvas)
(def spec-art (paint-art (data-load "data/delve/art")))
(def spec-pic (fn (_ f) ((fn (_ p) (if (null? p) () (rest p))) (List find (fn (_ p) (if (pair? p) (eq? (first p) 'picture) #f)) (rest (rest f))))))
(def spec-tiles (List filter (fn (_ f) (if (pair? f) (eq? (first f) 'tile) #f)) spec-art))
(def spec-named (fn (_ n) (List find (fn (_ f) (eq? (List ref 1 f) n)) spec-tiles)))
(write (list (List all? (fn (_ f) (not (null? (spec-pic f)))) spec-tiles)
             (List all? (fn (_ f) (if (eq? (List ref 1 f) 'panel) #t
                                    ((fn (_ c) (if (= (first c) 16) (= (List ref 1 c) 16) #f)) (first (spec-pic f))))) spec-tiles)
             ((fn (_ c) (List any? (fn (_ f) (if (eq? (List ref 1 f) 'floor) (eq? (first (spec-pic f)) c) #f)) spec-tiles))
              (first (spec-pic (spec-named 'passage))))
             (List ref 1 (spec-pic (spec-named 'floor)))
             (List ref 1 (spec-pic (spec-named 'player)))))
```
---
    (#t #t #t #t #f)

### a tile that moves has its pictures: its own rows' first, then each frame's

```roguelike
(def moving (paint-art (list '(colour "a" 10 20 30) '(colour "b" 200 100 50)
                             '(tile lamp (rows "ab" "ba") (frames 3 (rows "bb" "aa") (rows "aa" "aa"))))))
(def ps (List find (fn (_ p) (if (pair? p) (eq? (first p) 'pictures) #f)) (rest (rest (first (rest (rest moving)))))))
(write (list (List ref 1 ps) (List length (rest (rest ps)))
             (eq? (List ref 1 (List ref 2 ps)) (first (spec-pic (List ref 2 moving))))
             (List map (fn (_ p) (Canvas pixel (List ref 1 p) 0 0)) (rest (rest ps)))))
```
---
    (3 3 #t ((10 20 30 255) (200 100 50 255) (10 20 30 255)))

### the font: a letter's cell six wide, its ink and one clear column

```roguelike
(def spec-font (paint-font "art"))
(write (List ref 2 spec-font))
```
---
    6


## a frame

### the screen's size; the player drawn, rock black, the standing written

```roguelike
(def g (spec-game-on (spec-set-named "delve") 3 ()))
(def fa (frame-art spec-art ()))
(def p (paint-make spec-font))
(paint-turn! p g fa)
(def s (paint-frame! p g 0))
(def m (game-map g))
(def pl (game-player g))
(def at (frame-place (frame-camera (map-rows m) (map-cols m) (player-r pl) (player-c pl)) (player-r pl) (player-c pl)))
(def lit? (fn (_ px) (< 0 (+ (first px) (List ref 1 px) (List ref 2 px)))))
(write (list (first s) (List ref 1 s)
             (lit? (Canvas pixel s (+ 16 (* 2 (first at))) (+ 16 (+ paint-level-y (* 2 (- (rest at) frame-level-y))))))
             (Canvas pixel s 0 (+ paint-level-y 60))
             (List any? (fn (_ x) (lit? (Canvas pixel s x 351))) (List range 0 80))
             (paint-flickers? p)))
```
---
    (640 360 #t (0 0 0 255) #t #t)

### the pack looked at lies over the level on the panel, its lines written

```roguelike
(import roguelike/draw draw-overlay)
(def before (Canvas pixel s 20 60))
(game-key! g "i")
(paint-turn! p g fa)
(def s (paint-frame! p g 0))
(def ink? (fn (_ y) (List any? (fn (_ x) (= 206 (first (Canvas pixel s x y)))) (List range 8 200))))
(write (list (List length (draw-overlay g)) (equal? before (Canvas pixel s 20 60)) (List any? ink? (List range 58 74))))
```
---
    (1 #f #t)

### the zoom: the view as many cells as fill the screen at it, held to one to four; a frame drawn at each

```roguelike
(import roguelike/paint paint-zoom paint-zoom!)
(import roguelike/frame frame-view-rows frame-view-cols)
(def at-zoom (fn (_ z) (paint-zoom! p z) (paint-turn! p g fa) (paint-frame! p g 0)
                       (list (paint-zoom p) (frame-view-rows) (frame-view-cols) (first (Vector ref 5 p)))))
(write (list (at-zoom 1) (at-zoom 3) (at-zoom 4) (at-zoom 9) (at-zoom 0) (at-zoom 2)))
```
---
    ((1 18 40 640) (3 6 14 224) (4 5 10 160) (4 5 10 160) (1 18 40 640) (2 9 20 320))


## each place's art

### a region is drawn with its own set's art, the world's behind it for what it does not draw; each made once

```roguelike
(import roguelike/paint paint-arts)
(def spec-arts (paint-arts "data/kettle"))
(def spec-tiles-named
  (fn (_ art n) (List filter (fn (_ f) (if (pair? f) (if (eq? (first f) 'tile) (equal? (List ref 1 f) n) #f) #f)) art)))
(def spec-own-floors (List length (spec-tiles-named (paint-art (data-load "data/town/art")) 'floor)))
(def spec-light (fn (_ art) (rest (List find (fn (_ p) (if (pair? p) (eq? (first p) 'light) #f)) (first (spec-tiles-named art 'player))))))
(def town (spec-arts "town"))
(write (list (= spec-own-floors (List length (spec-tiles-named town 'floor)))
             (List length (spec-tiles-named town "farm dog"))
             (List length (spec-tiles-named (spec-arts "") "farm dog"))
             (spec-light (spec-arts "delve"))
             (spec-light (spec-arts ""))
             (eq? town (spec-arts "town"))))
```
---
    (#t 1 1 (255 196 118 5) (255 200 130 5) #t)

## blows

### a turn's blows are shown for eight frames: the target flashes, its damage written over it

```roguelike
(import roguelike/paint paint-animating? paint-step! paint-zoom!)
(import roguelike/state state-blow! state-clear-messages!)
(paint-zoom! p 2)
(def pl (game-player g))
(def m (game-map g))
(def at (frame-place (frame-camera (map-rows m) (map-cols m) (player-r pl) (player-c pl)) (player-r pl) (player-c pl)))
(def px (fn (_ s) (Canvas pixel s (+ 16 (* 2 (first at))) (+ 16 (+ paint-level-y (* 2 (- (rest at) frame-level-y)))))))
(state-clear-messages! g)
(paint-turn! p g fa)
(def calm (paint-animating? p))
(def plain (px (paint-frame! p g 0)))
(state-blow! g (player-r pl) (+ (player-c pl) 1) (player-r pl) (player-c pl) 'hit 3 ())
(paint-turn! p g fa)
(def struck (paint-animating? p))
(def flashed (px (paint-frame! p g 0)))
(def steps ((fn (self n) (if (paint-animating? p) (do (paint-step! p) (self (+ n 1))) n)) 0))
(write (list calm struck (not (equal? plain flashed)) steps (paint-animating? p)))
```
---
    (#f #t #t 8 #f)

## steps

### a thing that steps glides from the cell it left over five frames; a turn stood still shows nothing

```roguelike
(def g (spec-game-on (spec-set-named "delve") 3 ()))
(def m (game-map g))
(paint-turn! p g fa)
(def open (spec-open g))
(game-key! g (first open))
(state-clear-messages! g)
(paint-turn! p g fa)
(def stepping (paint-animating? p))
(def pl (game-player g))
(def at (frame-place (frame-camera (map-rows m) (map-cols m) (player-r pl) (player-c pl)) (player-r pl) (player-c pl)))
(def cell (fn (_ s) (List map (fn (_ d) (Canvas pixel s (+ (* 2 (first at)) d) (+ 16 (+ paint-level-y (* 2 (- (rest at) frame-level-y)))))) (List range 0 32))))
(def leaving (cell (paint-frame! p g 0)))
(def steps ((fn (self n) (if (paint-animating? p) (do (paint-step! p) (self (+ n 1))) n)) 0))
(def arrived (cell (paint-frame! p g 0)))
(game-key! g ".")
(state-clear-messages! g)
(paint-turn! p g fa)
(write (list stepping steps (not (equal? leaving arrived)) (paint-animating? p)))
```
---
    (#t 5 #t #f)

### a step shown with an item in view: the item's tile, which does not walk, stays put

```roguelike
(game-key! g (first (spec-open g)))
(state-clear-messages! g)
(paint-turn! p g fa)
(def s (Vector ref 3 p))
(def walker (List find (fn (_ op) (if (eq? (first op) 'tile) (< 5 (List length op)) #f)) (rest (rest s))))
(def item (List take 4 walker))
(Vector set! 3 (pair (first s) (pair (first (rest s)) (pair item (rest (rest s))))) p)
(write (list (paint-animating? p) (pair? (paint-frame! p g 0))))
```
---
    (#t #t)

## what flies

### a shot flies from the striker to its target for four frames, then lands as a blow does

```roguelike
(def g (spec-game-on (spec-set-named "delve") 3 ()))
(def m (game-map g))
(def pl (game-player g))
(paint-turn! p g fa)
(state-clear-messages! g)
(state-blow! g (player-r pl) (- (player-c pl) 4) (player-r pl) (player-c pl) 'hit 2 'shot)
(paint-turn! p g fa)
(def at (frame-place (frame-camera (map-rows m) (map-cols m) (player-r pl) (player-c pl)) (player-r pl) (player-c pl)))
; The middle row of the cells between, where the stone passes.
(def path (fn (_ s) (List map (fn (_ x) (Canvas pixel s x (+ 16 (+ paint-level-y (* 2 (- (rest at) frame-level-y)))))) (List range (* 2 (- (first at) 64)) (* 2 (first at))))))
(def flying (path (paint-frame! p g 0)))
(def steps ((fn (self n) (if (paint-animating? p) (do (paint-step! p) (self (+ n 1))) n)) 0))
(def after (path (paint-frame! p g 0)))
(write (list steps (not (equal? flying after))))
```
---
    (12 #t)
