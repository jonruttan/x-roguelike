# People in the streets
# @weight 2

roguelike/quests: a shop's keeper stands at the back of it with a
counter beside them, and a step at the counter is a word with them; a
district's (folk NAME LINE ...) is one of its people out of doors, who
says a LINE walked into, and with the strolls trait wanders the
streets and never goes under a roof.


## the counter

### the inn has one counter, beside the innkeeper and under the inn's roof, the floor across it from them free to stand on; the council house, no shop, has none

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def m (game-map g))
(def host (List find (fn (_ c) (str=? (creature-name c) "innkeeper")) (game-creatures g)))
(def counters (List flat-map (fn (_ r) (List flat-map (fn (_ c) (if (= (map-tile m r c) tile-counter) (list (pair r c)) ())) (List range 0 80))) (List range 0 22)))
(def at (first counters))
(def step (pair (- (first at) (creature-r host)) (- (rest at) (creature-c host))))
(write (list (List length counters) (first (map-place-at m (first at) (rest at)))
             (+ (* (first step) (first step)) (* (rest step) (rest step)))
             (map-walkable? m (+ (first at) (first step)) (+ (rest at) (rest step)))
             (< 0 (map-roof-at m (first at) (rest at)))))
```
---
    (1 "the inn" 1 #t #t)

### a step at the counter from across it puts up the innkeeper's goods, as a step at the innkeeper does

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def m (game-map g))
(def host (List find (fn (_ c) (str=? (creature-name c) "innkeeper")) (game-creatures g)))
(def at (first (List flat-map (fn (_ r) (List flat-map (fn (_ c) (if (= (map-tile m r c) tile-counter) (list (pair r c)) ())) (List range 0 80))) (List range 0 22))))
(def step (pair (- (first at) (creature-r host)) (- (rest at) (creature-c host))))
(game-creatures! g (list host))
(player-at! (game-player g) (+ (first at) (first step)) (+ (rest at) (rest step)))
(game-key! g (rest (Assoc find step (list (pair (pair -1 0) "j") (pair (pair 1 0) "k") (pair (pair 0 -1) "l") (pair (pair 0 1) "h")))))
(def asked (game-ask g))
(write (list (first asked) (List ref 1 asked)))
```
---
    ('choose "The innkeeper: what will you have?")

## the people of the streets

### the square has its carrier and its water-carrier, one of each, on open ground under no roof, and each walked into says a line of theirs

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def m (game-map g))
(def lines '(("carrier" "The pass is open till the snow, and I'll not winter here." "A packhorse wants oats, pit or no pit.")
             ("water-carrier" "The well-head serves the whole square, and the queue is longer each week.")))
(def named (fn (_ name) (List filter (fn (_ c) (str=? (creature-name c) name)) (game-creatures g))))
(def out? (fn (_ cr) (if (map-floor? m (creature-r cr) (creature-c cr)) (= 0 (map-roof-at m (creature-r cr) (creature-c cr))) #f)))
(def said (fn (_ name)
            (def cr (first (named name)))
            (game-key! g (spec-beside! g cr))
            (def line (first (List ref 3 (game-ask g))))
            (spec-settle! g)
            (List includes? line (rest (Assoc find name lines)))))
(write (List map (fn (_ name) (list (List length (named name)) (out? (first (named name))) (said name))) '("carrier" "water-carrier")))
```
---
    ((1 #t #t) (1 #t #t))

### one who strolls moves about over two hundred turns and is never under a roof nor off the floor; one who does not stays put

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def m (game-map g))
(def named (fn (_ name) (List find (fn (_ c) (str=? (creature-name c) name)) (game-creatures g))))
(def walker (named "carrier"))
(def from (pair (creature-r walker) (creature-c walker)))
(def turns
  (List map (fn (_ k)
              (game-key! g ".")
              (spec-settle! g)
              (when (= 0 (% k 10)) (Heap collect))
              (list (if (map-floor? m (creature-r walker) (creature-c walker)) (= 0 (map-roof-at m (creature-r walker) (creature-c walker))) #f)
                    (if (= (creature-r walker) (first from)) (= (creature-c walker) (rest from)) #f)))
    (List range 0 200)))
(write (list (List all? first turns) (< 10 (List length (List filter (fn (_ t) (not (List ref 1 t))) turns)))
             (creature-trait? walker 'strolls) (creature-trait? (named "innkeeper") 'strolls)))
```
---
    (#t #t #t #f)
