# Scale
# @weight 2

roguelike/scale: a level is drawn at a scale, (scale N), each cell N
metres across and the next number of the Fibonacci sequence down, and
every size a level style takes is in metres, coming out in cells at
the level's scale.


## the ladder

### a scale is a number of the Fibonacci sequence, its cell that many metres across and the next number down; any other number is not a scale

```roguelike
(write (List map scale-rung '(1 2 3 5 8 13 21 34 4 6 0)))
```
---
    ((1 . 2) (2 . 3) (3 . 5) (5 . 8) (8 . 13) (13 . 21) (21 . 34) (34 . 55) #f #f #f)

### metres come out in cells across, down and of ground covered, to the nearest, never less than a cell

```roguelike
(def rung (fn (_ n) (scale-rung n)))
(write (list (scale-across (rung 1) 7) (scale-down (rung 1) 7) (scale-across (rung 5) 12) (scale-down (rung 5) 12)
             (scale-across (rung 21) 3) (scale-area (rung 1) 48) (scale-area (rung 2) 48)))
```
---
    (7 4 2 2 1 24 8)

### a set naming a scale off the ladder is refused when a game is made, a band's as much as the set's

```roguelike
(def made? (fn (_ set) (guard (e (lit refused)) (do (game-make set 1 24 80) (lit made)))))
(write (list (made? (pair '(scale 1) (spec-set))) (made? (pair '(scale 4) (spec-set)))
             (made? (pair '(band "Here" 0 (scale 7)) (spec-set)))))
```
---
    ('made 'refused 'refused)

## levels at a scale

### at 1 every style but the fields draws the very level it drew when its sizes were cells; the fields differ where a hedge closed a gate

```roguelike
(def fingerprint
  (fn (_ m)
    ((fn (self r c h) (match ((= r 22) h) ((= c 80) (self (+ r 1) 0 h)) (#t (self r (+ c 1) (% (+ (* h 31) (map-tile m r c)) 1000003))))) 0 0 0)))
(write (List map (fn (_ style) (fingerprint (spec-level-on (list (list (lit level-style) style)) 4 3)))
                 '(rooms caves open town pit flood works well fields hills rim)))
```
---
    (643903 639372 693083 415496 476974 50345 192723 172364 365536 816843 922674)

### a hedge laid across a close stops short of a gate it would close, so every close can be walked to

```roguelike
(write (List map (fn (_ seed) (spec-connected? (spec-level-on '((level-style fields)) seed 3))) '(1 2 3 4 5 6)))
```
---
    (#t #t #t #t #t #t)

### at a scale where a house is a cell or two, the town draws its terraces solid, a door to each house, and lays several times the houses

```roguelike
(def doors (fn (_ m) (%spec-count m (fn (_ r c) (= (map-tile m r c) tile-door)))))
(write (List map (fn (_ seed)
                   (def one (spec-level-on '((level-style town) (terrace-length 60 150)) seed 0))
                   (def five (spec-level-on '((level-style town) (terrace-length 60 150) (scale 5)) seed 0))
                   (list (< (* 3 (doors one)) (doors five)) (spec-connected? five)))
                 '(1 2 3)))
```
---
    ((#t #t) (#t #t) (#t #t))

### every style draws at every scale up to the valley's without raising, its ground walkable throughout

```roguelike
(write (List map (fn (_ style)
                   (List map (fn (_ n) (spec-connected? (spec-level-on (list (list (lit level-style) style) (list (lit scale) n)) 2 3)))
                             '(2 5 21)))
                 '(rooms caves open town pit flood works well fields hills rim)))
```
---
    ((#t #t #t) (#t #t #t) (#t #t #t) (#t #t #t) (#t #t #t) (#t #t #t) (#t #t #t) (#t #t #t) (#t #t #t) (#t #t #t) (#t #t #t))
