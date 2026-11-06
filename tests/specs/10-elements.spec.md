# The elements
# @weight 1

What the delve set turns on in play: hunger as a store of food, gear
that asks for strength and grows by a scroll, traps found by
searching, and the blow on a sleeper.  Each is off in classic.


## hunger

### past nothing, starving costs a hit point every six turns and stops them returning; there is no faint

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(player-food! p 0)
(def hp (player-hp p))
(List for-each (fn (_ k) (game-key! g k)) (List map (fn (_ n) ".") (List range 0 12)))
(write (list (- hp (player-hp p)) (List count-if (fn (_ m) (str=? m "You are starving.")) (game-log g))
             (List any? (fn (_ m) (Str8 starts? "You faint" m)) (game-log g)) (Str8 includes? "Starving" (spec-row g 23)) (game-over g)))
```
---
    (2 2 #f #t ())

## gear

### armour past the player's strength protects less; an upgrade read on it mends that, and names say what they ask

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def harness (spec-drop-here! g "plated harness"))
(game-key! g ",")
(game-key! g "W")
(game-key! g "a")
(def worn (list (items-name g harness) (Str8 includes? "Arm:4" (spec-row g 23))))
(spec-drop-here! g "upgrade")
(game-key! g ",")
(game-key! g "r")
(game-key! g "b")
(def asked (list (spec-row g 0) (Str8 starts? " a) plated harness [6] (str 18) (worn)" (spec-row g 1))))
(game-key! g "a")
(write (list worn asked (game-messages g) (items-name g harness) (Str8 includes? "Arm:6" (spec-row g 23))
             (items-name g (items-new g (spec-item g "sledge")))))
```
---
    (("plated harness [6] (str 18)" #t) ("Upgrade what?" #t) ("Your plated harness glows for a moment.") "plated harness [7] (str 17)" #t "a sledge (str 17)")

## traps

### a level has traps, hidden; s finds one beside you, and a pit stepped on hurts and is drawn

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(def n (List length (game-traps g)))
(def open (spec-open g))
(def t (trap-make (first (rest open)) (rest (rest open)) (spec-trap g "pit") #f))
(game-traps! g (list t))
(def hidden (not (List any? (fn (_ r) (Str8 includes? "^" r)) (spec-screen g))))
(game-key! g "s")
(def found (list (game-messages g) (trap-found? t) (List any? (fn (_ r) (Str8 includes? "^" r)) (spec-screen g)) (game-turn g)))
(def hp (player-hp p))
(game-key! g (first open))
(write (list (< 0 n) (< n 4) hidden found (game-messages g) (< (player-hp p) hp)))
```
---
    (#t #t #t (("You find a pit.") #t #t 1) ("You fall into a pit.") #t)

### a trap comes back from a save, found or not

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def open (spec-open g))
(game-traps! g (list (trap-make (first (rest open)) (rest (rest open)) (spec-trap g "snare") #f) (trap-make 3 3 (spec-trap g "alarm") #t)))
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "delve") 24 80))
(File unlink path)
(write (List map (fn (_ t) (trap-found? t)) (game-traps h)))
```
---
    (#f #t)

## surprise

### a blow on a sleeper always lands, says so, and wakes it

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def open (spec-open g))
(def cr (spec-place! g "rust golem" (first (rest open)) (rest (rest open)) 1000 'asleep))
(game-key! g (first open))
(write (list (List take 2 (game-messages g)) (< (creature-hp cr) 1000) (creature-state cr)))
```
---
    (("You strike the rust golem unawares." "You hit the rust golem.") #t 'awake)
