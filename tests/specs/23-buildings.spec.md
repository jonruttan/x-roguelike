# Buildings
# @weight 2

roguelike/dungeon: a town level lays the buildings it names, (building
NAME (size W D) . PROPS), from their plans round its square, each
walled, its one door toward the square, and keeps them as the level's
named places; a building's door, stood on, says its (enter "TEXT").
The town set's districts each name theirs.


## the plans

### each of the town's districts lays every building it names, in order, walled, its one door in its wall, every door reached from the street

```roguelike
(def town (data-region (spec-set-named "kettle") "town"))
(def on-wall (fn (_ m p tile)
  (def r0 (List ref 1 p))
  (def c0 (List ref 2 p))
  (def r1 (List ref 3 p))
  (def c1 (List ref 4 p))
  (%spec-count m (fn (_ r c) (if (= (map-tile m r c) tile)
                               (if (if (< (- r0 1) r) (if (< r (+ r1 1)) (if (< (- c0 1) c) (< c (+ c1 1)) #f) #f) #f)
                                 (match ((= r r0) #t) ((= r r1) #t) ((= c c0) #t) (#t (= c c1)))
                                 #f)
                               #f)))))
(def whole? (fn (_ m p)
  (def side (fn (_ a b) (+ 1 (- (List ref b p) (List ref a p)))))
  (if (= 1 (on-wall m p tile-door)) (= (on-wall m p tile-wall) (- (* 2 (+ (side 1 3) (side 2 4))) 5)) #f)))
(def laid
  (fn (_ s)
    (def m (spec-level-on (List append (rest (rest s)) town) 3 0))
    (list (first s) (List map first (map-places m)) (List all? (fn (_ p) (whole? m p)) (map-places m)) (spec-connected? m))))
(write (List map laid (data-all town 'screen)))
```
---
    (("the Square" ("the council house" "the inn" "the pump-house") #t #t) ("the Pithead" ("the engine house" "the boiler house" "the smithy") #t #t) ("the River End" ("the mill" "the tannery" "the ropewalk") #t #t) ("the Terraces" ("the chapel" "the bakehouse") #t #t) ("Guild Street" ("the Guild hall" "the White Church" "the Guild's shop" "the chandler's") #t #t))

### a town that names no buildings is drawn as it was, with no places

```roguelike
(def plain '((level-style town) (square 30 12)))
(def built (pair '(building "the shed" (size 8 9)) plain))
(def m (spec-level-on plain 3 0))
(write (list (map-places m) (List map first (map-places (spec-level-on built 3 0)))))
```
---
    (() ("the shed"))

## the door

### a building's door, stood on, says the building's line; inside it is a floor

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(def m (game-map g))
(def inn (List find (fn (_ pl) (str=? (first pl) "the inn")) (map-places m)))
(import x/core/doors int/)
(def r (int/ (+ (List ref 1 inn) (List ref 3 inn)) 2))
(def c (List ref 4 inn))
(player-at! p r (+ c 1))
(game-key! g "h")
(def at-door (list (player-r p) (player-c p) (= (map-tile m r c) tile-door) (game-messages g)))
(game-key! g "h")
(write (list at-door (= (map-tile m (player-r p) (player-c p)) tile-floor) (first (map-place-at m (player-r p) (player-c p)))))
```
---
    ((14 15 #t ("The inn: carriers' talk, and stables for the packhorse trains.")) #t "the inn")

## kept

### a district's buildings are kept in a save and read back

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def before (map-places (game-map g)))
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "kettle") 24 80))
(File unlink path)
(write (list (List length before) (= (List length before) (List length (map-places (game-map h))))
             (List all? (fn (_ a) (List any? (fn (_ b) (if (str=? (first a) (first b)) (= (List ref 1 a) (List ref 1 b)) #f)) (map-places (game-map h)))) before)))
```
---
    (3 #t #t)
