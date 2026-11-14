; # x-roguelike -- a roguelike on x-lang
;
; ## tools/balance.x -- a plain player through many games, and what it found
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;   BALANCE_SEEDS=50 BALANCE_SET=delve x -l roguelike -f tools/balance.x
;
; A bot plays a game a seed, its attributes rolled from the seed in the
; ranges of tools/bots/attributes.xon, or of the archetype
; BALANCE_ARCHETYPE names: they say when it drinks, steps back, rests
; and goes for a foe, how far it chases and walks for an item, and how
; much of a level it sees before the stairs.  Each turn it does the first of: answer what is
; asked; drink; fight or step back from what is beside it; eat; rest;
; wield and wear the best it can lift; then pick up, walk to an item, go
; for a foe, run the errand on a world of screens, talk to a giver,
; walk to the edge of the unseen, search a wall with unseen ground
; behind it, and take the stairs.  Every walk is
; its own, over what it has seen; a creature it cannot reach is passed
; by, and it rests a turn only with nowhere at all to go.  The report:
; where games end, what ends them by band, the standing on arrival at
; each level, and what each game used.  BALANCE_TURNS caps a game, 6000
; unless given.  BALANCE_FIRST is the first seed, 1 unless given, so a
; game too long to share a run can have one to itself.  BALANCE_TRACE,
; set to anything, writes a line a key: the turn, level, hit points,
; place and what was said.
;
; BALANCE_KEEP=DIR saves each game, SET-SEED-LABEL.sav in DIR, the turn it
; first sees the creature BALANCE_BOSS names, the fireman unless given,
; or the turn it comes to the level BALANCE_DEPTH gives,
; and ends the game there, reported as capped;
; a game that never sees it leaves its save empty, so a batch wipes its
; own seeds' saves.  BALANCE_FROM=DIR fights again from those saves
; instead of playing games: BALANCE_TRIES times a seed, 20 unless given,
; the dice reseeded each try and the boss's hit points rolled again,
; with BOSS_HP, BOSS_ATTACK, BOSS_DEFENCE, BOSS_LEVEL ("LO HI" or "N")
; and BOSS_TRAITS (words, "-" for none) in place of the set's numbers
; for it, and BALANCE_TURNS, 400 unless given, the most a fight runs.
; LABEL is "0" for a game from the start.  BALANCE_START=DIR plays on
; from each save in DIR instead, BALANCE_TRIES times, 5 unless given,
; the dice reseeded each try, try T of the save labelled L labelled L.T:
; from one boss's saves, with BALANCE_KEEP another directory and
; BALANCE_BOSS the next boss, a batch keeps the games that live to see
; it.  The seed in a save's name is the bot's, whatever its label.
;
; The spread between attributes is the room
; skill has; what tools/model.x says a fight costs is what they
; are measured against.  An instrument, not a gate: nothing here is a
; spec.
;
; lint-known: %lang-root

(import x/type/vector)
(import x/sys/posix)
(import x/sys/gc)
(import x/num/random)
(import x/core/doors int/)
(import roguelike/data data-load data-one data-prop data-all)
(import roguelike/map map-rows map-cols map-in? map-walkable? map-seen? map-down map-up map-tile map-frontier? tile-down tile-up tile-door tile-wall tile-secret)
(import roguelike/state
  game-set game-depth game-deepest game-map game-player game-creatures game-pack game-over game-epitaph game-turn
  game-ask game-messages game-band band-name game-param
  player-r player-c player-hp player-hpmax player-str player-food player-lamp player-doused? player-weapon player-armour player-condition
  item-class item-name item-prop item-prop1 item-enchant item-letter item-r item-c game-floor
  creature-r creature-c creature-state creature-glyph creature-trait? creature-condition creature-hp creature-prop creature-prop1 state-defence state-adjacent? state-in-sight? state-dist state-shortfall state-creature-at state-items-at
  game-quest-state game-screens? game-screen game-screen-key game-hub game-chain game-inside state-creature-named
  game-top-set game-home game-place game-below?
  game-rng game-rng! creature-hp! creature-name state-roll game-traps item-charges player-rings game-blows creature-whole game-exploring?)
(import roguelike/save save-write! save-read)
(import roguelike/creatures creatures-shown? creatures-door-diagonal?)
(import roguelike/items items-goal-held? items-worn items-target items-known?)
(import roguelike/traps traps-found-at trap-r trap-c trap-found?)
(import roguelike/game game-make game-key! game-explore!)
(import roguelike/combat combat-player-dice combat-player-level combat-chill combat-dazzle)
(import roguelike/odds odds-hit odds-swings odds-regen odds-hurt odds-aim)

