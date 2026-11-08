# Creatures
# @weight 1

roguelike/creatures and roguelike/combat: what wakes, what strikes,
what runs, what dies, and the messages that outrun the row.


## striking

### an awake creature beside the player strikes each turn

```roguelike
(def g (spec-calm 5 ()))
(def open (spec-open g))
(def cr (spec-place! g "cave rat" (first (rest open)) (rest (rest open)) 100 'awake))
(game-key! g ".")
(def struck? (fn (_ m) (if (str=? m "The cave rat hits you.") #t (str=? m "The cave rat misses you."))))
(write (list (List all? struck? (game-messages g)) (List length (game-messages g)) (= (creature-r cr) (first (rest open))) (= (creature-c cr) (rest (rest open)))))
```
---
    (#t 1 #t #t)

### one three cells away on the same row does not strike; it closes in

```roguelike
(def g (spec-calm 5 ()))
(def line (if (null? (spec-open-line g 3)) (spec-open-line g 2) (spec-open-line g 3)))
(def cr (spec-place! g "cave rat" (first (rest line)) (rest (rest line)) 100 'awake))
(def before (state-dist (creature-r cr) (creature-c cr) (player-r (game-player g)) (player-c (game-player g))))
(game-key! g ".")
(def after (state-dist (creature-r cr) (creature-c cr) (player-r (game-player g)) (player-c (game-player g))))
(write (list (not (null? line)) (< 1 before) (null? (game-messages g)) (< after before)
             (state-adjacent? 3 3 3 6) (state-adjacent? 3 3 4 4) (state-adjacent? 3 3 3 3)))
```
---
    (#t #t #t #t #f #t #f)

### a sleeping one beside the player wakes

```roguelike
(def g (spec-calm 5 ()))
(def open (spec-open g))
(def cr (spec-place! g "cave rat" (first (rest open)) (rest (rest open)) 100 'asleep))
(def before (creature-state cr))
(game-key! g ".")
(write (list before (creature-state cr)))
```
---
    ('asleep 'awake)

### walking into a creature attacks it; slain, it is worth experience

```roguelike
(def g (spec-calm 5 ()))
(def open (spec-open g))
(spec-place! g "cave rat" (first (rest open)) (rest (rest open)) 1 'awake)
(def presses (spec-press-until g (first open) (fn (_) (null? (game-creatures g))) 50))
(write (list (< 0 presses) (= presses (game-turn g)) (player-exp (game-player g))
             (List any? (fn (_ m) (str=? m "You have slain the cave rat.")) (game-messages g))))
```
---
    (#t #t 2 #t)

### each blow of the turn is kept for a front end: who struck from where, at whom, how, for how much

```roguelike
(import roguelike/state game-blows)
(def g (spec-calm 5 ()))
(def open (spec-open g))
(def p (game-player g))
(def cr (spec-place! g "cave rat" (first (rest open)) (rest (rest open)) 1 'awake))
(spec-press-until g (first open) (fn (_) (null? (game-creatures g))) 50)
(def b (first (game-blows g)))
(def gone (game-blows g))
(game-key! g ".")
(write (list (first b) (= (List ref 1 b) (player-r p)) (= (List ref 2 b) (player-c p))
             (= (List ref 3 b) (first (rest open))) (= (List ref 4 b) (rest (rest open)))
             (List ref 5 b) (< 0 (List ref 6 b)) (List length gone) (game-blows g)))
```
---
    ('blow #t #t #t #t 'kill #t 1 ())

### a skittish creature badly hurt runs

```roguelike
(def g (spec-calm 5 ()))
(def open (spec-open g))
(def cr (spec-place! g "brute" (first (rest open)) (rest (rest open)) 1 'awake))
(game-key! g ".")
(write (creature-state cr))
```
---
    'fleeing

### the player can die

```roguelike
(def g (spec-calm 5 ()))
(def open (spec-open g))
(spec-place! g "brute" (first (rest open)) (rest (rest open)) 100 'awake)
(player-hp! (game-player g) 1)
(spec-press-until g "." (fn (_) (not (null? (game-over g)))) 100)
(def over (game-over g))
(def turn (game-turn g))
(game-key! g ".")
(write (list over (game-epitaph g) (player-hp (game-player g)) (= turn (game-turn g))
             (Str8 ends? "--any key--" (spec-row g 0))))
```
---
    ('dead "killed by a brute" 0 #t #t)

## the row

### messages that outrun the row wait on --More--

```roguelike
(def g (spec-calm 5 (list ".")))
(state-say! g "Something happens over here.")
(state-say! g "Something happens over there.")
(state-say! g "Something happens again.")
(game-more! g)
(def row (spec-row g 0))
(game-key! g " ")
(write (list row (game-messages g) (null? (game-ask g)) (game-turn g)))
```
---
    ("Something happens over here.  Something happens over there.  --More--" ("Something happens again.") #t 1)
