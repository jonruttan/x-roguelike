; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/state.x -- the game's state, and what every module asks of it
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A game, the player, a creature and an item are each a vector, read and
; written through the accessors here, so no other module knows a slot
; number.  The messages of a turn, the dice, the compass and the lookups
; by cell live here too, since every module needs them.

(module roguelike/state)

(import x/type/vector)
(import x/num/random)
(import x/core/doors obj-ref obj-set! int+ int/)
(import roguelike/data data-all data-one data-get data-prop data-prop1 data-trait?)
(import roguelike/map map-walkable?)

; --- the game ----------------------------------------------------------------

; A game is a vector: 0 the random source, 1 the set, 2 the depth, 3 the
; level, 4 the player, 5 the creatures, 6 the items on the floor, 7 the
; pack, 8 this turn's messages (newest first), 9 the turn, 10 a question
; being asked, 11 how the game ended or nil, 12 the guises, 13 the item
; names known, 14 the deepest level reached, 15 the log (newest first),
; 16 rows, 17 columns, 18 the epitaph, 19 the seed, 20 whether the goal
; has been placed, 21 the names of the pages placed, 22 the quests,
; (NAME . STATE) each, 23 the names of what the quests have placed, 24
; the level's traps, 25 the steps taken exploring, or nil when not, 26
; the screen stood on, (X . Y), or nil in a descent, 27 the levels
; kept, (KEY . LEVEL) each, a LEVEL being (MAP CREATURES FLOOR TRAPS),
; 28 the chain: the quests made for this game from the set's scenes,
; each a (quest ...) form as a set would write it, 29 the doors laid,
; (KEY . NAME) each, the screen's key and the interior behind it, 30
; the interior stood in, its name, or nil outside, 31 the marks of what
; the set has made sure of: "stocked N" for each level stocked, and one
; "band NAME: ITEM" for each item a band has laid.
; Every slot here is read through the object doors, not the class: a
; class send costs some two hundred objects, and a turn reads thousands.
(def %st-ref (fn (_ v k) (obj-ref v (int+ k 1))))
(def %st-set! (fn (_ v k x) (obj-set! v (int+ k 1) x)))
(def %st-get (fn (_ g k) (%st-ref g k)))
(def %st-put! (fn (_ g k x) (%st-set! g k x)))
(def game-rng (fn (_ g) (%st-get g 0)))
(def game-set (fn (_ g) (%st-get g 1)))
(def game-depth (fn (_ g) (%st-get g 2)))
(def game-depth! (fn (_ g n) (%st-put! g 2 n)))
(def game-map (fn (_ g) (%st-get g 3)))
(def game-map! (fn (_ g m) (%st-put! g 3 m)))
(def game-player (fn (_ g) (%st-get g 4)))
(def game-creatures (fn (_ g) (%st-get g 5)))
(def game-creatures! (fn (_ g l) (%st-put! g 5 l)))
(def game-floor (fn (_ g) (%st-get g 6)))
(def game-floor! (fn (_ g l) (%st-put! g 6 l)))
(def game-pack (fn (_ g) (%st-get g 7)))
(def game-pack! (fn (_ g l) (%st-put! g 7 l)))
(def game-messages (fn (_ g) (List reverse (%st-get g 8))))
(def game-messages! (fn (_ g l) (%st-put! g 8 l)))
(def game-turn (fn (_ g) (%st-get g 9)))
(def game-turn! (fn (_ g n) (%st-put! g 9 n)))
(def game-ask (fn (_ g) (%st-get g 10)))
(def game-ask! (fn (_ g q) (%st-put! g 10 q)))
(def game-over (fn (_ g) (%st-get g 11)))
(def game-over! (fn (_ g how) (%st-put! g 11 how)))
(def game-guises (fn (_ g) (%st-get g 12)))
(def game-known (fn (_ g) (%st-get g 13)))
(def game-known! (fn (_ g l) (%st-put! g 13 l)))
(def game-deepest (fn (_ g) (%st-get g 14)))
(def game-deepest! (fn (_ g n) (%st-put! g 14 n)))
(def game-log (fn (_ g) (%st-get g 15)))
(def game-rows (fn (_ g) (%st-get g 16)))
(def game-cols (fn (_ g) (%st-get g 17)))
(def game-epitaph (fn (_ g) (%st-get g 18)))
(def game-epitaph! (fn (_ g text) (%st-put! g 18 text)))
(def game-seed (fn (_ g) (%st-get g 19)))
(def game-goal-placed? (fn (_ g) (%st-get g 20)))
(def game-goal-placed! (fn (_ g) (%st-put! g 20 #t)))
(def game-pages-placed (fn (_ g) (%st-get g 21)))
(def game-page-placed! (fn (_ g name) (%st-put! g 21 (pair name (%st-get g 21)))))
(def game-quests (fn (_ g) (%st-get g 22)))
; Quest NAME's state: nil before it is opened, else open, reward or done.
(def game-quest-state
  (fn (_ g name)
    (def hit (List find (fn (_ p) (str=? (first p) name)) (%st-get g 22)))
    (if (null? hit) () (rest hit))))
(def game-quest-state!
  (fn (_ g name state)
    (%st-put! g 22 (pair (pair name state) (List reject (fn (_ p) (str=? (first p) name)) (%st-get g 22))))))
(def game-placed (fn (_ g) (%st-get g 23)))
(def game-placed? (fn (_ g name) (List includes? name (%st-get g 23))))
(def game-placed! (fn (_ g name) (%st-put! g 23 (pair name (%st-get g 23)))))
(def game-traps (fn (_ g) (%st-get g 24)))
(def game-traps! (fn (_ g l) (%st-put! g 24 l)))
(def game-exploring (fn (_ g) (%st-get g 25)))
(def game-exploring? (fn (_ g) (not (null? (%st-get g 25)))))
(def game-exploring! (fn (_ g n) (%st-put! g 25 n)))
(def game-screen (fn (_ g) (%st-get g 26)))
(def game-screen! (fn (_ g at) (%st-put! g 26 at)))
(def game-kept (fn (_ g) (%st-get g 27)))
; The level kept under KEY, or nil.
(def game-kept-level
  (fn (_ g key)
    (def hit (List find (fn (_ p) (str=? (first p) key)) (%st-get g 27)))
    (if (null? hit) () (rest hit))))
; LEVEL kept under KEY, in place of any kept there before.
(def game-keep!
  (fn (_ g key level)
    (%st-put! g 27 (pair (pair key level) (List reject (fn (_ p) (str=? (first p) key)) (%st-get g 27))))))

; The set's parameter HEAD, its values, or DEFAULT's.
(def game-param (fn (_ g head default) (data-one (game-set g) head default)))
(def game-param1 (fn (_ g head default) (data-get (game-set g) head default)))

; The set's (world SHAPE ...): descent, a line of levels joined by
; stairs, each made anew, which is the default; or (screens W H), a
; grid of W by H screens joined at their edges and kept.  The hub is
; the middle screen, where a game starts; a screen's depth is its
; distance from the hub, a step along either axis counting one.
(def game-world (fn (_ g) (game-param g (lit world) (list (lit descent)))))
(def game-screens? (fn (_ g) (eq? (first (game-world g)) (lit screens))))
(def game-world-cols (fn (_ g) (List ref 1 (game-world g))))
(def game-world-rows (fn (_ g) (List ref 2 (game-world g))))
(def game-hub (fn (_ g) (pair (int/ (game-world-cols g) 2) (int/ (game-world-rows g) 2))))
(def %st-abs (fn (_ n) (if (< n 0) (- 0 n) n)))
(def game-screen-distance
  (fn (_ g x y)
    (def hub (game-hub g))
    (+ (%st-abs (- x (first hub))) (%st-abs (- y (rest hub))))))
; Whether screen X Y lies within the world.
(def game-screen-in?
  (fn (_ g x y)
    (match ((< x 0) #f) ((< y 0) #f) ((< x (game-world-cols g)) (< y (game-world-rows g))) (#t #f))))
; The key a screen's level is kept under.
(def game-screen-key (fn (_ x y) (Str8 append (Str8 str x) "," (Str8 str y))))
(def game-chain (fn (_ g) (%st-get g 28)))
(def game-chain! (fn (_ g forms) (%st-put! g 28 forms)))
(def game-doors (fn (_ g) (%st-get g 29)))
; The interior behind the door of the screen kept under KEY, or nil.
(def game-door (fn (_ g key) (def d (List find (fn (_ p) (str=? (first p) key)) (%st-get g 29))) (if (null? d) () (rest d))))
(def game-door! (fn (_ g key name) (%st-put! g 29 (pair (pair key name) (%st-get g 29)))))
(def game-inside (fn (_ g) (%st-get g 30)))
(def game-inside! (fn (_ g name) (%st-put! g 30 name)))
(def game-sure (fn (_ g) (%st-get g 31)))
(def game-sure? (fn (_ g mark) (List includes? mark (%st-get g 31))))
(def game-sure! (fn (_ g mark) (%st-put! g 31 (pair mark (%st-get g 31)))))
; The key the level in hand is kept under: its screen's, or, inside,
; that with a > after it.
(def game-level-key
  (fn (_ g)
    (def key (game-screen-key (first (game-screen g)) (rest (game-screen g))))
    (if (null? (game-inside g)) key (Str8 append key ">"))))

; The set's bands, (band NAME TO . PROPS) each, run one after another
; from the first level, each to its TO: level 1 in a descent, the hub,
; ring 0, in a world of screens.  The band the depth is in, as (FROM .
; BAND), or nil past the last.
(def %st-band-at
  (fn (self bands depth from)
    (match ((null? bands) ())
           ((not (< (List ref 1 (first bands)) depth)) (pair from (first bands)))
           (#t (self (rest bands) depth (+ 1 (List ref 1 (first bands))))))))
(def %st-band-hit
  (fn (_ g) (%st-band-at (data-all (game-set g) (lit band)) (game-depth g) (if (game-screens? g) 0 1))))
(def game-band (fn (_ g) (def hit (%st-band-hit g)) (if (null? hit) () (rest hit))))
(def game-band-from (fn (_ g) (def hit (%st-band-hit g)) (if (null? hit) 0 (first hit))))
(def band-name (fn (_ b) (first b)))
(def band-to (fn (_ b) (List ref 1 b)))
(def band-prop1 (fn (_ b key default) (data-prop1 b key default)))
; The forms the level in hand is made and drawn by: its band's PROPS in
; front of the set's, so a knob or a glyph the band names is its own.
(def game-forms
  (fn (_ g) (def b (game-band g)) (if (null? b) (game-set g) (List append (rest (rest b)) (game-set g)))))

; --- the player --------------------------------------------------------------

; The player is a vector: 0 row, 1 column, 2 hit points, 3 the most, 4
; strength, 5 the most, 6 level, 7 experience, 8 gold, 9 the armour
; worn, 10 the weapon wielded, 11 the rings worn, 12 food, 13 the
; conditions, (NAME . TURNS).
(def player-r (fn (_ p) (%st-ref p 0)))
(def player-c (fn (_ p) (%st-ref p 1)))
(def player-at! (fn (_ p r c) (%st-set! p 0 r) (%st-set! p 1 c)))
(def player-hp (fn (_ p) (%st-ref p 2)))
(def player-hp! (fn (_ p n) (%st-set! p 2 n)))
(def player-hpmax (fn (_ p) (%st-ref p 3)))
(def player-hpmax! (fn (_ p n) (%st-set! p 3 n)))
(def player-str (fn (_ p) (%st-ref p 4)))
(def player-str! (fn (_ p n) (%st-set! p 4 n)))
(def player-strmax (fn (_ p) (%st-ref p 5)))
(def player-strmax! (fn (_ p n) (%st-set! p 5 n)))
(def player-level (fn (_ p) (%st-ref p 6)))
(def player-level! (fn (_ p n) (%st-set! p 6 n)))
(def player-exp (fn (_ p) (%st-ref p 7)))
(def player-exp! (fn (_ p n) (%st-set! p 7 n)))
(def player-gold (fn (_ p) (%st-ref p 8)))
(def player-gold! (fn (_ p n) (%st-set! p 8 n)))
(def player-armour (fn (_ p) (%st-ref p 9)))
(def player-armour! (fn (_ p it) (%st-set! p 9 it)))
(def player-weapon (fn (_ p) (%st-ref p 10)))
(def player-weapon! (fn (_ p it) (%st-set! p 10 it)))
(def player-rings (fn (_ p) (%st-ref p 11)))
(def player-rings! (fn (_ p l) (%st-set! p 11 l)))
(def player-food (fn (_ p) (%st-ref p 12)))
(def player-food! (fn (_ p n) (%st-set! p 12 n)))
(def player-conditions (fn (_ p) (%st-ref p 13)))
(def player-conditions! (fn (_ p l) (%st-set! p 13 l)))

(def %st-player-make
  (fn (_ set)
    (def spec (data-one set (lit player) (list 12 16)))
    (def p (Vector make 14 ()))
    (player-at! p 0 0)
    (player-hp! p (List ref 0 spec))
    (player-hpmax! p (List ref 0 spec))
    (player-str! p (List ref 1 spec))
    (player-strmax! p (List ref 1 spec))
    (player-level! p 1)
    (player-exp! p 0)
    (player-gold! p 0)
    (player-rings! p ())
    (player-food! p (data-get set (lit hunger) 1300))
    (player-conditions! p ())
    p))

; A condition's turns left on WHO (a player or creature's conditions
; list, by its accessors), or 0.
(def %st-cond-turns
  (fn (self conds name)
    (match ((null? conds) 0)
           ((eq? (first (first conds)) name) (rest (first conds)))
           (#t (self (rest conds) name)))))
(def %st-cond-set
  (fn (_ conds name turns)
    (pair (pair name turns) (List reject (fn (_ p) (eq? (first p) name)) conds))))
(def %st-cond-tick
  (fn (_ conds)
    (List reject (fn (_ p) (< (rest p) 1)) (List map (fn (_ p) (pair (first p) (- (rest p) 1))) conds))))

(def player-condition (fn (_ p name) (%st-cond-turns (player-conditions p) name)))
(def player-condition! (fn (_ p name turns) (player-conditions! p (%st-cond-set (player-conditions p) name turns))))
(def player-tick! (fn (_ p) (player-conditions! p (%st-cond-tick (player-conditions p)))))

; --- creatures ---------------------------------------------------------------

; A creature is a vector: 0 its kind, (NAME GLYPH . PROPS), 1 row, 2
; column, 3 hit points, 4 its state (asleep, awake, wandering or
; fleeing), 5 the conditions, 6 an item it carries, 7 where it is
; making for, (R . C), or nil.  Where it makes for is not saved: a
; creature read back picks its way afresh.
(def creature-make
  (fn (_ kind r c hp state)
    (def cr (Vector make 8 ()))
    (%st-set! cr 0 kind)
    (%st-set! cr 1 r)
    (%st-set! cr 2 c)
    (%st-set! cr 3 hp)
    (%st-set! cr 4 state)
    (%st-set! cr 5 ())
    cr))
(def creature-kind (fn (_ cr) (%st-ref cr 0)))
(def creature-r (fn (_ cr) (%st-ref cr 1)))
(def creature-c (fn (_ cr) (%st-ref cr 2)))
(def creature-at! (fn (_ cr r c) (%st-set! cr 1 r) (%st-set! cr 2 c)))
(def creature-hp (fn (_ cr) (%st-ref cr 3)))
(def creature-hp! (fn (_ cr n) (%st-set! cr 3 n)))
(def creature-state (fn (_ cr) (%st-ref cr 4)))
(def creature-state! (fn (_ cr s) (%st-set! cr 4 s)))
(def creature-carried (fn (_ cr) (%st-ref cr 6)))
(def creature-carried! (fn (_ cr it) (%st-set! cr 6 it)))
(def creature-target (fn (_ cr) (%st-ref cr 7)))
(def creature-target! (fn (_ cr at) (%st-set! cr 7 at)))
(def creature-name (fn (_ cr) (first (creature-kind cr))))
(def creature-glyph (fn (_ cr) (List ref 1 (creature-kind cr))))
(def creature-prop (fn (_ cr key default) (data-prop (creature-kind cr) key default)))
(def creature-prop1 (fn (_ cr key default) (data-prop1 (creature-kind cr) key default)))
(def creature-trait? (fn (_ cr flag) (data-trait? (creature-kind cr) flag)))
(def creature-condition (fn (_ cr name) (%st-cond-turns (%st-ref cr 5) name)))
(def creature-condition! (fn (_ cr name turns) (%st-set! cr 5 (%st-cond-set (%st-ref cr 5) name turns))))
(def creature-tick! (fn (_ cr) (%st-set! cr 5 (%st-cond-tick (%st-ref cr 5)))))

; --- items -------------------------------------------------------------------

; An item is a vector: 0 its form, (CLASS NAME . PROPS), 1 how many, 2
; charges, 3 enchantment, 4 its letter in the pack, 5 row, 6 column.
(def item-make
  (fn (_ form count charges)
    (def it (Vector make 7 ()))
    (%st-set! it 0 form)
    (%st-set! it 1 count)
    (%st-set! it 2 charges)
    (Vector set! 3 0 it)
    it))
(def item-form (fn (_ it) (%st-ref it 0)))
(def item-class (fn (_ it) (first (item-form it))))
(def item-name (fn (_ it) (List ref 1 (item-form it))))
(def item-prop (fn (_ it key default) (data-prop (item-form it) key default)))
(def item-prop1 (fn (_ it key default) (data-prop1 (item-form it) key default)))
(def item-count (fn (_ it) (%st-ref it 1)))
(def item-count! (fn (_ it n) (%st-set! it 1 n)))
(def item-charges (fn (_ it) (%st-ref it 2)))
(def item-charges! (fn (_ it n) (%st-set! it 2 n)))
(def item-enchant (fn (_ it) (%st-ref it 3)))
(def item-enchant! (fn (_ it n) (%st-set! it 3 n)))
(def item-letter (fn (_ it) (%st-ref it 4)))
(def item-letter! (fn (_ it l) (%st-set! it 4 l)))
(def item-r (fn (_ it) (%st-ref it 5)))
(def item-c (fn (_ it) (%st-ref it 6)))
(def item-at! (fn (_ it r c) (%st-set! it 5 r) (%st-set! it 6 c)))
(def item-class? (fn (_ it class) (eq? (item-class it) class)))
; Whether IT is of CLASS: one, any of a list, or anything for nil.
(def item-class-in?
  (fn (_ it class)
    (match ((null? class) #t)
           ((pair? class) (List any? (fn (_ c) (eq? (item-class it) c)) class))
           (#t (eq? (item-class it) class)))))

; --- making a game -----------------------------------------------------------

; The guises: each (guise CLASS NAME ...) of the set shuffled, as (CLASS .
; NAMES), so a class's Nth kind wears the Nth name this game.
(def %st-guises
  (fn (_ rng set)
    (List map (fn (_ args) (pair (first args) (rng shuffle (rest args)))) (data-all set (lit guise)))))

(def game-new
  (fn (_ set seed rows cols)
    (def g (Vector make 32 ()))
    (def rng (Random sw seed))
    (%st-put! g 0 rng)
    (%st-put! g 1 set)
    (%st-put! g 2 0)
    (%st-put! g 4 (%st-player-make set))
    (%st-put! g 9 0)
    (%st-put! g 12 (%st-guises rng set))
    (%st-put! g 14 0)
    (%st-put! g 16 rows)
    (%st-put! g 17 cols)
    (%st-put! g 18 "")
    (%st-put! g 19 seed)
    (%st-put! g 20 #f)
    (%st-put! g 21 ())
    (%st-put! g 22 ())
    (%st-put! g 23 ())
    (%st-put! g 24 ())
    (%st-put! g 25 ())
    (%st-put! g 26 ())
    (%st-put! g 27 ())
    (%st-put! g 28 ())
    (%st-put! g 29 ())
    (%st-put! g 30 ())
    g))

; --- messages ----------------------------------------------------------------

; TEXT said this turn, and kept in the log.
(def state-say!
  (fn (_ g text)
    (%st-put! g 8 (pair text (%st-get g 8)))
    (%st-put! g 15 (List take 100 (pair text (%st-get g 15))))))
(def state-clear-messages! (fn (_ g) (%st-put! g 8 ())))
(def state-clear-log! (fn (_ g) (%st-put! g 15 ())))

; TEXT with each {KEY} of SUBS, ((KEY . VALUE) ...), put in.
(def state-fill
  (fn (_ text subs)
    (List fold (fn (_ t sub) (Str8 replace (Str8 append "{" (first sub) "}") (rest sub) t)) text subs)))

; The set's message KEY, (message KEY "TEXT"), or DEFAULT, filled with SUBS.
(def state-text
  (fn (_ g key default subs)
    (def hit (List find (fn (_ args) (eq? (first args) key)) (data-all (game-set g) (lit message))))
    (state-fill (if (null? hit) default (List ref 1 hit)) subs)))

; Say the set's message KEY, or DEFAULT, filled with SUBS.
(def state-tell! (fn (_ g key default subs) (state-say! g (state-text g key default subs))))

; --- dice and the compass ----------------------------------------------------

(def state-roll (fn (_ rng lo hi) (if (< hi lo) lo (rng between lo hi))))
(def state-chance? (fn (_ rng pct) (< (rng int 100) pct)))

(def %st-compass
  (list (pair "h" (pair 0 -1)) (pair "j" (pair 1 0)) (pair "k" (pair -1 0)) (pair "l" (pair 0 1))
        (pair "y" (pair -1 -1)) (pair "u" (pair -1 1)) (pair "b" (pair 1 -1)) (pair "n" (pair 1 1))
        (pair (lit left) (pair 0 -1)) (pair (lit down) (pair 1 0)) (pair (lit up) (pair -1 0)) (pair (lit right) (pair 0 1))))
(def %st-key=? (fn (_ a b) (if (str? a) (if (str? b) (str=? a b) #f) (eq? a b))))
; The (DR . DC) KEY moves by, or nil for a key that is no direction.
(def state-dir
  (fn (_ key)
    (def hit (List find (fn (_ p) (%st-key=? (first p) key)) %st-compass))
    (if (null? hit) () (rest hit))))
(def state-dirs (fn (_) (List map rest (List take 8 %st-compass))))

(def %st-max (fn (_ a b) (if (< a b) b a)))
; The moves from R1 C1 to R2 C2, a diagonal step counting one.
(def state-dist (fn (_ r1 c1 r2 c2) (%st-max (%st-abs (- r1 r2)) (%st-abs (- c1 c2)))))
; Whether the two cells touch: a move apart, and not the same cell.
(def state-adjacent?
  (fn (_ r1 c1 r2 c2) (if (if (= r1 r2) (= c1 c2) #f) #f (< (state-dist r1 c1 r2 c2) 2))))
; Whether D, a (LO HI) of levels, covers DEPTH.
(def state-covers? (fn (_ d depth) (if (< depth (first d)) #f (not (< (List ref 1 d) depth)))))
(def state-sign (fn (_ n) (match ((< n 0) -1) ((< 0 n) 1) (#t 0))))

; --- lookups -----------------------------------------------------------------

(def state-creature-at
  (fn (_ g r c)
    (List find (fn (_ cr) (if (= (creature-r cr) r) (= (creature-c cr) c) #f)) (game-creatures g))))
(def state-items-at
  (fn (_ g r c)
    (List filter (fn (_ it) (if (= (item-r it) r) (= (item-c it) c) #f)) (game-floor g))))
(def state-player-at? (fn (_ g r c) (if (= (player-r (game-player g)) r) (= (player-c (game-player g)) c) #f)))
; The living creature named NAME, or nil.
(def state-creature-named
  (fn (_ g name) (List find (fn (_ cr) (str=? (creature-name cr) name)) (game-creatures g))))
; Whether a creature could step onto R C: walkable, and nobody there.
(def state-free?
  (fn (_ g r c)
    (match ((not (map-walkable? (game-map g) r c)) #f)
           ((state-player-at? g r c) #f)
           ((not (null? (state-creature-at g r c))) #f)
           (#t #t))))

; An object is itself by same?: eq? holds between two vectors alike.
(def state-remove-creature! (fn (_ g cr) (game-creatures! g (List reject (fn (_ x) (same? x cr)) (game-creatures g)))))
(def state-remove-floor! (fn (_ g it) (game-floor! g (List reject (fn (_ x) (same? x it)) (game-floor g)))))
(def state-remove-pack! (fn (_ g it) (game-pack! g (List reject (fn (_ x) (same? x it)) (game-pack g)))))

; --- the player's worth in a fight ------------------------------------------

; The sum of (bonus KEY N) over the rings worn.
(def state-ring-bonus
  (fn (_ g key)
    (List fold (fn (_ acc ring)
                 (def b (item-prop ring (lit bonus) ()))
                 (if (if (null? b) #f (eq? (first b) key)) (+ acc (List ref 1 b)) acc))
               0 (player-rings (game-player g)))))
(def state-ring? (fn (_ g key) (< 0 (state-ring-bonus g key))))

; Whether the level is one of the set's (gentle N) first.
(def state-gentle?
  (fn (_ g) (def n (game-param1 g (lit gentle) 0)) (if (< 0 n) (not (< n (game-depth g))) #f)))

(def state-strength (fn (_ g) (+ (player-str (game-player g)) (state-ring-bonus g (lit strength)))))

; The strength IT asks, its (strength N) less its enchantment, beyond
; the player's: 0 with none asked, or enough had.
(def state-shortfall
  (fn (_ g it)
    (def need (item-prop1 it (lit strength) 0))
    (def short (- (- need (item-enchant it)) (state-strength g)))
    (match ((= need 0) 0) ((< short 0) 0) (#t short))))

; The player's defence: the armour's, its enchantment, less what it
; asks in strength beyond the player's, and the rings'.
(def state-defence
  (fn (_ g)
    (def a (player-armour (game-player g)))
    (+ (if (null? a) 0 (- (+ (item-prop1 a (lit armour) 0) (item-enchant a)) (state-shortfall g a)))
       (state-ring-bonus g (lit protection)))))

(provide roguelike/state
  game-rng game-set game-depth game-depth! game-map game-map! game-player game-creatures game-creatures!
  game-floor game-floor! game-pack game-pack! game-messages game-messages! game-turn game-turn!
  game-ask game-ask! game-over game-over! game-guises game-known game-known! game-deepest game-deepest!
  game-log game-rows game-cols game-epitaph game-epitaph! game-seed game-goal-placed? game-goal-placed!
  game-pages-placed game-page-placed! game-quests game-quest-state game-quest-state! game-placed game-placed?
  game-placed! game-sure game-sure? game-sure! game-traps game-traps! game-exploring game-exploring? game-exploring!
  game-screen game-screen! game-kept game-kept-level game-keep! game-chain game-chain!
  game-doors game-door game-door! game-inside game-inside! game-level-key
  game-world game-screens? game-world-cols game-world-rows game-hub game-screen-distance game-screen-in?
  game-screen-key
  game-param game-param1 game-band game-band-from band-name band-to band-prop1 game-forms game-new
  player-r player-c player-at! player-hp player-hp! player-hpmax player-hpmax! player-str player-str!
  player-strmax player-strmax! player-level player-level! player-exp player-exp! player-gold player-gold!
  player-armour player-armour! player-weapon player-weapon! player-rings player-rings! player-food player-food!
  player-conditions player-conditions! player-condition player-condition! player-tick!
  creature-make creature-kind creature-r creature-c creature-at! creature-hp creature-hp! creature-state
  creature-state! creature-carried creature-carried! creature-target creature-target! creature-name creature-glyph creature-prop creature-prop1
  creature-trait? creature-condition creature-condition! creature-tick!
  item-make item-form item-class item-name item-prop item-prop1 item-count item-count! item-charges
  item-charges! item-enchant item-enchant! item-letter item-letter! item-r item-c item-at! item-class? item-class-in?
  state-say! state-clear-messages! state-clear-log! state-fill state-text state-tell!
  state-roll state-chance? state-dir state-dirs state-dist state-adjacent? state-covers? state-sign
  state-creature-at state-creature-named state-items-at state-player-at? state-free?
  state-remove-creature! state-remove-floor! state-remove-pack!
  state-ring-bonus state-ring? state-gentle? state-defence state-strength state-shortfall)
