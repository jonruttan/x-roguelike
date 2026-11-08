# The lamp
# @weight 2

roguelike/game: a set's (lamp FULL LOW) gives the player a lamp of
FULL seconds of oil, lit full at the start, or the first turn in the
set come from one without; it burns on the clock, is said at LOW and
going out, and out, sight is the cells beside.  An oil flask, (oil N),
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

## filling

### a flask pours ten minutes in, the lamp full at the most, picking it up and pouring each a second

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(def pour (fn (_ oil) (player-lamp! p oil) (spec-drop-here! g "oil flask") (game-key! g ",") (game-key! g "f") (game-key! g "a") (player-lamp p)))
(write (list (pour 100) (first (game-messages g)) (pour 1500)))
```
---
    (698 "You fill your lamp." 1799)

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
