# Random play on the delve set
# @weight 2

Random keys through whole games on the delve set, the screen drawn and
the invariants checked as they go; the classic set is in 07-random-play.
Apart, so each file stays inside the runner's time for a file.


## the delve set

### three games of twelve hundred keys raise nothing and keep every invariant

```roguelike
(def runs (List map (fn (_ seed) (spec-random-play (spec-set-named "delve") seed 1200)) (List range 1 4)))
(write (list (List filter (fn (_ r) (not (null? (List ref 4 r)))) runs)
             (< 60 (List fold (fn (_ a r) (+ a (List ref 2 r))) 0 runs))))
```
---
    (() #t)
