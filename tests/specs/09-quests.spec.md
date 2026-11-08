# Quests
# @weight 1

roguelike/quests: the people met below, spoken to by walking into
them, what each asks, and what it pays.  On the delve set.


## meeting

### the lampman stands on level 2, and a knocker there carries the lamp

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">")))
(def none (List any? (fn (_ cr) (str=? (creature-name cr) "lampman")) (game-creatures g)))
(down!)
(def keeper (List find (fn (_ cr) (str=? (creature-name cr) "lampman")) (game-creatures g)))
(def carrier (List find (fn (_ cr) (not (null? (creature-carried cr)))) (game-creatures g)))
(write (list none (not (null? keeper)) (creature-trait? keeper 'talks) (creature-name carrier) (item-name (creature-carried carrier)) (game-placed g)))
```
---
    (#f #t #t "knocker" "the foreman's lamp" ("the foreman's lamp" "giver the lamp"))

### walking into the lampman opens the quest and shows what it asks, for a turn; again, it presses

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(player-hp! (game-player g) 1000)
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">")))
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
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">")))
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
(def offered (list (spec-row g 0) (List any? (fn (_ r) (Str8 starts? " a) a miner's blade (str 14)   b) boiled leather [2] (str 12)" r)) (spec-screen g)) (game-quest-state g "the lamp")))
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
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">") (unless (null? (game-ask g)) (spec-dismiss! g))))
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
(def down! (fn (_) (def m (game-map g)) (player-at! (game-player g) (first (map-down m)) (rest (map-down m))) (game-key! g ">")))
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
