# Quests
# @weight 1

roguelike/quests: the people met below, spoken to by walking into
them, what each asks, and what it pays.  On the delve set.


## meeting

### the lampman stands on level 2 where he cuts no way, and a knocker there carries the lamp

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (spec-settle! g)))
(def none (List any? (fn (_ cr) (str=? (creature-name cr) "lampman")) (game-creatures g)))
(down!)
(def keeper (List find (fn (_ cr) (str=? (creature-name cr) "lampman")) (game-creatures g)))
(def carrier (List find (fn (_ cr) (not (null? (creature-carried cr)))) (game-creatures g)))
(def m (game-map g))
(def open (spec-cuts-no-way? m keeper (pair (player-r (game-player g)) (player-c (game-player g)))))
(write (list none (not (null? keeper)) (creature-trait? keeper 'talks) open (creature-name carrier) (item-name (creature-carried carrier)) (game-placed g)))
```
---
    (#f #t #t #t "knocker" "the foreman's lamp" ("the foreman's lamp" "giver the lamp"))

### walking into the lampman opens the quest and shows what it asks, for a turn; again, it presses

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (spec-settle! g)))
(down!)
(game-creatures! g (List filter (fn (_ cr) (creature-trait? cr 'talks)) (game-creatures g)))
(def keeper (first (game-creatures g)))
(def key (spec-beside! g keeper))
(def turn (game-turn g))
(def before (game-quest-state g "the lamp"))
(game-key! g key)
(def asked (list (spec-row g 0) (Str8 starts? " I kept the lamps at the breach." (spec-row g 1)) (- (game-turn g) turn) (game-quest-state g "the lamp")))
(spec-dismiss! g)
(game-key! g key)
(write (list before asked (Str8 starts? " No lamp yet." (spec-row g 1)) (state-adjacent? (creature-r keeper) (creature-c keeper) (player-r (game-player g)) (player-c (game-player g)))))
```
---
    (() ("lampman  --Enter--" #t 1 'open) #t #t)

### the lamp brought, the keeper offers two things; a takes the first, the lamp is gone, and there is no more to ask

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (spec-settle! g)))
(down!)
(game-creatures! g (List filter (fn (_ cr) (creature-trait? cr 'talks)) (game-creatures g)))
(def keeper (first (game-creatures g)))
(def key (spec-beside! g keeper))
(game-key! g key)
(spec-dismiss! g)
(spec-drop-here! g "the foreman's lamp")
(game-key! g ",")
(def held (List map (fn (_ it) (items-name g it)) (game-pack g)))
(game-key! g key)
(def offered (list (spec-row g 0) (List any? (fn (_ r) (if (Str8 starts? " a) a miner's blade (str 14)" r) (Str8 includes? "b) scale coat [4] (str 15)" r) #f)) (spec-screen g)) (game-quest-state g "the lamp")))
(game-key! g "a")
(def got (List map (fn (_ it) (items-name g it)) (game-pack g)))
(game-key! g key)
(write (list held offered got (game-quest-state g "the lamp") (game-messages g)))
```
---
    (("the foreman's lamp") ("Which will you take?" #t 'reward) ("a miner's blade (str 14)") 'done ("The lampman has nothing more to ask."))

### the surveyor on level 5 wants the level seen whole: a survey read, it pays

Level 4 opens a band, and its word with the stairs message outruns the
row: the --More-- is answered before the next step down.

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (spec-settle! g)))
(down!)
(down!)
(game-creatures! g ())
(down!)
(down!)
(game-creatures! g (List filter (fn (_ cr) (creature-trait? cr 'talks)) (game-creatures g)))
(def surveyor (first (game-creatures g)))
(def key (spec-beside! g surveyor))
(game-key! g key)
(spec-dismiss! g)
(game-key! g key)
(def pressed (Str8 starts? " Not the whole of it yet." (spec-row g 1)))
(spec-dismiss! g)
(spec-drop-here! g "survey")
(game-key! g ",")
(game-key! g "r")
(game-key! g "a")
(game-key! g key)
(def offered (spec-row g 0))
(game-key! g "b")
(write (list (game-depth g) (creature-name surveyor) pressed offered (List map item-class (game-pack g)) (game-quest-state g "the survey")))
```
---
    (5 "surveyor" #t "Which will you take?" ('ring) 'done)

## between sittings

### a quest's state and what it placed come back from a save

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (spec-settle! g)))
(down!)
(game-creatures! g (List filter (fn (_ cr) (creature-trait? cr 'talks)) (game-creatures g)))
(def keeper (first (game-creatures g)))
(game-key! g (spec-beside! g keeper))
(spec-dismiss! g)
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "delve") 24 80))
(File unlink path)
(write (list (game-quest-state h "the lamp") (game-placed h) (List map creature-name (game-creatures h))))
```
---
    ('open ("the foreman's lamp" "giver the lamp") ("lampman"))

## the salvager

### he stands near the arrival on level 4, the first of a band after the first, and on no level before, in the open where he cuts no way

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (spec-settle! g)))
(def seen (Vector of #f))
(def look! (fn (_) (when (List any? (fn (_ cr) (str=? (creature-name cr) "salvager")) (game-creatures g)) (Vector set! 0 #t seen))))
(look!)
(down!)
(look!)
(down!)
(look!)
(game-creatures! g ())
(down!)
(def p (game-player g))
(def man (List find (fn (_ cr) (str=? (creature-name cr) "salvager")) (game-creatures g)))
(def d (state-dist (creature-r man) (creature-c man) (player-r p) (player-c p)))
(def m (game-map g))
(def open (spec-cuts-no-way? m man (pair (player-r p) (player-c p))))
(write (list (Vector ref 0 seen) (game-depth g) (creature-trait? man 'talks) (< 1 d) (< d 8) open))
```
---
    (#f 4 #t #t #t #t)

### walked into, he puts up his counter: the band's stock at the set's prices, selling, and the purse

```roguelike
(game-creatures! g (list man))
(player-gold! p 200)
(game-key! g (spec-beside! g man))
(def asked (game-ask g))
(write (list (first asked) (List ref 1 asked) (rest (rest (List ref 3 asked)))))
```
---
    ('choose "The salvager: what will you have?" ("a) mending, 30 gold" "b) oil flask, 20 gold" "c) miner's tin, 15 gold" "d) blink, 40 gold" "e) miner's blade, 120 gold" "f) scale coat, 150 gold" "s) sell something" "" "You have 200 gold."))

### a letter buys: the scale coat for 150 gold, into the pack

```roguelike
(game-key! g "f")
(write (list (player-gold p) (List any? (fn (_ it) (str=? (item-name it) "scale coat")) (game-pack g)) (first (game-ask g))))
```
---
    (50 #t 'choose)

### his stock is what he has: the coat sold is gone from the counter, four mending empty it of mending, and walked into again, they are still gone

```roguelike
(def wares (fn (_) (List map rest (List ref 4 (game-ask g)))))
(def after-coat (wares))
(player-gold! p 200)
(game-key! g "a")
(game-key! g "a")
(game-key! g "a")
(game-key! g "a")
(def after-mending (wares))
(game-key! g "z")
(game-key! g (spec-beside! g man))
(write (list after-coat after-mending (wares)))
```
---
    (("mending, 30 gold" "oil flask, 20 gold" "miner's tin, 15 gold" "blink, 40 gold" "miner's blade, 120 gold" "Sell something") ("oil flask, 20 gold" "miner's tin, 15 gold" "blink, 40 gold" "miner's blade, 120 gold" "Sell something") ("oil flask, 20 gold" "miner's tin, 15 gold" "blink, 40 gold" "miner's blade, 120 gold" "Sell something"))

### his stock on level 7 is his own, untouched by what he sold on level 4

```roguelike
(game-key! g "z")
(def down7! (fn (_) (def mm (game-map g)) (game-creatures! g ()) (player-at! p (first (map-down mm)) (rest (map-down mm))) (game-key! g ">") (spec-settle! g)))
(down7!)
(down7!)
(down7!)
(def man7 (List find (fn (_ cr) (str=? (creature-name cr) "salvager")) (game-creatures g)))
; A step into him from whichever side of him is walkable.
(def side (List find (fn (_ d) (map-walkable? (game-map g) (+ (creature-r man7) (first (rest d))) (+ (creature-c man7) (rest (rest d)))))
            (list (pair "j" (pair -1 0)) (pair "k" (pair 1 0)) (pair "l" (pair 0 -1)) (pair "h" (pair 0 1)))))
(player-at! p (+ (creature-r man7) (first (rest side))) (+ (creature-c man7) (rest (rest side))))
(player-gold! p 200)
(game-key! g (first side))
(write (list (game-depth g) (wares)))
```
---
    (7 ("mending, 30 gold" "oil flask, 20 gold" "miner's tin, 15 gold" "blink, 40 gold" "sledge, 350 gold" "plated harness, 450 gold" "Sell something"))
