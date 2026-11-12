# Open fields
# @weight 2

A close is hedged about, and each hedged side of it has a way through:
a gate, or a gap in the hedge, (gaps PERCENT) of them gaps.  A field is
walked out of the way one is going, not round by its one gate.


## one close

### a close hedged all round with no way out is given one gate a side, each onto ground that can be stood on, and its corners stay hedge

```roguelike
(def box (fn (_)
           (def m (map-make 12 12))
           (List for-each (fn (_ r) (List for-each (fn (_ c) (map-set! m r c tile-floor)) (List range 0 12))) (List range 0 12))
           (List for-each (fn (_ i) (map-set! m 3 i tile-hedge) (map-set! m 8 i tile-hedge) (map-set! m i 3 tile-hedge) (map-set! m i 8 tile-hedge))
             (List range 3 9))
           m))
(def on? (fn (_ i) (if (< 2 i) (< i 9) #f)))
(def side (fn (_ m t) (list (%spec-count m (fn (_ r c) (if (= r 3) (if (on? c) (= (map-tile m r c) t) #f) #f)))
                            (%spec-count m (fn (_ r c) (if (= r 8) (if (on? c) (= (map-tile m r c) t) #f) #f)))
                            (%spec-count m (fn (_ r c) (if (= c 3) (if (on? r) (= (map-tile m r c) t) #f) #f)))
                            (%spec-count m (fn (_ r c) (if (= c 8) (if (on? r) (= (map-tile m r c) t) #f) #f))))))
(def corners (fn (_ m) (List all? (fn (_ at) (= (map-tile m (first at) (rest at)) tile-hedge)) (list (pair 3 3) (pair 3 8) (pair 8 3) (pair 8 8)))))
(def gated (box))
(dungeon-open-close! (Random sw 7) gated 4 4 7 7 0)
(def gapped (box))
(dungeon-open-close! (Random sw 7) gapped 4 4 7 7 100)
(write (list (side gated tile-gate) (corners gated) (side gapped tile-gate) (side gapped tile-floor) (corners gapped)))
```
---
    ((1 1 1 1) #t (0 0 0 0) (1 1 1 1) #t)

### a side with a way through already is left as it is, and a side with nothing to stand on beyond it stays shut

```roguelike
(def m (map-make 12 12))
(List for-each (fn (_ r) (List for-each (fn (_ c) (map-set! m r c tile-floor)) (List range 0 12))) (List range 0 12))
(List for-each (fn (_ i) (map-set! m 3 i tile-hedge) (map-set! m 8 i tile-hedge) (map-set! m 9 i tile-hedge) (map-set! m i 3 tile-hedge) (map-set! m i 8 tile-hedge))
  (List range 3 9))
(map-set! m 3 5 tile-gate)
(dungeon-open-close! (Random sw 7) m 4 4 7 7 0)
(def gates (fn (_ pred) (%spec-count m (fn (_ r c) (if (pred r c) (= (map-tile m r c) tile-gate) #f)))))
(write (list (gates (fn (_ r c) (= r 3))) (= (map-tile m 3 5) tile-gate) (gates (fn (_ r c) (= r 8)))
             (gates (fn (_ r c) (= c 3))) (gates (fn (_ r c) (= c 8)))))
```
---
    (1 #t 0 1 1)

## the valley's fields

### a screen of fields has more ways through its hedges than a gate a hedge, some of them gaps when the set says so, and every cell of it can still be walked to

```roguelike
(def ways (fn (_ m) (%spec-count m (fn (_ r c) (= (map-tile m r c) tile-gate)))))
(write (List map (fn (_ seed)
                   (def gated (spec-level-on '((level-style fields) (gaps 0)) seed 1))
                   (def n (ways gated))
                   (def mixed (spec-level-on '((level-style fields) (gaps 100)) seed 1))
                   (list (spec-connected? gated) (spec-connected? mixed) (< 30 n) (< (ways mixed) n)))
                 '(1 2 3 4)))
```
---
    ((#t #t #t #t) (#t #t #t #t) (#t #t #t #t) (#t #t #t #t))
