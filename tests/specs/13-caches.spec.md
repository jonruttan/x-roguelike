# Caches
# @weight 1

roguelike/items on the kettle set: what may lie at a depth, and the
band's caches, each a thing worth having with a keeper beside it.


## the depth gate

### nothing lies in the square that its (depth LO HI) keeps out, over six seeds

```roguelike
(def set (spec-valley))
(def allowed (list "mending" "survey" "walking staff" "waxed coat" "bread" "cheese" "gold"))
(def hub-ok?
  (fn (_ seed)
    (def g (spec-game-on set seed ()))
    (Heap collect)
    (List all? (fn (_ it) (List includes? (item-name it) allowed)) (game-floor g))))
(write (list (List all? hub-ok? (List range 1 7))
             (List any? (fn (_ f) (eq? (first (data-prop f 'depth ())) 2)) (data-all set 'item))))
```
---
    (#t #t)

## the caches

### a screen of the first ring lays the band's caches, each with a keeper beside it, and says the band's word

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(def p (game-player g))
(player-at! p 11 79)
(game-key! g "l")
(def classes (list 'potion 'food 'weapon))
(def kept? (fn (_ it) (List any? (fn (_ cr) (state-adjacent? (creature-r cr) (creature-c cr) (item-r it) (item-c it))) (game-creatures g))))
(def caches (List filter (fn (_ it) (if (List includes? (item-class it) classes) (kept? it) #f)) (game-floor g)))
(def n (List length caches))
(write (list (game-depth g) (< 1 n) (< n 5) (List any? (fn (_ m) (Str8 starts? "The farms:" m)) (game-log g))
             (List all? (fn (_ cr) (if (creature-trait? cr 'talks) #t (not (null? (creatures-kinds g 1))))) (game-creatures g))))
```
---
    (1 #t #t #t #t)

### the square, in no band, lays none

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(def kept? (fn (_ it) (List any? (fn (_ cr) (state-adjacent? (creature-r cr) (creature-c cr) (item-r it) (item-c it))) (game-creatures g))))
(write (list (List map creature-name (game-creatures g)) (List count-if kept? (game-floor g))))
```
---
    (("Guild clerk") 0)

## random play

### a game of a thousand keys with caches and keepers raises nothing and keeps every invariant

```roguelike
(def runs (List map (fn (_ seed) (spec-random-play (spec-valley) seed 1000)) (List range 8 9)))
(write (list (List filter (fn (_ r) (not (null? (List ref 4 r)))) runs)
             (< 20 (List fold (fn (_ a r) (+ a (List ref 2 r))) 0 runs))))
```
---
    (() #t)
