# Daylight
# @weight 3

roguelike/game: a set that says (light day) lies under the sky.  A
level of it is in view whole from anywhere on it, until the player
steps under a roof, where sight is the set's (view N) again.  By day
(view N) is still how far off a creature and the player notice one
another, what a creature's tale waits for, and what stops a walk.


## the sky

### kettle and its town say (light day), the delve does not; a screen of the valley is in view whole at the start, and so is the next one stepped onto

```roguelike
(def set (spec-set-named "kettle"))
(def g (spec-game-on (spec-valley) 4 ()))
(def p (game-player g))
(def bright (fn (_ m) (List fold (fn (_ a r) (+ a (List count-if (fn (_ c) (map-visible? m r c)) (List range 0 (map-cols m))))) 0 (List range 0 (map-rows m)))))
(def here (list (game-daylight? g) (bright (game-map g)) (spec-count-seen (game-map g))))
(game-creatures! g ())
(spec-settle! g)
(player-at! p 11 79)
(game-key! g "l")
(write (list (data-get set 'light 'dark) (data-get (data-region set "town") 'light 'dark) (data-get (data-region set "delve") 'light 'dark)
             here (list (game-daylight? g) (bright (game-map g)) (spec-count-seen (game-map g)))))
```
---
    ('day 'day 'dark (#t 1760 1760) (#t 1760 1760))

### the delve is as dark as it was: sight by the lamp, the rest unseen

```roguelike
(def g (spec-game-on (spec-set-named "delve") 4 ()))
(def m (game-map g))
(write (list (game-daylight? g) (< (* 4 (spec-count-seen m)) (* (map-rows m) (map-cols m)))))
```
---
    (#f #t)


## under a roof

### a step under a roof in the town is out of the daylight: the streets stay seen, and what is in view is what sight reaches

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(def m (game-map g))
(def cells (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range 0 (map-cols m)))) (List range 0 (map-rows m))))
(def bright (fn (_) (List count-if (fn (_ at) (map-visible? m (first at) (rest at))) cells)))
(def out (list (game-daylight? g) (bright) (spec-count-seen m)))
(def under (List find (fn (_ at) (if (= (map-tile m (first at) (rest at)) tile-floor) (< 0 (map-roof-at m (first at) (rest at))) #f)) cells))
(game-creatures! g ())
(spec-settle! g)
(player-at! p (first under) (rest under))
(game-key! g ".")
(write (list out (game-daylight? g) (< (bright) (List length cells)) (spec-count-seen m)))
```
---
    ((#t 1760 1760) #f #t 1760)


## what is in sight

### a creature far off is drawn and is not in sight: its tale waits, and it does not stop a walk; near, it is in sight and its tale is told

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(def p (game-player g))
(def m (game-map g))
(game-creatures! g ())
(spec-settle! g)
(def cells (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range 0 (map-cols m)))) (List range 0 (map-rows m))))
(def floor? (fn (_ at) (if (= (map-tile m (first at) (rest at)) tile-floor) (= 0 (map-roof-at m (first at) (rest at))) #f)))
(def far (List find (fn (_ at) (if (floor? at) (< 20 (state-dist (first at) (rest at) (player-r p) (player-c p))) #f)) cells))
(def dog (spec-place! g "farm dog" (first far) (rest far) 5 'asleep))
(game-key! g ".")
(spec-settle! g)
(def drawn (Str8 sub (rest far) 1 (List ref (+ (first far) 1) (spec-screen g))))
(def told (fn (_) (List count-if (fn (_ t) (not (null? (Str8 index-of "A farm dog:" t)))) (game-log g))))
(def away (list drawn (state-in-sight? g (first far) (rest far)) (told)))
(game-key! g "o")
(def walked (first (game-log g)))
(spec-settle! g)
(def beside (spec-open g))
(creature-at! dog (first (rest beside)) (rest (rest beside)))
(game-key! g ".")
(write (list away walked (state-in-sight? g (creature-r dog) (creature-c dog)) (told)))
```
---
    (("d" #f 0) "Nothing more to see on this screen." #t 1)
