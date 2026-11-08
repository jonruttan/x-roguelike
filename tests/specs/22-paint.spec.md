# The frame drawn
# @weight 1

The level's pictures drawn onto the screen (see `docs/graphics.md`):
the art decoded once, the level into a layer of its own each turn, and
each frame that layer, what stands on it, the light and the text.


## the art

### every tile with rows has its picture; one drawn as another takes that one's

```roguelike
(import roguelike/paint paint-art paint-font paint-make paint-screen paint-turn! paint-frame! paint-flickers? paint-width paint-height)
(import roguelike/frame frame-art frame-camera frame-place frame-tile-size)
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

### the font: a letter's cell eight wide

```roguelike
(def spec-font (paint-font "art"))
(write (List ref 2 spec-font))
```
---
    8


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
             (lit? (Canvas pixel s (+ 8 (first at)) (+ 8 (rest at))))
             (Canvas pixel s 0 0)
             (List any? (fn (_ x) (lit? (Canvas pixel s x 343))) (List range 0 80))
             (paint-flickers? p)))
```
---
    (640 360 #t (0 0 0 255) #t #t)

### the pack looked at lies over the level on the panel, its lines written

```roguelike
(import roguelike/draw draw-overlay)
(def before (Canvas pixel s 4 28))
(game-key! g "i")
(paint-turn! p g fa)
(def s (paint-frame! p g 0))
(def ink? (fn (_ y) (List any? (fn (_ x) (= 206 (first (Canvas pixel s x y)))) (List range 8 200))))
(write (list (List length (draw-overlay g)) (equal? before (Canvas pixel s 4 28)) (List any? ink? (List range 32 40))))
```
---
    (1 #f #t)
