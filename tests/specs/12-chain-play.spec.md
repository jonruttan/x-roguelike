# The chain, played
# @weight 1

The kettle set played at random, a thousand keys a game: nothing
raised and every invariant kept.  Apart from 12-chain and
12-chain-sweep so that no file nears the time limit on a hosted runner.


## random play

### two games of a thousand keys raise nothing and keep every invariant

```roguelike
(def runs (List map (fn (_ seed) (spec-random-play (spec-valley) seed 1000)) (List range 5 7)))
(write (list (List filter (fn (_ r) (not (null? (List ref 4 r)))) runs)
             (< 40 (List fold (fn (_ a r) (+ a (List ref 2 r))) 0 runs))))
```
---
    (() #t)
