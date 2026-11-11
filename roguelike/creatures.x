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
;
; A set with (hunt sight) hunts only by sight.  Every creature starts
; asleep, a wakeful one wandering.  A sleeper in view wakes by a chance
; of one in its distance plus the player's stealth; one wandering makes
; for a cell somewhere on the level, and notices the player in view by
; one in half its distance plus the stealth.  One awake makes for the
; player while in view, then for where it last saw them, and wanders
; again once there.  Those that arrive come wandering.  The set's
; (elbow-room N) puts nothing within N cells of where the player
; arrives; on its (gentle N) first levels a pack comes as one and none
; arrive.

(module roguelike/creatures)

(import x/type/vector)
(import x/core/doors int/)
(import roguelike/data data-all data-prop data-prop1 data-trait?)
(import roguelike/map map-visible? map-roofed? map-tile map-down tile-door)
(import roguelike/dungeon dungeon-spot)
(import roguelike/state
  game-rng game-set game-depth game-map game-player game-creatures game-creatures! game-turn game-param game-param1
  player-r player-c player-hp player-condition state-covers? state-blow!
  creature-make creature-r creature-c creature-at! creature-hp creature-hp! creature-state creature-state!
  creature-carried creature-name creature-prop creature-prop1 creature-trait? creature-condition creature-tick! state-a-kind
  creature-target creature-target!
  state-say! state-tell! state-roll state-chance? state-dirs state-dist state-adjacent? state-in-sight? state-sign state-free?
  state-ring? state-ring-bonus state-gentle?)
(import roguelike/combat combat-creature-attacks! combat-hurt-player!)

; --- spawning ----------------------------------------------------------------

