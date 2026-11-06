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
(import x/core/doors obj-ref obj-set! int+)
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
; (NAME . STATE) each, 23 the names of what the quests have placed.
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

; The set's parameter HEAD, its values, or DEFAULT's.
(def game-param (fn (_ g head default) (data-one (game-set g) head default)))
(def game-param1 (fn (_ g head default) (data-get (game-set g) head default)))

; The set's bands, (band NAME TO . PROPS) each, run one after another
; from level 1, each to its TO.  The band the depth is in, as (FROM .
; BAND), or nil past the last.
(def %st-band-at
  (fn (self bands depth from)
    (match ((null? bands) ())
           ((not (< (List ref 1 (first bands)) depth)) (pair from (first bands)))
           (#t (self (rest bands) depth (+ 1 (List ref 1 (first bands))))))))
(def game-band
  (fn (_ g)
    (def hit (%st-band-at (data-all (game-set g) (lit band)) (game-depth g) 1))
    (if (null? hit) () (rest hit))))
(def game-band-from
  (fn (_ g)
    (def hit (%st-band-at (data-all (game-set g) (lit band)) (game-depth g) 1))
    (if (null? hit) 0 (first hit))))
(def band-name (fn (_ b) (first b)))
(def band-to (fn (_ b) (List ref 1 b)))
(def band-prop1 (fn (_ b key default) (data-prop1 b key default)))

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
; column, 3 hit points, 4 its state (asleep, awake or fleeing), 5 the
; conditions, 6 an item it carries.
(def creature-make
  (fn (_ kind r c hp state)
    (def cr (Vector make 7 ()))
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
    (def g (Vector make 24 ()))
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

(def %st-abs (fn (_ n) (if (< n 0) (- 0 n) n)))
(def %st-max (fn (_ a b) (if (< a b) b a)))
; The moves from R1 C1 to R2 C2, a diagonal step counting one.
(def state-dist (fn (_ r1 c1 r2 c2) (%st-max (%st-abs (- r1 r2)) (%st-abs (- c1 c2)))))
; Whether the two cells touch: a move apart, and not the same cell.
(def state-adjacent?
  (fn (_ r1 c1 r2 c2) (if (if (= r1 r2) (= c1 c2) #f) #f (< (state-dist r1 c1 r2 c2) 2))))
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

; The player's defence: the armour's, its enchantment, and the rings'.
(def state-defence
  (fn (_ g)
    (def a (player-armour (game-player g)))
    (+ (if (null? a) 0 (+ (item-prop1 a (lit armour) 0) (item-enchant a)))
       (state-ring-bonus g (lit protection)))))
(def state-strength (fn (_ g) (+ (player-str (game-player g)) (state-ring-bonus g (lit strength)))))

(provide roguelike/state
  game-rng game-set game-depth game-depth! game-map game-map! game-player game-creatures game-creatures!
  game-floor game-floor! game-pack game-pack! game-messages game-messages! game-turn game-turn!
  game-ask game-ask! game-over game-over! game-guises game-known game-known! game-deepest game-deepest!
  game-log game-rows game-cols game-epitaph game-epitaph! game-seed game-goal-placed? game-goal-placed!
  game-pages-placed game-page-placed! game-quests game-quest-state game-quest-state! game-placed game-placed?
  game-placed! game-param game-param1 game-band game-band-from band-name band-to band-prop1
  game-new
  player-r player-c player-at! player-hp player-hp! player-hpmax player-hpmax! player-str player-str!
  player-strmax player-strmax! player-level player-level! player-exp player-exp! player-gold player-gold!
  player-armour player-armour! player-weapon player-weapon! player-rings player-rings! player-food player-food!
  player-conditions player-conditions! player-condition player-condition! player-tick!
  creature-make creature-kind creature-r creature-c creature-at! creature-hp creature-hp! creature-state
  creature-state! creature-carried creature-carried! creature-name creature-glyph creature-prop creature-prop1
  creature-trait? creature-condition creature-condition! creature-tick!
  item-make item-form item-class item-name item-prop item-prop1 item-count item-count! item-charges
  item-charges! item-enchant item-enchant! item-letter item-letter! item-r item-c item-at! item-class? item-class-in?
  state-say! state-clear-messages! state-clear-log! state-fill state-text state-tell!
  state-roll state-chance? state-dir state-dirs state-dist state-adjacent? state-sign
  state-creature-at state-creature-named state-items-at state-player-at? state-free?
  state-remove-creature! state-remove-floor! state-remove-pack!
  state-ring-bonus state-ring? state-defence state-strength)
