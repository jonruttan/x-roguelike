# A game
# @weight 1

roguelike/game driven by keys, as (Term key) decodes them: a new game
on level 1, moving, resting, what takes a turn and what does not, the
stairs, and what the screen shows.


## starting

### a new game is on level 1 with the player on the stairs up, and says so

```roguelike
(def g (spec-game 11 ()))
(def p (game-player g))
(write (list (game-depth g) (game-turn g) (= (map-tile (game-map g) (player-r p) (player-c p)) tile-up)
             (game-messages g) (player-hp p) (player-str p) (game-pack g)))
```
---
    (1 0 #t ("You descend into the Sunken Vault.  Find the Sunstone, and bring it back up.") 12 16 ())

### the same seed gives the same game

```roguelike
(def a (spec-game 11 (list "k" "k" "l" "." "j")))
(def b (spec-game 11 (list "k" "k" "l" "." "j")))
(write (list (= (player-r (game-player a)) (player-r (game-player b))) (= (player-c (game-player a)) (player-c (game-player b)))
             (= (List length (game-creatures a)) (List length (game-creatures b)))))
```
---
    (#t #t #t)

### the player stands in a room on the first level, and the room is in view

```roguelike
(def g (spec-game 11 ()))
(def p (game-player g))
(def room (map-room-at (game-map g) (player-r p) (player-c p)))
(write (list (not (null? room)) (map-visible? (game-map g) (player-r p) (player-c p))
             (map-seen? (game-map g) (player-r p) (player-c p))))
```
---
    (#t #t #t)

## turns

### resting takes a turn; an unknown key does not, and says so

```roguelike
(def g (spec-game 11 (list ".")))
(def h (spec-game 11 (list "%")))
(write (list (game-turn g) (game-turn h) (game-messages h)))
```
---
    (1 0 ("Unknown key.  ? lists them."))

### walking into rock takes no turn; a step onto floor takes one and moves the player

```roguelike
(def g (spec-game 11 ()))
(def p (game-player g))
(def walk (fn (self n) (def r (player-r p)) (game-key! g "k") (if (= r (player-r p)) n (self (+ n 1)))))
(def moved (walk 0))
(def turns (game-turn g))
(game-key! g "k")
(write (list (< 0 moved) (= turns moved) (= (game-turn g) turns)))
```
---
    (#t #t #t)

### hunger counts down a turn at a time

```roguelike
(def g (spec-game 11 (list "." "." ".")))
(write (list (player-food (game-player g)) (game-turn g)))
```
---
    (1297 3)

## the stairs

### > off the stairs says there are none; on them, the next level begins on its stairs up

```roguelike
(def g (spec-game 11 ()))
(def p (game-player g))
(def off (game-messages (spec-game 11 (list ">"))))
(player-at! p (first (map-down (game-map g))) (rest (map-down (game-map g))))
(game-key! g ">")
(write (list off (game-depth g) (game-deepest g) (= (map-tile (game-map g) (player-r p) (player-c p)) tile-up) (game-messages g)))
```
---
    (("There are no stairs here.") 2 2 #t ("You descend to level 2."))

### < without the goal is sealed

```roguelike
(write (game-messages (spec-game 11 (list "<"))))
```
---
    ("The way up is sealed.  Only the Sunstone can open it.")

## the screen

### the first row is the message, the last the standing, the level between

```roguelike
(def g (spec-game 11 ()))
(def rows (spec-screen g))
(write (list (List ref 0 rows) (List ref 23 rows) (< 0 (List length (List filter (fn (_ r) (Str8 includes? "@" r)) rows)))))
```
---
    ("You descend into the Sunken Vault.  Find the Sunstone, and bring it back up." "Level:1  Gold:0  Hp:12(12)  Str:16(16)  Arm:0  Exp:1/0" #t)

### i lists the pack over the level until a key, and takes no turn

```roguelike
(def g (spec-game 11 (list "i")))
(def rows (spec-screen g))
(def top (List ref 0 rows))
(game-key! g (lit escape))
(write (list top (Str8 starts? " Your pack is empty." (List ref 1 rows)) (game-turn g) (null? (game-ask g))))
```
---
    ("Your pack:  --any key--" #t 0 #t)

### a list laid over the level is gone from the screen once a key is pressed

The game draws every frame on one screen, so a row the level leaves
blank must still be written over.

```roguelike
(def g (spec-game 11 ()))
(def s (Screen make 24 80))
(def shown? (fn (_) (List any? (fn (_ r) (Str8 includes? "rest a turn" (Screen row-text s r))) (List range 0 24))))
(game-key! g "?")
(game-draw! g s)
(def during (shown?))
(game-key! g (lit escape))
(game-draw! g s)
(write (list during (shown?)))
```
---
    (#t #f)

### ? shows the keys

```roguelike
(def g (spec-game 11 (list "?")))
(write (list (List ref 0 (spec-screen g)) (Str8 starts? " h j k l y u b n  move; the arrows too." (List ref 1 (spec-screen g)))))
```
---
    ("The keys:  --any key--" #t)

### Q asks, and y ends the game

```roguelike
(def g (spec-game 11 (list "Q")))
(def asked (List ref 0 (spec-screen g)))
(game-key! g "n")
(def still (game-over g))
(game-key! g "Q")
(game-key! g "y")
(write (list asked still (game-over g) (game-epitaph g) (game-score g)))
```
---
    ("Really quit?" () 'quit "quit" 50)
