# Town
# @weight 1

roguelike/dungeon's town, (level-style town): streets, a square and
buildings; and a band's forms in front of the set's for the levels in
it and their drawing, so that Kettle's square is a town and the valley
round it is not.


## the town

### a town: a street round the edge, the square clear in the middle, and rows of terraces, each house walls round a floor with one door onto the street

```roguelike
(def m (dungeon-generate (Random sw 5) 22 80 0 '((level-style town) (square 14 8))))
(def cells (fn (_ r0 c0 r1 c1) (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range c0 (+ c1 1)))) (List range r0 (+ r1 1)))))
(def tile (fn (_ p) (map-tile m (first p) (rest p))))
(def floor? (fn (_ ps) (List all? (fn (_ p) (= (tile p) tile-floor)) ps)))
(def doors (List filter (fn (_ p) (= (tile p) tile-door)) (cells 0 0 21 79)))
(def beside (fn (_ p) (List count-if (fn (_ d) (= (tile (pair (+ (first p) (first d)) (+ (rest p) (rest d)))) tile-floor))
                        (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1)))))
(write (list (floor? (List append (cells 0 0 0 79) (cells 21 0 21 79) (cells 0 0 21 0) (cells 0 79 21 79)))
             (floor? (cells 9 33 12 46))
             (< 10 (List length doors))
             (List all? (fn (_ p) (= (beside p) 2)) doors)
             (< (* 4 (List length doors)) (List count-if (fn (_ p) (= (tile p) tile-wall)) (cells 0 0 21 79)))
             (null? (map-rooms m)) (null? (map-down m))))
```
---
    (#t #t #t #t #t #t #t)

## a band's forms

### Kettle's square is a town, its houses with doors; the valley's hub round the town's door, and a screen out in the farms, are hedged fields

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def doors-at (fn (_ m) (List fold + 0 (List map (fn (_ r) (List count-if (fn (_ c) (= (map-tile m r c) tile-door)) (List range 0 80))) (List range 0 22)))))
(def square (list (band-name (game-band g)) (< 3 (doors-at (game-map g))) (data-get (game-forms g) 'level-style ())))
(def h (spec-game-on (spec-valley) 4 ()))
(def hub (list (band-name (game-band h)) (data-get (game-forms h) 'level-style ())))
(player-at! (game-player h) 11 79)
(game-key! h "l")
(write (list square hub (game-screen h) (band-name (game-band h)) (data-get (game-forms h) 'level-style ())))
```
---
    (("Kettle" #t 'town) ("Kettle" 'fields) (4 . 2) "The Farms" 'fields)
