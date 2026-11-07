# Interiors
# @weight 1

roguelike/interiors and roguelike/game on the kettle set: the places
behind doors in a world of screens.  Most cases put a shed in front of
the set's own interiors, at every depth but the hub's and a chance of
a hundred, so a screen of the first ring always has a door.


## the set

### the kettle set has three interiors, one for each ring of bands, each made its own way, and the pit on the square, which goes below

```roguelike
(def set (spec-set-named "kettle"))
(def prop (fn (_ f key) (def p (Assoc find key (rest f))) (if (null? p) () (rest p))))
(def made (fn (_ f) (if (null? (prop f 'below)) (first (prop f 'level-style)) (pair 'below (prop f 'below)))))
(write (List map (fn (_ f) (list (first f) (prop f 'depth) (made f))) (data-all set 'interior)))
```
---
    (("farmhouse cellar" (1 2) 'rooms) ("shepherd's bothy" (3 3) 'rooms) ("old city vault" (4 5) 'works) ("pit" (0 0) ('below "delve")))

## doors

### a screen of the first ring lays a door off its outer ring when an interior covers it; the hub lays only the pit's

```roguelike
(def set (pair '(interior "shed" (depth 1 9) (chance 100) (rooms 1 1) (creatures 0 0) (items 0 0) (enter "A shed.")) (spec-set-named "kettle")))
(def g (spec-game-on set 4 ()))
(def p (game-player g))
(def hub (list (not (null? (map-down (game-map g)))) (game-door g "3,2")))
(game-creatures! g ())
(player-at! p 11 79)
(game-key! g "l")
(spec-settle! g)
(def door (map-down (game-map g)))
(write (list hub (not (null? door)) (= (map-tile (game-map g) (first door) (rest door)) tile-down) (game-door g "4,2")
             (< 0 (first door)) (< (first door) 21) (< 0 (rest door)) (< (rest door) 79)))
```
---
    ((#t "pit") #t #t "shed" #t #t #t #t)

### a step onto the door says where it goes

```roguelike
(def set (pair '(interior "shed" (depth 1 9) (chance 100) (rooms 1 1) (creatures 0 0) (items 0 0) (enter "A shed.")) (spec-set-named "kettle")))
(def g (spec-game-on set 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-at! p 11 79)
(game-key! g "l")
(spec-settle! g)
(game-creatures! g ())
(def door (map-down (game-map g)))
(def d (List find (fn (_ d) (= (map-tile (game-map g) (+ (first door) (first (rest d))) (+ (rest door) (rest (rest d)))) tile-floor))
         (list (pair "j" (pair -1 0)) (pair "k" (pair 1 0)) (pair "l" (pair 0 -1)) (pair "h" (pair 0 1)))))
(player-at! p (+ (first door) (first (rest d))) (+ (rest door) (rest (rest d))))
(game-key! g (first d))
(write (list (= (player-r p) (first door)) (= (player-c p) (rest door)) (game-messages g)))
```
---
    (#t #t ("There is a way into the shed here."))

### > on the door goes in: the interior's own level, made by its forms, with a way out and no way on, and what it says the first time

```roguelike
(def set (pair '(interior "shed" (depth 1 9) (chance 100) (rooms 1 1) (creatures 0 0) (items 0 0) (enter "A shed.")) (spec-set-named "kettle")))
(def g (spec-game-on set 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-at! p 11 79)
(game-key! g "l")
(spec-settle! g)
(game-creatures! g ())
(def screen (game-map g))
(def door (map-down screen))
(player-at! p (first door) (rest door))
(game-key! g ">")
(def m (game-map g))
(write (list (game-inside g) (same? m screen) (map-down m) (= (player-r p) (first (map-up m))) (= (player-c p) (rest (map-up m)))
             (List length (map-rooms m)) (List filter (fn (_ x) (if (str=? x "You go into the shed.") #t (str=? x "A shed."))) (List reverse (List take 5 (game-log g))))
             (game-level-key g) (List length (game-kept g))
             (Str8 starts? "Screen:4,2 " (List ref 23 (spec-screen g)))))
```
---
    ("shed" #f () #t #t 1 ("You go into the shed." "A shed.") "4,2>" 3 #t)

### < on the way out comes out on the door, the screen as it was left; in again, the interior as it was left

```roguelike
(def set (pair '(interior "shed" (depth 1 9) (chance 100) (rooms 1 1) (creatures 0 0) (items 0 0) (enter "A shed.")) (spec-set-named "kettle")))
(def g (spec-game-on set 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-at! p 11 79)
(game-key! g "l")
(spec-settle! g)
(game-creatures! g ())
(def screen (game-map g))
(def door (map-down screen))
(player-at! p (first door) (rest door))
(game-key! g ">")
(spec-settle! g)
(game-creatures! g ())
(def inside (game-map g))
(game-key! g "<")
(def out (list (game-inside g) (same? (game-map g) screen) (= (player-r p) (first door)) (= (player-c p) (rest door)) (game-messages g)))
(game-creatures! g ())
(game-key! g ">")
(write (list out (same? (game-map g) inside) (game-inside g) (game-messages g)))
```
---
    ((() #t #t #t ("You come out of the shed.")) #t "shed" ("You go into the shed."))

### > finds no stairs on a screen with no door, and no way further in inside

```roguelike
(def set (pair '(interior "shed" (depth 1 9) (chance 100) (rooms 1 1) (creatures 0 0) (items 0 0) (enter "A shed.")) (spec-set-named "kettle")))
(def g (spec-game-on set 4 ()))
(def p (game-player g))
(game-creatures! g ())
(game-key! g ">")
(def hub (game-messages g))
(player-at! p 11 79)
(game-key! g "l")
(spec-settle! g)
(game-creatures! g ())
(def door (map-down (game-map g)))
(player-at! p (first door) (rest door))
(game-key! g ">")
(spec-settle! g)
(game-creatures! g ())
(game-key! g ">")
(write (list hub (game-messages g) (first (game-screen g)) (rest (game-screen g)) (game-inside g)))
```
---
    (("There are no stairs in the open air.") ("There is no way further in.") 4 2 "shed")

## saving

### a save inside an interior comes back inside, the screen and the interior both kept and the door known

```roguelike
(def set (pair '(interior "shed" (depth 1 9) (chance 100) (rooms 1 1) (creatures 0 0) (items 0 0) (enter "A shed.")) (spec-set-named "kettle")))
(def g (spec-game-on set 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-at! p 11 79)
(game-key! g "l")
(spec-settle! g)
(game-creatures! g ())
(def door (map-down (game-map g)))
(player-at! p (first door) (rest door))
(game-key! g ">")
(spec-settle! g)
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path set 24 80))
(File unlink path)
(def screen (game-kept-level h "4,2"))
(write (list (game-inside h) (game-level-key h) (List length (game-kept h)) (game-door h "4,2") (map-down (game-map h))
             (= (first (map-down (List ref 0 screen))) (first door)) (= (rest (map-down (List ref 0 screen))) (rest door))
             (same? (game-map h) (List ref 0 (game-kept-level h "4,2>")))))
```
---
    ("shed" "4,2>" 3 "shed" () #t #t #t)

## the kettle set's own

### the farmhouse cellar is the only door the first ring lays, and over six seeds it lays some

```roguelike
(def set (spec-set-named "kettle"))
(def door-east
  (fn (_ seed)
    (def g (spec-game-on set seed ()))
    (game-creatures! g ())
    (player-at! (game-player g) 11 79)
    (game-key! g "l")
    (Heap collect)
    (game-door g "4,2")))
(def names (List reject null? (List map door-east (List range 1 7))))
(write (list (List distinct names) (< 0 (List length names))))
```
---
    (("farmhouse cellar") #t)

## random play

### a game of a thousand keys among doors raises nothing and keeps every invariant

```roguelike
(def set (pair '(interior "shed" (depth 1 9) (chance 100) (rooms 1 2) (creatures 0 1) (items 0 1)) (spec-set-named "kettle")))
(def runs (List map (fn (_ seed) (spec-random-play set seed 1000)) (List range 3 4)))
(write (list (List filter (fn (_ r) (not (null? (List ref 4 r)))) runs)
             (< 10 (List fold (fn (_ a r) (+ a (List ref 2 r))) 0 runs))))
```
---
    (() #t)
