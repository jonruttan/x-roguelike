# Time
# @weight 2

roguelike/game: a turn takes the time to walk a cell at the level's
scale, a metre and four tenths a second, and the game's clock counts
the seconds.  Hunger, starving and hit points back are counted on the
clock, so a level at (scale 1) keeps a second a turn, and the valley's
fields take a quarter of a minute each.


## the turn

### a turn at each rung takes the seconds a cell is walked in, a second at least

```roguelike
(write (List map (fn (_ n) (scale-seconds (scale-rung n))) (list 1 2 3 5 8 13 21 34)))
```
---
    (1 1 2 4 6 9 15 24)

### a turn takes a second in the classic set and the town, a quarter minute on the valley, and food goes by the second

```roguelike
(def classic (spec-game 11 (list "." "." ".")))
(def town (spec-game-on (spec-set-named "kettle") 4 ()))
(game-creatures! town ())
(game-key! town ".")
(game-key! town ".")
(def valley (spec-game-on (spec-valley) 4 ()))
(game-creatures! valley ())
(game-key! valley ".")
(game-key! valley ".")
(write (List map (fn (_ g) (list (game-turn g) (game-clock g) (player-food (game-player g)))) (list classic town valley)))
```
---
    ((3 3 1297) (2 2 43198) (2 30 43170))

## hunger

### the valley's quarter minute past four hours of food is felt

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(game-creatures! g ())
(player-food! (game-player g) 14410)
(game-key! g ".")
(write (list (player-food (game-player g)) (game-messages g)))
```
---
    (14395 ("You are getting hungry."))

### past nothing, a hit point goes when the clock passes ten minutes, not a turn

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-food! p -100)
(game-clock! g 570)
(def hp (player-hp p))
(game-key! g ".")
(def first-turn (- hp (player-hp p)))
(game-key! g ".")
(write (list first-turn (- hp (player-hp p)) (game-clock g)))
```
---
    (0 1 600)

### bread fills by six hours, to a day's at the most, picking it up and eating each a quarter minute

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(def p (game-player g))
(game-creatures! g ())
(def eat (fn (_ food) (player-food! p food) (spec-drop-here! g "bread") (game-key! g ",") (game-key! g "e") (game-key! g "a") (player-food p)))
(write (list (eat 20000) (eat 80000)))
```
---
    (41570 86385)

## hit points

### a hit point comes back each half minute on the clock: two turns on the valley, thirty in the town

```roguelike
(def valley (spec-game-on (spec-valley) 4 ()))
(def town (spec-game-on (spec-set-named "kettle") 4 ()))
(def back
  (fn (_ g n)
    (game-creatures! g ())
    (player-hp! (game-player g) 1)
    (List for-each (fn (_ k) (game-creatures! g ()) (game-key! g ".")) (List range 0 n))
    (player-hp (game-player g))))
(write (list (back valley 1) (back valley 2) (back town 29) (back town 30)))
```
---
    (1 2 1 2)

### a level quickens them by the set's (regen N QUICKEN), two seconds unless given: at level five the classic set's twenty are twelve, the Delve's twelve are twelve

```roguelike
(import roguelike/state player-level!)
(def back
  (fn (_ g)
    (spec-settle! g)
    (player-level! (game-player g) 5)
    (player-hp! (game-player g) 1)
    (List for-each (fn (_ k) (game-creatures! g ()) (game-key! g ".")) (List range 0 24))
    (player-hp (game-player g))))
(write (list (back (spec-game 11 ())) (back (spec-game-on (spec-set-named "delve") 4 ()))))
```
---
    (3 3)

## saving

### the clock is saved with the game and read back

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(game-creatures! g ())
(game-key! g ".")
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-valley) 24 80))
(File unlink path)
(write (list (game-clock g) (game-clock h)))
```
---
    (15 15)
