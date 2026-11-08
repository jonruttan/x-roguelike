; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/interiors.x -- the places behind doors in a world of screens
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A set's (interior NAME . PROPS) is a place behind a door: a screen
; made at a depth its (depth LO HI) covers lays a door to it when its
; (chance PERCENT) comes up, the first of the interiors to do so, one
; door a screen at most; a named screen's own interiors come first.
; The door is a way in, > on it; the
; interior's level is made by its own forms before the set's, so any
; knob it names -- (level-style ...), rooms when it names none, (rooms
; LO HI), (lit ...), (creatures LO HI), (items LO HI) -- is its own,
; and it has a way out, < on it, and no way further down.  Its (enter
; "TEXT") is said the first time in.  One with (region NAME) has no
; level of its own: its door goes into the world's region NAME.  What
; goes in and out, and what is kept, is the game's (see game.x).

(module roguelike/interiors)

(import roguelike/data data-all data-one data-get data-region)
(import roguelike/map
  map-rows map-cols map-set! map-down! map-each! map-walkable? map-fill-unreached! map-place-at
  tile-down tile-floor tile-wall tile-thicket)
(import roguelike/dungeon dungeon-spot)
(import x/core/doors int/)
(import roguelike/scale scale-rung scale-across scale-down)
(import roguelike/state
  game-rng game-set game-forms game-depth game-map game-door! game-level-key game-top-set
  game-player player-r player-c player-at! state-covers? state-chance? state-free? state-items-at)

; The set's interior named NAME, (NAME . PROPS), or nil.
(def %in-named (fn (_ g name) (List find (fn (_ f) (str=? (first f) name)) (data-all (game-forms g) (lit interior)))))
; The values of F's (KEY ...), or DEFAULT.
(def %in-prop (fn (_ f key default) (def p (Assoc find key (rest f))) (if (null? p) default (rest p))))

; The first value of the (KEY ...) of the interior NAME, or DEFAULT.
(def interiors-prop1
  (fn (_ g name key default)
    (def f (%in-named g name))
    (if (null? f) default (first (%in-prop f key (list default))))))

; The forms the interior NAME's level is made by: its own, then (stairs
; up), (level-style rooms) and (scale 1), then the set's.  Open ground
; has no way out, so an interior that names no style is rooms; and it
; is a place a person walks about in, so one that names no scale is at
; 1, whatever the ground outside is drawn at.
(def interiors-params
  (fn (_ g name)
    (def f (%in-named g name))
    (List append (if (null? f) () (rest f))
      (list (list (lit stairs) (lit up)) (list (lit level-style) (lit rooms)) (list (lit scale) 1))
      (game-set g))))

; The ground the region NAME covers on M, (W . H) cells at this level's
; scale, when it is a world of screens, each as many cells as M at the
; region's own scale, and it fits with three cells to spare all round;
; else nil.
(def %in-ground
  (fn (_ g m name)
    (def region (data-region (game-top-set g) name))
    (def world (if (null? region) () (data-one region (lit world) ())))
    (if (if (null? world) #t (not (eq? (first world) (lit screens)))) ()
      (do (def there (scale-rung (data-get region (lit scale) 1)))
          (def here (scale-rung (data-get (game-forms g) (lit scale) 1)))
          (def w (scale-across here (* (List ref 1 world) (* (map-cols m) (first there)))))
          (def h (scale-down here (* (List ref 2 world) (* (map-rows m) (rest there)))))
          (if (if (< (+ w 6) (map-cols m)) (< (+ h 6) (map-rows m)) #f) (pair w h) ())))))
; The region's ground, SIZE, walled in the middle of M, its door on the
; west face on the middle row and the cell before it open; ground cut
; off from that cell is filled, and the player, walled in, stands on it.
; The door's cell, (R . C).
(def %in-place!
  (fn (_ g m size)
    (def mid (int/ (map-rows m) 2))
    (def r0 (- mid (int/ (rest size) 2)))
    (def c0 (int/ (- (map-cols m) (first size)) 2))
    (def p (game-player g))
    (map-each! r0 c0 (+ r0 (- (rest size) 1)) (+ c0 (- (first size) 1)) (fn (_ r c) (map-set! m r c tile-wall)))
    (map-set! m mid (- c0 1) tile-floor)
    (map-fill-unreached! m mid (- c0 1) tile-thicket)
    (unless (map-walkable? m (player-r p) (player-c p)) (player-at! p mid (- c0 1)))
    (pair mid c0)))

; On a screen just made, a door to the first interior whose depth
; covers it and whose chance comes up: the stairs down on a free cell
; off the outer ring and out of any building, the interior's name kept
; under the screen's key.
; A door into a region that is a world of screens is laid in the
; region's own ground, drawn at its size when it fits (%in-ground).
(def interiors-door!
  (fn (_ g)
    (def m (game-map g))
    (def pick
      (List find
        (fn (_ f) (if (state-covers? (%in-prop f (lit depth) (list 1 99)) (game-depth g))
                    (state-chance? (game-rng g) (first (%in-prop f (lit chance) (list 0))))
                    #f))
        (data-all (game-forms g) (lit interior))))
    (def inner?
      (fn (_ r c)
        (match ((< r 1) #f) ((< c 1) #f) ((< (- (map-rows m) 2) r) #f) ((< (- (map-cols m) 2) c) #f)
               ((not (state-free? g r c)) #f)
               ((not (null? (map-place-at m r c))) #f)
               (#t (null? (state-items-at g r c))))))
    (def ground (if (null? pick) () (%in-ground g m (first (%in-prop pick (lit region) (list ""))))))
    (def at (match ((null? pick) ()) ((not (null? ground)) (%in-place! g m ground)) (#t (dungeon-spot (game-rng g) m inner? 100))))
    (unless (null? at)
      (do (map-set! m (first at) (rest at) tile-down)
          (map-down! m at)
          (game-door! g (game-level-key g) (first pick))))))

(provide roguelike/interiors interiors-door! interiors-params interiors-prop1)