; The set's kinds for DEPTH: those whose (depth LO HI) covers it, never
; one that talks, which a quest places.
(def creatures-kinds
  (fn (_ g depth)
    (List filter (fn (_ k) (if (data-trait? k (lit talks)) #f (state-covers? (data-prop k (lit depth) (list 1 99)) depth)))
      (data-all (game-set g) (lit creature)))))

(def %cr-hp
  (fn (_ g kind)
    (def d (data-prop kind (lit hp) (list 1 6)))
    (state-roll (game-rng g) (first d) (List ref 1 d))))
(def %cr-hp-most (fn (_ cr) (List ref 1 (creature-prop cr (lit hp) (list 1 6)))))

; Whether the set hunts by sight, (hunt sight).
(def %cr-sight? (fn (_ g) (eq? (game-param1 g (lit hunt) (lit anywhere)) (lit sight))))
; One chance in N, N at least one.
(def %cr-one-in? (fn (_ g n) (= 0 ((game-rng g) int (if (< n 1) 1 n)))))
(def %cr-stealth (fn (_ g) (state-ring-bonus g (lit stealth))))
; How far CR stands from the player.
(def %cr-dist
  (fn (_ g cr) (def p (game-player g)) (state-dist (creature-r cr) (creature-c cr) (player-r p) (player-c p))))

; How a new creature of KIND starts: awake when asked; when wakeful,
; awake, or wandering by sight; asleep by sight; else asleep by a
; chance of three in five.
(def %cr-start
  (fn (_ g kind awake?)
    (match (awake? (lit awake))
           ((data-trait? kind (lit wakeful)) (if (%cr-sight? g) (lit wandering) (lit awake)))
           ((%cr-sight? g) (lit asleep))
           ((state-chance? (game-rng g) 60) (lit asleep))
           (#t (lit awake)))))

(def %cr-around
  (list (pair -1 -1) (pair -1 0) (pair -1 1) (pair 0 -1) (pair 0 1) (pair 1 -1) (pair 1 0) (pair 1 1)))

; A creature of KIND at R C in STATE: the one, or, for a kind with
; (pack LO HI), that many at most, the rest on free cells around it.
(def creatures-place!
  (fn (_ g kind r c state)
    (def pack (if (state-gentle? g) () (data-prop kind (lit pack) ())))
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

; Whether a creature may be put at R C: free, out of view, and past the
; set's elbow room from the player.
(def %cr-spot?
  (fn (_ g r c)
    (def p (game-player g))
    (match ((not (state-free? g r c)) #f)
           ((state-in-sight? g r c) #f)
           (#t (< (game-param1 g (lit elbow-room) 0) (state-dist r c (player-r p) (player-c p)))))))
; One creature of the depth put where it may be, in the state START
; gives its kind.
(def %cr-spawn-one!
  (fn (_ g start)
    (def kinds (creatures-kinds g (game-depth g)))
    (unless (null? kinds)
      (do (def kind ((game-rng g) choice kinds))
          (def at (dungeon-spot (game-rng g) (game-map g) (fn (_ r c) (%cr-spot? g r c)) 100))
          (unless (null? at)
            (creatures-place! g kind (first at) (rest at) (start kind)))))))
; One creature of the depth, AWAKE? or as it comes.
(def creatures-spawn-one!
  (fn (_ g awake?) (%cr-spawn-one! g (fn (_ kind) (%cr-start g kind awake?)))))

(def creatures-spawn!
  (fn (self g n awake?) (unless (< n 1) (do (creatures-spawn-one! g awake?) (self g (- n 1) awake?)))))

; The set's kind named NAME, or nil.
(def creatures-kind
  (fn (_ g name) (List find (fn (_ k) (str=? (first k) name)) (data-all (game-set g) (lit creature)))))

; A guardian: the kind named NAME put on a free cell beside the stairs
; down, or anywhere with none free or no stairs, asleep unless wakeful.
(def creatures-guardian!
  (fn (_ g name)
    (def kind (creatures-kind g name))
    (def down (map-down (game-map g)))
    (def beside (if (null? down) ()
                  (List find (fn (_ d) (state-free? g (+ (first down) (first d)) (+ (rest down) (rest d))))
                    ((game-rng g) shuffle %cr-around))))
    (def at (if (null? beside) (dungeon-spot (game-rng g) (game-map g) (fn (_ r c) (state-free? g r c)) 100)
              (pair (+ (first down) (first beside)) (+ (rest down) (rest beside)))))
    (unless (if (null? kind) #t (null? at))
      (creatures-place! g kind (first at) (rest at) (if (data-trait? kind (lit wakeful)) (lit awake) (lit asleep))))))

; Whether the level has room for one more: always, but by sight, while
; it holds fewer than the most of the set's (creatures LO HI), those
; that talk aside.  Those by sight are not drawn to the player to be
; killed, and would gather without it.
(def %cr-room?
  (fn (_ g)
    (if (not (%cr-sight? g)) #t
      (< (List count-if (fn (_ cr) (not (creature-trait? cr (lit talks)))) (game-creatures g))
         (List ref 1 (game-param g (lit creatures) (list 3 6)))))))

; Now and then a creature arrives on the level, awake, or wandering by
; sight: one chance in the set's (wander N) a turn while there is room,
; none on a gentle level.
(def creatures-wander!
  (fn (_ g)
    (when (match ((state-gentle? g) #f) ((not (%cr-room? g)) #f) (#t (%cr-one-in? g (game-param1 g (lit wander) 60))))
      (%cr-spawn-one! g (fn (_ kind) (if (%cr-sight? g) (lit wandering) (lit awake)))))))

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

(def %cr-seen? (fn (_ g cr) (state-in-sight? g (creature-r cr) (creature-c cr))))
(def %cr-player-at (fn (_ g) (pair (player-r (game-player g)) (player-c (game-player g)))))
; CR awake, making for the player.
(def %cr-rouse! (fn (_ g cr) (creature-state! cr (lit awake)) (creature-target! cr (%cr-player-at g))))

; A sleeping CR wakes when the player is next to it; when in view, by
; a chance of one in three, one in ten with a ring of stealth.  By
; sight, only in view, by one in its distance plus the stealth.
(def %cr-wakes?
  (fn (_ g cr)
    (def near? (state-adjacent? (creature-r cr) (creature-c cr) (player-r (game-player g)) (player-c (game-player g))))
    (match ((%cr-sight? g) (if (%cr-seen? g cr) (%cr-one-in? g (+ (%cr-dist g cr) (%cr-stealth g))) #f))
           (near? #t)
           ((not (%cr-seen? g cr)) #f)
           ((state-ring? g (lit stealth)) (state-chance? (game-rng g) 10))
           (#t (state-chance? (game-rng g) 34)))))
(def %cr-maybe-wake! (fn (_ g cr) (when (%cr-wakes? g cr) (%cr-rouse! g cr))))

; CR a step toward where it makes for, a cell of the level picked when
; it has none.  Once there, or stopped, it has none again.
(def %cr-head!
  (fn (_ g cr)
    (when (null? (creature-target cr))
      (creature-target! cr (dungeon-spot (game-rng g) (game-map g) (fn (_ r c) (state-free? g r c)) 100)))
    (def to (creature-target cr))
    (def r0 (creature-r cr))
    (def c0 (creature-c cr))
    (unless (null? to) (%cr-toward! g cr (first to) (rest to)))
    (when (match ((null? to) #t)
                 ((if (= r0 (creature-r cr)) (= c0 (creature-c cr)) #f) #t)
                 ((if (= (first to) (creature-r cr)) (= (rest to) (creature-c cr)) #f) #t)
                 (#t #f))
      (creature-target! cr ()))))

; A wandering CR notices the player in view by one in half its distance
; plus the stealth, and otherwise goes on its way; one stationary waits.
(def %cr-wander!
  (fn (_ g cr)
    (match ((if (%cr-seen? g cr) (%cr-one-in? g (+ (int/ (%cr-dist g cr) 2) (%cr-stealth g))) #f) (%cr-rouse! g cr))
           ((creature-trait? cr (lit stationary)) ())
           (#t (%cr-head! g cr)))))

; An awake CR, by sight: for the player in view, else for where it last
; saw them, and wandering once there.
(def %cr-hunt!
  (fn (_ g cr)
    (if (%cr-seen? g cr)
      (do (creature-target! cr (%cr-player-at g)) (%cr-toward! g cr (player-r (game-player g)) (player-c (game-player g))))
      (do (unless (null? (creature-target cr)) (%cr-head! g cr))
          (when (null? (creature-target cr)) (creature-state! cr (lit wandering)))))))

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
; Either is kept as a blow, with what flew, for a front end to show.
(def %cr-breathe!
  (fn (_ g cr)
    (def p (game-player g))
    (def let-fly!
      (fn (_ what lo-hi cause)
        (def n (state-roll (game-rng g) (first lo-hi) (List ref 1 lo-hi)))
        (combat-hurt-player! g n (Str8 append cause (creature-name cr)))
        (state-blow! g (creature-r cr) (creature-c cr) (player-r p) (player-c p)
          (if (< (player-hp p) 1) (lit kill) (lit hit)) n what)))
    (if (creature-trait? cr (lit breath))
      (do (state-tell! g (lit breath) "The {name} breathes {what} at you!"
            (list (pair "name" (creature-name cr)) (pair "what" (creature-prop1 cr (lit breath) "fire"))))
          (let-fly! (lit breath) (creature-prop cr (lit bolt) (list 2 8)) "burned by a "))
      (do (state-tell! g (lit shot) "The {name} shoots {what} at you!"
            (list (pair "name" (creature-name cr)) (pair "what" (creature-prop1 cr (lit shot) "something"))))
          (let-fly! (lit shot) (creature-prop cr (lit ranged) (list 1 4)) "shot by a ")))))

; A creature with (summon NAME) calls one of that kind to its side,
; one turn in ten while the player is in view.
(def %cr-summons?
  (fn (_ g cr)
    (match ((not (creature-trait? cr (lit summon))) #f)
           ((not (%cr-seen? g cr)) #f)
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
          (state-tell! g (lit summoned) "The {name} calls, and {a-what} answers."
            (list (pair "name" (creature-name cr)) (pair "what" name) (pair "a-what" (state-a-kind kind))))))))

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
      ((eq? (creature-state cr) (lit wandering)) (%cr-wander! g cr))
      ((%cr-breathes? g cr) (%cr-breathe! g cr))
      ((%cr-summons? g cr) (%cr-summon! g cr))
      ((eq? (creature-state cr) (lit fleeing)) (%cr-away! g cr (player-r p) (player-c p)))
      ((state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) (combat-creature-attacks! g cr (creatures-shown? g cr)))
      ((creature-trait? cr (lit stationary)) ())
      ((if (creature-trait? cr (lit erratic)) (state-chance? (game-rng g) 50) #f) (%cr-random-step! g cr))
      ((%cr-sight? g) (%cr-hunt! g cr))
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

; Whether CR is drawn: in view, under no roof, and not invisible, unless
; the player sees the unseen.
(def creatures-shown?
  (fn (_ g cr)
    (match ((< 0 (player-condition (game-player g) (lit seeing))) #t)
           ((not (map-visible? (game-map g) (creature-r cr) (creature-c cr))) #f)
           ((map-roofed? (game-map g) (creature-r cr) (creature-c cr)) #f)
           ((creature-trait? cr (lit invisible)) #f)
           (#t #t))))

; Every creature asleep or wandering awake, making for the player: a
; clamour.
(def creatures-wake-all!
  (fn (_ g)
    (List for-each (fn (_ cr) (when (match ((eq? (creature-state cr) (lit asleep)) #t) ((eq? (creature-state cr) (lit wandering)) #t) (#t #f))
                                (%cr-rouse! g cr)))
      (game-creatures g))))
; Every creature in view runs.
(def creatures-scare!
  (fn (_ g)
    (List for-each (fn (_ cr) (when (%cr-seen? g cr) (creature-state! cr (lit fleeing))))
      (game-creatures g))))

(provide roguelike/creatures
  creatures-kinds creatures-kind creatures-place! creatures-spawn-one! creatures-spawn! creatures-guardian!
  creatures-wander! creatures-door-diagonal?
  creatures-can-step? creatures-act! creatures-shown? creatures-wake-all! creatures-scare!)
