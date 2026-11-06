# Random play on the classic set, seeds four to six
# @weight 2

Random keys through three more classic games; the first three are in
07-random-play, and the delve set in 07-random-play-delve, so each
file stays inside the runner's time for a file.


## the classic set

### three more games of twelve hundred keys raise nothing and keep every invariant

```roguelike
(def runs (List map (fn (_ seed) (spec-random-play (spec-set) seed 1200)) (List range 4 7)))
(write (list (List filter (fn (_ r) (not (null? (List ref 4 r)))) runs)
             (< 75 (List fold (fn (_ a r) (+ a (List ref 2 r))) 0 runs))))
```
---
    (() #t)
