# The delve set
# @weight 1

What the delve set turns on: caves, sight to a radius, packs, ranged
and summoning creatures, auto-explore, the log, potions and scrolls
known on sight, bands with their guardians, and pages.  The classic
set leaves every one of them off, and its specs stand.  What it turns
on in play -- hunger as a store, gear that asks strength, traps, the
blow on a sleeper -- is in 10-elements.


## the set

### the delve set loads: twelve levels in four bands, sight to seven, a store of food

```roguelike
(def set (spec-set-named "delve"))
(write (list (data-get set 'set "") (List ref 2 (data-one set 'goal ())) (data-get set 'view 0) (data-get set 'hunger 1)
             (data-get set 'level-style 'rooms) (List length (data-all set 'creature))
             (List map (fn (_ b) (List ref 1 b)) (data-all set 'band)) (List length (data-all set 'page))))
```
---
    ("delve" 12 7 43200 'caves 24 (3 6 9 12) 9)

## bands

### a new game says its band; the next band says its word on its first level, and no other

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def first-said (game-messages g))
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (spec-settle! g)))
(def bands (list "The Galleries:" "The Flood:" "The Old Works:" "The Heart:"))
(def said (fn (_ m) (if (Str8 starts? "You climb" m) #t (List any? (fn (_ b) (Str8 starts? b m)) bands))))
(down!)
(def second (List filter said (game-messages g)))
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
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (spec-settle! g)))
(down!)
(def none (List any? (fn (_ cr) (str=? (creature-name cr) "fireman")) (game-creatures g)))
(down!)
(def guardian (List find (fn (_ cr) (str=? (creature-name cr) "fireman")) (game-creatures g)))
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
    (#f #t ("The fireman stands over the shaft down.") (3 #t) 4)

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
    ("a scrap  --Enter--" #t #t 2 1 #t)

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

### standing water rises with the depth: none above level 4, more each level below, only ever over floor

```roguelike
(def set (spec-set-named "delve"))
(def tally
  (fn (_ depth)
    (def m (spec-level-on set 3 depth))
    (def count (fn (_ t) (List fold (fn (_ a b) (+ a b)) 0 (List map (fn (_ r) (List count-if (fn (_ c) (= (map-tile m r c) t)) (List range 0 (map-cols m)))) (List range 0 (map-rows m))))))
    (def v (list (count tile-shallow) (+ (count tile-floor) (count tile-shallow))))
    (Heap collect)
    v))
(def ts (List map tally (list 3 5 8 12)))
(import x/core/doors int/)
(def share (fn (_ t) (int/ (* 100 (first t)) (List ref 1 t))))
(write (list (first (first ts)) (List map (fn (_ t) (< (share t) 51)) ts)
             (< 0 (share (List ref 1 ts))) (< (share (List ref 1 ts)) (share (List ref 2 ts))) (< (share (List ref 2 ts)) (share (List ref 3 ts)))))
```
---
    (0 (#t #t #t #t) #t #t #t)


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

### a wall opened is seen through from the same place, at the next light

```roguelike
(import roguelike/map map-set!)
(def m (spec-level 7 1))
(def room (first (map-rooms m)))
(def at (room-centre room))
(def r (first at))
(def past (fn (_) (map-light-radius! m r (rest at) 12) (map-visible? m r (+ (room-c1 room) 1))))
(def shut (past))
(map-set! m r (room-c1 room) tile-floor)
(write (list shut (past) (past)))
```
---
    (#f #t #t)

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

### below the first level, a pack is placed together

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(player-at! (game-player g) (first (map-down (game-map g))) (rest (map-down (game-map g))))
(game-key! g ">") (spec-settle! g)
(game-creatures! g ())
(def open (spec-open g))
(creatures-place! g (spec-creature g "pit ferret") (first (rest open)) (rest (rest open)) 'asleep)
(def n (List length (game-creatures g)))
(write (list (< 1 n) (< n 5) (List all? (fn (_ cr) (str=? (creature-name cr) "pit ferret")) (game-creatures g))
             (List all? (fn (_ cr) (< (state-dist (creature-r cr) (creature-c cr) (first (rest open)) (rest (rest open))) 2)) (game-creatures g))))
```
---
    (#t #t #t #t)

### a ranged creature in line lets fly

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(player-hp! (game-player g) 1000)
(def line (if (null? (spec-open-line g 3)) (spec-open-line g 2) (spec-open-line g 3)))
(def cr (spec-place! g "knocker" (first (rest line)) (rest (rest line)) 100 'awake))
(creature-state! cr 'fleeing)
(def shot? (fn (_) (List any? (fn (_ m) (str=? m "The knocker shoots a stone at you!")) (game-log g))))
(spec-press-until g "." shot? 80)
(write (list (not (null? line)) (shot?) (< (player-hp (game-player g)) 1000)))
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
(spec-press-until g "." (fn (_) (List any? (fn (_ cr) (str=? (creature-name cr) "old 'un")) (game-creatures g))) 100)
(write (list (< 1 (List length (game-creatures g))) (List any? (fn (_ cr) (str=? (creature-name cr) "old 'un")) (game-creatures g))
             (List any? (fn (_ m) (Str8 starts? "The ossuary priest calls" m)) (game-log g))))
```
---
    (#t #t #t)

### a kind's tale is told the first time one comes into view, a line a message, and not again that game

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(game-creatures! g ())
(def open (spec-open g))
(def told (fn (_) (List count-if (fn (_ x) (Str8 starts? "A knocker: " x)) (game-log g))))
(def before (told))
(spec-place! g "knocker" (first (rest open)) (rest (rest open)) 1000 'asleep)
(game-key! g ".")
(def once (told))
(def said (List reverse (List filter (fn (_ x) (List any? (fn (_ p) (Str8 starts? p x)) (list "A knocker: " "left a crust" "throws stones"))) (game-log g))))
(game-creatures! g ())
(spec-place! g "knocker" (first (rest open)) (rest (rest open)) 1000 'asleep)
(game-key! g ".")
(write (list before once (told) said))
```
---
    (0 1 1 ("A knocker: the hewers' tale of the thing that knocks in the rock," "left a crust at every shift.  Since the breach it walks, and" "throws stones."))

### a creature met is named after its article: "an" before a vowel, "a" before the rest, and a guardian's own "the"

```roguelike
(def kinds (data-all (spec-set-named "delve") 'creature))
(def kind-named (fn (_ name) (List find (fn (_ k) (str=? (first k) name)) kinds)))
(write (List map (fn (_ n) (state-a-kind (kind-named n))) (list "knocker" "old 'un" "ossuary priest" "Old Man")))
```
---
    ("a knocker" "an old 'un" "an ossuary priest" "the Old Man")

## exploring and the log

### o takes a step toward what is unseen, and the walk goes on a step a call until nothing is left; a key stops it

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(def before (pair (player-r p) (player-c p)))
(def seen (spec-count-seen (game-map g)))
(game-key! g "o")
(def first-step (list (not (if (= (first before) (player-r p)) (= (rest before) (player-c p)) #f)) (game-turn g) (game-exploring? g)))
(def walk (fn (self n) (if (game-explore! g) (self (+ n 1)) n)))
(def steps (walk 0))
(def walked (list (< 0 steps) (game-exploring? g) (= (game-turn g) (+ 1 steps)) (< seen (spec-count-seen (game-map g)))))
(game-key! g "o")
(game-key! g ".")
(write (list first-step walked (game-exploring? g)))
```
---
    ((#t 1 #t) (#t #f #t #t) #f)

### one who talks, in view, does not stop the walk

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def open (spec-open g))
(def cr (spec-place! g "surveyor" (first (rest open)) (rest (rest open)) 1 'awake))
(spec-beside! g cr)
(game-key! g "o")
(write (list (game-exploring? g) (game-explore! g)))
```
---
    (#t #t)

### the walk goes round one who talks, never into them

```roguelike
(def first-step
  (fn (_)
    (def g (spec-game-on (spec-set-named "delve") 4 ()))
    (game-creatures! g ())
    (game-key! g "o")
    (pair (player-r (game-player g)) (player-c (game-player g)))))
(def at (first-step))
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(spec-place! g "surveyor" (first at) (rest at) 1 'awake)
(game-key! g "o")
(def walk (fn (self n asked) (if (game-explore! g) (self (+ n 1) (if asked #t (not (null? (game-ask g))))) (list n asked))))
(def done (walk 0 (not (null? (game-ask g)))))
(write (list (< 0 (first done)) (first (rest done))))
```
---
    (#t #f)

### L shows what was said lately, and takes no turn

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 (list "." "L")))
(write (list (spec-row g 0) (Str8 starts? " You enter the Delve." (spec-row g 1)) (game-turn g)))
```
---
    ("Lately:  --Enter--" #t 1)

## known on sight

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

## hunting by sight

### a new game's creatures are all asleep, none within eight cells of the player, and the first level has no traps

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(def kept (List reject (fn (_ cr) (creature-trait? cr 'talks)) (game-creatures g)))
(write (list (< 0 (List length kept)) (List all? (fn (_ cr) (eq? (creature-state cr) 'asleep)) kept)
             (List all? (fn (_ cr) (< 8 (state-dist (creature-r cr) (creature-c cr) (player-r p) (player-c p)))) kept)
             (game-traps g)))
```
---
    (#t #t #t ())

### on the first level a pack comes as one and none arrive; below it, they arrive wandering

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(game-creatures! g ())
(def open (spec-open g))
(creatures-place! g (spec-creature g "pit ferret") (first (rest open)) (rest (rest open)) 'asleep)
(def alone (List length (game-creatures g)))
(game-creatures! g ())
(spec-press-until g "s" (fn (_) #f) 60)
(def none (List length (game-creatures g)))
(def m (game-map g))
(player-at! (game-player g) (first (map-down m)) (rest (map-down m)))
(game-key! g ">") (spec-settle! g)
(game-creatures! g ())
(spec-press-until g "s" (fn (_) (not (null? (game-creatures g)))) 400)
(write (list alone none (game-depth g) (not (null? (game-creatures g)))
             (List all? (fn (_ cr) (eq? (creature-state cr) 'wandering)) (game-creatures g))))
```
---
    (1 0 2 #t #t)

### a sleeper beside the player wakes; one wandering beside them notices them; one awake out of sight with nowhere to go wanders

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(game-creatures! g ())
(def m (game-map g))
(def open (spec-open g))
(def sleeper (spec-place! g "pit ferret" (first (rest open)) (rest (rest open)) 1000 'asleep))
(game-key! g "s")
(def woke (creature-state sleeper))
(game-key! g " ")
(creature-state! sleeper 'wandering)
(game-key! g "s")
(def noticed (creature-state sleeper))
(game-creatures! g ())
(def hidden (List find (fn (_ at) (if (= (map-tile m (first at) (rest at)) tile-floor) (not (map-visible? m (first at) (rest at))) #f))
              (List fold (fn (_ acc r) (List append acc (List map (fn (_ c) (pair r c)) (List range 0 80)))) () (List range 0 22))))
(def far (spec-place! g "rust golem" (first hidden) (rest hidden) 1000 'awake))
(game-key! g "s")
(write (list woke noticed (creature-state far)))
```
---
    ('awake 'awake 'wandering)

### a blow on one wandering lands unawares

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def open (spec-open g))
(spec-place! g "rust golem" (first (rest open)) (rest (rest open)) 1000 'wandering)
(game-key! g (first open))
(write (first (game-messages g)))
```
---
    "You strike the rust golem unawares."

## what each level is sure of

### something to eat lies on every level; the Galleries lay one vigour, one upgrade and one pick over their three levels

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def food? (fn (_) (List any? (fn (_ it) (eq? (item-class it) 'food)) (game-floor g))))
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (spec-settle! g)))
(def first-food (food?))
(down!)
(def second-food (food?))
(down!)
(def count (fn (_ name) (List count-if (fn (_ x) (str=? x (Str8 append "band The Galleries: " name))) (game-sure g))))
(write (list (game-depth g) first-food second-food (food?) (count "vigour") (count "upgrade") (count "pick")))
```
---
    (3 #t #t #t 1 1 1)
