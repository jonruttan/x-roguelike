# The delve set
# @weight 1

What the delve set turns on: caves, sight to a radius, packs, ranged
and summoning creatures, auto-explore, the log, no hunger, potions and
scrolls known on sight, bands with their guardians, and pages.  The
classic set leaves every one of them off, and its specs stand.


## the set

### the delve set loads: twelve levels in four bands, sight to seven, no hunger

```roguelike
(def set (spec-set-named "delve"))
(write (list (data-get set 'set "") (List ref 2 (data-one set 'goal ())) (data-get set 'view 0) (data-get set 'hunger 1)
             (data-get set 'level-style 'rooms) (List length (data-all set 'creature))
             (List map (fn (_ b) (List ref 1 b)) (data-all set 'band)) (List length (data-all set 'page))))
```
---
    ("delve" 12 7 0 'caves 20 (3 6 9 12) 9)

## bands

### a new game says its band; the next band says its word on its first level, and no other

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def first-said (game-messages g))
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">")))
(down!)
(def second (game-messages g))
(down!)
(game-creatures! g ())
(down!)
(write (list first-said second (game-depth g) (List reverse (List take 2 (game-log g)))))
```
---
    (("You enter the Delve.  The Lodestar lies twelve levels down; bring it back up." "The Galleries: the worked mine, propped and railed, its lamps long out.") ("You climb down to level 2.") 4 ("You climb down to level 4." "The Flood: the water stands here, and runs one way."))

### the band's guardian waits by the shaft down on its last level, and bars it while it lives; barred takes no turn

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">")))
(down!)
(def none (List any? (fn (_ cr) (str=? (creature-name cr) "pit foreman")) (game-creatures g)))
(down!)
(def guardian (List find (fn (_ cr) (str=? (creature-name cr) "pit foreman")) (game-creatures g)))
(def m (game-map g))
(def near? (< (state-dist (creature-r guardian) (creature-c guardian) (first (map-down m)) (rest (map-down m))) 2))
(def turn (game-turn g))
(down!)
(def barred (game-messages g))
(def still (list (game-depth g) (= turn (game-turn g))))
(game-creatures! g (List reject (fn (_ cr) (same? cr guardian)) (game-creatures g)))
(down!)
(write (list none near? barred still (game-depth g)))
```
---
    (#f #t ("The pit foreman stands over the shaft down.") (3 #t) 4)

## pages

### the first page lies on level 1, once

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def pages (List filter (fn (_ it) (eq? (item-class it) 'page)) (game-floor g)))
(write (list (List length pages) (item-name (first pages)) (game-pages-placed g)))
```
---
    (1 "the foreman's log, first leaf" ("the foreman's log, first leaf"))

### r reads a page: its lines lie over the level until a key, it takes a turn, and the page is kept

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(def it (item-make (list 'page "a scrap" (list 'text "one line" "two line")) 1 0))
(item-at! it (player-r p) (player-c p))
(game-floor! g (pair it (game-floor g)))
(game-key! g ",")
(game-key! g "r")
(game-key! g "a")
(write (list (spec-row g 0) (Str8 starts? " one line" (spec-row g 1)) (Str8 starts? " two line" (spec-row g 2)) (game-turn g)
             (List length (game-pack g)) (null? (game-ask (spec-game-on (spec-set-named "delve") 4 (list "r"))))))
```
---
    ("a scrap  --any key--" #t #t 2 1 #t)

### a page in the pack and the pages placed come back from a save

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(def page (List find (fn (_ it) (eq? (item-class it) 'page)) (game-floor g)))
(item-at! page (player-r p) (player-c p))
(game-key! g ",")
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "delve") 24 80))
(File unlink path)
(def kept (first (game-pack h)))
(write (list (item-class kept) (item-name kept) (item-letter kept) (game-pages-placed h)))
```
---
    ('page "the foreman's log, first leaf" "a" ("the foreman's log, first leaf"))

## caves

### a cave has no rooms, stairs on floor apart, a third or more of it floor, and every cell reachable

```roguelike
(def set (spec-set-named "delve"))
(def m (spec-level-on set 4 1))
(def open (spec-count-open m))
(def floor (List fold (fn (_ a b) (+ a b)) 0 (List map (fn (_ r) (List count-if (fn (_ c) (= (map-tile m r c) tile-floor)) (List range 0 80))) (List range 0 22))))
(write (list (map-rooms m) (map-tile m (first (map-down m)) (rest (map-down m))) (map-tile m (first (map-up m)) (rest (map-up m)))
             (< 20 (state-dist (first (map-up m)) (rest (map-up m)) (first (map-down m)) (rest (map-down m))))
             (< (* 22 80 30) (* 100 floor)) (< (* 100 floor) (* 22 80 50))
             (List all? (fn (_ ok) ok) (List map (fn (_ seed) ((fn (_ v) (Heap collect) v) (spec-connected? (spec-level-on set seed 1)))) (List range 1 11)))))
```
---
    (() 5 6 #t #t #t #t)

## sight

### light to a radius stops at a wall: the wall is seen, what lies past it is not

```roguelike
(def m (spec-level 7 1))
(def room (first (map-rooms m)))
(def at (room-centre room))
(map-light-radius! m (first at) (rest at) 12)
(def c (rest at))
(write (list (map-visible? m (room-r0 room) c) (map-visible? m (- (room-r0 room) 1) c)
             (map-visible? m (first at) (room-c1 room)) (map-visible? m (first at) (+ (room-c1 room) 1))
             (map-seen? m (room-r0 room) c)))
```
---
    (#t #f #t #f #t)

### a delve game sees by sight: nothing past seven cells is in view

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(def m (game-map g))
(def far (Vector of 0))
(List for-each (fn (_ r) (List for-each (fn (_ c) (when (if (map-visible? m r c) (< 7 (state-dist r c (player-r p) (player-c p))) #f) (Vector set! 0 (+ 1 (Vector ref 0 far)) far))) (List range 0 80))) (List range 0 22))
(write (list (Vector ref 0 far) (map-visible? m (player-r p) (player-c p)) (< 0 (spec-count-seen m))))
```
---
    (0 #t #t)

## creatures

### a pack is placed together

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def open (spec-open g))
(creatures-place! g (spec-creature g "mine rat") (first (rest open)) (rest (rest open)) 'asleep)
(def n (List length (game-creatures g)))
(write (list (< 1 n) (< n 5) (List all? (fn (_ cr) (str=? (creature-name cr) "mine rat")) (game-creatures g))
             (List all? (fn (_ cr) (< (state-dist (creature-r cr) (creature-c cr) (first (rest open)) (rest (rest open))) 2)) (game-creatures g))))
```
---
    (#t #t #t #t)

### a ranged creature in line lets fly

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def line (if (null? (spec-open-line g 3)) (spec-open-line g 2) (spec-open-line g 3)))
(def cr (spec-place! g "sling imp" (first (rest line)) (rest (rest line)) 100 'awake))
(creature-state! cr 'fleeing)
(def shot? (fn (_) (List any? (fn (_ m) (str=? m "The sling imp shoots a stone at you!")) (game-log g))))
(spec-press-until g "." shot? 80)
(write (list (not (null? line)) (shot?) (< (player-hp (game-player g)) 14)))
```
---
    (#t #t #t)

### a summoner calls company while in view

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def open (spec-open g))
(spec-place! g "ossuary priest" (first (rest open)) (rest (rest open)) 1000 'awake)
(player-hp! (game-player g) 1000)
(spec-press-until g "." (fn (_) (< 1 (List length (game-creatures g)))) 100)
(write (list (< 1 (List length (game-creatures g))) (List any? (fn (_ cr) (str=? (creature-name cr) "bone husk")) (game-creatures g))
             (List any? (fn (_ m) (Str8 starts? "The ossuary priest calls" m)) (game-log g))))
```
---
    (#t #t #t)

## exploring and the log

### o walks toward what is unseen until something comes into view, or nothing is left

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(def before (pair (player-r p) (player-c p)))
(def seen (spec-count-seen (game-map g)))
(game-key! g "o")
(def moved (not (if (= (first before) (player-r p)) (= (rest before) (player-c p)) #f)))
(write (list moved (< 0 (game-turn g)) (< seen (spec-count-seen (game-map g)))))
```
---
    (#t #t #t)

### L shows what was said lately, and takes no turn

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 (list "." "L")))
(write (list (spec-row g 0) (Str8 starts? " You enter the Delve." (spec-row g 1)) (game-turn g)))
```
---
    ("Lately:  --any key--" #t 1)

## no hunger, known on sight

### food never counts down and the standing never says so

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(List for-each (fn (_ k) (game-key! g k)) (List map (fn (_ n) ".") (List range 0 30)))
(write (list (player-food (game-player g)) (game-turn g) (Str8 includes? "Fainting" (spec-row g 23))))
```
---
    (0 30 #f)

### a potion is named before it is tried; a wand is not

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def potion (spec-drop-here! g "mending"))
(def wand (spec-drop-here! g "sparks"))
(write (list (items-known? g potion) (items-name g potion) (items-known? g wand) (Str8 ends? " wand" (items-name g wand))))
```
---
    (#t "a potion of mending" #f #t)
