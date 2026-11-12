# Buildings
# @weight 2

roguelike/dungeon: a town level lays the buildings it names round its
square and keeps them as the level's named places: (building NAME (size
W D) . PROPS), a box, walled, its one door toward the square; or
(building NAME (plan "ROW" ...) . PROPS), put together a cell a
character, as it is drawn.  A building's door, stood on, says its
(enter "TEXT").  Every building, and every house of a terrace, is under
a roof: drawn as roof from outside, all but its doors, and open to the
eye, whole, from inside.  The town set's districts each name theirs.


## the plans

### each of the town's districts lays every building it names, in order, every door and yard reached from the street

```roguelike
(def town (data-region (spec-set-named "kettle") "town"))
(def laid
  (fn (_ s)
    (def m (spec-level-on (List append (rest (rest s)) town) 3 0))
    (list (first s) (List map first (map-places m)) (spec-connected? m))))
(write (List map laid (data-all town 'screen)))
```
---
    (("the Square" ("the council house" "the inn" "the pump-house") #t) ("the Pithead" ("the engine house" "the boiler house" "the smithy") #t) ("the River End" ("the mill" "the tannery" "the ropewalk") #t) ("the Terraces" ("the chapel" "the bakehouse") #t) ("Guild Street" ("the Guild hall" "the White Church" "the Guild's shop" "the chandler's") #t))

### a town that names no buildings is drawn as it was, with no places; a building of a size is a box, walled, with one door

```roguelike
(def on-wall (fn (_ m p tile)
  (def r0 (List ref 1 p))
  (def c0 (List ref 2 p))
  (def r1 (List ref 3 p))
  (def c1 (List ref 4 p))
  (%spec-count m (fn (_ r c) (if (= (map-tile m r c) tile)
                               (if (if (< (- r0 1) r) (if (< r (+ r1 1)) (if (< (- c0 1) c) (< c (+ c1 1)) #f) #f) #f)
                                 (match ((= r r0) #t) ((= r r1) #t) ((= c c0) #t) (#t (= c c1)))
                                 #f)
                               #f)))))
(def whole? (fn (_ m p)
  (def side (fn (_ a b) (+ 1 (- (List ref b p) (List ref a p)))))
  (if (= 1 (on-wall m p tile-door)) (= (on-wall m p tile-wall) (- (* 2 (+ (side 1 3) (side 2 4))) 5)) #f)))
(def plain '((level-style town) (square 30 12)))
(def built (pair '(building "the shed" (size 8 9)) plain))
(def m (spec-level-on plain 3 0))
(def shed (spec-level-on built 3 0))
(write (list (map-places m) (List map first (map-places shed)) (whole? shed (first (map-places shed)))))
```
---
    (() ("the shed") #t)

### a plan is laid as it is drawn: walls, floors and doors, a blank left as street, a character of its own the terrain its cell names; all of it under the roof but the cells open to the sky

```roguelike
(def b23-set '((level-style town) (square 30 12) (cell "~" water open)
  (building "the mill" (cell "," floor open)
    (plan "#####  "
          "#...#,,"
          "#...+,~"
          "#.#.#"
          "#####"))))
(def b23-m (spec-level-on b23-set 3 0))
(def b23-p (first (map-places b23-m)))
(def b23-grid
  (fn (_ f)
    (List map (fn (_ r) (List map (fn (_ c) (f r c)) (List range (List ref 2 b23-p) (+ (List ref 4 b23-p) 1))))
      (List range (List ref 1 b23-p) (+ (List ref 3 b23-p) 1)))))
(write (list (first b23-p)
             (b23-grid (fn (_ r c) (map-tile b23-m r c)))
             (b23-grid (fn (_ r c) (if (< 0 (map-roof-at b23-m r c)) 1 0)))
             (list tile-wall tile-floor tile-door tile-water)))
```
---
    ("the mill" ((2 2 2 2 2 1 1) (2 1 1 1 2 1 1) (2 1 1 1 3 1 7) (2 1 2 1 2 1 1) (2 2 2 2 2 1 1)) ((1 1 1 1 1 0 0) (1 1 1 1 1 0 0) (1 1 1 1 1 0 0) (1 1 1 1 1 0 0) (1 1 1 1 1 0 0)) (2 1 3 7))

### a plan's character that names nothing, and a cell that names no terrain, are errors

```roguelike
(def b23-bad (fn (_ forms) (guard (e (if (Err err? e) (e msg) 'other)) (do (spec-level-on (pair '(level-style town) forms) 3 0) 'laid))))
(write (list (b23-bad '((building "a" (plan "#?#"))))
             (b23-bad '((cell "?" lava) (building "a" (plan "#?#"))))
             (b23-bad '((cell "?" water) (building "a" (plan "#?#"))))))
```
---
    ("a plan's character is #, ., +, a blank or a (cell ...)" "a plan's cell is a kind of terrain" 'laid)


## the door

### a building's door, stood on, says the building's line; inside it is a floor

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def p (game-player g))
(game-creatures! g ())
(def m (game-map g))
(def inn (List find (fn (_ pl) (str=? (first pl) "the inn")) (map-places m)))
(def r (+ (List ref 1 inn) 2))
(def c (List ref 4 inn))
(player-at! p r (+ c 1))
(game-key! g "h")
(def at-door (list (player-r p) (player-c p) (= (map-tile m r c) tile-door) (game-messages g)))
(game-key! g "h")
(write (list at-door (= (map-tile m (player-r p) (player-c p)) tile-floor) (first (map-place-at m (player-r p) (player-c p)))))
```
---
    ((13 15 #t ("The inn: carriers' talk, and stables for the packhorse trains.")) #t "the inn")


## the roof

### from the street a building is drawn as roof, all but the doors into it, and whoever is in it is not drawn; from its door the roof is off and the whole of it shows; out again, the roof is back

```roguelike
(def b23-g (spec-game-on (spec-set-named "kettle") 4 ()))
(def b23-gm (game-map b23-g))
(def b23-inn (List find (fn (_ pl) (str=? (first pl) "the inn")) (map-places b23-gm)))
(def b23-rows
  (fn (_)
    (def screen (spec-screen b23-g))
    (List map (fn (_ r) (Str8 sub (List ref 2 b23-inn) 13 (List ref (+ r 1) screen)))
      (List range (List ref 1 b23-inn) (+ (List ref 1 b23-inn) 5)))))
(player-at! (game-player b23-g) (+ (List ref 1 b23-inn) 2) (+ (List ref 4 b23-inn) 2))
(game-key! b23-g "h")
(def b23-out (list (b23-rows) (map-roof-off b23-gm)))
(game-key! b23-g "h")
(def b23-in (list (b23-rows) (< 0 (map-roof-off b23-gm))))
(game-key! b23-g "l")
(write (list b23-out b23-in (b23-rows)))
```
---
    ((("^^^^^^^^^^^^^" "^^^^^^^^^^^^^" "^^^^^^^^^^^^+" "^^^^^^^^^^^^^" "^^^+^^^^^^^^^") 0) (("#############" "#&....#.....#" "#_....+.....@" "#.....#.....#" "###+#########") #t) ("^^^^^^^^^^^^^" "^^^^^^^^^^^^^" "^^^^^^^^^^^^+" "^^^^^^^^^^^^^" "^^^+^^^^^^^^^"))

### each house of a terrace is under a roof of its own, its walls and its door with it, and the street under none

```roguelike
(def b23-t (dungeon-generate (Random sw 5) 22 80 0 '((level-style town) (square 14 8))))
(def b23-all (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range 0 80))) (List range 0 22)))
(def b23-id (fn (_ at) (map-roof-at b23-t (first at) (rest at))))
(def b23-is? (fn (_ at t) (= (map-tile b23-t (first at) (rest at)) t)))
(def b23-doors (List filter (fn (_ at) (b23-is? at tile-door)) b23-all))
(def b23-floors
  (fn (_ at want?)
    (List count-if (fn (_ d) ((fn (_ q) (if (b23-is? q tile-floor) (want? (b23-id q)) #f)) (pair (+ (first at) (first d)) (+ (rest at) (rest d)))))
      (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1)))))
(def b23-ids (List fold (fn (_ ids at) (if (List includes? (b23-id at) ids) ids (pair (b23-id at) ids))) () b23-doors))
(write (list (List all? (fn (_ at) (< 0 (b23-id at))) (List filter (fn (_ at) (if (b23-is? at tile-wall) #t (b23-is? at tile-door))) b23-all))
             (List all? (fn (_ at) (= 1 (b23-floors at (fn (_ id) (= id (b23-id at)))))) b23-doors)
             (List all? (fn (_ at) (= 1 (b23-floors at (fn (_ id) (= id 0))))) b23-doors)
             (= (List length b23-ids) (List length b23-doors))))
```
---
    (#t #t #t #t)

### a roof is peaked along its longer side: a far slope, a ridge and a near slope, or a west slope, a ridge and an east slope; a ridge with no middle row lies to the north

```roguelike
(import roguelike/map map-make map-roof! map-roof-pitch)
(def b23-pm (map-make 12 20))
(def b23-box! (fn (_ id r0 c0 h w) (List for-each (fn (_ r) (List for-each (fn (_ c) (map-roof! b23-pm r c id)) (List range c0 (+ c0 w)))) (List range r0 (+ r0 h)))))
(def b23-down (fn (_ c r0 h) (List map (fn (_ r) (map-roof-pitch b23-pm r c)) (List range r0 (+ r0 h)))))
(def b23-along (fn (_ r c0 w) (List map (fn (_ c) (map-roof-pitch b23-pm r c)) (List range c0 (+ c0 w)))))
(b23-box! 1 1 1 5 7)
(b23-box! 2 1 9 4 6)
(b23-box! 3 6 1 6 3)
(def b23-first (list (b23-down 3 1 5) (b23-down 10 1 4) (b23-along 8 1 3) (map-roof-pitch b23-pm 0 0)))
(b23-box! 3 6 4 6 6)
(write (list b23-first (b23-down 5 6 6)))
```
---
    (((1 1 2 3 3) (1 2 3 3) (4 5 6) 0) (1 1 2 3 3 3))

### in the window a roofed cell takes the roof's pictures: the slope it is on with the rims at the roof's edge, and its front where the street lies south; a door in the front is a doorway in it, a door on another side is roof; a dormer in the roof over each door, facing the way it opens; a stoop on the ground outside each door, on the side it opens to; inside, the cell's own

```roguelike
(import roguelike/frame frame-art frame-cell)
(import roguelike/map map-seen!)
(def b23-art (frame-art (data-load "data/town/art") "Kettle"))
(def b23-pics
  (fn (_ r c)
    (List map (fn (_ op) (list (first (List ref 3 op)) (first (rest (List find (fn (_ x) (if (pair? x) (eq? (first x) 'part) #f)) (List append (rest (List ref 3 op)) (list '(part ()))))))))
      (frame-cell b23-art b23-gm r c 0 0))))
(def b23-r (List ref 1 b23-inn))
(def b23-c (List ref 2 b23-inn))
(def b23-roofed (List map (fn (_ dr) (b23-pics (+ b23-r dr) (+ b23-c 6))) (List range 0 5)))
(def b23-verge (b23-pics (+ b23-r 1) b23-c))
(def b23-doors (list (b23-pics (+ b23-r 4) (+ b23-c 3)) (b23-pics (+ b23-r 2) (+ b23-c 12))))
(def b23-dormers (list (b23-pics (+ b23-r 3) (+ b23-c 3)) (b23-pics (+ b23-r 3) (+ b23-c 5))))
(def b23-roof-ops (fn (_ r c) (map-seen! b23-gm r c) (List filter (fn (_ x) (eq? (first x) 'roof)) (b23-pics r c))))
(def b23-stoops (list (b23-roof-ops (+ b23-r 5) (+ b23-c 3)) (b23-roof-ops (+ b23-r 2) (+ b23-c 13)) (b23-roof-ops (+ b23-r 5) (+ b23-c 5))))
(game-key! b23-g "h")
(write (list b23-roofed b23-verge b23-doors b23-dormers b23-stoops (b23-pics (+ b23-r 2) (+ b23-c 3))))
```
---
    (((('roof 'north) ('roof 'n)) (('roof 'north)) (('roof 'ridge)) (('roof 'top)) (('roof 'face))) (('roof 'north) ('roof 'w)) ((('roof 'face) ('roof 'doorway)) (('roof 'ridge) ('roof 'e) ('roof 'dormer-e))) ((('roof 'top) ('roof 'dormer)) (('roof 'top))) ((('roof 'stoop-s)) (('roof 'stoop-e)) ()) (('floor ())))

### the front of a roof running north and south is its gable: the peak under the ridge, a rake either side of it, a low end beyond; a roof two wide has its peak and one rake

```roguelike
(import roguelike/map map-seen!)
(b23-box! 4 6 11 6 5)
(b23-box! 5 6 17 6 2)
(List for-each (fn (_ c) (map-seen! b23-pm 11 c)) (List range 0 20))
(def b23-front
  (fn (_ c0 w)
    (List map (fn (_ c) (List ref 1 (first (rest (List ref 3 (first (frame-cell b23-art b23-pm 11 c 0 0))))))) (List range c0 (+ c0 w)))))
(write (list (b23-front 11 5) (b23-front 17 2) (b23-front 1 2)))
```
---
    (('gable-ww 'gable-w 'gable 'gable-e 'gable-ee) ('gable 'gable-e) ('face 'face))


## kept

### a district's buildings and their roofs are kept in a save and read back

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def before (map-places (game-map g)))
(def b23-sum (fn (_ m) (List fold (fn (_ n at) (+ n (* (+ 1 (rest at)) (map-roof-at m (first at) (rest at))))) 0 b23-all)))
(def tmp (File temp "/tmp/x-roguelike-"))
(File close (first tmp))
(def path (rest tmp))
(save-write! g path)
(def h (save-read path (spec-set-named "kettle") 24 80))
(File unlink path)
(write (list (List length before) (= (List length before) (List length (map-places (game-map h))))
             (List all? (fn (_ a) (List any? (fn (_ b) (if (str=? (first a) (first b)) (= (List ref 1 a) (List ref 1 b)) #f)) (map-places (game-map h)))) before)
             (< 0 (b23-sum (game-map g))) (= (b23-sum (game-map g)) (b23-sum (game-map h)))))
```
---
    (3 #t #t #t #t)
