# In view
# @weight 1

roguelike/game: v lists what a player keeping count would know: the
turn and the clock, each condition on the player and its turns left,
and each creature drawn, how far and which way, its mind, how hurt it
is against the hit points it was whole at, and its conditions.


## v

### with nothing about, the turn and the clock, and no turn taken

```roguelike
(import roguelike/state creature-condition! creature-whole player-condition!)
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(def view (fn (_) (game-key! g "v") ((fn (_ q) (spec-dismiss! g) (list (List ref 1 q) (List ref 3 q))) (game-ask g))))
(def turn (game-turn g))
(write (list (view) (= turn (game-turn g))))
```
---
    (("In view:" ("Turn 0, 0:00:00 on the clock." "Nothing that moves is in view.")) #t)

### a creature asleep and whole; then awake, hurt to under half, and slowed, the player quick

```roguelike
(def cr (spec-place! g "pit ferret" (player-r p) (+ (player-c p) 1) 8 'asleep))
(def asleep (List ref 1 (view)))
(creature-state! cr 'awake)
(creature-hp! cr 3)
(creature-condition! cr 'slowed 5)
(player-condition! p 'hasted 1)
(write (list asleep (List ref 1 (view))))
```
---
    (("Turn 0, 0:00:00 on the clock." "a pit ferret, 1 east: asleep") ("Turn 0, 0:00:00 on the clock." "You are quick for 1 turn." "a pit ferret, 1 east: awake, badly hurt, slowed for 5 turns"))

### hurt, nearly dead, one that has not noticed and one fleeing; a talker awake is only there

```roguelike
(creature-condition! cr 'slowed 0)
(def minds (fn (_ hp state) (creature-hp! cr hp) (creature-state! cr state) (List ref 2 (List ref 1 (view)))))
(def three (list (minds 5 'wandering) (minds 2 'fleeing) (minds 8 'awake)))
(game-creatures! g ())
(player-condition! p 'hasted 0)
(spec-place! g "lampman" (player-r p) (- (player-c p) 1) 1 'awake)
(write (list three (List ref 1 (List ref 1 (view)))))
```
---
    (("a pit ferret, 1 east: has not noticed you, hurt" "a pit ferret, 1 east: fleeing, nearly dead" "a pit ferret, 1 east: awake") "a lampman, 1 west")

### a save keeps what a creature was whole at

```roguelike
(game-creatures! g ())
(def cr (spec-place! g "pit ferret" (player-r p) (+ (player-c p) 1) 8 'awake))
(creature-hp! cr 3)
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(save-write! g (rest tmp))
(def h (save-read (rest tmp) (spec-set-named "delve") 24 80))
(File unlink (rest tmp))
(write (List map (fn (_ c) (list (creature-hp c) (creature-whole c))) (game-creatures h)))
```
---
    ((3 8))
