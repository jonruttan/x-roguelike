# The chain, swept
# @weight 1

roguelike/chain on the kettle set over many seeds: every chain drawn
sound, and no link's want astray.  Apart from 12-chain and
12-chain-play so that no file nears the time limit on a hosted runner.


## the chain drawn

### every chain the first twelve seeds draw is sound, and they are not all the same

```roguelike
(def set (spec-set-named "kettle"))
(def sound?
  (fn (_ chain)
    (def prop (fn (_ q key) (data-prop (rest q) key ())))
    (def n (List length chain))
    (def want (fn (_ q) (List ref 1 (prop q 'wants))))
    (def gift (fn (_ q) (List ref 1 (first (prop q 'rewards)))))
    (match ((< n 2) #f) ((< 3 n) #f)
           ((not (eq? (first (first (prop (first chain) 'rewards))) 'goal)) #f)
           ((null? (prop (List ref (- n 1) chain) 'lies)) #f)
           (#t (List all? (fn (_ i) (str=? (want (List ref i chain)) (gift (List ref (+ i 1) chain)))) (List range 0 (- n 1)))))))
(def chains (List map (fn (_ seed) ((fn (_ g) (Heap collect) (game-chain g)) (spec-game-on set seed ()))) (List range 1 13)))
(def heads (List distinct (List map (fn (_ c) (List ref 1 (first c))) chains)))
(write (list (List all? sound? chains) (< 1 (List length heads)) (< 1 (List length (List distinct (List map (fn (_ c) (Str8 str (List length c))) chains))))))
```
---
    (#t #t #t)

## what lies where

### a link's want lies nowhere but where the chain says: no token in the square, over six seeds

```roguelike
(def set (spec-set-named "kettle"))
(def tokens (fn (_ seed) (def g (spec-game-on set seed ())) (Heap collect) (List count-if (fn (_ it) (eq? (item-class it) 'token)) (game-floor g))))
(write (List map tokens (List range 1 7)))
```
---
    (0 0 0 0 0 0)