(def %bl-say (fn (_ text) (Sys fd-write 1 text)))
(def %bl-env
  (fn (_ name default)
    (def v (Sys getenv name))
    (if (if (null? v) #t (str=? v "")) default v)))
(def %bl-int (fn (_ s) ((prim-ref (lit convert) (lit to)) s (Type named INTEGER) 10)))

; A key pressed, and kept for the trace.
(def %bl-tracing (not (str=? (%bl-env "BALANCE_TRACE" "") "")))
(def %bl-pressed (Vector of ()))
(def %bl-key!
  (fn (_ g key)
    (when %bl-tracing (Vector set! 0 (pair key (Vector ref 0 %bl-pressed)) %bl-pressed))
    (game-key! g key)))

; --- what the bot may know ---------------------------------------------------

; The bot knows what a player would: the ground it has seen, the
; creatures in view, the traps found, what the game says, and its pack
; as the game names it.  It knows the rules and the set as one who has
; played before does: each kind's dice and traits, the odds, who stands
; on which level.  It does not know where a creature out of view is, how
; hurt one is, whether one sleeps, or what an untried wand does.

; The creatures in view, and the one of them at R C, or nil.
(def %bl-seen (fn (_ g) (List filter (fn (_ cr) (creatures-shown? g cr)) (game-creatures g))))
(def %bl-seen-at
  (fn (_ g r c) (List find (fn (_ cr) (if (= (creature-r cr) r) (= (creature-c cr) c) #f)) (%bl-seen g))))
; Whether CR is a creature in sight, not one only sensed: what breaks a
; camp (game.x), and what a rest waits on.  One the bot cannot see can
; break a camp too, the game saying "You start up": the rest waits a
; turn on that as well, or the camp is made and broken without end.
(def %bl-in-sight?
  (fn (_ g cr) (if (null? cr) #f (state-in-sight? g (creature-r cr) (creature-c cr)))))
; Whether the game has just said TEXT.
(def %bl-told? (fn (_ g text) (List any? (fn (_ m) (Str8 includes? text m)) (game-messages g))))

; What has been watched of each creature seen on this level, slot 23 of
; S: (CREATURE STIRRED R . C), where it was last seen, and whether it
; has been seen to move or the player was struck with it beside them.
; One that has done neither is taken to be asleep.
(def %bl-watch!
  (fn (_ g s struck?)
    (def p (game-player g))
    (def seen (%bl-seen g))
    (def kept (List reject (fn (_ e) (List any? (fn (_ cr) (same? cr (first e))) seen)) (Vector ref 23 s)))
    (def note
      (fn (_ cr)
        (def was (List find (fn (_ e) (same? (first e) cr)) (Vector ref 23 s)))
        (def beside? (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)))
        (def stirred
          (match ((null? was) (if struck? beside? #f)) ((List ref 1 was) #t)
                 ((if struck? beside? #f) #t)
                 ((not (= (first (rest (rest was))) (creature-r cr))) #t)
                 (#t (not (= (rest (rest (rest was))) (creature-c cr))))))
        (pair cr (pair stirred (pair (creature-r cr) (creature-c cr))))))
    (Vector set! 23 (List append (List map note seen) kept) s)))
(def %bl-watched (fn (_ s cr) (List find (fn (_ e) (same? (first e) cr)) (Vector ref 23 s))))
; Whether CR, in view, is after the player or running from them: the
; look (v) says each creature in view is asleep, has not noticed, is
; awake or is fleeing.
(def %bl-stirring?
  (fn (_ s cr) (match ((eq? (creature-state cr) (lit awake)) #t) ((eq? (creature-state cr) (lit fleeing)) #t) (#t #f))))
; Whether searching in the dark should stop for a hostile: FOE beside,
; or one shown, awake and free to come.  One asleep, not yet noticing,
; fleeing or keeping its place is no threat to a search, so the lamp is
; not lit for it, nor kept lit.
(def %bl-roused?
  (fn (_ g s foe)
    (if (null? foe)
      (not (null? (List find (fn (_ cr) (match ((not (%bl-hostile? cr)) #f) ((creature-trait? cr (lit stationary)) #f)
                                                 ((not (creatures-shown? g cr)) #f) (#t (eq? (creature-state cr) (lit awake)))))
                    (%bl-seen g))))
      #t)))
; How much of its kind's usual hit points CR has left, in eighths, by
; the look's word for it: whole, hurt, badly hurt or nearly dead.
(def %bl-wounds
  (fn (_ cr)
    (def hp (creature-hp cr))
    (def whole (creature-whole cr))
    (match ((not (< hp whole)) 8) ((< whole (* 2 hp)) 6) ((< whole (* 4 hp)) 3) (#t 1))))

; The creatures the bot has slowed with a wand, (CREATURE . UNTIL), and
; the turn its last scroll of stillness holds to: what it did itself,
; and was told of.
(def %bl-slowed (Vector of ()))
(def %bl-still (Vector of 0))
; The wands found empty: one that sputtered.
(def %bl-empty (Vector of ()))

; The turn as the bot's turn began.
(def %bl-now (Vector of 0))
(def %bl-slowed? (fn (_ cr) (< 0 (creature-condition cr (lit slowed)))))
; A rest: under a lamp, a camp, the lamp put out and no oil burned, run
; a turn at a time as a front end runs it, till it breaks; with no lamp
; or none lit, or a camp broken before a turn passed, a turn's wait.
(def %bl-rest!
  (fn (_ g)
    (def run (fn (self n) (when (if (game-exploring? g) (< n 2000) #f) (do (game-explore! g) (Heap collect) (self (+ n 1))))))
    (def turn (game-turn g))
    (when (< 0 (player-lamp (game-player g)))
      (do (%bl-key! g "c") (run 0)))
    (when (= turn (game-turn g)) (%bl-key! g "s"))))
; Whether IT is a wand the bot has tried and that has a charge left: a
; wand that is known shows its charges.
(def %bl-wand-known?
  (fn (_ g it)
    (match ((not (items-known? g it)) #f)
           ((List any? (fn (_ x) (same? x it)) (Vector ref 0 %bl-empty)) #f)
           (#t (< 0 (item-charges it))))))

; --- walking -----------------------------------------------------------------

(def %bl-dirs
  (list (pair "h" (pair 0 -1)) (pair "j" (pair 1 0)) (pair "k" (pair -1 0)) (pair "l" (pair 0 1))
        (pair "y" (pair -1 -1)) (pair "u" (pair -1 1)) (pair "b" (pair 1 -1)) (pair "n" (pair 1 1))))
(def %bl-key-for
  (fn (_ dr dc) (first (List find (fn (_ d) (if (= (first (rest d)) dr) (= (rest (rest d)) dc) #f)) %bl-dirs))))

; The sleepers in view whose fight the bot would not start, set each
; turn: they are left to sleep, and gone round as a sitter is.
(def %bl-wary (Vector of ()))
; Whether CR is a hostile in view that keeps its place, or a sleeper
; best left, to be gone
; round: a walk shuns the cells beside it.
(def %bl-sitter?
  (fn (_ g cr)
    (match ((creature-trait? cr (lit talks)) #f) ((not (creatures-shown? g cr)) #f)
           ((List any? (fn (_ x) (same? x cr)) (Vector ref 0 %bl-wary)) #t)
           (#t (creature-trait? cr (lit stationary))))))
(def %bl-shunned?
  (fn (_ g r c)
    (List any? (fn (_ cr) (if (%bl-sitter? g cr) (state-adjacent? (creature-r cr) (creature-c cr) r c) #f)) (%bl-seen g))))

; Whether the bot, with nowhere left to go on a level, has given up
; going round what sits there.
(def %bl-bold (Vector of 0))
; Where sitters were seen on this level, (R . C) each, gone round out
; of sight as in it: a player remembers what sleeps there, and drops it
; once the place is seen empty.
(def %bl-sat (Vector of ()))
(def %bl-sat!
  (fn (_ g)
    (def here (List map (fn (_ cr) (pair (creature-r cr) (creature-c cr))) (List filter (fn (_ cr) (%bl-sitter? g cr)) (%bl-seen g))))
    (def kept (List reject (fn (_ at) (state-in-sight? g (first at) (rest at))) (Vector ref 0 %bl-sat)))
    (Vector set! 0 (List append here kept) %bl-sat)))

; The cells a walk does not cross, a vector by cell: #t where a creature
; stands and where a trap has been found, which a walk may still end
; on, and `shun` beside a sitter, which it may not: one in view, or one
; remembered where it was seen (%bl-sat).
(def %bl-barred
  (fn (_ g cols n)
    (def v (Vector make n #f))
    (def m (game-map g))
    (def shun!
      (fn (_ at)
        (List for-each
          (fn (_ d)
            (def r (+ (first at) (first (rest d))))
            (def c (+ (rest at) (rest (rest d))))
            (when (map-in? m r c) (Vector set! (+ (* r cols) c) (lit shun) v)))
          %bl-dirs)))
    (when (< (Vector ref 0 %bl-bold) 1)
      (do (List for-each (fn (_ cr) (when (%bl-sitter? g cr) (shun! (pair (creature-r cr) (creature-c cr))))) (%bl-seen g))
          (List for-each (fn (_ at) (shun! at) (Vector set! (+ (* (first at) cols) (rest at)) #t v)) (Vector ref 0 %bl-sat))))
    (List for-each (fn (_ cr) (Vector set! (+ (* (creature-r cr) cols) (creature-c cr)) #t v)) (%bl-seen g))
    (List for-each (fn (_ t) (when (if (< 1 (Vector ref 0 %bl-bold)) #f (trap-found? t)) (Vector set! (+ (* (trap-r t) cols) (trap-c t)) #t v))) (game-traps g))
    v))

; The shortest walk over seen, walkable cells, clear of creatures and
; found traps, from the player to a cell GOAL? allows no more than MOST
; steps away: its cells in order, the goal last, or nil.  A breadth-
; first search, a layer a step.  FROM holds for each cell the cell it
; was reached from, -1 for one that cannot be stood on, so a cell is
; weighed once however many it is beside.
(def %bl-search
  (fn (_ g goal? most)
    (def m (game-map g))
    (def p (game-player g))
    (def cols (map-cols m))
    (def n (* (map-rows m) cols))
    (def from (Vector make n ()))
    (def barred (%bl-barred g cols n))
    (def start (+ (* (player-r p) cols) (player-c p)))
    (def spread
      (fn (self ds r c i t back)
        (if (null? ds) back
          (do (def dr (first (rest (first ds))))
              (def dc (rest (rest (first ds))))
              (def rr (+ r dr))
              (def cc (+ c dc))
              (def j (+ (* rr cols) cc))
              (self (rest ds) r c i t
                (match ((not (map-in? m rr cc)) back)
                       ((not (null? (Vector ref j from))) back)
                       ((not (map-seen? m rr cc)) (do (Vector set! j -1 from) back))
                       ((not (map-walkable? m rr cc)) (do (Vector set! j -1 from) back))
                       ((match ((= dr 0) #f) ((= dc 0) #f) ((= t tile-door) #t) (#t (= (map-tile m rr cc) tile-door))) back)
                       ((eq? (Vector ref j barred) (lit shun)) (do (Vector set! j -1 from) back))
                       ((if (Vector ref j barred) (not (goal? rr cc)) #f) (do (Vector set! j -1 from) back))
                       (#t (do (Vector set! j i from) (pair j back)))))))))
    (def trail (fn (self i path) (if (= i start) path (self (Vector ref i from) (pair i path)))))
    (def search
      (fn (self front back k)
        (match
          ((null? front) (if (if (null? back) #t (< most (+ k 1))) () (self (List reverse back) () (+ k 1))))
          (#t (do (def i (first front))
                  (def r (int/ i cols))
                  (def c (- i (* r cols)))
                  (match ((if (= i start) #f (goal? r c)) (trail i ()))
                         (#t (self (rest front) (spread %bl-dirs r c i (map-tile m r c) back) k))))))))
    (Vector set! start -1 from)
    (search (list start) () 0)))

; The walk kept under TAG in slot 12 of S, as far as it still serves: nil
; unless its next cell is beside the player and can be stepped on, its
; last is still one GOAL? allows, and it is no more than MOST steps.
(def %bl-kept
  (fn (_ g s tag goal? most)
    (def m (game-map g))
    (def p (game-player g))
    (def cols (map-cols m))
    (def here (+ (* (player-r p) cols) (player-c p)))
    (def entry (List find (fn (_ e) (eq? (first e) tag)) (Vector ref 12 s)))
    (def had (if (null? entry) () (rest entry)))
    (def path (if (null? had) () (if (= (first had) here) (rest had) had)))
    (def row (fn (_ i) (int/ i cols)))
    (def col (fn (_ i) (- i (* (row i) cols))))
    (match ((null? path) ())
           ((< most (List length path)) ())
           ((not (state-adjacent? (row (first path)) (col (first path)) (player-r p) (player-c p))) ())
           ((creatures-door-diagonal? m (player-r p) (player-c p) (- (row (first path)) (player-r p)) (- (col (first path)) (player-c p))) ())
           ((not ((fn (_ last) (goal? (row last) (col last))) (List ref (- (List length path) 1) path))) ())
           ((if (< 0 (Vector ref 0 %bl-bold)) #f (%bl-shunned? g (row (first path)) (col (first path)))) ())
           ((null? (rest path)) path)
           ((not (null? (%bl-seen-at g (row (first path)) (col (first path))))) ())
           ((if (< 1 (Vector ref 0 %bl-bold)) #f (not (null? (traps-found-at g (row (first path)) (col (first path)))))) ())
           (#t path))))

; Where the player and every creature stand, as (CELL . SUM): while it
; is as it was, a walk that could not be found still cannot.
(def %bl-standing
  (fn (_ g)
    (def p (game-player g))
    (def cols (map-cols (game-map g)))
    (pair (+ (* (player-r p) cols) (player-c p))
          (List fold (fn (_ sum cr) (% (+ (* 3 sum) (+ (* (creature-r cr) cols) (creature-c cr))) 1000003)) 0 (%bl-seen g)))))
; Whether the walk TAG names was looked for within MOST from this
; standing and not found: slot 15 of S keeps (TAG MOST CELL . SUM) each.
(def %bl-no-way?
  (fn (_ s tag most standing)
    (def e (List find (fn (_ e) (eq? (first e) tag)) (Vector ref 15 s)))
    (match ((null? e) #f) ((not (= (List ref 1 e) most)) #f)
           ((not (= (first (rest (rest e))) (first standing))) #f)
           (#t (= (rest (rest (rest e))) (rest standing))))))

; The first step, (DR . DC), of the walk TAG names to a cell GOAL?
; allows no more than MOST steps away, or nil: the walk kept from the
; turn before while it serves, searched for afresh when it does not,
; and not searched for again from where none was found.  A search can
; make millions of objects, and a turn tries several: the heap is swept
; before each, so a turn's peak is one search's, not their sum.
(def %bl-step-within
  (fn (_ g s tag goal-at? most)
    (def p (game-player g))
    ; A walk onto one of the people is a talk, not a step: their cell is
    ; a goal only for the walks to someone.
    (def goal? (if (match ((eq? tag (lit giver)) #t) ((eq? tag (lit creature)) #t) (#t #f)) goal-at?
                 (fn (_ r c) (if (goal-at? r c)
                               ((fn (_ cr) (if (null? cr) #t (not (creature-trait? cr (lit talks))))) (%bl-seen-at g r c))
                               #f))))
    (def cols (map-cols (game-map g)))
    (def standing (%bl-standing g))
    (def kept (%bl-kept g s tag goal? most))
    (def none? (if (null? kept) (%bl-no-way? s tag most standing) #f))
    (def path (match (none? ()) ((null? kept) (do (Heap collect) (%bl-search g goal? most))) (#t kept)))
    (when %bl-tracing
      (Vector set! 0 (pair (Str8 append "{" (symbol->str tag) (match ((not (null? kept)) " kept") ((null? path) " none") (#t " found")) "}")
                           (Vector ref 0 %bl-pressed))
                  %bl-pressed))
    (Vector set! 12 (pair (pair tag path) (List reject (fn (_ e) (eq? (first e) tag)) (Vector ref 12 s))) s)
    (when (null? path)
      (Vector set! 15 (pair (pair tag (pair most standing)) (List reject (fn (_ e) (eq? (first e) tag)) (Vector ref 15 s))) s))
    (if (null? path) ()
      (do (def r (int/ (first path) cols))
          (pair (- r (player-r p)) (- (- (first path) (* r cols)) (player-c p)))))))

(def %bl-walk!
  (fn (_ g s tag goal?)
    (def d (%bl-step-within g s tag goal? 9999))
    (if (null? d) #f (do (%bl-key! g (%bl-key-for (first d) (rest d))) #t))))

; --- what the bot sees -------------------------------------------------------

(def %bl-hostile? (fn (_ cr) (not (creature-trait? cr (lit talks)))))
(def %bl-beside
  (fn (_ g pred)
    (def p (game-player g))
    (List find (fn (_ cr) (if (pred cr) (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) #f))
      (%bl-seen g))))
; The hostile beside the player to strike, or nil: one that summons
; first, as what it calls keeps coming while it stands; then the one
; that looks most hurt, the soonest down.
(def %bl-foe
  (fn (_ g)
    (def p (game-player g))
    (def beside (List filter (fn (_ cr) (if (%bl-hostile? cr) (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) #f))
                  (%bl-seen g)))
    (def rank (fn (_ cr) (+ (if (creature-trait? cr (lit summon)) 0 10) (%bl-wounds cr))))
    (List fold (fn (_ best cr) (if (null? best) cr (if (< (rank cr) (rank best)) cr best))) () beside)))
; The nearest hostile in view that does not keep its place, or nil.
(def %bl-shown-hostile
  (fn (_ g)
    (def p (game-player g))
    (def far (fn (_ cr) (state-dist (creature-r cr) (creature-c cr) (player-r p) (player-c p))))
    (List fold (fn (_ best cr)
                 (match ((not (%bl-hostile? cr)) best) ((creature-trait? cr (lit stationary)) best)
                        ((not (creatures-shown? g cr)) best) ((null? best) cr)
                        ((< (far cr) (far best)) cr) (#t best)))
      () (%bl-seen g))))
; A step toward CR, or the blow, or the talk, when it is beside the
; player: a step onto a creature is taken whatever it stands on, so one
; beside is walked into and not walked to.
(def %bl-toward-creature!
  (fn (_ g s cr)
    (def p (game-player g))
    (if (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p))
      (do (%bl-key! g (%bl-key-for (- (creature-r cr) (player-r p)) (- (creature-c cr) (player-c p)))) #t)
      (do (when %bl-tracing
            (Vector set! 0 (pair (Str8 append "{to " (creature-name cr) " " (Str8 str (creature-state cr)) " " (Str8 str (creature-r cr)) "," (Str8 str (creature-c cr)) "}")
                                 (Vector ref 0 %bl-pressed)) %bl-pressed))
          (%bl-walk! g s (lit creature) (fn (_ r c) (if (= r (creature-r cr)) (= c (creature-c cr)) #f)))))))

(def %bl-in-pack (fn (_ g pred) (List find pred (game-pack g))))
(def %bl-of-class (fn (_ wanted) (fn (_ it) (eq? (item-class it) wanted))))
(def %bl-named? (fn (_ it name) (str=? (item-name it) name)))

; A weapon's worth: the middle of its dice plus its enchantment; armour's:
; its value and enchantment less what it asks beyond the player's strength.
(def %bl-weapon-worth
  (fn (_ g it)
    (def d (item-prop it (lit damage) (list 1 2)))
    (if (< 0 (state-shortfall g it)) 0 (+ (first d) (List ref 1 d) (* 2 (item-enchant it))))))
(def %bl-armour-worth
  (fn (_ g it) (- (+ (item-prop1 it (lit armour) 0) (item-enchant it)) (state-shortfall g it))))
(def %bl-best
  (fn (_ g group worth)
    (List fold (fn (_ best it) (if (if (null? best) #t (< (worth g best) (worth g it))) it best))
      () (List filter (%bl-of-class group) (game-pack g)))))

; --- the bot's state ---------------------------------------------------------

; S, the bot's own state for a game: 0 whether the level is explored, 1
; the place that was for, 2 potions drunk, 3 foods eaten, 4 whether the
; giver here has been talked to since the level was explored, 5 the
; hostile creatures met, 6 the turn a weapon was first held, 7 the count
; met by then, 8 the items left lying because they would not come up, 9
; the cells beside the unseen already stood on here, a vector by cell,
; 10 oil flasks poured, 11 turns taken with the lamp out, 12 the walks
; kept here, (TAG . CELLS) each, 13 the turn the level was come to, 14
; whether its shaft was found barred, 15 the walks not found, 16 the
; slow creature last stepped clear of, and where it stood, 17 where the
; player last was, 18 how much the pack held at the last talk here, 19
; the foe last set out after, 20 the foes given up here, 21 where the
; last turns were spent, 22 the hit points at the last turn, 23 what
; was watched of each creature, 24 the blows of the last turn, 25
; whether a secret door has been found here since the level was last
; explored, 26 the wall cells searched beside, a vector by cell, 27 the
; secret doors found, 28 the seconds of lamp burnt here, 29 the lamp at
; the last turn.

; Where the player stands, as text: the depth, or on a world of screens
; the screen and any interior.
(def %bl-place
  (fn (_ g)
    (if (game-screens? g)
      (Str8 append (game-screen-key g (first (game-screen g)) (rest (game-screen g))) "/" (if (null? (game-inside g)) "" (game-inside g)))
      (Str8 str (game-depth g)))))
(def %bl-here? (fn (_ g s) (str=? (Vector ref 1 s) (%bl-place g))))
(def %bl-explored? (fn (_ g s) (if (%bl-here? g s) (Vector ref 0 s) #f)))
(def %bl-explored! (fn (_ g s) (Vector set! 0 #t s) (Vector set! 1 (%bl-place g) s) (Vector set! 4 #f s) (Vector set! 25 #f s)))
(def %bl-new-level! (fn (_ g s) (Vector set! 0 #f s) (Vector set! 1 (%bl-place g) s) (Vector set! 4 #f s) (Vector set! 9 () s) (Vector set! 12 () s)
    (Vector set! 25 #f s) (Vector set! 26 () s) (Vector set! 28 0 s) (Vector set! 31 (List length (%bl-secrets g)) s) (Vector set! 33 #f s)
    (Vector set! 13 (game-turn g) s) (Vector set! 14 #f s) (Vector set! 15 () s) (Vector set! 17 () s) (Vector set! 19 () s) (Vector set! 20 () s) (Vector set! 21 () s) (Vector set! 23 () s) (Vector set! 0 () %bl-slowed) (Vector set! 0 0 %bl-bold) (Vector set! 0 () %bl-sat)))

; With nowhere at all to go on a level: the first time, the cells beside
; the unseen are all to be stood on again and what sits is no longer
; gone round; the second, a found trap is no longer gone round either.
; A turn's rest.
(def %bl-unstick!
  (fn (_ g s)
    (def stage (Vector ref 0 %bl-bold))
    (when (< stage 2)
      (do (Vector set! 9 () s)
          (Vector set! 12 () s)
          (Vector set! 15 () s)
          (Vector set! 0 (+ stage 1) %bl-bold)))
    (%bl-key! g "s")))
; Bold, a step toward the nearest hostile on ground that has been seen:
; one asleep in a passage closes it.  #f with none to reach, or not bold.
(def %bl-clear-the-way!
  (fn (_ g s)
    (if (< 0 (Vector ref 0 %bl-bold))
      (%bl-walk! g s (lit blocker) (fn (_ r c) ((fn (_ cr) (if (null? cr) #f (%bl-hostile? cr))) (%bl-seen-at g r c))))
      #f)))
; The bot going to and fro: slot 21 of S keeps the cells of the last
; eight turns with nothing hostile beside it, and when those are two
; cells turn about, four times there and back, what it is after cannot
; be had.  The foe in view and the quarry are given up for the level,
; and the walks kept and those not found are forgotten.
(def %bl-turning!
  (fn (_ g s foe shown)
    (def p (game-player g))
    (def here (+ (* (player-r p) (map-cols (game-map g))) (player-c p)))
    (def past (if (null? foe) (List take 8 (pair here (Vector ref 21 s))) ()))
    (def about?
      (match ((< (List length past) 8) #f) ((= (first past) (List ref 1 past)) #f)
             (#t (List all? (fn (_ k) (= (List ref k past) (List ref (% k 2) past))) (List range 2 8)))))
    (Vector set! 21 (if about? () past) s)
    (when about?
      (do (Vector set! 20 (List reject null? (pair shown (pair (Vector ref 19 s) (Vector ref 20 s)))) s)
          (Vector set! 19 () s)
          (Vector set! 12 () s)
          (Vector set! 15 () s)))))

; The player thrown somewhere else on the level, more than a step from
; where slot 17 of S last had them: the walks kept and those not found
; are for another place, and the bot is no longer bold.
(def %bl-thrown!
  (fn (_ g s)
    (def p (game-player g))
    (def was (Vector ref 17 s))
    (when (if (null? was) #f (< 1 (state-dist (first was) (rest was) (player-r p) (player-c p))))
      (do (Vector set! 12 () s) (Vector set! 15 () s) (Vector set! 0 0 %bl-bold)))
    (Vector set! 17 (pair (player-r p) (player-c p)) s)))

; Whether the level has light left to look about by: the lamp burnt
; here, slot 28 of S, under the share of the oil in hand, lamp and
; flasks, and of what the bands below still lay, that this level and
; each below it to the goal would have alike.  A camp burns none.
; Always, in a set with no lamp.
(def %bl-light-left?
  (fn (_ g s)
    (def p (game-player g))
    (def last (List ref 2 (data-one (game-top-set g) (lit goal) (list "" "" 1))))
    (def oil (List fold (fn (_ n it) (if (eq? (item-class it) (lit oil)) (+ n (item-prop1 it (lit oil) 600)) n)) 0 (game-pack g)))
    (def levels (+ 1 (if (< (game-depth g) last) (- last (game-depth g)) 0)))
    (match ((null? (game-param g (lit lamp) ())) #t) ((< (player-lamp p) 0) #t)
           (#t (< (* levels (Vector ref 28 s)) (+ (player-lamp p) (+ oil (%bl-sure-oil g last))))))))
; The oil the bands owe the levels below this one down to LAST: a band
; lays each oil with (per-band N) N times over its levels, so a level of
; it holds its share.  The bot knows the set, as one who has played.
(def %bl-sure-oil
  (fn (_ g last)
    (def tos (List map (fn (_ b) (List ref 1 b)) (data-all (game-set g) (lit band))))
    (def each (List fold (fn (_ n f) (if (eq? (first f) (lit oil))
                                       (+ n (* (first (data-prop f (lit per-band) (list 0))) (first (data-prop f (lit oil) (list 0))))) n))
                0 (data-all (game-set g) (lit item))))
    (def share
      (fn (_ d)
        (def to (List find (fn (_ t) (not (< t d))) tos))
        (def before (List filter (fn (_ t) (< t d)) tos))
        (def from (if (null? before) 1 (+ 1 (List fold (fn (_ a b) (if (< a b) b a)) 0 before))))
        (if (null? to) 0 (int/ each (+ 1 (- to from))))))
    (List fold (fn (_ n d) (+ n (share d))) 0 (List range (+ 1 (game-depth g)) (+ 1 last)))))

; The letter of what an upgrade goes on: the weapon in hand, else the
; armour worn, else none of them.
(def %bl-upgraded
  (fn (_ g)
    (def p (game-player g))
    (match ((not (null? (player-weapon p))) (item-letter (player-weapon p)))
           ((not (null? (player-armour p))) (item-letter (player-armour p)))
           (#t (lit escape)))))
(def %bl-answer!
  (fn (_ g q)
    (%bl-key! g (match ((eq? (first q) (lit choose)) "a") ((eq? (first q) (lit yn)) "n")
                        ((if (eq? (first q) (lit item)) (str=? (List ref 1 q) "Upgrade what?") #f) (%bl-upgraded g))
                        ((eq? (first q) (lit more)) (lit enter)) ((eq? (first q) (lit look)) (lit enter)) (#t (lit escape))))))

(def %bl-use! (fn (_ g key it) (%bl-key! g key) (%bl-key! g (item-letter it))))

; Whether to walk into the giver CR: not yet since the level was reached
; or explored, or holding a token with a pack not as it was at the last
; talk here, slot 18 of S: a token this giver does not want changes
; nothing, and is not offered twice.
(def %bl-talk?
  (fn (_ g s cr)
    (match ((not (Vector ref 4 s)) #t)
           ((null? (%bl-in-pack g (%bl-of-class (lit token)))) #f)
           (#t (not (= (Vector ref 18 s) (List length (game-pack g))))))))

; The items at R C the bot has not given up on.
(def %bl-given-up? (fn (_ s it) (List any? (fn (_ x) (same? x it)) (Vector ref 8 s))))
(def %bl-wanted-at
  (fn (_ g s r c) (List reject (fn (_ it) (%bl-given-up? s it)) (state-items-at g r c))))
; Whether any item the bot has not given up lies on a seen cell: the
; walk to one searches the whole seen map, so it waits on this.
(def %bl-any-wanted?
  (fn (_ g s)
    (List any? (fn (_ it) (if (map-seen? (game-map g) (item-r it) (item-c it)) (not (%bl-given-up? s it)) #f)) (game-floor g))))

; Picks up what lies here; what stays put is left for good.
(def %bl-pick-up!
  (fn (_ g s)
    (def p (game-player g))
    (%bl-key! g ",")
    (List for-each (fn (_ it) (Vector set! 8 (pair it (Vector ref 8 s)) s))
      (%bl-wanted-at g s (player-r p) (player-c p)))))

(def %bl-at-stairs?(fn (_ g t) (= (map-tile (game-map g) (player-r (game-player g)) (player-c (game-player g))) t)))
(def %bl-stairs-goal (fn (_ g t) (fn (_ r c) (= (map-tile (game-map g) r c) t))))

; A step toward the nearest seen cell beside the unseen that the player
; has not yet stood on here, or #f with none to reach.  Standing on one
; spends it: some edges never show what lies past them, and a walk back
; to one would go to and fro for good.  One a person stands on is left:
; a walk onto it is a talk.
(def %bl-to-frontier!
  (fn (_ g s)
    (def m (game-map g))
    (def p (game-player g))
    (def cols (map-cols m))
    (when (null? (Vector ref 9 s)) (Vector set! 9 (Vector make (* (map-rows m) cols) #f) s))
    (def spent (Vector ref 9 s))
    (Vector set! (+ (* (player-r p) cols) (player-c p)) #t spent)
    (def person? (fn (_ r c) ((fn (_ cr) (if (null? cr) #f (creature-trait? cr (lit talks)))) (%bl-seen-at g r c))))
    (%bl-walk! g s (lit frontier)
      (fn (_ r c) (match ((Vector ref (+ (* r cols) c) spent) #f) ((person? r c) #f) (#t (map-frontier? m r c)))))))

; --- walls that could hide a room --------------------------------------------

; A secret door draws as wall, and is read as one: whether the seen cell
; at R C shows as wall.
(def %bl-wall-shown?
  (fn (_ m r c)
    (if (map-seen? m r c) ((fn (_ t) (if (= t tile-wall) #t (= t tile-secret))) (map-tile m r c)) #f)))
; Whether, past the wall a step from R C along DR DC, a block two deep
; and three across lies unseen, the cells straight behind the wall among
; them: room enough for the smallest room a secret door hides, two deep
; and three wide, its door anywhere along it, and its far side inside
; BOX, the block the seen level spans.
(def %bl-unseen-behind?
  (fn (_ m box r c dr dc)
    (def unseen?
      (fn (_ k j)
        (def rr (+ r (+ (* k dr) (* j dc))))
        (def cc (+ c (+ (* k dc) (* j dr))))
        (if (map-in? m rr cc) (not (map-seen? m rr cc)) #f)))
    (if (List any?
          (fn (_ from)
            (List all? (fn (_ k) (List all? (fn (_ j) (unseen? k j)) (List range from (+ from 3)))) (list 2 3)))
          (list -2 -1 0))
      (%bl-in-box? box (+ r (* 3 dr)) (+ c (* 3 dc)))
      #f)))
; The rows and columns the seen cells span, (TOP BOTTOM LEFT RIGHT): the
; level is rooms packed in a block, and unseen ground inside the block
; is room enough for one, where rock past its edge is only rock.
(def %bl-seen-box
  (fn (_ m)
    (def rows (List filter (fn (_ r) (List any? (fn (_ c) (map-seen? m r c)) (List range 0 (map-cols m)))) (List range 0 (map-rows m))))
    (def cols (List filter (fn (_ c) (List any? (fn (_ r) (map-seen? m r c)) rows)) (List range 0 (map-cols m))))
    (if (null? rows) (list 0 -1 0 -1) (list (first rows) (first (List reverse rows)) (first cols) (first (List reverse cols))))))
(def %bl-in-box?
  (fn (_ box r c)
    (if (< r (first box)) #f (if (< (List ref 1 box) r) #f (if (< c (List ref 2 box)) #f (not (< (List ref 3 box) c)))))))
; Whether the unseen ground at R C is a pocket the level closes round:
; of the four ways out of it, three meet a seen cell within 16 unseen
; ones, not the map's edge.
(def %bl-enclosed?
  (fn (_ m r c)
    (def shut?
      (fn (self rr cc dr dc n)
        (match ((not (map-in? m rr cc)) #f) ((map-seen? m rr cc) #t) ((< 15 n) #f)
               (#t (self (+ rr dr) (+ cc dc) dr dc (+ n 1))))))
    (< 2 (List length (List filter (fn (_ d) (shut? (+ r (first d)) (+ c (rest d)) (first d) (rest d) 0))
                                   (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1)))))))
; Whether R C is a place to search from: walkable and seen, a wall beside
; it across a side not yet searched, unseen ground behind that wall, and
; with POCKET? that ground a pocket.  Slot 26 of S holds the wall cells
; searched beside, a vector by cell.
(def %bl-search-spot?
  (fn (_ g s pocket? r c)
    (def m (game-map g))
    (def cols (map-cols m))
    (def searched (Vector ref 26 s))
    (if (if (map-seen? m r c) (map-walkable? m r c) #f)
      (List any?
        (fn (_ d)
          (def wr (+ r (first d)))
          (def wc (+ c (rest d)))
          (match ((not (%bl-wall-shown? m wr wc)) #f) ((Vector ref (+ (* wr cols) wc) searched) #f)
                 ((not (%bl-unseen-behind? m (Vector ref 30 s) r c (first d) (rest d))) #f)
                 (pocket? (%bl-enclosed? m (+ r (* 2 (first d))) (+ c (* 2 (rest d)))))
                 (#t #t)))
        (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1)))
      #f)))
; A search here, every wall beside the player kept as searched.
(def %bl-search-here!
  (fn (_ g s)
    (def m (game-map g))
    (def p (game-player g))
    (def cols (map-cols m))
    (List for-each
      (fn (_ dr)
        (List for-each
          (fn (_ dc)
            (def r (+ (player-r p) dr))
            (def c (+ (player-c p) dc))
            (when (map-in? m r c) (Vector set! (+ (* r cols) c) #t (Vector ref 26 s))))
          (list -1 0 1)))
      (list -1 0 1))
    (%bl-key! g "s")))
; With the goal not yet held, a search for a secret door: here, at a
; place to search from, or a step toward the nearest within SEARCH
; steps, a pocket's before any other; none on a level a survey has
; shown, which opens them all, nor once the way down has been seen:
; a door hidden then hides nothing the game needs, and the turns spent
; tapping walls are lamp oil.  With no light left for the
; level the lamp is put out first and the walls searched in the dark,
; a search beside needing none; it is lit again when there is light to
; spare or nothing left to search.  #f with nothing to do.
(def %bl-to-wall!
  (fn (_ g s who)
    (def m (game-map g))
    (def p (game-player g))
    (def most (%bl-at who (lit search)))
    (when (null? (Vector ref 26 s)) (Vector set! 26 (Vector make (* (map-rows m) (map-cols m)) #f) s))
    (Vector set! 30 (%bl-seen-box m) s)
    (def aim
      (fn (_ tag pocket?)
        (if (%bl-search-spot? g s pocket? (player-r p) (player-c p)) (lit here)
          (%bl-step-within g s tag (fn (_ r c) (%bl-search-spot? g s pocket? r c)) most))))
    (def lit? (if (str=? (%bl-env "BALANCE_DARK_SEARCH" "") "") (%bl-light-left? g s) #t))
    (def down (map-down m))
    (def a (match ((< most 1) ()) ((items-goal-held? g) ()) ((Vector ref 33 s) ())
                  ((if (null? down) #f (map-seen? m (first down) (rest down))) ())
                  (#t ((fn (_ a) (if (null? a) (aim (lit wall) #f) a)) (aim (lit pocket) #t)))))
    (def out? (player-doused? p))
    (when (if %bl-tracing (not lit?) #f)
      (Vector set! 0 (pair (Str8 append "{dark: " (Str8 str (Vector ref 28 s)) " burnt}") (Vector ref 0 %bl-pressed)) %bl-pressed))
    (match ((null? a) (if (if out? (< 0 (player-lamp p)) #f) (do (%bl-key! g "x") #t) #f))
           ((if out? lit? #f) (do (%bl-key! g "x") #t))
           ((if lit? #f (if out? #f (< 0 (player-lamp p))))
             (if (%bl-roused? g s ()) #f (do (%bl-key! g "x") #t)))
           ((eq? a (lit here)) (do (%bl-search-here! g s) #t))
           (#t (do (%bl-key! g (%bl-key-for (first a) (rest a))) #t)))))

; --- who the bot is ----------------------------------------------------------

; The bots' make, tools/bots/attributes.xon: the attributes and their
; ranges, and the archetypes that narrow them.  The ranges a run rolls
; in: each attribute's, or the archetype's BALANCE_ARCHETYPE names.
(def %bl-make (fn (_) (data-load (Str8 append %lang-root "/tools/bots"))))
(def %bl-ranges
  (fn (_ make)
    (def name (%bl-env "BALANCE_ARCHETYPE" ""))
    (def kind (List find (fn (_ f) (str=? (first f) name)) (data-all make (lit archetype))))
    (when (if (str=? name "") #f (null? kind)) (Err raise (lit value) "no such archetype" name))
    (List map (fn (_ a)
                (def narrowed (if (null? kind) () (data-prop kind (first a) ())))
                (list (first a) (if (null? narrowed) (List ref 1 a) (first narrowed))
                      (if (null? narrowed) (List ref 2 a) (List ref 1 narrowed))))
      (data-all make (lit attribute)))))

; The bot for SEED: (ARCHETYPE (ATTRIBUTE . N) ...), each N rolled in its
; range from a random source of its own, made from the seed so the
; game's is untouched, unless BALANCE_ATTRIBUTE fixes it.
(def %bl-who
  (fn (_ ranges seed)
    (def rng (Random sw (+ 7919 seed)))
    (pair (%bl-env "BALANCE_ARCHETYPE" "anyone")
      (List map (fn (_ a)
                  (def n (rng between (List ref 1 a) (List ref 2 a)))
                  (def given (%bl-env (Str8 append "BALANCE_" (Str8 upcase (symbol->str (first a)))) ""))
                  (pair (first a) (if (str=? given "") n (%bl-int given))))
        ranges))))
(def %bl-who-text
  (fn (_ who) (Str8 join " " (List map (fn (_ kv) (Str8 append (symbol->str (first kv)) " " (Str8 str (rest kv)))) (rest who)))))
(def %bl-at (fn (_ who key) (rest (List find (fn (_ kv) (eq? (first kv) key)) (rest who)))))

; Whether the player has under PCT % of full hit points.
(def %bl-under? (fn (_ p pct) (< (* 100 (player-hp p)) (* pct (player-hpmax p)))))
; The % WHO rests to under KEY, rest or ready: while the lamp burns no
; more than LIT, as resting spends the light, unless a guardian is here
; to be met whole.
(def %bl-mark
  (fn (_ g s who key)
    (def full (%bl-at who key))
    (match ((< (player-lamp (game-player g)) 1) full) ((Vector ref 14 s) full) ((not (null? (%bl-guardian g))) full)
           ((< (%bl-at who (lit lit)) full) (%bl-at who (lit lit)))
           (#t full))))

; A step out of CR's reach, one beside no other hostile first, then the
; furthest, then one out of the line of every hostile in view that
; shoots or breathes; or #f when none gains, or when held, as a step
; then goes nowhere and the turn is lost.  Backing off beside another
; is struck by it, and down a shooter's line is shot all the way.
(def %bl-away!
  (fn (_ g cr)
    (def p (game-player g))
    (def m (game-map g))
    (if (%bl-held? g) #f (%bl-away-from! g cr p m))))
; Whether the player is held, so that a step goes nowhere.
(def %bl-held? (fn (_ g) (< 0 (player-condition (game-player g) (lit held)))))
(def %bl-away-from!
  (fn (_ g cr p m)
    (def shooters (List filter (fn (_ x) (if (%bl-hostile? x) (if (creature-trait? x (lit ranged)) #t (creature-trait? x (lit breath))) #f))
                               (%bl-seen g)))
    (def others (List filter (fn (_ x) (if (same? x cr) #f (%bl-hostile? x))) (%bl-seen g)))
    (def far
      (fn (_ r c)
        ((fn (_ d)
           (match ((< d 2) (* 2 d))
                  (#t (+ (if (List any? (fn (_ x) (state-adjacent? (creature-r x) (creature-c x) r c)) others) 0 100)
                         (* 2 d) (if (List any? (fn (_ x) (%bl-in-line? x r c)) shooters) 0 1)))))
         (state-dist r c (creature-r cr) (creature-c cr)))))
    (def best
      (List fold
        (fn (_ best d)
          (def r (+ (player-r p) (first (rest d))))
          (def c (+ (player-c p) (rest (rest d))))
          (match ((not (map-in? m r c)) best) ((not (map-walkable? m r c)) best)
                 ((not (null? (%bl-seen-at g r c))) best)
                 ((not (null? (traps-found-at g r c))) best)
                 ((creatures-door-diagonal? m (player-r p) (player-c p) (first (rest d)) (rest (rest d))) best)
                 ((< (first best) (far r c)) (pair (far r c) (first d)))
                 (#t best)))
        (pair (far (player-r p) (player-c p)) ()) %bl-dirs))
    (if (null? (rest best)) #f (do (%bl-key! g (rest best)) #t))))

; The percentage of the level's open ground the player has seen.
(def %bl-seen-pct
  (fn (_ g)
    (def m (game-map g))
    (def cols (map-cols m))
    (def count
      (fn (self i open seen)
        (if (< i (* (map-rows m) cols))
          (do (def r (int/ i cols))
              (def c (- i (* r cols)))
              (if (map-walkable? m r c) (self (+ i 1) (+ open 1) (if (map-seen? m r c) (+ seen 1) seen)) (self (+ i 1) open seen)))
          (if (= open 0) 100 (int/ (* 100 seen) open)))))
    (count 0 0 0)))

; --- weighing a fight --------------------------------------------------------

; The hit points a fight with CR is likely to cost the player: the swings
; to take what CR has left, by the game's odds (odds.x), its regeneration
; counted and, dazzling, its spoiling the player's aim, times what it
; does a turn at its speed and, cold, slowing the player.
(def %bl-speed
  (fn (_ cr) (match ((creature-trait? cr (lit fast)) (lit fast)) ((creature-trait? cr (lit slow)) (lit slow)) (#t ()))))
(def %bl-turns
  (fn (_ g cr)
    (def span (creature-prop cr (lit hp) (list 1 6)))
    (def hp (int/ (+ (* (%bl-wounds cr) (+ (first span) (List ref 1 span) 1)) 15) 16))
    (def t (odds-swings (odds-hit (combat-player-level g) (creature-prop1 cr (lit defence) 3)) (combat-player-dice g) 0 hp))
    (def aim (odds-aim (creature-prop1 cr (lit level) 1) (state-defence g) (%bl-speed cr)
                       (if (creature-trait? cr (lit dazzle)) combat-dazzle 0)))
    (/ (if (creature-trait? cr (lit regen)) (odds-regen t hp) t) aim)))
(def %bl-hurt
  (fn (_ g cr)
    (odds-hurt (creature-prop1 cr (lit level) 1) (creature-prop cr (lit attack) (list 1 2)) (state-defence g) (%bl-speed cr)
               (if (creature-trait? cr (lit cold)) combat-chill 0))))
(def %bl-cost (fn (_ g cr) (* (%bl-turns g cr) (%bl-hurt g cr))))
; The hurt a turn from every hostile in view but CR able to reach the
; player: one beside at its blow, one that shoots or breathes with the
; player in its line at three tenths of its shot; one held counted for
; nothing.
(def %bl-volley
  (fn (_ g cr)
    (def p (game-player g))
    (def shot
      (fn (_ x)
        (def span (if (creature-trait? x (lit breath)) (creature-prop x (lit bolt) (list 2 8)) (creature-prop x (lit ranged) (list 1 4))))
        (/ (* 3 (+ (first span) (List ref 1 span))) 20)))
    (List fold
      (fn (_ sum x)
        (match ((same? x cr) sum)
               ((not (%bl-hostile? x)) sum)
               ((< 0 (creature-condition x (lit held))) sum)
               ((state-adjacent? (creature-r x) (creature-c x) (player-r p) (player-c p)) (+ sum (%bl-hurt g x)))
               ((if (creature-trait? x (lit ranged)) #f (not (creature-trait? x (lit breath)))) sum)
               ((not (%bl-in-line? x (player-r p) (player-c p))) sum)
               ((null? (%bl-aim g x)) sum)
               (#t (+ sum (shot x)))))
      0 (%bl-seen g))))
; Whether the fight with CR is likely lost: it costs all the player has,
; with what else in view reaches the player while it lasts.
(def %bl-losing?
  (fn (_ g cr) (not (< (* (%bl-turns g cr) (+ (%bl-hurt g cr) (%bl-volley g cr))) (player-hp (game-player g))))))
; Whether WHO would start the fight with CR: it costs no more than
; COURAGE % of what the player has.
(def %bl-worth?
  (fn (_ g who cr)
    (def cost (* (%bl-turns g cr) (+ (%bl-hurt g cr) (%bl-volley g cr))))
    (not (< (* (player-hp (game-player g)) (%bl-at who (lit courage))) (* 100 cost)))))
; Whether POTION's least mending fits in what the player has lost.
(def %bl-mends?
  (fn (_ g potion)
    (def p (game-player g))
    (def e (item-prop potion (lit effect) (list (lit heal) 1 1)))
    (not (< (- (player-hpmax p) (player-hp p)) (List ref 1 e)))))
; Whether to drink POTION with FOE beside: the fight lost without it, and
; the potion's least mending all of use.
(def %bl-drink-now?
  (fn (_ g foe potion)
    (match ((null? foe) #f) ((null? potion) #f) ((%bl-losing? g foe) (%bl-mends? g potion)) (#t #f))))
; Whether a step away from CR gains a turn: not when the player is slowed
; or held, nor from one that is fast or shoots, as it then strikes for
; each step.
(def %bl-free?
  (fn (_ g cr)
    (def p (game-player g))
    (match ((< 0 (player-condition p (lit slowed))) #f)
           ((< 0 (player-condition p (lit held))) #f)
           ((creature-trait? cr (lit ranged)) #f)
           (#t (not (creature-trait? cr (lit fast)))))))

; --- the slow, outpaced ------------------------------------------------------

; Whether CR takes a turn in two: slow or slowed, and neither fast nor
; hastened.
(def %bl-slow?
  (fn (_ cr)
    (match ((creature-trait? cr (lit fast)) #f)
           ((%bl-slowed? cr) #t)
           ((creature-trait? cr (lit slow)) #t)
           (#t #f))))
; Whether the slow take a turn after the player's next key: they do on
; an odd turn, and the turn is counted before they move.
(def %bl-slow-next? (fn (_ g) (= 0 (% (game-turn g) 2))))
(def %bl-hostile-beside?
  (fn (_ g r c)
    (List any? (fn (_ cr) (if (%bl-hostile? cr) (state-adjacent? (creature-r cr) (creature-c cr) r c) #f)) (%bl-seen g))))
; Whether what is beside the player can be outpaced: every hostile
; there slow, and the player at their own pace and not held.
(def %bl-outpace?
  (fn (_ g)
    (def p (game-player g))
    (match ((< 0 (player-condition p (lit slowed))) #f)
           ((< 0 (player-condition p (lit hasted))) #f)
           ((< 0 (player-condition p (lit held))) #f)
           (#t (List all?(fn (_ cr)
                              (match ((not (%bl-hostile? cr)) #t)
                                     ((not (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p))) #t)
                                     (#t (%bl-slow? cr))))
                 (%bl-seen g))))))
; Whether R C is where CR can shoot to: on its row, column or diagonal
; within seven cells.
(def %bl-in-line?
  (fn (_ cr r c)
    (def dr (- r (creature-r cr)))
    (def dc (- c (creature-c cr)))
    (def ar (if (< dr 0) (- 0 dr) dr))
    (def ac (if (< dc 0) (- 0 dc) dc))
    (match ((< 7 ar) #f) ((< 7 ac) #f) ((= ar 0) #t) ((= ac 0) #t) (#t (= ar ac)))))
; A hostile awake that shoots and has the player in its line with
; nothing between, in view or not: a shot shows where it came from.  Or
; nil.
(def %bl-shooter
  (fn (_ g)
    (def p (game-player g))
    (List find (fn (_ cr)
                 (match ((not (%bl-hostile? cr)) #f) ((not (creature-trait? cr (lit ranged))) #f)

                        ((not (%bl-in-line? cr (player-r p) (player-c p))) #f)
                        (#t (not (null? (%bl-aim g cr))))))
      (%bl-seen g))))
; A step out of CR's line, or #f with none.
(def %bl-out-of-line!
  (fn (_ g cr)
    (def p (game-player g))
    (def m (game-map g))
    (def hit
      (List find
        (fn (_ d)
          (def r (+ (player-r p) (first (rest d))))
          (def c (+ (player-c p) (rest (rest d))))
          (match ((not (map-in? m r c)) #f) ((not (map-walkable? m r c)) #f)
                 ((creatures-door-diagonal? m (player-r p) (player-c p) (first (rest d)) (rest (rest d))) #f)
                 ((not (null? (%bl-seen-at g r c))) #f)
                 ((not (null? (traps-found-at g r c))) #f)
                 (#t (not (%bl-in-line? cr r c)))))
        %bl-dirs))
    (match ((%bl-held? g) #f) ((null? hit) #f) (#t (do (%bl-key! g (first hit)) #t)))))

; Whether the player can stand on R C: walkable, with no creature and no
; found trap on it.
(def %bl-free?-cell
  (fn (_ g r c)
    (def m (game-map g))
    (match ((not (map-in? m r c)) #f) ((not (map-walkable? m r c)) #f)
           ((not (null? (%bl-seen-at g r c))) #f)
           (#t (null? (traps-found-at g r c))))))
; How much ground lies open past R C, to MOST cells: those that can be
; stood on, beside nothing hostile, reached from it a step at a time.  A
; dead end has little.
(def %bl-room
  (fn (_ g r c most)
    (def cols (map-cols (game-map g)))
    (def grow
      (fn (self front seen n)
        (match ((null? front) n) ((not (< n most)) n)
               (#t (do (def at (first front))
                       (def new (List filter
                                  (fn (_ d)
                                    (def rr (+ (first at) (first (rest d))))
                                    (def cc (+ (rest at) (rest (rest d))))
                                    (match ((List includes? (+ (* rr cols) cc) seen) #f) ((not (%bl-free?-cell g rr cc)) #f)
                                           (#t (not (%bl-hostile-beside? g rr cc)))))
                                  %bl-dirs))
                       (def cells (List map (fn (_ d) (pair (+ (first at) (first (rest d))) (+ (rest at) (rest (rest d))))) new))
                       (self (List append (rest front) cells)
                             (List append (List map (fn (_ k) (+ (* (first k) cols) (rest k))) cells) seen)
                             (+ n (List length cells))))))))
    (grow (list (pair r c)) (list (+ (* r cols) c)) 1)))
; A step to a cell beside nothing hostile, the one with the most room
; past it, or #f with none.
(def %bl-clear-step! (fn (_ g) (%bl-step-clear-of! g %bl-hostile?)))
; With slow and other hostiles beside the player, on the slow ones'
; turn: a step to a cell beside none of the slow, so they spend it
; following and the rest are fought alone.  #f with no such step, or
; when every one beside is slow (outpaced) or none is.
(def %bl-shed-slow!
  (fn (_ g)
    (def p (game-player g))
    (def beside (List filter (fn (_ cr) (if (%bl-hostile? cr) (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) #f))
                             (%bl-seen g)))
    (match ((not (%bl-slow-next? g)) #f)
           ((< 0 (player-condition p (lit slowed))) #f)
           ((< 0 (player-condition p (lit held))) #f)
           ((not (List any? %bl-slow? beside)) #f)
           ((List all? %bl-slow? beside) #f)
           (#t (%bl-step-clear-of! g (fn (_ cr) (if (%bl-hostile? cr) (%bl-slow? cr) #f)))))))
; A step to a cell beside none that COUNTS? allows, the one with the
; most room past it, or #f with none.
(def %bl-step-clear-of!
  (fn (_ g counts?)
    (def p (game-player g))
    (def m (game-map g))
    (def best
      (List fold
        (fn (_ best d)
          (def r (+ (player-r p) (first (rest d))))
          (def c (+ (player-c p) (rest (rest d))))
          (match ((not (%bl-free?-cell g r c)) best)
                 ((creatures-door-diagonal? m (player-r p) (player-c p) (first (rest d)) (rest (rest d))) best)
                 ((List any? (fn (_ cr) (if (counts? cr) (state-adjacent? (creature-r cr) (creature-c cr) r c) #f)) (%bl-seen g)) best)
                 (#t ((fn (_ room) (if (< (first best) room) (pair room (first d)) best)) (%bl-room g r c 24)))))
        (pair 0 ()) %bl-dirs))
    (match ((%bl-held? g) #f) ((null? (rest best)) #f) (#t (do (%bl-key! g (rest best)) #t)))))
; Whether FOE stands where it stood when the player last stepped clear
; of it, slot 16 of S, (CREATURE R . C): it does not follow, and
; stepping clear of it again gains nothing.
(def %bl-stays?
  (fn (_ s foe)
    (def was (Vector ref 16 s))
    (match ((null? was) #f) ((not (same? (first was) foe)) #f)
           ((not (= (first (rest was)) (creature-r foe))) #f)
           (#t (= (rest (rest was)) (creature-c foe))))))
; How many of the eight cells about R C can be stood on: how many can
; come at one who stands there.
(def %bl-open
  (fn (_ g r c)
    (def m (game-map g))
    (List length (List filter (fn (_ d) (map-walkable? m (+ r (first (rest d))) (+ c (rest (rest d))))) %bl-dirs))))
; With two or more hostile beside the player, a step to the cell beside
; them that fewest can come at, when it is narrower than where they
; stand: a pack is met in a passage, one at a time.  Not when held.  #f
; with no such step.
(def %bl-to-passage!
  (fn (_ g)
    (def p (game-player g))
    (def m (game-map g))
    (def crowd (List length (List filter (fn (_ cr) (if (%bl-hostile? cr) (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) #f))
                              (%bl-seen g))))
    (def best
      (List fold
        (fn (_ best d)
          (def r (+ (player-r p) (first (rest d))))
          (def c (+ (player-c p) (rest (rest d))))
          (match ((not (%bl-free?-cell g r c)) best)
                 ((creatures-door-diagonal? m (player-r p) (player-c p) (first (rest d)) (rest (rest d))) best)
                 ((< (%bl-open g r c) (first best)) (pair (%bl-open g r c) (first d)))
                 (#t best)))
        (pair (%bl-open g (player-r p) (player-c p)) ()) %bl-dirs))
    (match ((< crowd 2) #f) ((< 0 (player-condition p (lit held))) #f) ((null? (rest best)) #f)
           (#t (do (%bl-key! g (rest best)) #t)))))

; The slow FOE beside the player, outpaced: struck on the turn it cannot
; answer; on the turn it can, one not yet after the player waited on,
; one that follows stepped clear of, and one that stays struck, two
; blows to its one.  With nowhere clear of every hostile to step, a step
; out of its reach all the same, so its turn goes on following; with
; none, it is struck.
(def %bl-outpace!
  (fn (_ g s who foe)
    (def stood (pair foe (pair (creature-r foe) (creature-c foe))))
    (match ((not (%bl-slow-next? g)) (%bl-toward-creature! g s foe))
           ((not (%bl-stirring? s foe)) (%bl-key! g "s"))
           ((%bl-stays? s foe) (%bl-toward-creature! g s foe))
           ((%bl-clear-step! g) (Vector set! 16 stood s))
           ((%bl-away! g foe) (Vector set! 16 stood s))
           (#t (%bl-toward-creature! g s foe)))))
; Whether to wait for CR to come: slow, awake, and two cells off, so its
; next step brings it beside the player on a turn it cannot strike.  A
; slow one steps every other turn, so one still in the cell it held
; when the wait began three turns on is not coming, and is not waited
; for there again.  The wait, (CR R C TURN), is kept in %bl-awaited.
; None with one that shoots in sight: every turn waited is a shot.
(def %bl-awaited (Vector of ()))
(def %bl-await?
  (fn (_ g s cr)
    (def p (game-player g))
    (def w (Vector ref 0 %bl-awaited))
    (def same-wait? (match ((null? w) #f) ((not (same? (first w) cr)) #f)
                           (#t (if (= (List ref 1 w) (creature-r cr)) (= (List ref 2 w) (creature-c cr)) #f))))
    (def shot? (if (%bl-told? g "shoots") #t
                 (List any? (fn (_ x) (if (%bl-hostile? x) (if (creature-trait? x (lit ranged)) (%bl-in-sight? g x) #f) #f)) (%bl-seen g))))
    (def wait? (match ((null? cr) #f) (shot? #f) ((not (%bl-slow? cr)) #f) ((not (eq? (creature-state cr) (lit awake))) #f)
                      ((not (= 2 (state-dist (creature-r cr) (creature-c cr) (player-r p) (player-c p)))) #f)
                      (same-wait? (< (game-turn g) (+ 3 (List ref 3 w))))
                      (#t #t)))
    (when (if wait? (not same-wait?) #f)
      (Vector set! 0 (list cr (creature-r cr) (creature-c cr) (game-turn g)) %bl-awaited))
    wait?))

; --- what the pack answers with ----------------------------------------------

; The bot knows a thing by its make, not its guise: a player learns a
; wand by zapping it, the bot is told.

; The first thing of CLASS in the pack whose effect is NAME, a wand only
; with a charge left; or nil.
(def %bl-with-effect
  (fn (_ g class name)
    (%bl-in-pack g
      (fn (_ it)
        (def e (item-prop it (lit effect) ()))
        (match ((not (eq? (item-class it) class)) #f) ((null? e) #f) ((not (eq? (first e) name)) #f)
               ((eq? class (lit wand)) (%bl-wand-known? g it))
               (#t #t))))))
; The first of NAMES the pack has a thing of CLASS for.
(def %bl-first-effect
  (fn (_ g class names)
    (List fold (fn (_ hit name) (if (null? hit) (%bl-with-effect g class name) hit)) () names)))

; What every hostile beside the player is likely to cost together, one
; held still counted for nothing.
(def %bl-peril
  (fn (_ g)
    (def p (game-player g))
    (List fold
      (fn (_ sum cr)
        (match ((not (%bl-hostile? cr)) sum)
               ((not (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p))) sum)
               ((< 0 (creature-condition cr (lit held))) sum)
               (#t (+ sum (%bl-cost g cr)))))
      0 (%bl-seen g))))

; The way, (DR . DC), a wand is pointed at CR: along a row, a column or
; a diagonal, within eight cells, with nothing else in the way; or nil.
(def %bl-aim
  (fn (_ g cr)
    (def p (game-player g))
    (def dr (- (creature-r cr) (player-r p)))
    (def dc (- (creature-c cr) (player-c p)))
    (def ar (if (< dr 0) (- 0 dr) dr))
    (def ac (if (< dc 0) (- 0 dc) dc))
    (def way (pair (%bl-sign dr) (%bl-sign dc)))
    (match ((< 8 ar) ()) ((< 8 ac) ())
           ((not (match ((= ar 0) #t) ((= ac 0) #t) (#t (= ar ac)))) ())
           ((same? cr (items-target g (player-r p) (player-c p) (first way) (rest way) 8)) way)
           (#t ()))))
; Whether CR is one to turn a wand on.  Charges are few, and kept for
; what cannot be had another way: a band's guardian; any beside a
; confused player, whose swings go astray where a wand's aim does not;
; and any other, one that keeps its place among them, only when the
; fight beside the player is likely lost,
; by the odds or by blows from the unseen, which the odds do not weigh.
(def %bl-dear?
  (fn (_ g s who cr)
    (def p (game-player g))
    (def guardian (%bl-guardian g))
    (match ((if (null? guardian) #f (same? guardian cr)) #t)
           ((if (< 0 (player-condition p (lit confused))) (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) #f) #t)
           ((%bl-unseen-lost? g s who) #t)
           (#t (not (< (%bl-peril g) (player-hp p)))))))
; A wand zapped at CR when it is dear and in line: of those the bot has
; tried, a bolt, a drain, a banishing, and on one neither slow nor
; fast, lethargy, after which it is outpaced; with none of those, one
; not yet tried, to learn what it does.  One that sputters is empty,
; and is not zapped again.  What it slowed is remembered for as long as
; the wand's (effect slow N) gives.  #f with none zapped.
(def %bl-zap!
  (fn (_ g s who cr)
    (def way (if (null? cr) () (if (%bl-dear? g s who cr) (%bl-aim g cr) ())))
    (def slows? (match ((null? cr) #f) ((%bl-slow? cr) #f) (#t (not (creature-trait? cr (lit fast))))))
    (def tried (if (null? way) ()
                 (%bl-first-effect g (lit wand)
                   (if slows? (list (lit bolt) (lit drain) (lit slow) (lit teleport-other)) (list (lit bolt) (lit drain) (lit teleport-other))))))
    (def untried (if (null? way) ()
                   (%bl-in-pack g (fn (_ it) (match ((not (eq? (item-class it) (lit wand))) #f) ((items-known? g it) #f)
                                                    (#t (not (List any? (fn (_ x) (same? x it)) (Vector ref 0 %bl-empty)))))))))
    (def wand (if (null? tried) untried tried))
    (if (null? wand) #f
      (do (%bl-use! g "z" wand)
          (%bl-key! g (%bl-key-for (first way) (rest way)))
          (when (%bl-told? g "sputters") (Vector set! 0 (pair wand (Vector ref 0 %bl-empty)) %bl-empty))
          (when (%bl-told? g " slows")
            (Vector set! 0 (pair (pair cr (+ (game-turn g) (List ref 1 (item-prop wand (lit effect) (list (lit slow) 0)))))
                                 (Vector ref 0 %bl-slowed))
                        %bl-slowed))
          #t))))

; With the fight beside the player likely lost, a scroll read to get out
; of it: stillness, panic, or a blink away.  A blow from something
; unseen, with no sight of it, counts as lost with a foe in view beside
; as well, with blows unseen from two cells or more, or once WHO is
; under its retreat: its cost cannot be weighed,
; and alone above that mark it is struck back at.  Panic scares only what is in view, and one scared with more
; than half its hit points turns again at once (creatures.x), so it is
; read only with every hostile beside looking badly hurt.  What
; stillness holds is remembered for as long as its (effect hold N)
; gives.  #f with none read.
(def %bl-unseen-lost?
  (fn (_ g s who)
    (def p (game-player g))
    (match ((null? (%bl-unseen-blow g s)) #f) ((< 0 (player-condition p (lit seeing))) #f)
           ((not (null? (%bl-beside g %bl-hostile?))) #t)
           ((< 1 (%bl-unseen-cells g s)) #t)
           (#t (%bl-under? p (%bl-at who (lit retreat)))))))
(def %bl-flee!
  (fn (_ g s who)
    (def p (game-player g))
    (def unseen? (%bl-unseen-lost? g s who))
    (def scares? (not (List any? (fn (_ cr) (match ((not (%bl-hostile? cr)) #f)
                                                   ((not (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p))) #f)
                                                   (#t (< 3 (%bl-wounds cr)))))
                        (%bl-seen g))))
    (def scroll (match (unseen? (%bl-first-effect g (lit scroll) (list (lit hold) (lit teleport))))
                       ((< (%bl-peril g) (player-hp p)) ())
                       (scares? (%bl-first-effect g (lit scroll) (list (lit hold) (lit fear) (lit teleport))))
                       (#t (%bl-first-effect g (lit scroll) (list (lit hold) (lit teleport))))))
    (def e (if (null? scroll) () (item-prop scroll (lit effect) ())))
    (if (null? scroll) #f
      (do (%bl-use! g "r" scroll)
          (when (eq? (first e) (lit hold)) (Vector set! 0 (+ (game-turn g) (List ref 1 e)) %bl-still))
          #t))))

; What is used as soon as it is held: a ring on a free hand, vigour
; drunk, an upgrade read, a survey read on a level not yet explored.
; And in a fight: clear sight with something unseen beside the player,
; quickness when the fight would cost half of what they have.  #f with
; nothing used.
(def %bl-ready!
  (fn (_ g s foe)
    (def p (game-player g))
    (def ring (%bl-in-pack g (fn (_ it) (if (eq? (item-class it) (lit ring)) (str=? (items-worn g it) "") #f))))
    (def unseen? (%bl-told? g "Something unseen"))
    (def use
      (match
        ((if (null? ring) #f (< (List length (player-rings p)) 2)) (pair "P" ring))
        ((not (null? (%bl-with-effect g (lit potion) (lit strength)))) (pair "q" (%bl-with-effect g (lit potion) (lit strength))))
        ((not (null? (%bl-with-effect g (lit scroll) (lit upgrade)))) (pair "r" (%bl-with-effect g (lit scroll) (lit upgrade))))
        ((if (null? foe) (not (%bl-explored? g s)) #f)
          ((fn (_ it) (if (null? it) () (pair "r" it))) (%bl-with-effect g (lit scroll) (lit mapping))))
        ((if unseen? (= 0 (player-condition p (lit seeing))) #f)
          ((fn (_ it) (if (null? it) () (pair "q" it))) (%bl-with-effect g (lit potion) (lit seeing))))
        ((if (null? foe) #f (if (< 0 (player-condition p (lit hasted))) #f (not (< (* 2 (%bl-peril g)) (player-hp p)))))
          ((fn (_ it) (if (null? it) () (pair "q" it))) (%bl-with-effect g (lit potion) (lit haste))))
        (#t ())))
    (if (null? use) #f (do (%bl-use! g (first use) (rest use)) #t))))

; With the pack within two of full, a thing of no use dropped and left
; for good: a weapon or armour that is neither the best held nor in
; use, or a potion that poisons.  A full pack takes up nothing more,
; the goal with the rest.  #f with nothing dropped.
(def %bl-shed!
  (fn (_ g s)
    (def weapon (%bl-best g (lit weapon) %bl-weapon-worth))
    (def armour (%bl-best g (lit armour) %bl-armour-worth))
    (def spare?
      (fn (_ it best)
        (match ((same? it best) #f) (#t (str=? (items-worn g it) "")))))
    (def junk
      (%bl-in-pack g
        (fn (_ it)
          (def e (item-prop it (lit effect) ()))
          (match ((eq? (item-class it) (lit weapon)) (spare? it weapon))
                 ((eq? (item-class it) (lit armour)) (spare? it armour))
                 ((eq? (item-class it) (lit potion)) (if (null? e) #f (eq? (first e) (lit poison))))
                 (#t #f)))))
    (match ((< (List length (game-pack g)) 24) #f) ((null? junk) #f)
           (#t (do (Vector set! 8 (pair junk (Vector ref 8 s)) s) (%bl-use! g "d" junk) #t)))))

; Whether the bot is past fighting for its own sake: on the goal's
; level, where the goal is all there is to have, or carrying it up.
(def %bl-running?
  (fn (_ g)
    (if (items-goal-held? g) #t
      (= (game-depth g) (List ref 2 (data-one (game-top-set g) (lit goal) (list "" "" 0)))))))
; Whether, running, the bot goes on its way with a hostile beside it: a
; step away is a turn the creature spends following.  Not held or
; slowed, nothing fast beside it, and not struck since its last turn,
; slot 22 of S its hit points then: one that lands its blows is fought.
(def %bl-slips?
  (fn (_ g s)
    (def p (game-player g))
    (def fast? (List any? (fn (_ cr)
                            (match ((not (%bl-hostile? cr)) #f) ((not (creature-trait? cr (lit fast))) #f)
                                   (#t (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)))))
                 (%bl-seen g)))
    (match ((not (%bl-running? g)) #f) ((< 0 (player-condition p (lit held))) #f) ((< 0 (player-condition p (lit slowed))) #f)
           (fast? #f)
           (#t (not (< (player-hp p) (Vector ref 22 s)))))))

; A blow back at something unseen: the game shows the air stir where an
; unseen blow came from, so one struck from a cell beside the player
; with nothing in view on it is struck at there.  #f with no such blow
; this turn.  The blows are kept from the turn they fell in, slot 24 of
; S, as answering the game's --More-- clears them.
;
; One struck at is still there on a turn it does not strike, unless it
; was slain: for two turns after its last blow, a cell still beside the
; player with nothing in view on it is struck at again, not camped
; beside.  The last blow, (TURN R C), is kept in %bl-unseen-near.
(def %bl-unseen-near (Vector of ()))
(def %bl-unseen-again
  (fn (_ g)
    (def p (game-player g))
    (def near (Vector ref 0 %bl-unseen-near))
    (match ((null? near) ()) ((< (game-turn g) (List ref 0 near)) ()) ((< 2 (- (game-turn g) (List ref 0 near))) ())
           ((%bl-told? g "slain") ())
           ((not (state-adjacent? (List ref 1 near) (List ref 2 near) (player-r p) (player-c p))) ())
           ((not (null? (%bl-seen-at g (List ref 1 near) (List ref 2 near)))) ())
           (#t near))))
(def %bl-strike-unseen!
  (fn (_ g s)
    (def p (game-player g))
    (def from (%bl-unseen-blow g s))
    (def again (%bl-unseen-again g))
    (match ((not (null? from))
             (do (Vector set! 0 (list (game-turn g) (List ref 1 from) (List ref 2 from)) %bl-unseen-near)
                 (%bl-key! g (%bl-key-for (- (List ref 1 from) (player-r p)) (- (List ref 2 from) (player-c p)))) #t))
           ((not (null? again))
             (do (%bl-key! g (%bl-key-for (- (List ref 1 again) (player-r p)) (- (List ref 2 again) (player-c p)))) #t))
           (#t #f))))
; The blows this turn from cells beside the player with nothing in view
; on them; the first of them, or nil; and how many cells they came from.
(def %bl-unseen-blow
  (fn (_ g s) ((fn (_ bs) (if (null? bs) () (first bs))) (%bl-unseen-blows g s))))
(def %bl-unseen-cells
  (fn (_ g s)
    (List length
      (List fold (fn (_ cells b) (if (List any? (fn (_ x) (if (= (first x) (List ref 1 b)) (= (rest x) (List ref 2 b)) #f)) cells) cells
                                   (pair (pair (List ref 1 b) (List ref 2 b)) cells)))
        () (%bl-unseen-blows g s)))))
(def %bl-unseen-blows
  (fn (_ g s)
    (def p (game-player g))
    (List filter
        (fn (_ b)
          (match ((not (= (List ref 3 b) (player-r p))) #f) ((not (= (List ref 4 b) (player-c p))) #f)
                 ((not (state-adjacent? (List ref 1 b) (List ref 2 b) (player-r p) (player-c p))) #f)
                 (#t (null? (%bl-seen-at g (List ref 1 b) (List ref 2 b))))))
        ((fn (_ kept) (if (null? kept) () (if (= (first kept) (game-turn g)) (rest kept) ()))) (Vector ref 24 s)))))

; --- the turn ----------------------------------------------------------------

; The hostile creature here that no depth lays, a band's guardian, or nil.
(def %bl-guardian
  (fn (_ g)
    (List find (fn (_ cr) (if (%bl-hostile? cr) ((fn (_ d) (if (null? d) #f (= 0 (List ref 1 d)))) (creature-prop cr (lit depth) ())) #f))
      (%bl-seen g))))
; The guardian CR that bars the shaft, gone after: fought when in view,
; after a rest to full when the fight is likely lost; else looked for in
; what is unseen, and with none of that left, walked to.
(def %bl-hunt!
  (fn (_ g s cr)
    (def p (game-player g))
    (match
           ((if (%bl-losing? g cr) (< (player-hp p) (player-hpmax p)) #f) (%bl-key! g "s"))
           ((%bl-toward-creature! g s cr) ())
           (#t (%bl-key! g "s")))))

; Out of a lost fight down the stairs: on them, down; within twelve
; steps, a step to them.  Not with the goal in hand, which goes up, nor
; down a shaft found barred, slot 14 of S, which a try down marks as
; %bl-descend! does.  #f with no such way.
(def %bl-down-and-out!
  (fn (_ g s)
    (match ((items-goal-held? g) #f) ((Vector ref 14 s) #f)
           ((%bl-at-stairs? g tile-down)
             (do (%bl-key! g ">")
                 (when (List any? (fn (_ m) (Str8 includes? "shaft" m)) (game-messages g)) (Vector set! 14 #t s))
                 #t))
           (#t ((fn (_ d) (if (null? d) #f (do (%bl-key! g (%bl-key-for (first d) (rest d))) #t)))
                 (%bl-step-within g s (lit stairs) (%bl-stairs-goal g tile-down) 12))))))

; To the stairs and down them, or up with the goal: rested to READY first
; with nothing hostile in view.  A shaft found barred is kept in slot 14
; of S, and its guardian gone after until it is dead: out of view, to
; where it was last seen, (DEPTH R C) in %bl-hunted.
(def %bl-hunted (Vector of ()))
; With no way to the stairs yet, toward what is unseen; with nowhere at
; all to go, toward any hostile in view, and only then rests a turn.
(def %bl-descend!
  (fn (_ g s who shown)
    (def p (game-player g))
    (def up? (items-goal-held? g))
    (def t (if up? tile-up tile-down))
    (def guardian (if (Vector ref 14 s) (%bl-guardian g) ()))
    (unless (null? guardian)
      (Vector set! 0 (list (game-depth g) (creature-r guardian) (creature-c guardian)) %bl-hunted))
    (def last ((fn (_ h) (match ((not (null? guardian)) ()) ((not (Vector ref 14 s)) ()) ((null? h) ())
                                ((not (= (first h) (game-depth g))) ())
                                ((if (= (List ref 1 h) (player-r p)) (= (List ref 2 h) (player-c p)) #f)
                                  (do (Vector set! 0 () %bl-hunted) ()))
                                (#t h)))
               (Vector ref 0 %bl-hunted)))
    (match
      ((match ((%bl-in-sight? g shown) #f) ((%bl-told? g "shoots") #f) ((%bl-told? g "You start up") #f) (#t (%bl-under? p (%bl-mark g s who (lit ready))))) (%bl-rest! g))
      ((not (null? guardian)) (%bl-hunt! g s guardian))
      ((if (null? last) #f (%bl-walk! g s (lit guardian) (fn (_ r c) (if (= r (List ref 1 last)) (= c (List ref 2 last)) #f)))) ())
      ((if (Vector ref 14 s) (%bl-to-frontier! g s) #f) ())
      ((Vector ref 14 s) (do (Vector set! 14 #f s) (%bl-unstick! g s)))
      ((%bl-at-stairs? g t)
        (do (%bl-key! g (if up? "<" ">"))
            (when (List any? (fn (_ m) (Str8 includes? "shaft" m)) (game-messages g))
              (Vector set! 14 #t s))))
      ((%bl-walk! g s (lit stairs) (%bl-stairs-goal g t)) ())
      ((%bl-to-frontier! g s) ())
      ((if (null? shown) #f (%bl-toward-creature! g s shown)) ())
      ((match ((null? shown) #f) ((not (creature-trait? shown (lit ranged))) #f) (#t (%bl-out-of-line! g shown))) ())
      ((%bl-clear-the-way! g s) ())
      (#t (%bl-unstick! g s)))))

; Whether to pour the flask OIL into the lamp under the set's (lamp FULL
; LOW): with it out, or with room for the whole flask.
(def %bl-pour?
  (fn (_ g oil lamp)
    (def n (player-lamp (game-player g)))
    (match ((null? oil) #f) ((null? lamp) #f) ((= n 0) #t) ((< n 0) #f)
           (#t (not (< (- (List ref 0 lamp) n) (item-prop1 oil (lit oil) 600)))))))

(def %bl-turn!
  (fn (_ g s who)
    (def p (game-player g))
    (def q (game-ask g))
    (def foe (%bl-foe g))
    (def potion (%bl-in-pack g (fn (_ it) (if (eq? (item-class it) (lit potion)) (Str8 includes? "mending" (item-name it)) #f))))
    (def food (%bl-in-pack g (%bl-of-class (lit food))))
    (def oil (%bl-in-pack g (%bl-of-class (lit oil))))
    (def lamp (game-param g (lit lamp) ()))
    (def hungry (List ref 1 (game-param g (lit hunger) (list 1300 300 150))))
    (def weapon (%bl-best g (lit weapon) %bl-weapon-worth))
    (def armour (%bl-best g (lit armour) %bl-armour-worth))
    (def shown ((fn (_ cr) (if (null? cr) (%bl-shooter g) cr)) (%bl-shown-hostile g)))
    (unless (%bl-here? g s)
      (do (%bl-new-level! g s)
          (when %bl-tracing (%bl-line "secret doors here: " (%bl-secrets-text g)))))
    ; A secret door found opens ground to be looked over.
    (when (%bl-told? g "You find a secret door.")
      (do (Vector set! 0 #f s) (Vector set! 25 #t s) (Vector set! 27 (+ 1 (Vector ref 27 s)) s)
          (Vector set! 31 (- (Vector ref 31 s) 1) s)))
    ; A survey read opens every secret door on the level: none is left
    ; to search for, and those it opened are counted, for the tally.
    (when (if (Vector ref 33 s) #f (%bl-told? g "The level's shape comes to you."))
      (do (Vector set! 33 #t s) (Vector set! 32 (+ (Vector ref 32 s) (Vector ref 31 s)) s) (Vector set! 31 0 s)))
    ; The lamp burnt here: what it has fallen by since the last turn, a
    ; flask poured not counted.
    (when (< (player-lamp p) (Vector ref 29 s))
      (Vector set! 28 (+ (Vector ref 28 s) (- (Vector ref 29 s) (player-lamp p))) s))
    (Vector set! 29 (player-lamp p) s)
    (%bl-thrown! g s)
    (%bl-turning! g s foe shown)
    (Vector set! 0 (game-turn g) %bl-now)
    (unless (null? (game-blows g)) (Vector set! 24 (pair (game-turn g) (game-blows g)) s))
    (%bl-watch! g s (< (player-hp p) (Vector ref 22 s)))
    (Vector set! 0 (List filter (fn (_ cr) (match ((not (%bl-hostile? cr)) #f) ((%bl-stirring? s cr) #f)
                                                  ((same? cr (%bl-guardian g)) #f)
                                                  (#t (not (%bl-worth? g who cr)))))
                     (%bl-seen g))
                %bl-wary)
    (%bl-sat! g)
    (def slips (%bl-slips? g s))
    (unless (%bl-under? p (%bl-mark g s who (lit rest))) (Vector set! 34 #f s))
    (def struck? (< (player-hp p) (Vector ref 22 s)))
    (Vector set! 22 (player-hp p) s)
    (match
      ((not (null? q)) (%bl-answer! g q))
      ; Searching in the dark, a foe roused or a blow from the unseen
      ; lights the lamp again.
      ((if (player-doused? p) (if (< 0 (player-lamp p)) (if struck? #t (%bl-roused? g s foe)) #f) #f)
        (%bl-key! g "x"))
      ((if (null? potion) #f (%bl-under? p (%bl-at who (lit quaff))))
        (do (%bl-use! g "q" potion) (Vector set! 2 (+ 1 (Vector ref 2 s)) s)))
      ((%bl-drink-now? g foe potion)
        (do (%bl-use! g "q" potion) (Vector set! 2 (+ 1 (Vector ref 2 s)) s)))
      ((%bl-ready! g s foe) ())
      ((%bl-flee! g s who) ())
      ((if (null? foe) (%bl-strike-unseen! g s) #f) ())
      ((%bl-zap! g s who (match ((not (null? foe))
                                ((fn (_ cr) (if (null? cr) foe cr))
                                  (List find (fn (_ cr) (if (%bl-hostile? cr) (if (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) (%bl-dear? g s who cr) #f) #f))
                                    (%bl-seen g))))
                              ((null? shown) (List find (fn (_ cr) (%bl-sitter? g cr)) (%bl-seen g)))
                              ((not (%bl-stirring? s shown)) ()) (#t shown))) ())
      ; Held with nothing beside to strike: a step goes nowhere, so the
      ; turn is waited out.
      ((if (null? foe) (%bl-held? g) #f) (%bl-key! g "s"))
      ((if (null? foe) #f slips) (%bl-onward! g s who shown))
      ((if (null? foe) #f (%bl-shed-slow! g)) ())
      ((if (null? foe) #f (%bl-to-passage! g)) ())
      ((if (null? foe) #f (%bl-outpace? g)) (%bl-outpace! g s who foe))
      ((not (null? foe))
        (unless (if (if (< 0 (%bl-at who (lit retreat))) (%bl-free? g foe) #f)
                  (if (if (%bl-losing? g foe) #t (%bl-under? p (%bl-at who (lit retreat))))
                    (if (%bl-away! g foe) (do (Vector set! 34 #t s) #t) #f) #f) #f)
          (%bl-toward-creature! g s foe)))
      ; Low, with no mending to drink and a hostile in view: down the
      ; stairs when they are near and not found barred, as nothing follows
      ; a player off a level; else a step away from it, not on to the
      ; next thing, unless it is fast or shoots and strikes for every
      ; step, or its
      ; fight is likely won, as a step away is only a blow put off; out
      ; of its view, a rest.  Once backed off, slot 34 of S, it keeps off
      ; until rested.
      ((match ((not (null? potion)) #f) ((null? shown) #f)
              ((not (if (Vector ref 34 s) #t (%bl-under? p (%bl-at who (lit quaff))))) #f)
              ((%bl-down-and-out! g s) #t)
              ((not (%bl-free? g shown)) #f)
              ((not (%bl-losing? g shown)) #f)
              (#t (do (Vector set! 34 #t s) (%bl-away! g shown))))
        ())
      ; One that shoots, in whose line the player stands, whose fight is
      ; not worth it: a step out of its line, not on under its fire.
      ((match ((null? shown) #f) ((not (null? foe)) #f)
              ((not (if (creature-trait? shown (lit ranged)) #t (creature-trait? shown (lit breath)))) #f)
              ((not (%bl-in-line? shown (player-r p) (player-c p))) #f)
              ((%bl-worth? g who shown) #f)
              (#t (%bl-away! g shown)))
        ())
      ((if (null? food) #f (< (player-food p) hungry))
        (do (%bl-use! g "e" food) (Vector set! 3 (+ 1 (Vector ref 3 s)) s)))
      ((match ((%bl-in-sight? g shown) #f) ((%bl-told? g "shoots") #f) ((%bl-told? g "You start up") #f)
              ((not (null? (%bl-unseen-blow g s))) #f)
              (#t (%bl-under? p (%bl-mark g s who (lit rest)))))
        ; One that never moves, in sight, breaks a camp before it starts:
        ; a step out of its sight first.
        ((fn (_ sitter) (unless (if (null? sitter) #f (%bl-away! g sitter)) (%bl-rest! g)))
          (List find (fn (_ cr) (if (%bl-hostile? cr) (if (creature-trait? cr (lit stationary)) (%bl-in-sight? g cr) #f) #f))
            (%bl-seen g))))
      ((%bl-pour? g oil lamp)
        (do (%bl-use! g "f" oil) (Vector set! 10 (+ 1 (Vector ref 10 s)) s)))
      ((if (null? weapon) #f (if (same? weapon (player-weapon p)) #f (< 0 (%bl-weapon-worth g weapon))))
        (%bl-use! g "w" weapon))
      ((if (null? armour) #f (if (null? (player-armour p)) #t (< (%bl-armour-worth g (player-armour p)) (%bl-armour-worth g armour))))
        (if (null? (player-armour p)) (%bl-use! g "W" armour) (%bl-key! g "T")))
      ((if (null? foe) (%bl-shed! g s) #f) ())
      ; Backed off with nowhere further to step, or woken from a rest:
      ; it waits with a hostile in sight and rests again without one,
      ; not on to the next thing.
      ((Vector ref 34 s) (if (%bl-in-sight? g shown) (%bl-key! g "s") (%bl-rest! g)))
      (#t (%bl-onward! g s who shown)))))

; --- a world of screens ------------------------------------------------------

; The errand on a world of screens, in a player's order, or nil with no
; chain: (KIND (X . Y) GIVER PLACE), PLACE the region the screen is in,
; or "".  Outward, talk to each giver not yet
; spoken to, which is when a player learns where the next stands; then
; fetch the last want where it lies; then inward, talk again to each
; giver whose want is held; and with the goal held, home.
(def %bl-errand
  (fn (_ g)
    (def links (game-chain g))
    (def state (fn (_ f) (game-quest-state g (List ref 1 f))))
    (def at (fn (_ f key) (def v (data-prop f key (list 0 0))) (pair (first v) (List ref 1 v))))
    (def want (fn (_ f) (List ref 1 (data-prop f (lit wants) (list (lit bring) "")))))
    (def place (fn (_ f) (first (data-prop f (lit region) (list "")))))
    (def held? (fn (_ name) (not (null? (%bl-in-pack g (fn (_ it) (%bl-named? it name)))))))
    (def unopened (List find (fn (_ f) (null? (state f))) links))
    (def back (List find (fn (_ f) (if (eq? (state f) (lit done)) #f (held? (want f)))) (List reverse links)))
    (match ((null? links) ())
           ((%bl-goal-held? g) (list (lit home) (rest (game-home g)) "" (first (game-home g))))
           ((not (null? unopened)) (list (lit talk) (at unopened (lit screen)) (List ref 2 unopened) (place unopened)))
           ((not (null? back)) (list (lit talk) (at back (lit screen)) (List ref 2 back) (place back)))
           (#t (list (lit fetch) (at (List ref (- (List length links) 1) links) (lit lies)) "" "")))))

(def %bl-sign (fn (_ n) (match ((< n 0) -1) ((< 0 n) 1) (#t 0))))

; Toward what is left unseen here, or a turn's rest with none left.
(def %bl-look!
  (fn (_ g s)
    (match ((%bl-explored? g s) (%bl-key! g "s"))
           ((%bl-to-frontier! g s) ())
           (#t (do (%bl-explored! g s) (%bl-key! g "s"))))))

; A step toward screen TO: along the row first, then the column, to the
; edge on that side, and off it.
(def %bl-cross!
  (fn (_ g s to)
    (def m (game-map g))
    (def p (game-player g))
    (def dx (%bl-sign (- (first to) (first (game-screen g)))))
    (def dy (if (= dx 0) (%bl-sign (- (rest to) (rest (game-screen g)))) 0))
    (def edge? (fn (_ r c)
                 (match ((< 0 dx) (= c (- (map-cols m) 1))) ((< dx 0) (= c 0))
                        ((< 0 dy) (= r (- (map-rows m) 1))) (#t (= r 0)))))
    (match ((edge? (player-r p) (player-c p)) (%bl-key! g (%bl-key-for dy dx)))
           ((%bl-walk! g s (lit edge) edge?) ())
           (#t (%bl-look! g s)))))

; Toward the giver NAME on this screen, a walk into them being a talk.
(def %bl-talk-to!
  (fn (_ g s name)
    (def cr (state-creature-named g name))
    (unless (if (null? cr) #f (if (creatures-shown? g cr) (%bl-toward-creature! g s cr) #f)) (%bl-look! g s))))

; Whether the game's goal is in the pack, the set it began on's, in a
; region or not.
(def %bl-goal-held?
  (fn (_ g)
    (def name (first (data-one (game-top-set g) (lit goal) (list "the prize"))))
    (not (null? (%bl-in-pack g (fn (_ it) (if (eq? (item-class it) (lit goal)) (str=? (item-name it) name) #f)))))))

; A step toward the place PLACE: out of a region off any edge of its
; world, the way to its door's world; or into the region, across to the
; hub, to its door, and in.
(def %bl-to-place!
  (fn (_ g s place)
    (def p (game-player g))
    (def door (map-down (game-map g)))
    (def hub (game-hub g))
    (match ((game-below? g) (%bl-cross! g s (pair -1 (rest (game-screen g)))))
           ((not (if (= (first (game-screen g)) (first hub)) (= (rest (game-screen g)) (rest hub)) #f)) (%bl-cross! g s hub))
           ((null? door) (%bl-look! g s))
           ((if (= (player-r p) (first door)) (= (player-c p) (rest door)) #f) (%bl-key! g ">"))
           ((%bl-walk! g s (lit door) (fn (_ r c) (if (= r (first door)) (= c (rest door)) #f))) ())
           (#t (%bl-look! g s)))))

; The errand's step: into its place, across to its screen, then the
; talk, the fetch, or home, where the win comes at the end of the turn.
(def %bl-errand!
  (fn (_ g s errand shown)
    (def to (List ref 1 errand))
    (def there? (if (= (first (game-screen g)) (first to)) (= (rest (game-screen g)) (rest to)) #f))
    (match ((not (str=? (game-place g) (List ref 3 errand))) (%bl-to-place! g s (List ref 3 errand)))
           ((not there?) (%bl-cross! g s to))
           ((eq? (first errand) (lit talk)) (%bl-talk-to! g s (List ref 2 errand)))
           ((eq? (first errand) (lit home)) (%bl-key! g "."))
           ((not (null? shown)) (unless (%bl-toward-creature! g s shown) (%bl-look! g s)))
           (#t (%bl-look! g s)))))

; The errand of this level not yet done, (quest NAME GIVER . PROPS), or
; nil: the bot knows the set, and so who stands where.
(def %bl-errand-here
  (fn (_ g)
    (List find
      (fn (_ q)
        (if (= (first (data-prop q (lit level) (list 0))) (game-depth g))
          (not (eq? (game-quest-state g (List ref 1 q)) (lit done)))
          #f))
      (data-all (game-set g) (lit quest)))))
; Whether its giver has been spoken to.
(def %bl-asked? (fn (_ g q) (not (null? (game-quest-state g (List ref 1 q))))))
(def %bl-wants (fn (_ q) (data-prop q (lit wants) (list ()))))
; Whether the level is to be looked over whatever the light: its giver
; not yet found, or wanting the whole of it seen.  An errand is worth
; its light, for what it pays.
(def %bl-surveying?
  (fn (_ g)
    (def q (%bl-errand-here g))
    (match ((null? q) #f) ((not (%bl-asked? g q)) #t) (#t (eq? (first (%bl-wants q)) (lit explore))))))
; Whether what Q asks for is in hand: the level seen, or every thing it
; wants brought in the pack.
(def %bl-met-want?
  (fn (_ g s q)
    (if (eq? (first (%bl-wants q)) (lit explore)) (%bl-explored? g s)
      (List all? (fn (_ name) (not (null? (%bl-in-pack g (fn (_ it) (%bl-named? it name)))))) (rest (%bl-wants q))))))
; A step toward one of the people: one in view to be spoken to, or out
; of view, to where one to be spoken to was last seen, slot 23 of S; or
; this level's giver, spoken to before, with what they asked for in
; hand.  #f with none to go to.
(def %bl-to-giver!
  (fn (_ g s)
    (def q (%bl-errand-here g))
    (def seen (List find (fn (_ cr) (if (creature-trait? cr (lit talks)) (creatures-shown? g cr) #f)) (%bl-seen g)))
    (def met (if (null? seen)
               (List find (fn (_ e) (if (creature-trait? (first e) (lit talks)) (%bl-talk? g s (first e)) #f)) (Vector ref 23 s))
               ()))
    (def owed (match ((null? q) ()) ((not (%bl-asked? g q)) ()) ((not (%bl-met-want? g s q)) ())
                     (#t (state-creature-named g (List ref 2 q)))))
    (def stood (if (null? owed) () (%bl-watched s owed)))
    (def at (if (null? stood) () (rest (rest stood))))
    (match ((not (null? seen)) (if (%bl-talk? g s seen) (%bl-toward-creature! g s seen) #f))
           ((if (null? met) #f
              (%bl-walk! g s (lit giver) (fn (_ r c) (if (= r (List ref 2 met)) (= c (rest (rest (rest met)))) #f))))
             #t)
           ((null? at) #f) ((not (%bl-talk? g s owed)) #f)
           (#t (%bl-walk! g s (lit giver) (fn (_ r c) (if (= r (first at)) (= c (rest at)) #f)))))))

; A step toward the quarry, slot 19 of S, the foe last set out after:
; while its fight is worth it, it is gone after though another is nearer
; in view, or the bot would turn about between two.  Out of view, it is
; looked for where it was last seen.  One no way can be found to, or not
; there when the bot arrives, is given up for the level, slot 20 of S,
; and not set out after again.  STEP-TO walks, under a name of its own,
; to a creature within so many steps.  Nil with none.
(def %bl-to-quarry
  (fn (_ g s who step-to)
    (def cr (Vector ref 19 s))
    (def p (game-player g))
    (def was (if (null? cr) () (%bl-watched s cr)))
    (def seen? (if (null? cr) #f (List any? (fn (_ x) (same? x cr)) (%bl-seen g))))
    (def at (if (null? was) () (rest (rest was))))
    (def there? (if (null? at) #f (if (= (first at) (player-r p)) (= (rest at) (player-c p)) #f)))
    (def step
      (match ((null? cr) ()) ((null? was) ())
             ((not (%bl-worth? g who cr)) ())
             (seen? (step-to (lit quarry) cr (%bl-at who (lit chase))))
             (there? ())
             (#t (%bl-step-within g s (lit quarry) (fn (_ r c) (if (= r (first at)) (= c (rest at)) #f)) (%bl-at who (lit chase))))))
    (when (if (null? cr) #f (null? step))
      (do (Vector set! 20 (pair cr (Vector ref 20 s)) s) (Vector set! 19 () s)))
    step))

; With nothing pressing: what lies here, an item within reach (within
; GREED with a hostile in view, unless already on the way to it, so a
; hostile coming into view and out again does not turn the bot about;
; none with one awake two cells off or closer, or one awake not worth
; fighting in view, as a step to it walks into their blows), a foe in
; view within CHASE whose fight
; is worth it to COURAGE, the errand on a world of screens, the giver, the level
; until CURIOSITY of it is seen, the stairs.  A foe it cannot reach is
; passed by, and none is gone after under the READY mark: a fight is
; picked rested.
(def %bl-onward!
  (fn (_ g s who shown)
    (def p (game-player g))
    (def giver (%bl-beside g (fn (_ cr) (creature-trait? cr (lit talks)))))
    (def here (%bl-wanted-at g s (player-r p) (player-c p)))
    (def wanted? (fn (_ r c) (not (null? (%bl-wanted-at g s r c)))))
    (def close? (List any? (fn (_ cr) (match ((not (%bl-hostile? cr)) #f) ((creature-trait? cr (lit stationary)) #f)
                                             ((not (eq? (creature-state cr) (lit awake))) #f)
                                             (#t (< (state-dist (creature-r cr) (creature-c cr) (player-r p) (player-c p)) 3))))
                  (%bl-seen g)))
    (def reach (match ((null? shown) (if close? 0 9999)) (close? 0)
                      ((if (eq? (creature-state shown) (lit awake)) (not (%bl-worth? g who shown)) #f) 0)
                      ((not (null? (%bl-kept g s (lit item) wanted? 9999))) 9999) (#t (%bl-at who (lit greed)))))
    (def to-item (if (if (< 0 reach) (%bl-any-wanted? g s) #f)
                   (%bl-step-within g s (lit item) wanted? reach) ()))
    (def shoots? (if (null? shown) #f (creature-trait? shown (lit ranged))))
    (def step-to
      (fn (_ tag cr most) (%bl-step-within g s tag (fn (_ r c) (if (= r (creature-r cr)) (= c (creature-c cr)) #f)) most)))
    (def wounded? (%bl-under? p (%bl-mark g s who (lit ready))))
    (def to-shown (if (match ((null? shown) #t) ((%bl-running? g) #t) ((Vector ref 34 s) #t) (wounded? #t) ((eq? (creature-state shown) (lit fleeing)) #t)
                             ((List any? (fn (_ x) (same? x shown)) (Vector ref 20 s)) #t)
                             (#t (not (%bl-worth? g who shown))))
                    ()
                    (step-to (lit foe) shown (if shoots? 9999 (%bl-at who (lit chase))))))
    (unless (null? to-shown) (Vector set! 19 shown s))
    (def to-foe (match ((not (null? to-shown)) to-shown) (wounded? ()) (#t (%bl-to-quarry g s who step-to))))
    (def errand (if (game-screens? g) (%bl-errand g) ()))
    (def curious? (match ((%bl-explored? g s) #f) ((%bl-surveying? g) #t) ((Vector ref 25 s) #t) ((not (%bl-light-left? g s)) #f)
                         ((< 99 (%bl-at who (lit curiosity))) #t)
                         (#t (< (%bl-seen-pct g) (%bl-at who (lit curiosity))))))
    (match
      ((not (null? here)) (%bl-pick-up! g s))
      ((not (null? to-item)) (%bl-key! g (%bl-key-for (first to-item) (rest to-item))))
      ((%bl-await? g s shown)
        (do (when %bl-tracing
              (Vector set! 0 (pair (Str8 append "{await " (creature-name shown) " " (Str8 str (creature-state shown)) "}") (Vector ref 0 %bl-pressed)) %bl-pressed))
            (%bl-key! g "s")))
      ((not (null? to-foe)) (%bl-key! g (%bl-key-for (first to-foe) (rest to-foe))))
      ((not (null? errand)) (%bl-errand! g s errand shown))
      ((if (null? giver) #f (%bl-talk? g s giver))
        (do (%bl-toward-creature! g s giver) (Vector set! 4 #t s) (Vector set! 18 (List length (game-pack g)) s)))
      ((%bl-to-giver! g s) ())
      ((if curious? (%bl-to-frontier! g s) #f) ())
      (curious? (do (%bl-explored! g s) (unless (%bl-to-wall! g s who) (%bl-descend! g s who shown))))
      ((%bl-to-wall! g s who) ())
      (#t (%bl-descend! g s who shown)))))

; --- a game ------------------------------------------------------------------

; A record of each level on arrival: (DEPTH TURN HP HPMAX WEAPON-WORTH ARMOUR FOOD).
(def %bl-arrival
  (fn (_ g)
    (def p (game-player g))
    (def w (player-weapon p))
    (list (game-depth g) (game-turn g) (player-hp p) (player-hpmax p)
          (if (null? w) 0 (%bl-weapon-worth g w))
          (if (null? (player-armour p)) 0 (%bl-armour-worth g (player-armour p)))
          (player-food p) (player-lamp p) (List length (List filter (%bl-of-class (lit oil)) (game-pack g))))))

; The level as the game's end left it, for the trace: @ the player, a
; creature its glyph, ^ a found trap, > the way down, seen or not; of
; the rest, . ground seen, ? ground not seen, # other seen, and blank.
; For the trace, not the bot: where the level's secret doors are, R,C
; each, or "none".
(def %bl-secrets
  (fn (_ g)
    (def m (game-map g))
    (List flat-map (fn (_ r) (List map (fn (_ c) (Str8 append (Str8 str r) "," (Str8 str c)))
                                   (List filter (fn (_ c) (= (map-tile m r c) tile-secret)) (List range 0 (map-cols m)))))
          (List range 0 (map-rows m)))))
(def %bl-secrets-text (fn (_ g) ((fn (_ at) (if (null? at) "none" (Str8 join " " at))) (%bl-secrets g))))
(def %bl-chart
  (fn (_ g)
    (def m (game-map g))
    (def p (game-player g))
    (def cell
      (fn (_ r c)
        (def cr (state-creature-at g r c))
        (match ((if (= r (player-r p)) (= c (player-c p)) #f) "@")
               ((not (null? cr)) (creature-glyph cr))
               ((not (null? (traps-found-at g r c))) "^")
               ((= (map-tile m r c) tile-down) ">")
               ((= (map-tile m r c) tile-secret) "S")
               ((map-walkable? m r c) (if (map-seen? m r c) "." "?"))
               ((map-seen? m r c) "#")
               (#t " "))))
    (List for-each
      (fn (_ r) (%bl-line (Str8 join "" (List map (fn (_ c) (cell r c)) (List range 0 (map-cols m))))))
      (List range 0 (map-rows m)))))

; One game from SEED to its end or CAP turns: (SEED HOW EPITAPH DEEPEST
; TURNS POTIONS FOODS ARRIVALS WEAPON-TURN MET), the turn a weapon was
; first held or nil, and the hostile creatures met by then, or by the
; end.  Thirty keys without a turn passing is the bot stuck, and it
; rests one.
(def %bl-trace
  (fn (_ g)
    (def p (game-player g))
    (def keys (List reverse (Vector ref 0 %bl-pressed)))
    (Vector set! 0 () %bl-pressed)
    (%bl-line (Str8 str (game-turn g)) " L" (Str8 str (game-depth g)) " t" (Str8 str (int/ (Sys clock) 1000)) " hp " (Str8 str (player-hp p)) "/" (Str8 str (player-hpmax p))
              " at " (Str8 str (player-r p)) "," (Str8 str (player-c p))
              " [" (Str8 join "" (List map (fn (_ k) (if (str? k) k (Str8 append "<" (symbol->str k) ">"))) keys)) "]  "
              (Str8 join " | " (game-messages g)))
    (when (List any? (fn (_ k) (if (str? k) (str=? k "{stairs found}") #f)) keys) (%bl-chart g))))

; The hostile creatures in view join those met, slot 5 of S, once each;
; the turn a weapon is first held is slot 6, and the count met by then
; slot 7.
(def %bl-met!
  (fn (_ g s)
    (List for-each
      (fn (_ cr)
        (if (if (%bl-hostile? cr) (creatures-shown? g cr) #f)
          (unless (List any? (fn (_ m) (same? m cr)) (Vector ref 5 s)) (Vector set! 5 (pair cr (Vector ref 5 s)) s))))
      (game-creatures g))
    (when (if (null? (Vector ref 6 s)) (not (null? (player-weapon (game-player g)))) #f)
      (do (Vector set! 6 (game-turn g) s) (Vector set! 7 (List length (Vector ref 5 s)) s)))))

; --- the boss: kept where first seen, fought again and again ---------------

; The save SET-SEED-LABEL.sav in the directory DIR: SEED the bot's,
; LABEL the play it came from, "0" a game from the start and "L.T" try T
; on from the save labelled L.
(def %bl-set-name (fn (_ set) (first (data-one set (lit set) (list "set")))))
(def %bl-save-path
  (fn (_ dir set seed label) (Str8 append dir "/" (%bl-set-name set) "-" (Str8 str seed) "-" label ".sav")))

; The saves in DIR not left empty, of seeds FROM to FROM + SEEDS - 1, as
; (SEED LABEL PATH) each.
(def %bl-saves
  (fn (_ dir set from seeds)
    (def head (Str8 append (%bl-set-name set) "-"))
    (def parse
      (fn (_ name)
        (def mid (Str8 sub (Str8 length head) (- (Str8 length name) (+ (Str8 length head) 4)) name))
        (def at (Str8 index-of "-" mid))
        (def path (Str8 append dir "/" name))
        (match ((< at 1) ())
               ((= 0 (Str8 length (File read-all path))) ())
               (#t (list (%bl-int (Str8 sub 0 at mid)) (Str8 sub (+ at 1) (- (Str8 length mid) (+ at 1)) mid) path)))))
    (def named? (fn (_ n) (if (Str8 starts? head n) (Str8 ends? ".sav" n) #f)))
    (def in? (fn (_ sv) (if (null? sv) #f (if (< (first sv) from) #f (< (first sv) (+ from seeds))))))
    (List filter in? (List map parse (List filter named? (File list-dir dir))))))

; The games a batch plays, as (SEED LABEL PATH TRY) each: without
; BALANCE_START a game a seed from the start; with it, BALANCE_TRIES
; games on from each save there, 5 unless given.
(def %bl-plays
  (fn (_ set from seeds)
    (def start (%bl-env "BALANCE_START" ""))
    (def tries (%bl-int (%bl-env "BALANCE_TRIES" "5")))
    (if (str=? start "") (List map (fn (_ seed) (list seed "0" "" 0)) (List range from (+ from seeds)))
      (List flat-map (fn (_ sv) (List map (fn (_ t) (list (first sv) (Str8 append (List ref 1 sv) "." (Str8 str t)) (List ref 2 sv) t))
                                          (List range 1 (+ tries 1))))
        (%bl-saves start set from seeds)))))

; A creature BALANCE_BOSS names, on the level and in view, or nil: of
; several, any one in view.
(def %bl-boss-shown
  (fn (_ g name)
    (List find (fn (_ cr) (if (str=? (creature-name cr) name) (creatures-shown? g cr) #f)) (game-creatures g))))

; The game of PLAY, (SEED LABEL FROM TRY): made from the seed, or read
; from the save FROM with the dice reseeded by the try.
(def %bl-start
  (fn (_ set play)
    (def seed (first play))
    (if (str=? (List ref 2 play) "") (game-make set seed 24 80)
      (do (def g (save-read (List ref 2 play) set 24 80))
          (game-rng! g (Random sw (+ (* 7907 seed) (* 104729 (List ref 3 play)))))
          g))))

(def %bl-game
  (fn (_ set play cap who)
    (def seed (first play))
    (def trace? (not (str=? (%bl-env "BALANCE_TRACE" "") "")))
    (def heap? (not (str=? (%bl-env "BALANCE_HEAP" "") "")))
    (def keep (%bl-env "BALANCE_KEEP" ""))
    (def boss (%bl-env "BALANCE_BOSS" "fireman"))
    (def deep (%bl-int (%bl-env "BALANCE_DEPTH" "0")))
    (def path (if (str=? keep "") "" (%bl-save-path keep set seed (List ref 1 play))))
    (Heap collect)
    (def g (%bl-start set play))
    (unless (str=? path "") (File write-all path ""))
    (def kept (Vector of (str=? path "")))
    (def s (Vector of #f "" 0 0 #f () () 0 () () 0 0 () 0 #f () () () -1 () () () 0 () () #f () 0 0 -1 () 0 0 #f #f))
    (def arrivals (Vector of (list (%bl-arrival g))))
    (def loop
      (fn (self turn stalled)
        (def depth (game-depth g))
        (unless (match ((not (null? (game-over g))) #t) ((< cap (game-turn g)) #t) ((str=? path "") #f) (#t (Vector ref 0 kept)))
          (do (if (if (< 30 stalled) (null? (game-ask g)) #f) (%bl-key! g ".") (%bl-turn! g s who))
              (%bl-met! g s)
              (when (= 0 (player-lamp (game-player g))) (Vector set! 11 (+ 1 (Vector ref 11 s)) s))
              (when trace? (%bl-trace g))
              (unless (match ((Vector ref 0 kept) #t) ((if (< 0 deep) (not (< (game-depth g) deep)) #f) #f)
                             (#t (null? (%bl-boss-shown g boss))))
                (do (save-write! g path) (Vector set! 0 #t kept)))
              (when heap? (%bl-line "heap " (Str8 str (game-turn g)) " " (Str8 str (Heap count))))
              (Heap collect)
              (unless (= depth (game-depth g)) (Vector set! 0 (pair (%bl-arrival g) (Vector ref 0 arrivals)) arrivals))
              (self (game-turn g) (if (= turn (game-turn g)) (+ stalled 1) 0))))))
    (loop 0 0)
    (when trace? (%bl-line "pack: " (Str8 join ", " (List map item-name (game-pack g)))))
    (when trace? (%bl-chart g))
    (list seed (if (null? (game-over g)) (lit capped) (game-over g)) (game-epitaph g) (game-deepest g) (game-turn g)
          (Vector ref 2 s) (Vector ref 3 s) (List reverse (Vector ref 0 arrivals))
          (Vector ref 6 s) (if (null? (Vector ref 6 s)) (List length (Vector ref 5 s)) (Vector ref 7 s))
          (Vector ref 10 s) (Vector ref 11 s) (Vector ref 27 s) (Vector ref 32 s))))

; The numbers in the words of S.
(def %bl-nums (fn (_ s) (List map %bl-int (List reject (fn (_ w) (str=? w "")) (Str8 split " " s)))))
; PROPS with (KEY . VALS) in place of any KEY there was.
(def %bl-prop (fn (_ props key vals) (pair (pair key vals) (List reject (fn (_ p) (if (pair? p) (eq? (first p) key) #f)) props))))
; PROPS as BOSS_HP, BOSS_ATTACK, BOSS_DEFENCE, BOSS_LEVEL and BOSS_TRAITS
; give them; a trait list of "-" is none.
(def %bl-boss-props
  (fn (_ props)
    (def nums (fn (_ have env key) (def v (%bl-env env "")) (if (str=? v "") have (%bl-prop have key (%bl-nums v)))))
    (def traits (%bl-env "BOSS_TRAITS" ""))
    (def with (nums (nums (nums (nums props "BOSS_HP" (lit hp)) "BOSS_ATTACK" (lit attack)) "BOSS_DEFENCE" (lit defence)) "BOSS_LEVEL" (lit level)))
    (if (str=? traits "") with
      (%bl-prop with (lit traits) (List map (fn (_ w) (Str8 ->sym w)) (List reject (fn (_ w) (if (str=? w "") #t (str=? w "-"))) (Str8 split " " traits)))))))
; SET with the creature NAME's numbers as the BOSS_ variables give them.
(def %bl-boss-set
  (fn (_ set name)
    (List map (fn (_ f)
                (if (if (pair? f) (if (eq? (first f) (lit creature)) (str=? (List ref 1 f) name) #f) #f)
                  (pair (first f) (pair (List ref 1 f) (pair (List ref 2 f) (%bl-boss-props (rest (rest (rest f)))))))
                  f))
              set)))
(def %bl-boss-text
  (fn (_ set name)
    (def rec (List find (fn (_ k) (str=? (first k) name)) (data-all set (lit creature))))
    (def show (fn (_ key) (Str8 append (symbol->str key) " " (Str8 join " " (List map (fn (_ v) (if (symbol? v) (symbol->str v) (Str8 str v))) (data-prop rec key ()))))))
    (Str8 join "  " (List map show (list (lit hp) (lit attack) (lit defence) (lit level) (lit traits))))))

; One fight from the save at PATH, try TRY: the dice reseeded by the
; try, the boss in view, or else the first of its name, given its hit
; points again in its range, and WHO playing until that one is dead,
; the player is, the level is left, or CAP turns pass.  (OUTCOME HP
; HPMAX TURNS), or nil with no save there or no such creature.
(def %bl-fight
  (fn (_ set path seed try who boss cap)
    (Heap collect)
    (def g (if (File exists? path) (save-read path set 24 80) ()))
    (if (null? g) ()
      (do (game-rng! g (Random sw (+ (* 7907 seed) (* 104729 try))))
          (def shown (%bl-boss-shown g boss))
          (def cr (if (null? shown) (state-creature-named g boss) shown))
          (unless (null? cr)
            (do (def hp (creature-prop cr (lit hp) (list 1 1)))
                (creature-hp! cr (state-roll (game-rng g) (first hp) (List ref 1 hp)))))
          (def s (Vector of #f "" 0 0 #f () () 0 () () 0 0 () 0 #f () () () -1 () () () 0 () () #f () 0 0 -1 () 0 0 #f #f))
          (def depth (game-depth g))
          (def start (game-turn g))
          (def loop
            (fn (self turn stalled)
              (match ((not (null? (game-over g))) (game-over g))
                     ((not (= depth (game-depth g))) (lit left))
                     ((not (List any? (fn (_ c) (same? c cr)) (game-creatures g))) (lit beat))
                     ((< (+ start cap) (game-turn g)) (lit capped))
                     (#t (do (if (if (< 30 stalled) (null? (game-ask g)) #f) (%bl-key! g ".") (%bl-turn! g s who))
                             (Heap collect)
                             (self (game-turn g) (if (= turn (game-turn g)) (+ stalled 1) 0)))))))
          (def outcome (if (null? cr) () (loop start 0)))
          (def p (game-player g))
          (if (null? cr) () (list outcome (player-hp p) (player-hpmax p) (- (game-turn g) start)))))))

(def %bl-fights
  (fn (_ set ranges from seeds)
    (def dir (%bl-env "BALANCE_FROM" ""))
    (def boss (%bl-env "BALANCE_BOSS" "fireman"))
    (def tries (%bl-int (%bl-env "BALANCE_TRIES" "20")))
    (def cap (%bl-int (%bl-env "BALANCE_TURNS" "400")))
    (def bset (%bl-boss-set set boss))
    (def is (fn (_ o) (fn (_ r) (eq? (first r) o))))
    (def line
      (fn (_ head rs)
        (def beat (List filter (is (lit beat)) rs))
        (%bl-line head (Str8 str (List length rs)) " fights: beat " (Str8 str (List length beat))
                  ", dead " (Str8 str (%bl-count (is (lit dead)) rs))
                  ", left " (Str8 str (%bl-count (is (lit left)) rs))
                  ", capped " (Str8 str (%bl-count (is (lit capped)) rs))
                  "; on a win " (Str8 str (%bl-mean (List map (fn (_ r) (int/ (* 100 (List ref 1 r)) (List ref 2 r))) beat))) "% hp left"
                  ", " (Str8 str (%bl-mean (List map (fn (_ r) (List ref 3 r)) rs))) " turns")))
    (%bl-line "Boss: " boss "  " (%bl-boss-text bset boss))
    (def all
      (List flat-map
        (fn (_ sv)
          (def seed (first sv))
          (def who (%bl-who ranges seed))
          (def rs (List reject null? (List map (fn (_ try) (%bl-fight bset (List ref 2 sv) seed try who boss cap)) (List range 1 (+ tries 1)))))
          (unless (null? rs) (line (Str8 append "seed " (Str8 str seed) "-" (List ref 1 sv) ": ") rs))
          rs)
        (%bl-saves dir set from seeds)))
    (line "All: " all)))

; --- the report --------------------------------------------------------------

(def %bl-pad (fn (_ n s) (if (< (Str8 length s) n) (Str8 append (Str8 repeat (- n (Str8 length s)) " ") s) s)))
(def %bl-rpad (fn (_ n s) (if (< (Str8 length s) n) (Str8 append s (Str8 repeat (- n (Str8 length s)) " ")) s)))
(def %bl-num (fn (_ n) (%bl-pad 6 (Str8 str n))))
(def %bl-mean (fn (_ l) (if (null? l) 0 (int/ (List fold (fn (_ a b) (+ a b)) 0 l) (List length l)))))
(def %bl-count (fn (_ pred l) (List length (List filter pred l))))
(def %bl-line (fn (_ . parts) (%bl-say (Str8 append (Str8 join "" parts) "\n"))))

(def %bl-band-of
  (fn (_ set depth)
    (def bands (List filter (fn (_ f) (eq? (first f) (lit band))) set))
    (def hit (List find (fn (_ b) (not (< (List ref 2 b) depth))) bands))
    (match ((null? bands) "every level") ((null? hit) "beyond") (#t (List ref 1 hit)))))

(def %bl-ended? (fn (_ how) (fn (_ r) (eq? (List ref 1 r) how))))
; Every level from the top to the deepest any game reached, rows with
; no games left out where they are printed.
(def %bl-levels
  (fn (_ games) (List range 0 (+ 1 (List fold (fn (_ m r) (if (< m (List ref 3 r)) (List ref 3 r) m)) 0 games)))))
(def %bl-adjoin (fn (_ acc x) (if (List includes? x acc) acc (List append acc (list x)))))

(def %bl-totals
  (fn (_ games)
    (%bl-line "Games: " (Str8 str (List length games)) "  won " (Str8 str (%bl-count (%bl-ended? (lit won)) games))
              "  dead " (Str8 str (%bl-count (%bl-ended? (lit dead)) games))
              "  capped " (Str8 str (%bl-count (%bl-ended? (lit capped)) games)))))

(def %bl-ends-row
  (fn (_ games d)
    (def at (List filter (fn (_ r) (= (List ref 3 r) d)) games))
    (unless (null? at)
      (%bl-line (%bl-num d) (%bl-num (List length at)) (%bl-num (%bl-count (%bl-ended? (lit dead)) at))))))

(def %bl-ends
  (fn (_ set games)
    (%bl-line "Where games end (deepest level reached)")
    (%bl-line " level  games   dead")
    (List for-each (fn (_ d) (%bl-ends-row games d)) (%bl-levels games))))

(def %bl-cause-row
  (fn (_ set dead bands cause)
    (def in (fn (_ b) (fn (_ r) (if (str=? (List ref 2 r) cause) (str=? (%bl-band-of set (List ref 3 r)) b) #f))))
    (%bl-line (%bl-rpad 28 (Str8 append " " cause))
              (Str8 join "" (List map (fn (_ b) (%bl-pad 16 (Str8 str (%bl-count (in b) dead)))) bands)))))

(def %bl-causes
  (fn (_ set games)
    (def dead (List filter (%bl-ended? (lit dead)) games))
    (def causes (List fold (fn (_ acc r) (%bl-adjoin acc (List ref 2 r))) () dead))
    (def bands (List fold (fn (_ acc r) (%bl-adjoin acc (%bl-band-of set (List ref 3 r)))) () dead))
    (%bl-line "What ends a game, by the band it ended in")
    (%bl-line (%bl-rpad 28 " cause") (Str8 join "" (List map (fn (_ b) (%bl-pad 16 b)) bands)))
    (List for-each (fn (_ cause) (%bl-cause-row set dead bands cause)) causes)))

; The arrival records of GAMES at level D.
(def %bl-arrivals-at
  (fn (_ games d) (List reject null? (List map (fn (_ r) (List find (fn (_ a) (= (first a) d)) (List ref 7 r))) games))))
(def %bl-mean-of (fn (_ k rows) (%bl-mean (List map (fn (_ a) (List ref k a)) rows))))

(def %bl-arrival-row
  (fn (_ games d)
    (def rows (%bl-arrivals-at games d))
    (unless (null? rows)
      (%bl-line (%bl-num d) (%bl-num (List length rows))
                (%bl-num (%bl-mean (List map (fn (_ a) (int/ (* 100 (List ref 2 a)) (List ref 3 a))) rows)))
                (%bl-num (if (< d 1) 0 (- (%bl-mean-of 1 rows) (%bl-mean-of 1 (%bl-arrivals-at games (- d 1))))))
                (%bl-num (%bl-mean-of 4 rows)) (%bl-num (%bl-mean-of 5 rows)) (%bl-num (%bl-mean-of 6 rows))
                (%bl-num (%bl-mean-of 7 rows)) (%bl-num (%bl-mean-of 8 rows))))))

(def %bl-arrivals
  (fn (_ set games)
    (%bl-line "On arrival at each level (over the games that got there)")
    (%bl-line " level  games   hp%  turns  weapon armour   food   lamp flasks")
    (List for-each (fn (_ d) (%bl-arrival-row games d)) (%bl-levels games))))

(def %bl-first-weapon
  (fn (_ games)
    (def armed (List filter (fn (_ r) (not (null? (List ref 8 r)))) games))
    (def bare (List reject (fn (_ r) (not (null? (List ref 8 r)))) games))
    (%bl-line "The first weapon")
    (%bl-line " found in " (Str8 str (List length armed)) " of " (Str8 str (List length games)) " games, on turn "
              (Str8 str (%bl-mean (List map (fn (_ r) (List ref 8 r)) armed))) ", with "
              (Str8 str (%bl-mean (List map (fn (_ r) (List ref 9 r)) armed))) " creatures met before it")
    (%bl-line " never found in " (Str8 str (List length bare)) " games, which met "
              (Str8 str (%bl-mean (List map (fn (_ r) (List ref 9 r)) bare))) " creatures")))

(def %bl-report
  (fn (_ set games)
    (def mean (fn (_ k) (Str8 str (%bl-mean (List map (fn (_ r) (List ref k r)) games)))))
    (%bl-totals games)
    (%bl-line "")
    (%bl-ends set games)
    (%bl-line "")
    (%bl-causes set games)
    (%bl-line "")
    (%bl-first-weapon games)
    (%bl-line "")
    (%bl-arrivals set games)
    (%bl-line "")
    (%bl-line "A game, on average: turns " (mean 4) "  potions drunk " (mean 5) "  foods eaten " (mean 6)
              "  flasks poured " (mean 10) "  turns dark " (mean 11))
    (%bl-line "Secret doors found, in all: " (Str8 str (List fold (fn (_ n r) (+ n (List ref 12 r))) 0 games))
              "  opened by a survey: " (Str8 str (List fold (fn (_ n r) (+ n (List ref 13 r))) 0 games)))))

; --- the run -----------------------------------------------------------------

(def %bl-main
  (fn (_)
    (def seeds (%bl-int (%bl-env "BALANCE_SEEDS" "10")))
    (def from (%bl-int (%bl-env "BALANCE_FIRST" "1")))
    (def cap (%bl-int (%bl-env "BALANCE_TURNS" "6000")))
    (def name (%bl-env "BALANCE_SET" "delve"))
    (def ranges (%bl-ranges (%bl-make)))
    (def set (data-load (Str8 append %lang-root "/data/" name)))
    (if (not (str=? (%bl-env "BALANCE_FROM" "") "")) (%bl-fights set ranges from seeds) (%bl-games set ranges from seeds cap))))

(def %bl-games
  (fn (_ set ranges from seeds cap)
    (def games
      (List map (fn (_ play)
                  (def seed (first play))
                  (def who (%bl-who ranges seed))
                  (def began (Sys clock))
                  (def r (%bl-game set play cap who))
                  (%bl-say (Str8 append "seed " (Str8 str seed) "-" (List ref 1 play) ": " (symbol->str (List ref 1 r)) " at level " (Str8 str (List ref 3 r))
                                       " after " (Str8 str (List ref 4 r)) " turns, " (Str8 str (int/ (- (Sys clock) began) (* 1000 (+ 1 (List ref 4 r))))) " ms each"
                                       (if (eq? (List ref 1 r) (lit dead)) (Str8 append ", " (List ref 2 r)) "") "\n"
                                       "  " (%bl-who-text who) "\n"))
                  r)
        (%bl-plays set from seeds)))
    (%bl-line "")
    (%bl-line "Archetype: " (%bl-env "BALANCE_ARCHETYPE" "anyone"))
    (%bl-report set games)))

(%bl-main)
