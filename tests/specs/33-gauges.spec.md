# The gauges
# @weight 1

roguelike/draw: the stores the player draws down, food under the
set's (hunger ...) and oil under its (lamp ...), each as what is left
of the most it holds, on the standing row and for the window's
standing.


## what is left

### the delve begins half fed, its lamp full, and the standing row says so

```roguelike
(import roguelike/draw draw-gauges)
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(write (list (draw-gauges g) (Str8 includes? "Food:50%  Lamp:100%" (spec-row g 23))))
```
---
    ((("Food" 50 0) ("Lamp" 100 0)) #t)

### a part of one counts whole; hungry and a low lamp are warnings under their own names

```roguelike
(def p (game-player g))
(player-food! p 14400)
(player-lamp! p 600)
(def low (list (draw-gauges g) (Str8 includes? "Hungry:17%  Lamp low:34%" (spec-row g 23))))
(player-food! p 3600)
(player-lamp! p 1)
(write (list low (draw-gauges g)))
```
---
    (((("Hungry" 17 1) ("Lamp low" 34 1)) #t) (("Weak" 5 2) ("Lamp low" 1 1)))

### with nothing left the name stands alone

```roguelike
(player-food! p 0)
(player-lamp! p 0)
(write (list (draw-gauges g) (Str8 includes? "Starving  Dark" (spec-row g 23))))
```
---
    ((("Starving" 0 2) ("Dark" 0 2)) #t)

### fuller than the set's most is full

```roguelike
(player-food! p 90000)
(write (first (draw-gauges g)))
```
---
    ("Food" 100 0)

### a set with no lamp has the one gauge, food of its own most

```roguelike
(write (list (draw-gauges (spec-game 11 ())) (draw-gauges (spec-game-on (spec-valley) 4 ()))))
```
---
    ((("Food" 65 0)) (("Food" 50 0)))
