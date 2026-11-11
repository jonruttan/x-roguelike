# Finding people
# @weight 3

roguelike/quests: an errand with a screen of its own leads somewhere
while it is not over: the first of the chain, not yet asked, to its
giver; one open, to what it wants, where that lies or with whoever
gives it; one whose want is in the pack, back to its giver.  The map
marks the screen with ! and says the way, and the screen come onto
says which way the one looked for stands.


## the chain

### every link says where it is found from the hub, the first, moved home, by the name of its screen there, and a want that lies, where it lies

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def links (List map rest (game-chain g)))
(def end (List ref (- (List length links) 1) links))
(def at (fn (_ q key) (pair (first (data-prop q key ())) (List ref 1 (data-prop q key ())))))
(def v (spec-game-on (spec-valley) 4 ()))
(write (list (List map (fn (_ q) (data-prop1 q 'found "")) links)
             (List all? (fn (_ q) (str=? (data-prop1 q 'found "") (chain-where v (game-hub v) (at q 'screen)))) (rest links))
             (str=? (data-prop1 end 'lies-found "") (chain-where v (game-hub v) (at end 'lies)))
             (List map (fn (_ q) (data-prop1 q 'lies-found "")) (List take (- (List length links) 1) links))))
```
---
    (("in the Square" "out in the farms, north of here" "up in the hills, south-east of here") #t #t ("" ""))


## the map

### in the town m names each district, which way it lies and who keeps a building there, and the errand not yet asked

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(spec-settle! g)
(game-key! g "m")
(write (List ref 3 (game-ask g)))
```
---
    ("     " "  @  " "     " "" "the Square, here: innkeeper" "the Pithead, north: engine-wright, smith" "the River End, south: miller, tanner" "the Terraces, east: chapel warden, baker" "Guild Street, west: councillor, deacon, chandler" "" "! The Guild clerk is asking for help: right here.")

### in the valley m says the band stood in and which way it lies from the town

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(def p (game-player g))
(game-creatures! g ())
(spec-settle! g)
(game-key! g "m")
(def hub (List drop 5 (List ref 3 (game-ask g))))
(spec-settle! g)
(player-at! p 0 40)
(game-key! g "k")
(spec-settle! g)
(game-creatures! g ())
(player-at! p 11 79)
(game-key! g "l")
(spec-settle! g)
(game-key! g "m")
(write (list hub (List drop 5 (List ref 3 (game-ask g)))))
```
---
    (("" "You are in Kettle." "" "! The Guild clerk is asking for help: right here.") ("" "You are in The Hills, north-east of Kettle." "" "! The Guild clerk is asking for help: just outside the town, south-west of here."))

### an errand asked marks the screen it leads to with ! and says the way there; from the town, the way is said from the town

```roguelike
(def v (spec-game-on (spec-valley) 4 ()))
(def links (List map rest (game-chain v)))
(def one (first links))
(def two (List ref 1 links))
(def before (list (quests-leads v) (quests-errands v)))
(game-quest-state! v (first one) 'open)
(def to (data-prop two 'screen ()))
(game-key! v "m")
(def rows (List ref 3 (game-ask v)))
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(game-quest-state! g (first (rest (first (game-chain g)))) 'open)
(write (list before (quests-leads v) (equal? (quests-leads v) (list (pair (first to) (List ref 1 to))))
             (Str8 sub (* 2 (first to)) 1 (List ref (List ref 1 to) rows)) (quests-errands v)
             (quests-leads g) (quests-errands g)))
```
---
    ((((3 . 2)) ("! The Guild clerk is asking for help: right here.")) ((3 . 1)) #t "!" ("! For the Guild clerk, a letter of the council: out in the farms, north of here.") () ("! For the Guild clerk, a letter of the council: out in the farms, north of here."))

### with the want in the pack the errand leads back to its giver; with the reward to choose, the same; over, nowhere

```roguelike
(def v (spec-game-on (spec-valley) 4 ()))
(def one (first (List map rest (game-chain v))))
(def want (List ref 1 (data-prop one 'wants ())))
(game-quest-state! v (first one) 'open)
(game-pack! v (pair (item-make (list 'token want) 1 0) (game-pack v)))
(def back (list (quests-leads v) (quests-errands v)))
(game-quest-state! v (first one) 'reward)
(def owes (quests-errands v))
(game-quest-state! v (first one) 'done)
(write (list back owes (quests-leads v) (quests-errands v)))
```
---
    ((((3 . 2)) ("! The Guild clerk is waiting for a letter of the council: right here.")) ("! The Guild clerk has something for you: right here.") () ())


## the screen come onto

### at the start the one asking is made out, and which way; a step away, nothing is said

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def name (List ref 2 (first (game-chain g))))
(def cr (List find (fn (_ c) (str=? (creature-name c) name)) (game-creatures g)))
(def made? (fn (_ t) ((fn (_ i) (if (null? i) #f (= i 0))) (Str8 index-of "You make out" t))))
(def said (List filter made? (game-log g)))
(spec-settle! g)
(def logged (List length (game-log g)))
(spec-beside! g cr)
(quests-sighted! g)
(write (list (List length said) (equal? 0 (Str8 index-of (Str8 append "You make out the " name " to the ") (first said))) (= logged (List length (game-log g)))))
```
---
    (1 #t #t)

### on the screen an open errand leads to, the giver there is made out; on the one its want lies on, the thing, or the one who has it

```roguelike
(def v (spec-game-on (spec-valley) 4 ()))
(def p (game-player v))
(def links (List map rest (game-chain v)))
(def end (List ref (- (List length links) 1) links))
(List for-each (fn (_ q) (game-quest-state! v (first q) 'open)) links)
(def walk!
  (fn (self x y)
    (def here (game-screen v))
    (def dx (- x (first here)))
    (def dy (- y (rest here)))
    (unless (if (= dx 0) (= dy 0) #f)
      (do (spec-settle! v)
          (if (= dx 0)
            (do (player-at! p (if (< dy 0) 0 21) 40) (game-key! v (if (< dy 0) "k" "j")))
            (do (player-at! p 11 (if (< dx 0) 0 79)) (game-key! v (if (< dx 0) "h" "l"))))
          (self x y)))))
(def said (fn (_ name) (List filter (fn (_ t) (not (null? (Str8 index-of name t)))) (List take 3 (game-log v)))))
(def two (List ref 1 links))
(walk! (first (data-prop two 'screen ())) (List ref 1 (data-prop two 'screen ())))
(def person (said (List ref 1 two)))
(walk! (first (data-prop end 'lies ())) (List ref 1 (data-prop end 'lies ())))
(write (list person (said (List ref 1 (data-prop end 'wants ())))))
```
---
    (("You make out the town surveyor to the north-west.") ("You make out a pair of hobnailed boots to the east."))


## saving

### a game saved in the town brings its chain back whole: the first link's region, and where each is found

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(spec-settle! g)
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "kettle") 24 80))
(File unlink path)
(write (list ((fn (_ w) (str=? (w (game-chain g)) (w (game-chain h)))) (prim-ref (lit io) (lit write-to-str)))
             (data-prop1 (rest (first (game-chain h))) 'region "") (quests-errands h)))
```
---
    (#t "town" ("! The Guild clerk is asking for help: right here."))
