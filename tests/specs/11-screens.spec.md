# A world of screens
# @weight 1

roguelike/game on the kettle set: a world of screens, (world screens
W H), joined at their edges and kept, open ground, the map of the
world, and the win at the hub.  The classic and delve sets are
descents, and their specs stand.


## the set

### the kettle set loads: seven by five screens, open ground, a goal with no level, hunger as a store, four bands from the square

```roguelike
(def set (spec-set-named "kettle"))
(def world (data-one set 'world ()))
(write (list (data-get set 'set "") (first world) (List ref 1 world) (List ref 2 world) (data-get set 'level-style 'rooms)
             (List length (data-one set 'goal ())) (data-get set 'hunger 1) (List length (data-all set 'creature))
             (List map (fn (_ b) (List ref 1 b)) (data-all set 'band))))
```
---
    ("kettle" 'screens 7 5 'open 2 1200 28 (0 1 3 5))

## open ground

### no rooms and no stairs, the outer ring floor, most of it floor with some wall, and every cell reachable

```roguelike
(def set (spec-set-named "kettle"))
(def m (spec-level-on set 4 1))
(def count (fn (_ t) (List fold (fn (_ a b) (+ a b)) 0 (List map (fn (_ r) (List count-if (fn (_ c) (= (map-tile m r c) t)) (List range 0 80))) (List range 0 22)))))
(def floor (count tile-floor))
(def ring? (List all? (fn (_ p) (= (map-tile m (first p) (rest p)) tile-floor))
             (List append (List map (fn (_ c) (pair 0 c)) (List range 0 80)) (List map (fn (_ c) (pair 21 c)) (List range 0 80))
                          (List map (fn (_ r) (pair r 0)) (List range 0 22)) (List map (fn (_ r) (pair r 79)) (List range 0 22)))))
(write (list (map-rooms m) (map-down m) (map-up m) ring? (< (* 22 80 60) (* 100 floor)) (< (* 100 floor) (* 22 80 98)) (< 0 (count tile-wall))
             (List all? (fn (_ ok) ok) (List map (fn (_ seed) ((fn (_ v) (Heap collect) v) (spec-connected? (spec-level-on set seed 1)))) (List range 1 11)))))
```
---
    (() () () #t #t #t #t #t)

## the hub

### a new game starts on the hub screen, in its middle, at depth 0, nobody about but the chain's giver, and says so

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(write (list (first (game-screen g)) (rest (game-screen g)) (first (game-hub g)) (rest (game-hub g)) (game-depth g) (List map creature-name (game-creatures g))
             (player-r p) (< (state-dist 11 40 (player-r p) (player-c p)) 10) (game-messages g) (List ref 23 (spec-screen g))))
```
---
    (3 2 3 2 0 ("Guild clerk") 11 #t ("Kettle's square, by the well-head.  Someone here knows where the Guild's ledger is; ask about.") "Screen:3,2  Gold:0  Hp:14(14)  Str:16(16)  Arm:0  Exp:1/0")

## the edges

### a step off the east edge is a step onto the next screen, landing on its west edge in the same row, a turn

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(player-at! p 11 79)
(game-key! g "l")
(write (list (first (game-screen g)) (rest (game-screen g)) (game-depth g) (game-deepest g) (player-r p) (player-c p) (game-turn g)
             (List length (game-kept g)) (List ref 23 (spec-screen g))))
```
---
    (4 2 1 1 11 0 1 2 "Screen:4,2  Gold:0  Hp:14(14)  Str:16(16)  Arm:0  Exp:1/0")

### at the valley's edge the step goes nowhere, says so, and takes no turn

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(player-at! p 0 40)
(game-key! g "k")
(game-creatures! g ())
(spec-settle! g)
(player-at! p 0 40)
(game-key! g "k")
(game-creatures! g ())
(spec-settle! g)
(def at (list (first (game-screen g)) (rest (game-screen g)) (game-depth g)))
(player-at! p 0 40)
(def turns (game-turn g))
(game-key! g "k")
(write (list at (first (game-screen g)) (rest (game-screen g)) (game-messages g) (= turns (game-turn g)) (player-r p) (player-c p)))
```
---
    ((3 0 2) 3 0 ("The valley ends here.") #t 0 40)

### a screen is kept: what was dropped there is there on return, and what was seen stays seen

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(spec-drop-here! g "hatchet")
(def m (game-map g))
(def seen (spec-count-seen m))
(player-at! p 11 79)
(game-key! g "l")
(game-creatures! g ())
(def away (same? m (game-map g)))
(player-at! p 11 0)
(game-key! g "h")
(write (list away (same? m (game-map g)) (List any? (fn (_ it) (str=? (item-name it) "hatchet")) (game-floor g))
             (not (< (spec-count-seen (game-map g)) seen)) (first (game-screen g)) (rest (game-screen g)) (player-c p)
             (List length (game-kept g))))
```
---
    (#f #t #t #t 3 2 79 2)

### m lays the map of the world over the screen, @ where you stand and . where you have been; a descent has none

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(player-at! p 11 79)
(game-key! g "l")
(game-key! g "m")
(def rows (spec-screen g))
(def d (spec-game 11 (list "m")))
(write (list (List ref 0 rows) (List ref 1 rows) (List ref 2 rows) (List ref 3 rows) (List ref 4 rows) (game-turn g)
             (game-messages d) (game-turn d)))
```
---
    ("The valley:  --any key--" "" "" "       . @" "" 1 ("You know only the level you stand on.") 0)

## the goal

### a goal with no level lies on no screen, however far out: it is someone's to give

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def goal? (fn (_) (List any? (fn (_ it) (eq? (item-class it) 'goal)) (game-floor g))))
(def go! (fn (_ r c key) (game-creatures! g ()) (player-at! p r c) (game-key! g key) (spec-settle! g)))
(go! 11 79 "l")
(go! 11 79 "l")
(go! 11 79 "l")
(def three (list (game-depth g) (goal?)))
(go! 0 40 "k")
(def four (list (game-depth g) (goal?)))
(go! 11 0 "h")
(go! 0 40 "k")
(write (list three four (game-depth g) (goal?)))
```
---
    ((3 #f) (4 #f) 4 #f)

### the goal brought back to the square is the win; brought elsewhere, it is not

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(def goal (item-make (list 'goal "the Guild ledger") 1 0))
(item-letter! goal "a")
(game-pack! g (pair goal (game-pack g)))
(player-at! p 11 79)
(game-key! g "l")
(def not-yet (game-over g))
(game-creatures! g ())
(player-at! p 11 0)
(game-key! g "h")
(write (list not-yet (game-over g) (game-messages g)))
```
---
    (() 'won ("You lay the ledger on the well-head.  Kettle has its proof, and the Guild has lost its mine."))

## saving

### a save keeps every screen visited and where you stand, and comes back the same

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(spec-drop-here! g "hatchet")
(player-at! p 11 79)
(game-key! g "l")
(game-creatures! g ())
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "kettle") 24 80))
(File unlink path)
(def q (game-player h))
(def hub (game-kept-level h "3,2"))
(def same-at? (fn (_ a b) (if (null? a) (null? b) (if (null? b) #f (if (= (first a) (first b)) (= (rest a) (rest b)) #f)))))
(write (list (not (null? h)) (first (game-screen h)) (rest (game-screen h)) (game-depth h) (player-r q) (player-c q)
             (List length (game-kept h)) (List any? (fn (_ it) (str=? (item-name it) "hatchet")) (List ref 2 hub))
             (= (spec-count-seen (List ref 0 hub)) (spec-count-seen (List ref 0 (game-kept-level g "3,2"))))
             (same? (game-map h) (List ref 0 (game-kept-level h "4,2"))) (same-at? (map-down (game-map h)) (map-down (game-map g))) (game-messages h)))
```
---
    (#t 4 2 1 11 0 2 #t #t #t #t ("Welcome back."))

## random play

### two games of a thousand keys raise nothing and keep every invariant

```roguelike
(def runs (List map (fn (_ seed) (spec-random-play (spec-set-named "kettle") seed 1000)) (List range 1 3)))
(write (list (List filter (fn (_ r) (not (null? (List ref 4 r)))) runs)
             (< 40 (List fold (fn (_ a r) (+ a (List ref 2 r))) 0 runs))))
```
---
    (() #t)
