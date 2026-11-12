# The elements
# @weight 1

What the delve set turns on in play: hunger as a store of food, gear
that asks for strength and grows by a scroll, traps found by
searching, and the blow on a sleeper.  Each is off in classic.


## hunger

### past nothing, starving costs a hit point when the clock passes ten minutes and stops them returning; there is no faint

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(def p (game-player g))
(player-food! p 0)
(game-clock! g 595)
(def hp (player-hp p))
(List for-each (fn (_ k) (game-key! g k)) (List map (fn (_ n) ".") (List range 0 12)))
(write (list (- hp (player-hp p)) (List count-if (fn (_ m) (str=? m "You are starving.")) (game-log g))
             (List any? (fn (_ m) (Str8 starts? "You faint" m)) (game-log g)) (Str8 includes? "Starving" (spec-row g 23)) (game-over g)))
```
---
    (1 1 #f #t ())

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

### a level past the first has traps, hidden; s finds one beside you, and a pit stepped on hurts and is drawn

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(player-at! p (first (map-down (game-map g))) (rest (map-down (game-map g))))
(game-key! g ">")
(game-creatures! g ())
(def turn (game-turn g))
(def n (List length (game-traps g)))
(def open (spec-open g))
(def t (trap-make (first (rest open)) (rest (rest open)) (spec-trap g "pit") #f))
(game-traps! g (list t))
(def hidden (not (List any? (fn (_ r) (Str8 includes? "^" r)) (spec-screen g))))
(game-key! g "s")
(def found (list (game-messages g) (trap-found? t) (List any? (fn (_ r) (Str8 includes? "^" r)) (spec-screen g)) (- (game-turn g) turn)))
(def hp (player-hp p))
(game-key! g (first open))
(write (list (< 0 n) (< n 4) hidden found (game-messages g) (< (player-hp p) hp)))
```
---
    (#t #t #t (("You find a pit.") #t #t 1) ("You fall into a pit.") #t)

### with the lamp lit, a ring of (bonus light 3) has s find a trap three off in sight, and one beside noticed at a turn's end

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(player-at! p (first (map-down (game-map g))) (rest (map-down (game-map g))))
(game-key! g ">")
(game-creatures! g ())
(def line (spec-open-line g 3))
(def far (trap-make (first (rest line)) (rest (rest line)) (spec-trap g "pit") #f))
(game-traps! g (list far))
(game-key! g "s")
(def bare (trap-found? far))
(def ring (item-make (list 'ring "illumination" (list 'bonus 'light 3)) 1 0))
(item-letter! ring "z")
(game-pack! g (pair ring (game-pack g)))
(game-key! g "P")
(game-key! g "z")
(game-creatures! g ())
(game-key! g "s")
(def keen (list (trap-found? far) (game-messages g)))
(def open (spec-open g))
(def near (trap-make (first (rest open)) (rest (rest open)) (spec-trap g "pit") #f))
(game-traps! g (list near))
(game-creatures! g ())
(game-key! g ".")
(write (list (not (null? line)) bare keen (trap-found? near)))
```
---
    (#t #f (#t ("You find a pit.")) #t)

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

### a trap that throws is never laid where it would leave no way from the stairs up to the stairs down

A level cut to one passage a cell wide, the stairs at its ends, and
traps laid on it forty times over: the pits, snares and alarms go
down, and no drop shaft does.  With a second row beside the passage
there is a way round, and drop shafts go down too.

```roguelike
(import roguelike/map map-set! map-up! map-down! map-way?)
(import roguelike/traps traps-place! trap-kind)
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(player-at! p (first (map-down (game-map g))) (rest (map-down (game-map g))))
(game-key! g ">")
(game-creatures! g ())
(game-floor! g ())
(def m (game-map g))
(def cut!
  (fn (_ rows)
    (List for-each (fn (_ r) (List for-each (fn (_ c) (map-set! m r c tile-rock)) (List range 0 (map-cols m)))) (List range 0 (map-rows m)))
    (List for-each (fn (_ r) (List for-each (fn (_ c) (map-set! m r c tile-floor)) (List range 10 31))) rows)
    (map-set! m 5 10 tile-up)
    (map-set! m 5 30 tile-down)
    (map-up! m (pair 5 10))
    (map-down! m (pair 5 30))
    (game-traps! g ())
    (List for-each (fn (_ k) (traps-place! g)) (List range 0 40))))
(def throws (fn (_) (List length (List filter (fn (_ t) (str=? (first (trap-kind t)) "drop shaft")) (game-traps g)))))
(cut! (list 5))
(def narrow (list (< 0 (List length (game-traps g))) (throws)))
(cut! (list 5 6))
(def wide (list (< 0 (throws)) (map-way? m (map-up m) (map-down m) (List map (fn (_ t) (pair (Vector ref 0 t) (Vector ref 1 t))) (List filter (fn (_ t) (str=? (first (trap-kind t)) "drop shaft")) (game-traps g))))))
(write (list narrow wide))
```
---
    ((#t 0) (#t #t))

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
