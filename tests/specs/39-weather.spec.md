# Weather
# @weight 3

roguelike/state: the world of a set with `(weather HOURS (KIND WEIGHT
SHIFT . PROPS) ...)` has a spell of weather each HOURS on the game's
clock, drawn from the seed, and with `(temperature LOW HIGH PEAK)` a
temperature on the hour, the weather's SHIFT on it.  Under the sky the
weather limits sight and is told and heard, the cold and the heat burn
food and the chill costs hit points; the people of the streets shelter
from it under a roof and speak of it (see `README.md`).

## the spells

### the valley's skies by the spell from three in the afternoon, the same for the same seed, with the hour's degrees; the Delve has neither

```roguelike
(def w39-at (fn (_ g s) (game-clock! g s) (list (game-hour g) (game-weather g) (game-temperature g))))
(def w39-skies (fn (_ g) (List map (fn (_ s) (w39-at g (* s 10800))) '(0 1 2 3 5))))
(def w39-g (spec-game-on (spec-valley) 4 ()))
(def w39-d (spec-game-on (spec-set-named "delve") 4 ()))
(write (list (w39-skies w39-g) (equal? (w39-skies w39-g) (w39-skies (spec-game-on (spec-valley) 4 ())))
             (list (game-weather w39-d) (game-temperature w39-d))))
```
---
    (((15 'cloud 21) (18 'storm 13) (21 'clear 18) (0 'rain 8) (6 'rain 1)) #t (() ()))

## under the sky

### a storm coming on is told and heard by its key, sight falls to its view, and the storm is heard over the band; its air is a song and sounds of the world

```roguelike
(import roguelike/sound sound-places)
(import roguelike/state game-said)
(def g (spec-game-on (spec-valley) 4 ()))
(def m (game-map g))
(def w39-lit (fn (_) (List fold (fn (_ a r) (+ a (List count-if (fn (_ c) (map-visible? m r c)) (List range 0 (map-cols m))))) 0 (List range 0 (map-rows m)))))
(game-creatures! g ())
(spec-settle! g)
(def w39-before (list (game-daylight? g) (w39-lit) (sound-places g)))
(game-clock! g 10795)
(game-key! g ".")
(def w39-k (spec-set-named "kettle"))
(def w39-air (List find (fn (_ a) (str=? (first a) "storm")) (data-all w39-k 'ambience)))
(def w39-named? (fn (_ head n) (List any? (fn (_ f) (str=? (first f) n)) (data-all w39-k head))))
(write (list w39-before
             (list (game-weather g) (game-daylight? g) (< (w39-lit) 50) (sound-places g)
                   (List any? (fn (_ s) (str=? s "A storm breaks over the valley.")) (game-messages g))
                   (List includes? 'storm (game-said g)))
             (w39-named? 'song (List ref 1 (List find (fn (_ p) (if (pair? p) (eq? (first p) 'bed) #f)) (rest w39-air))))
             (List all? (fn (_ p) (w39-named? 'sound (List ref 1 p)))
                        (List filter (fn (_ p) (if (pair? p) (eq? (first p) 'random) #f)) (rest w39-air)))))
```
---
    ((#t 1760 ("Kettle")) ('storm #f #t ("storm" "Kettle") #t #t) #t #t)

### a turn's food burns at its rate in the mild afternoon, half again in the cold of a rainy dawn, and a quarter again in the next afternoon's heat

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(def p (game-player g))
(game-creatures! g ())
(def w39-burn (fn (_ s) (game-clock! g s) (player-food! p 40000) (game-key! g ".") (- 40000 (player-food p))))
(write (List map (fn (_ s) (list (game-temperature (do (game-clock! g s) g)) (w39-burn s))) '(0 54000 86400)))
```
---
    ((21 15) (1 22) (24 18))

### under the chill's mark a turn at its count tells the cold; in the mild afternoon nothing

```roguelike
(import roguelike/state state-clear-messages!)
(def w39-set (List map (fn (_ f) (if (if (pair? f) (eq? (first f) 'chill) #f) (list 'chill 2 (List ref 2 f)) f)) (spec-valley)))
(def g (spec-game-on w39-set 4 ()))
(def p (game-player g))
(game-creatures! g ())
(def w39-every (List ref 2 (List find (fn (_ f) (if (pair? f) (eq? (first f) 'chill) #f)) (spec-valley))))
(def w39-turn (fn (_ s)
                (game-clock! g s)
                (state-clear-messages! g)
                (game-key! g ".")
                (list (game-temperature g) (List any? (fn (_ m) (str=? m "You are chilled to the bone.")) (game-messages g)))))
(write (list (w39-turn 0) (w39-turn (- 54000 (+ (% 54000 w39-every) 1)))))
```
---
    ((21 #f) (1 #t))

## the people of the streets

### in a storm one who strolls goes under a roof within a hundred turns and stays there; when it clears they come out again

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(def m (game-map g))
(def walker (List find (fn (_ c) (str=? (creature-name c) "carrier")) (game-creatures g)))
(def w39-in? (fn (_) (< 0 (map-roof-at m (creature-r walker) (creature-c walker)))))
(def w39-walk (fn (_ n) (List map (fn (_ k) (game-key! g ".") (spec-settle! g) (when (= 0 (% k 10)) (Heap collect)) (w39-in?)) (List range 0 n))))
(def w39-start (w39-in?))
(game-clock! g 10800)
(def w39-storm (w39-walk 150))
(game-clock! g 21600)
(def w39-clear (w39-walk 150))
(write (list w39-start (game-weather g)
             (List any? (fn (_ x) x) (List take 100 w39-storm)) (List all? (fn (_ x) x) (List drop 100 w39-storm))
             (List any? not w39-clear)))
```
---
    (#f 'clear #t #t #t)

### walked into in a storm, one of the people of the streets has the world's word on it among their lines

```roguelike
(def g (spec-game-on (spec-set-named "kettle") 4 ()))
(game-clock! g 10800)
(def walker (List find (fn (_ c) (str=? (creature-name c) "water-carrier")) (game-creatures g)))
(def w39-said (fn (_)
                (game-key! g (spec-beside! g walker))
                (def line (first (List ref 3 (game-ask g))))
                (spec-settle! g)
                line))
(def w39-lines (List map (fn (_ k) (w39-said)) (List range 0 4)))
(write (List includes? "Get in out of it, you fool!" w39-lines))
```
---
    #t

### v gives the weather's name and the degrees on a line after the hour's

```roguelike
(def g (spec-game-on (spec-valley) 4 ()))
(game-clock! g 10800)
(game-key! g "v")
(write (List filter (fn (_ s) (not (null? (Str8 index-of "degrees" s)))) (List ref 3 (game-ask g))))
```
---
    ("A storm, 13 degrees.")
