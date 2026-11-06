; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/creatures.x -- what lives on a level, and what it does each turn
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A level is peopled from the set's creatures whose (depth LO HI) covers
; it, each put out of view, most of them asleep.  Each turn a sleeping
; creature may wake when the player is close; an awake one strikes when
; adjacent and otherwise steps toward the player, a fleeing one away; a
; stationary one waits; an erratic one wanders half the time; one that
; talks does nothing at all.  Traits read here: wakeful, fast, slow,
; regen, stationary, erratic, invisible, breath, skittish, talks.  A fast creature takes two turns in one; a slow one,
; every other; so does one slowed by a wand.  A creature held by a
; scroll does nothing.

(module roguelike/creatures)

(import x/type/vector)
(import x/core/doors int/)
(import roguelike/data data-all data-prop data-prop1 data-trait?)
(import roguelike/map map-visible? map-tile map-down tile-door)
(import roguelike/dungeon dungeon-spot)
(import roguelike/state
  game-rng game-set game-depth game-map game-player game-creatures game-creatures! game-turn game-param1
  player-r player-c player-condition
  creature-make creature-r creature-c creature-at! creature-hp creature-hp! creature-state creature-state!
  creature-carried creature-name creature-prop creature-prop1 creature-trait? creature-condition creature-tick!
  state-say! state-tell! state-roll state-chance? state-dirs state-dist state-adjacent? state-sign state-free?
  state-ring?)
(import roguelike/combat combat-creature-attacks! combat-hurt-player!)

; --- spawning ----------------------------------------------------------------

