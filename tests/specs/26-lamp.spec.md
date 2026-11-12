# The lamp
# @weight 2

roguelike/game: a set's (lamp FULL LOW) gives the player a lamp of
FULL seconds of oil, lit full at the start, or the first turn in the
set come from one without; it burns on the clock, is said at LOW and
going out, and out, sight is the cells beside.  A camp, c, is a rest
with it put out: no oil burns.  An oil flask, (oil N),
pours N seconds in with f, to FULL at the most.


## lit

### the delve begins with its lamp full; kettle and classic carry none

```roguelike
(def lamp-of (fn (_ set) (player-lamp (game-player (spec-game-on set 4 ())))))
(write (list (lamp-of (spec-set-named "delve")) (lamp-of (spec-valley)) (lamp-of (spec-set))))
```
---
    (1800 -1 -1)

### come down the pit from Kettle with none, the way down lights the lamp full, and it burns from there

```roguelike
(def g (spec-to-pithead! (spec-game-on (spec-set-named "kettle") 4 ())))
(def p (game-player g))
(def door (map-down (game-map g)))
(player-at! p (first door) (rest door))
(def before (player-lamp p))
(game-key! g ">")
(def lighted (list (player-lamp p) (first (game-log g))))
(game-creatures! g ())
(def c0 (game-clock g))
(spec-press-until g "." (fn (_) (< c0 (game-clock g))) 5)
(write (list before lighted (< c0 (game-clock g)) (= (player-lamp p) (- 1800 (- (game-clock g) c0)))))
```
---
    (-1 (1800 "You light your lamp.") #t #t)

## burning

### the lamp burns a second a turn, is said at ten minutes left and going out, and shows on the standing row

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(player-lamp! p 601)
(game-key! g ".")
(def low (list (player-lamp p) (game-messages g) (Str8 includes? "Lamp low" (spec-row g 23))))
(player-lamp! p 1)
(game-key! g ".")
(write (list low (player-lamp p) (game-messages g) (Str8 includes? "Dark" (spec-row g 23))))
```
---
    ((600 ("Your lamp burns low.") #t) 0 ("Your lamp goes out.") #t)

### out, no more than the cells beside are in view, and where the player stands

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(def m (game-map g))
(def in-view (fn (_) (List length (List filter (fn (_ rc) (map-visible? m (first rc) (rest rc)))
                                     (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range 0 (map-cols m)))) (List range 0 (map-rows m)))))))
(game-creatures! g ())
(game-key! g ".")
(def bright (in-view))
(player-lamp! p 0)
(game-creatures! g ())
(game-key! g ".")
(write (list (< 9 bright) (not (< 9 (in-view))) (map-visible? m (player-r p) (player-c p))))
```
---
    (#t #t #t)

### out, a ring put on with (bonus light 3) lights the cells within three, and no further

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(def m (game-map g))
(def seen (fn (_) (List flat-map (fn (_ r) (List flat-map (fn (_ c) (if (map-visible? m r c) (list (state-dist r c (player-r p) (player-c p))) ()))
                                                    (List range 0 (map-cols m))))
                    (List range 0 (map-rows m)))))
(player-lamp! p 0)
(game-creatures! g ())
(game-key! g ".")
(def bare (seen))
(def ring (item-make (list 'ring "light" (list 'bonus 'light 3)) 1 0))
(item-letter! ring "z")
(game-pack! g (pair ring (game-pack g)))
(game-creatures! g ())
(game-key! g "P")
(game-key! g "z")
(def glowing (seen))
(write (list (List all? (fn (_ d) (< d 2)) bare) (List length (player-rings p))
             (List any? (fn (_ d) (< 1 d)) glowing) (List all? (fn (_ d) (< d 4)) glowing)))
```
---
    (#t 1 #t #t)

## filling

### a flask pours five minutes in, the lamp full at the most, picking it up and pouring each a second

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(def pour (fn (_ oil) (player-lamp! p oil) (spec-drop-here! g "oil flask") (game-key! g ",") (game-key! g "f") (game-key! g "a") (player-lamp p)))
(write (list (pour 100) (first (game-messages g)) (pour 1700)))
```
---
    (398 "You fill your lamp." 1799)

### where the set has no lamp there is none to fill, and the flask is kept

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(game-creatures! g ())
(spec-drop-here! g "oil flask")
(game-key! g ",")
(game-key! g "f")
(game-key! g "a")
(write (list (player-lamp (game-player g)) (game-messages g) (List any? (fn (_ it) (str=? (items-name g it) "an oil flask")) (game-pack g))))
```
---
    (-1 ("You have no lamp to fill.") #t)

## camping

### camped, no oil burns, hit points come back on the clock and sight is the cells beside; rested, the camp breaks

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(def m (game-map g))
(game-creatures! g ())
(game-key! g ".")
(def in-view (fn (_) (List length (List flat-map (fn (_ r) (List filter (fn (_ c) (map-visible? m r c)) (List range 0 (map-cols m)))) (List range 0 (map-rows m))))))
(def before (in-view))
(player-hp! p (- (player-hpmax p) 2))
(def lamp (player-lamp p))
(def c0 (game-clock g))
(game-key! g "c")
(def made (list (game-messages g) (game-exploring? g) (< 9 before) (< (in-view) 10)))
(def run (fn (self n) (when (if (game-exploring? g) (< n 200) #f) (do (game-creatures! g ()) (game-explore! g) (self (+ n 1))))))
(run 0)
(write (list made (= (player-hp p) (player-hpmax p)) (= lamp (player-lamp p)) (< 3 (- (game-clock g) c0)) (List includes? "You are rested, and break camp." (game-messages g)) (game-exploring? g) (= before (in-view))))
```
---
    ((("You make camp.") #t #t #t) #t #t #t #t #f #t)

### a key ends a camp, and the lamp burns again; with nothing to mend there is none to make

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(game-key! g ".")
(game-key! g "c")
(def whole (list (game-messages g) (game-exploring? g)))
(player-hp! p 1)
(game-key! g "c")
(game-creatures! g ())
(def lamp (player-lamp p))
(game-key! g ".")
(write (list whole (game-exploring? g) (- lamp (player-lamp p))))
```
---
    ((("You have no need of rest.") #f) #f 1)

### a creature come beside the camp rouses it

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(game-key! g ".")
(player-hp! p 1)
(game-key! g "c")
(def open (spec-open g))
(game-creatures! g ())
(spec-place! g "mine rat" (first (rest open)) (rest (rest open)) 3 'asleep)
(game-explore! g)
(write (list (game-exploring? g) (List includes? "You start up: a mine rat is on you." (game-messages g))))
```
---
    (#f #t)

### under (camp 3 30) hit points come back three times as fast as resting a turn at a time

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(game-key! g ".")
(def rest-turns (fn (self n) (if (if (< (player-hp p) (player-hpmax p)) (< n 400) #f) (do (game-creatures! g ()) (game-key! g ".") (self (+ n 1))) n)))
(player-hp! p (- (player-hpmax p) 6))
(def resting (rest-turns 0))
(player-hp! p (- (player-hpmax p) 6))
(def t0 (game-turn g))
(game-key! g "c")
(def run (fn (self n) (when (if (game-exploring? g) (< n 400) #f) (do (game-creatures! g ()) (game-explore! g) (self (+ n 1))))))
(run 0)
(def camping (- (game-turn g) t0))
(write (list (= (player-hp p) (player-hpmax p)) (< (* 2 camping) resting) (< camping resting)))
```
---
    (#t #t #t)

### a camp rouses sleepers near it, unseen, and leaves those past twelve cells asleep

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(def m (game-map g))
(game-creatures! g ())
(game-key! g ".")
(def cells (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range 0 (map-cols m)))) (List range 0 (map-rows m))))
(def at-dist (fn (_ lo hi) (List filter (fn (_ rc) (if (map-floor? m (first rc) (rest rc))
                                                     ((fn (_ d) (if (< (- lo 1) d) (< d (+ hi 1)) #f)) (state-dist (first rc) (rest rc) (player-r p) (player-c p)))
                                                     #f))
                              cells)))
(def place (fn (_ rc) (spec-place! g "mine rat" (first rc) (rest rc) 3 'asleep) (first (game-creatures g))))
(def near (List map place (at-dist 2 2)))
(def far (place (first (at-dist 14 40))))
(def run (fn (self n) (when (if (game-exploring? g) (< n 400) #f) (do (game-explore! g) (self (+ n 1))))))
(def roused? (fn (_) (List any? (fn (_ cr) (not (eq? (creature-state cr) 'asleep))) near)))
(def camp (fn (self n) (when (if (< 0 n) (not (roused?)) #f) (do (player-hp! p 1) (game-key! g "c") (run 0) (self (- n 1))))))
(camp 20)
(write (list (< 0 (List length near)) (List any? (fn (_ cr) (not (eq? (creature-state cr) 'asleep))) near) (creature-state far)))
```
---
    (#t #t 'asleep)

## saving

### the lamp is saved with the game and read back

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(game-creatures! g ())
(player-lamp! (game-player g) 777)
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "delve") 24 80))
(File unlink path)
(write (player-lamp (game-player h)))
```
---
    777
