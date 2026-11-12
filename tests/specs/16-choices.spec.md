# Choices
# @weight 1

roguelike/data's choices: a set's (choice GROUP NAME . FORMS), the
ways to play it, each made by putting its forms in front of the set's;
and roguelike/save keeping a game's choices.


## what a set offers

### kettle offers three sizes and three difficulties; classic offers none

```roguelike
(write (list (data-choices (spec-valley)) (data-choices (spec-set))))
```
---
    ((('size 'small) ('size 'normal) ('size 'large) ('difficulty 'easy) ('difficulty 'normal) ('difficulty 'hard)) ())

## choosing

### a small valley is five screens by three, its hub in the middle, and its errand two links at most

```roguelike
(def set (data-choose (spec-valley) '((size small))))
(def chain-length (fn (_ seed) (def g (spec-game-on set seed ())) (List length (game-chain g))))
(def g (spec-game-on set 4 ()))
(write (list (data-chosen set) (data-one set 'world ()) (game-hub g)
             (List all? (fn (_ n) (if (< 0 n) (< n 3) #f)) (List map chain-length (List range 1 4)))))
```
---
    ((('size 'small)) ('screens 5 3) (2 . 1) #t)

### a large errand is four or five links: the longest way the scenes walk back from the goal runs five deep, but for the checkweighman's, which goes down the pit at once

```roguelike
(def set (data-choose (spec-valley) '((size large))))
(def scenes (data-all set 'scene))
(def want (fn (_ s) (first (data-prop s 'wants ()))))
(def gives? (fn (_ s name) (def gv (data-prop s 'gives ())) (if (< (List length gv) 2) #f (str=? (List ref 1 gv) name))))
(def most (fn (_ ns) (List fold (fn (_ a n) (if (< a n) n a)) 0 ns)))
(def depth
  (fn (self s used)
    (def cands (List filter (fn (_ c) (if (List includes? (first c) used) #f (gives? c (want s)))) scenes))
    (if (if (null? cands) #t (< 4 (List length used))) (List length used)
      (most (List map (fn (_ c) (self c (pair (first c) used))) cands)))))
(def starts (List filter (fn (_ s) (eq? (first (data-prop s 'gives ())) 'goal)) scenes))
(def chain-length (fn (_ seed) (def g (spec-game-on set seed ())) (Heap collect) (List length (game-chain g))))
(write (list (List map (fn (_ s) (depth s (list (first s)))) starts)
             (List all? (fn (_ n) (if (< 3 n) (< n 6) #f)) (List map chain-length (List range 1 5)))))
```
---
    ((5 5 1) #t)

### choices from two groups combine; each overrides the set's own knob, and what neither names is the set's

```roguelike
(def kettle (spec-valley))
(def set (data-choose kettle '((size large) (difficulty hard))))
(write (list (data-chosen set) (data-one set 'chain ()) (data-one set 'creatures ()) (data-one set 'starve ())
             (data-one set 'world ()) (data-one kettle 'chain ())))
```
---
    ((('size 'large) ('difficulty 'hard)) (4 5) (3 7) (3) ('screens 7 5) (2 3))

### normal is the set as it stands, and is kept as chosen

```roguelike
(def kettle (spec-valley))
(def set (data-choose kettle '((size normal))))
(write (list (data-chosen set) (= (List length set) (+ 1 (List length kettle))) (data-one set 'chain ()) (data-chosen kettle)))
```
---
    ((('size 'normal)) #t (2 3) ())

### a choice the set does not offer, or a group chosen twice, is refused and says what there is

```roguelike
(def why (fn (_ set picks) (guard (e (e msg)) (data-choose set picks) "made")))
(write (list (why (spec-valley) '((size huge)))
             (why (spec-valley) '((size small) (size large)))
             (why (spec-set) '((size small)))))
```
---
    ("the set has no choice size=huge; it has size=small size=normal size=large difficulty=easy difficulty=normal difficulty=hard" "size is chosen more than once" "the set has no choice size=small; it has none")

## saving

### a save keeps its choices: read on the plain set, the game is the small valley again; a choice the set no longer offers is dropped

```roguelike
(def kettle (spec-valley))
(def g (spec-game-on (data-choose kettle '((size small) (difficulty easy))) 4 ()))
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path kettle 24 80))
(def bare (List reject (fn (_ f) (if (eq? (first f) 'choice) (eq? (List ref 1 f) 'size) #f)) kettle))
(def k (save-read path bare 24 80))
(File unlink path)
(write (list (data-chosen (game-set h)) (game-hub h) (data-one (game-set h) 'creatures ()) (data-chosen (game-set k))))
```
---
    ((('size 'small) ('difficulty 'easy)) (2 . 1) (1 3) (('difficulty 'easy)))
