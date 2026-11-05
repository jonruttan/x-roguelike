# Random play
# @weight 2

Thousands of random keys through whole games on both sets, the screen
drawn and the invariants checked as they go: nothing raises, nobody
stands where they cannot, every creature beside the player is drawn.


## the classic set

### six games of twelve hundred keys raise nothing and keep every invariant

```roguelike
(def runs (List map (fn (_ seed) (spec-random-play (spec-set) seed 1200)) (List range 1 7)))
(write (list (List filter (fn (_ r) (not (null? (List ref 4 r)))) runs)
             (< 150 (List fold (fn (_ a r) (+ a (List ref 2 r))) 0 runs))))
```
---
    (() #t)

## the delve set

### three games of twelve hundred keys raise nothing and keep every invariant

```roguelike
(def runs (List map (fn (_ seed) (spec-random-play (spec-set-named "delve") seed 1200)) (List range 1 4)))
(write (list (List filter (fn (_ r) (not (null? (List ref 4 r)))) runs)
             (< 60 (List fold (fn (_ a r) (+ a (List ref 2 r))) 0 runs))))
```
---
    (() #t)
