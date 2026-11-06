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
; (chance PERCENT) comes up, the first of the set's interiors to do so,
; one door a screen at most.  The door is a way in, > on it; the
; interior's level is made by its own forms before the set's, so any
; knob it names -- (level-style ...), rooms when it names none, (rooms
; LO HI), (lit ...), (creatures LO HI), (items LO HI) -- is its own,
; and it has a way out, < on it, and no way further down.  Its (enter
; "TEXT") is said the first time in.  What goes in and out, and what is
; kept, is the game's (see game.x).

(module roguelike/interiors)

(import roguelike/data data-all)
(import roguelike/map map-rows map-cols map-set! map-down! tile-down)
(import roguelike/dungeon dungeon-spot)
(import roguelike/state
  game-rng game-set game-depth game-map game-door! game-level-key
  state-covers? state-chance? state-free? state-items-at)

; The set's interior named NAME, (NAME . PROPS), or nil.
(def %in-named (fn (_ g name) (List find (fn (_ f) (str=? (first f) name)) (data-all (game-set g) (lit interior)))))
; The values of F's (KEY ...), or DEFAULT.
(def %in-prop (fn (_ f key default) (def p (Assoc find key (rest f))) (if (null? p) default (rest p))))

; The first value of the (KEY ...) of the interior NAME, or DEFAULT.
(def interiors-prop1
  (fn (_ g name key default)
    (def f (%in-named g name))
    (if (null? f) default (first (%in-prop f key (list default))))))

; The forms the interior NAME's level is made by: its own, then (stairs
; up) and (level-style rooms), then the set's.  Open ground has no way
; out, so an interior that names no style is rooms.
(def interiors-params
  (fn (_ g name)
    (def f (%in-named g name))
    (List append (if (null? f) () (rest f))
      (list (list (lit stairs) (lit up)) (list (lit level-style) (lit rooms)))
      (game-set g))))

; On a screen just made, a door to the first interior whose depth
; covers it and whose chance comes up: the stairs down on a free cell
; off the outer ring, the interior's name kept under the screen's key.
(def interiors-door!
  (fn (_ g)
    (def m (game-map g))
    (def pick
      (List find
        (fn (_ f) (if (state-covers? (%in-prop f (lit depth) (list 1 99)) (game-depth g))
                    (state-chance? (game-rng g) (first (%in-prop f (lit chance) (list 0))))
                    #f))
        (data-all (game-set g) (lit interior))))
    (def inner?
      (fn (_ r c)
        (match ((< r 1) #f) ((< c 1) #f) ((< (- (map-rows m) 2) r) #f) ((< (- (map-cols m) 2) c) #f)
               ((not (state-free? g r c)) #f)
               (#t (null? (state-items-at g r c))))))
    (def at (if (null? pick) () (dungeon-spot (game-rng g) m inner? 100)))
    (unless (null? at)
      (do (map-set! m (first at) (rest at) tile-down)
          (map-down! m at)
          (game-door! g (game-level-key g) (first pick))))))

(provide roguelike/interiors interiors-door! interiors-params interiors-prop1)
