# Shapes
# @weight 2

roguelike/map's kinds of terrain, each with what a creature can do on
it, and roguelike/dungeon's levels carved in the shape of where they
are: the Delve's pit, flooded reach, well-keepers' works and well-house,
and the valley's fields, hills and rim.  A level's terrain says what a
cell is; how it looks is the front-end's (see the last case).


## terrain

### deep water stops a step, a gate and bog bear one, and a hedge and a coal pillar are as solid as a wall

```roguelike
(write (List map map-passable? (list tile-water tile-gate tile-bog tile-hedge tile-pillar tile-dressed tile-floor)))
```
---
    (#f #t #t #f #f #f #t)

## the Delve

### a pit: a haulage road the length of the level, pillars of coal off it, the stairs at its ends, every bord walkable from the shaft

```roguelike
(def count (fn (_ m t) (%spec-count m (fn (_ r c) (= (map-tile m r c) t)))))
(def road? (fn (_ m) (List all? (fn (_ c) (if (map-walkable? m 10 c) (map-walkable? m 11 c) #f)) (List range 2 78))))
(write (List map (fn (_ seed)
                   (def m (spec-level-on '((level-style pit)) seed 2))
                   (list (spec-connected? m) (road? m) (< 30 (count m tile-pillar))
                         (List all? (fn (_ at) (if (< 9 (first at)) (< (first at) 12) #f)) (list (map-up m) (map-down m)))))
                 '(1 2 3)))
```
---
    ((#t #t #t #t) (#t #t #t #t) (#t #t #t #t))

### a flooded reach: a channel from the west edge to the east with deep water along it, the stairs up at the west end and down at the east, and a way along it dry enough to wade

```roguelike
(def count (fn (_ m t) (%spec-count m (fn (_ r c) (= (map-tile m r c) t)))))
(write (List map (fn (_ seed)
                   (def m (spec-level-on '((level-style flood)) seed 5))
                   (list (spec-connected? m) (rest (map-up m)) (rest (map-down m)) (< 20 (count m tile-water))))
                 '(1 2 3)))
```
---
    ((#t 2 77 #t) (#t 2 77 #t) (#t 2 77 #t))

### the well-keepers' works: a stair along the middle, vaults off it in pairs, each with its door facing the stair, all of dressed stone

```roguelike
(def count (fn (_ m t) (%spec-count m (fn (_ r c) (= (map-tile m r c) t)))))
(def doors (fn (_ m r) (List filter (fn (_ c) (= (map-tile m r c) tile-door)) (List range 0 80))))
(write (List map (fn (_ seed)
                   (def m (spec-level-on '((level-style works)) seed 8))
                   (list (spec-connected? m) (map-up m) (map-down m)
                         (< 3 (List length (doors m 10))) (equal? (doors m 10) (doors m 12))
                         (< 100 (count m tile-dressed)) (= 0 (count m tile-wall))))
                 '(1 2 3)))
```
---
    ((#t (11 . 2) (11 . 77) #t #t #t #t) (#t (11 . 2) (11 . 77) #t #t #t #t) (#t (11 . 2) (11 . 77) #t #t #t #t))

### the well-house: a cave round a walled court with a door in each side, the stone's pool in the court, and the way on beside the pool

```roguelike
(def count (fn (_ m t) (%spec-count m (fn (_ r c) (= (map-tile m r c) t)))))
(write (List map (fn (_ seed)
                   (def m (spec-level-on '((level-style well) (cave-fill 38)) seed 11))
                   (list (spec-connected? m) (count m tile-water) (count m tile-door) (first (map-down m))
                         (not (if (if (< 3 (first (map-up m))) (< (first (map-up m)) 17) #f) (if (< 22 (rest (map-up m))) (< (rest (map-up m)) 56) #f) #f))))
                 '(1 2 3)))
```
---
    ((#t 125 4 6 #t) (#t 125 4 6 #t) (#t 125 4 6 #t))

## the valley

### fields: a road along the middle row, hedged closes either side with gates, and every cell open to the edges

```roguelike
(def count (fn (_ m t) (%spec-count m (fn (_ r c) (= (map-tile m r c) t)))))
(def edge? (fn (_ m) (List all? (fn (_ c) (if (map-walkable? m 0 c) (map-walkable? m 21 c) #f)) (List range 0 80))))
(write (List map (fn (_ seed)
                   (def m (spec-level-on '((level-style fields)) seed 1))
                   (list (spec-connected? m) (edge? m) (List all? (fn (_ c) (map-walkable? m 11 c)) (List range 0 80))
                         (< 40 (+ (count m tile-hedge) (count m tile-thicket))) (< 2 (count m tile-gate)) (null? (map-down m))))
                 '(1 2 3)))
```
---
    ((#t #t #t #t #t #t) (#t #t #t #t #t #t) (#t #t #t #t #t #t))

### hills: gritstone edges across the heath, bog in the low ground, and every cell open to the edges

```roguelike
(def count (fn (_ m t) (%spec-count m (fn (_ r c) (= (map-tile m r c) t)))))
(def edge? (fn (_ m) (List all? (fn (_ c) (if (map-walkable? m 0 c) (map-walkable? m 21 c) #f)) (List range 0 80))))
(write (List map (fn (_ seed)
                   (def m (spec-level-on '((level-style hills)) seed 3))
                   (list (spec-connected? m) (edge? m) (< 10 (count m tile-edge)) (< 5 (count m tile-bog))))
                 '(1 2 3)))
```
---
    ((#t #t #t #t) (#t #t #t #t) (#t #t #t #t))

### the rim: limestone scars and the well-keepers' fallen walls, and every cell open to the edges

```roguelike
(def count (fn (_ m t) (%spec-count m (fn (_ r c) (= (map-tile m r c) t)))))
(def edge? (fn (_ m) (List all? (fn (_ c) (if (map-walkable? m 0 c) (map-walkable? m 21 c) #f)) (List range 0 80))))
(write (List map (fn (_ seed)
                   (def m (spec-level-on '((level-style rim)) seed 5))
                   (list (spec-connected? m) (edge? m) (< 10 (count m tile-scar)) (< 10 (count m tile-dressed))))
                 '(1 2 3)))
```
---
    ((#t #t #t #t) (#t #t #t #t) (#t #t #t #t))

## the look

### the terminal draws a kind of terrain by the set's glyph for it, or its own: a step off the valley's hub onto the farms' road shows the hedges either side

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(player-at! (game-player g) 11 79)
(game-key! g "l")
(def row (spec-row g 11))
(write (list (band-name (game-band g)) (data-get (game-forms g) 'level-style ())
             (List any? (fn (_ c) (str=? (Str8 sub c 1 row) (bytes->str (list 34)))) (List range 2 9))))
```
---
    ("The Farms" 'fields #t)