(def %cr-covers? (fn (_ d depth) (if (< depth (first d)) #f (not (< (List ref 1 d) depth)))))
; The set's kinds for DEPTH.
(def creatures-kinds
  (fn (_ g depth)
    (List filter (fn (_ k) (%cr-covers? (data-prop k (lit depth) (list 1 99)) depth)) (data-all (game-set g) (lit creature)))))

(def %cr-hp
  (fn (_ g kind)
    (def d (data-prop kind (lit hp) (list 1 6)))
    (state-roll (game-rng g) (first d) (List ref 1 d))))
(def %cr-hp-most (fn (_ cr) (List ref 1 (creature-prop cr (lit hp) (list 1 6)))))

; How a new creature of KIND starts: awake when asked, when wakeful, or
; by a chance of two in five.
(def %cr-start
  (fn (_ g kind awake?)
    (match (awake? (lit awake))
           ((data-trait? kind (lit wakeful)) (lit awake))
           ((state-chance? (game-rng g) 60) (lit asleep))
           (#t (lit awake)))))

(def %cr-around
  (list (pair -1 -1) (pair -1 0) (pair -1 1) (pair 0 -1) (pair 0 1) (pair 1 -1) (pair 1 0) (pair 1 1)))

; A creature of KIND at R C in STATE: the one, or, for a kind with
; (pack LO HI), that many at most, the rest on free cells around it.
(def creatures-place!
  (fn (_ g kind r c state)
    (def pack (data-prop kind (lit pack) ()))
    (def more (if (null? pack) 0 (- (state-roll (game-rng g) (first pack) (List ref 1 pack)) 1)))
    (game-creatures! g (pair (creature-make kind r c (%cr-hp g kind) state) (game-creatures g)))
    ((fn (self dirs n)
       (unless (if (null? dirs) #t (< n 1))
         (do (def rr (+ r (first (first dirs))))
             (def cc (+ c (rest (first dirs))))
             (if (state-free? g rr cc)
               (do (game-creatures! g (pair (creature-make kind rr cc (%cr-hp g kind) state) (game-creatures g)))
                   (self (rest dirs) (- n 1)))
               (self (rest dirs) n)))))
     ((game-rng g) shuffle %cr-around) more)))

; One creature of the depth, out of view, AWAKE? or as it comes.
(def creatures-spawn-one!
  (fn (_ g awake?)
    (def kinds (creatures-kinds g (game-depth g)))
    (unless (null? kinds)
      (do (def kind ((game-rng g) choice kinds))
          (def at (dungeon-spot (game-rng g) (game-map g)
                    (fn (_ r c) (if (state-free? g r c) (not (map-visible? (game-map g) r c)) #f)) 100))
          (unless (null? at)
            (creatures-place! g kind (first at) (rest at) (%cr-start g kind awake?)))))))

(def creatures-spawn!
  (fn (self g n awake?) (unless (< n 1) (do (creatures-spawn-one! g awake?) (self g (- n 1) awake?)))))

; The set's kind named NAME, or nil.
(def creatures-kind
  (fn (_ g name) (List find (fn (_ k) (str=? (first k) name)) (data-all (game-set g) (lit creature)))))

; A guardian: the kind named NAME put on a free cell beside the stairs
; down, or anywhere with none free, asleep unless wakeful.
(def creatures-guardian!
  (fn (_ g name)
    (def kind (creatures-kind g name))
    (def down (map-down (game-map g)))
    (def beside (List find (fn (_ d) (state-free? g (+ (first down) (first d)) (+ (rest down) (rest d))))
                  ((game-rng g) shuffle %cr-around)))
    (def at (if (null? beside) (dungeon-spot (game-rng g) (game-map g) (fn (_ r c) (state-free? g r c)) 100)
              (pair (+ (first down) (first beside)) (+ (rest down) (rest beside)))))
    (unless (if (null? kind) #t (null? at))
      (creatures-place! g kind (first at) (rest at) (if (data-trait? kind (lit wakeful)) (lit awake) (lit asleep))))))

; Now and then a creature arrives on the level, awake: one chance in the
; set's (wander N) a turn.
(def creatures-wander!
  (fn (_ g) (when (= 0 ((game-rng g) int (game-param1 g (lit wander) 60))) (creatures-spawn-one! g #t))))

; --- moving ------------------------------------------------------------------

; A doorway is passed straight through, never on the diagonal.
(def creatures-door-diagonal?
  (fn (_ m r c dr dc)
    (match ((= dr 0) #f) ((= dc 0) #f)
           ((= (map-tile m r c) tile-door) #t)
           ((= (map-tile m (+ r dr) (+ c dc)) tile-door) #t)
           (#t #f))))
(def creatures-can-step?
  (fn (_ g r c dr dc)
    (if (creatures-door-diagonal? (game-map g) r c dr dc) #f (state-free? g (+ r dr) (+ c dc)))))

; CR moved by the first of DIRS, (DR . DC) each, that it can take.
(def %cr-step-first!
  (fn (_ g cr dirs)
    (def hit (List find (fn (_ d)
                          (match ((= (first d) 0) (if (= (rest d) 0) #f (creatures-can-step? g (creature-r cr) (creature-c cr) 0 (rest d))))
                                 (#t (creatures-can-step? g (creature-r cr) (creature-c cr) (first d) (rest d)))))
                        dirs))
    (unless (null? hit) (creature-at! cr (+ (creature-r cr) (first hit)) (+ (creature-c cr) (rest hit))))))

; The ways to try to get DR DC closer: straight, then along either axis,
; then a sidestep.
(def %cr-ways
  (fn (_ dr dc)
    (list (pair dr dc) (pair dr 0) (pair 0 dc) (pair dr 1) (pair dr -1) (pair 1 dc) (pair -1 dc))))
(def %cr-toward!
  (fn (_ g cr r c)
    (%cr-step-first! g cr (%cr-ways (state-sign (- r (creature-r cr))) (state-sign (- c (creature-c cr)))))))
(def %cr-away!
  (fn (_ g cr r c)
    (%cr-step-first! g cr (%cr-ways (state-sign (- (creature-r cr) r)) (state-sign (- (creature-c cr) c))))))
(def %cr-random-step! (fn (_ g cr) (%cr-step-first! g cr (list ((game-rng g) choice (state-dirs))))))

; --- the turn ----------------------------------------------------------------

; A sleeping CR wakes when the player is next to it; when in view, by
; a chance of one in three, one in ten with a ring of stealth.
(def %cr-maybe-wake!
  (fn (_ g cr)
    (def p (game-player g))
    (def near? (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)))
    (def seen? (map-visible? (game-map g) (creature-r cr) (creature-c cr)))
    (when (match (near? #t) ((not seen?) #f) ((state-ring? g (lit stealth)) (state-chance? (game-rng g) 10)) (#t (state-chance? (game-rng g) 34)))
      (creature-state! cr (lit awake)))))

; Whether CR, with breath, has the player in a line within seven cells.
(def %cr-in-line?
  (fn (_ cr p)
    (def dr (- (player-r p) (creature-r cr)))
    (def dc (- (player-c p) (creature-c cr)))
    (def ar (if (< dr 0) (- 0 dr) dr))
    (def ac (if (< dc 0) (- 0 dc) dc))
    (match ((< 7 ar) #f) ((< 7 ac) #f) ((= ar 0) #t) ((= ac 0) #t) ((= ar ac) #t) (#t #f))))
; A creature with breath, (bolt LO HI), or ranged, (ranged LO HI),
; lets fly along a line to the player, three times in ten.
(def %cr-breathes?
  (fn (_ g cr)
    (match ((not (if (creature-trait? cr (lit breath)) #t (creature-trait? cr (lit ranged)))) #f)
           ((not (%cr-in-line? cr (game-player g))) #f)
           (#t (state-chance? (game-rng g) 30)))))
(def %cr-breathe!
  (fn (_ g cr)
    (if (creature-trait? cr (lit breath))
      (do (def bolt (creature-prop cr (lit bolt) (list 2 8)))
          (state-tell! g (lit breath) "The {name} breathes {what} at you!"
            (list (pair "name" (creature-name cr)) (pair "what" (creature-prop1 cr (lit breath) "fire"))))
          (combat-hurt-player! g (state-roll (game-rng g) (first bolt) (List ref 1 bolt))
            (Str8 append "burned by a " (creature-name cr))))
      (do (def shot (creature-prop cr (lit ranged) (list 1 4)))
          (state-tell! g (lit shot) "The {name} shoots {what} at you!"
            (list (pair "name" (creature-name cr)) (pair "what" (creature-prop1 cr (lit shot) "something"))))
          (combat-hurt-player! g (state-roll (game-rng g) (first shot) (List ref 1 shot))
            (Str8 append "shot by a " (creature-name cr)))))))

; A creature with (summon NAME) calls one of that kind to its side,
; one turn in ten while the player is in view.
(def %cr-summons?
  (fn (_ g cr)
    (match ((not (creature-trait? cr (lit summon))) #f)
           ((not (map-visible? (game-map g) (creature-r cr) (creature-c cr))) #f)
           (#t (state-chance? (game-rng g) 10)))))
(def %cr-summon!
  (fn (_ g cr)
    (def name (creature-prop1 cr (lit summon) ""))
    (def kind (creatures-kind g name))
    (def spot (List find (fn (_ d) (state-free? g (+ (creature-r cr) (first d)) (+ (creature-c cr) (rest d))))
                ((game-rng g) shuffle %cr-around)))
    (unless (if (null? kind) #t (null? spot))
      (do (game-creatures! g (pair (creature-make kind (+ (creature-r cr) (first spot)) (+ (creature-c cr) (rest spot))
                                                  (%cr-hp g kind) (lit awake))
                                   (game-creatures g)))
          (state-tell! g (lit summoned) "The {name} calls, and a {what} answers."
            (list (pair "name" (creature-name cr)) (pair "what" name)))))))

; A skittish creature runs when down to a quarter of its hit points, and
; comes back once over half; one that stole something keeps running.
(def %cr-mind!
  (fn (_ g cr)
    (def most (%cr-hp-most cr))
    (match
      ((not (null? (creature-carried cr))) ())
      ((if (eq? (creature-state cr) (lit fleeing)) (< (int/ most 2) (creature-hp cr)) #f) (creature-state! cr (lit awake)))
      ((if (creature-trait? cr (lit skittish)) (< (* 4 (creature-hp cr)) most) #f) (creature-state! cr (lit fleeing)))
      (#t ()))))

(def %cr-regen!
  (fn (_ g cr)
    (when (if (creature-trait? cr (lit regen)) (= 0 (% (game-turn g) 3)) #f)
      (when (< (creature-hp cr) (%cr-hp-most cr)) (creature-hp! cr (+ (creature-hp cr) 1))))))

(def %cr-act-one!
  (fn (_ g cr)
    (def p (game-player g))
    (%cr-mind! g cr)
    (match
      ((creature-trait? cr (lit talks)) ())
      ((< 0 (creature-condition cr (lit held))) ())
      ((eq? (creature-state cr) (lit asleep)) (%cr-maybe-wake! g cr))
      ((%cr-breathes? g cr) (%cr-breathe! g cr))
      ((%cr-summons? g cr) (%cr-summon! g cr))
      ((eq? (creature-state cr) (lit fleeing)) (%cr-away! g cr (player-r p) (player-c p)))
      ((state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) (combat-creature-attacks! g cr))
      ((creature-trait? cr (lit stationary)) ())
      ((if (creature-trait? cr (lit erratic)) (state-chance? (game-rng g) 50) #f) (%cr-random-step! g cr))
      (#t (%cr-toward! g cr (player-r p) (player-c p))))))

; How many turns CR takes this turn: two when fast or hastened, one
; every other turn when slow or slowed, else one.
(def %cr-turns
  (fn (_ g cr)
    (def slow? (if (creature-trait? cr (lit slow)) #t (< 0 (creature-condition cr (lit slowed)))))
    (def fast? (if (creature-trait? cr (lit fast)) #t (< 0 (creature-condition cr (lit hasted)))))
    (match ((if slow? fast? #f) 1)
           (slow? (% (game-turn g) 2))
           (fast? 2)
           (#t 1))))
(def %cr-act-times!
  (fn (self g cr n)
    (when (if (< 0 n) (< 0 (creature-hp cr)) #f)
      (do (%cr-act-one! g cr) (self g cr (- n 1))))))

; Every creature takes its turn, in the order they came, each still
; alive when its turn comes.
(def creatures-act!
  (fn (_ g)
    (List for-each
      (fn (_ cr)
        (when (List any? (fn (_ x) (same? x cr)) (game-creatures g))
          (do (%cr-regen! g cr)
              (%cr-act-times! g cr (%cr-turns g cr))
              (creature-tick! cr))))
      (game-creatures g))))

; Whether CR is drawn: in view, and not invisible unless the player sees
; the unseen.
(def creatures-shown?
  (fn (_ g cr)
    (match ((< 0 (player-condition (game-player g) (lit seeing))) #t)
           ((not (map-visible? (game-map g) (creature-r cr) (creature-c cr))) #f)
           ((creature-trait? cr (lit invisible)) #f)
           (#t #t))))

; Every creature awake: a clamour.
(def creatures-wake-all! (fn (_ g) (List for-each (fn (_ cr) (when (eq? (creature-state cr) (lit asleep)) (creature-state! cr (lit awake)))) (game-creatures g))))
; Every creature in view runs.
(def creatures-scare!
  (fn (_ g)
    (List for-each (fn (_ cr) (when (map-visible? (game-map g) (creature-r cr) (creature-c cr)) (creature-state! cr (lit fleeing))))
      (game-creatures g))))

(provide roguelike/creatures
  creatures-kinds creatures-kind creatures-place! creatures-spawn-one! creatures-spawn! creatures-guardian!
  creatures-wander! creatures-door-diagonal?
  creatures-can-step? creatures-act! creatures-shown? creatures-wake-all! creatures-scare!)
