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
; walk to the edge of the unseen, and take the stairs.  Every walk is
; its own, over what it has seen; a creature it cannot reach is passed
; by, and it rests a turn only with nowhere at all to go.  The report:
; where games end, what ends them by band, the standing on arrival at
; each level, and what each game used.  BALANCE_TURNS caps a game, 6000
; unless given.  BALANCE_FIRST is the first seed, 1 unless given, so a
; game too long to share a run can have one to itself.  BALANCE_TRACE,
; set to anything, writes a line a key: the turn, level, hit points,
; place and what was said.  The spread between attributes is the room
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
(import roguelike/map map-rows map-cols map-in? map-walkable? map-seen? map-down map-up map-tile tile-down tile-up)
(import roguelike/state
  game-set game-depth game-deepest game-map game-player game-creatures game-pack game-over game-epitaph game-turn
  game-ask game-messages game-band band-name game-param
  player-r player-c player-hp player-hpmax player-str player-food player-weapon player-armour
  item-class item-name item-prop item-prop1 item-enchant item-letter item-r item-c game-floor
  creature-r creature-c creature-state creature-trait? state-adjacent? state-dist state-shortfall state-creature-at state-items-at
  game-quest-state game-screens? game-screen game-screen-key game-hub game-chain game-inside state-creature-named)
(import roguelike/creatures creatures-shown? creatures-door-diagonal?)
(import roguelike/items items-goal-held?)
(import roguelike/traps traps-found-at)
(import roguelike/game game-make game-key! game-frontier?)

(def %bl-say (fn (_ text) (Sys fd-write 1 text)))
(def %bl-env
  (fn (_ name default)
    (def v (Sys getenv name))
    (if (if (null? v) #t (str=? v "")) default v)))
(def %bl-int (fn (_ s) ((prim-ref (lit convert) (lit to)) s (Type named INTEGER) 10)))

; --- walking -----------------------------------------------------------------

(def %bl-dirs
  (list (pair "h" (pair 0 -1)) (pair "j" (pair 1 0)) (pair "k" (pair -1 0)) (pair "l" (pair 0 1))
        (pair "y" (pair -1 -1)) (pair "u" (pair -1 1)) (pair "b" (pair 1 -1)) (pair "n" (pair 1 1))))
(def %bl-key-for
  (fn (_ dr dc) (first (List find (fn (_ d) (if (= (first (rest d)) dr) (= (rest (rest d)) dc) #f)) %bl-dirs))))

; The first step, (DR . DC), of the shortest walk over seen, walkable
; cells, clear of creatures and found traps, from the player to a cell
; GOAL? allows no more than MOST steps away, or nil: a breadth-first
; search, a layer a step.
(def %bl-step-toward (fn (_ g goal?) (%bl-step-within g goal? 9999)))
(def %bl-step-within
  (fn (_ g goal? most)
    (def m (game-map g))
    (def p (game-player g))
    (def cols (map-cols m))
    (def came (Vector make (* (map-rows m) cols) ()))
    (def at (fn (_ r c) (+ (* r cols) c)))
    (def reach
      (fn (_ r c step)
        (List reject null?
          (List map (fn (_ d)
                      (def rr (+ r (first (rest d))))
                      (def cc (+ c (rest (rest d))))
                      (match ((not (map-in? m rr cc)) ())
                             ((not (map-seen? m rr cc)) ())
                             ((not (map-walkable? m rr cc)) ())
                             ((creatures-door-diagonal? m r c (first (rest d)) (rest (rest d))) ())
                             ((not (null? (Vector ref (at rr cc) came))) ())
                             ((if (goal? rr cc) #f (not (null? (state-creature-at g rr cc)))) ())
                             ((if (goal? rr cc) #f (not (null? (traps-found-at g rr cc)))) ())
                             (#t (do (Vector set! (at rr cc) (if (null? step) (rest d) step) came) (pair rr cc)))))
                    %bl-dirs))))
    (def search
      (fn (self front back n)
        (match
          ((null? front) (if (if (null? back) #t (< most (+ n 1))) () (self (List reverse back) () (+ n 1))))
          (#t (do (def r (first (first front)))
                  (def c (rest (first front)))
                  (def step (Vector ref (at r c) came))
                  (if (if (eq? step #t) #f (goal? r c)) step
                    (self (rest front) (List append (reach r c (if (eq? step #t) () step)) back) n)))))))
    (Vector set! (at (player-r p) (player-c p)) #t came)
    (search (list (pair (player-r p) (player-c p))) () 0)))

(def %bl-walk!
  (fn (_ g goal?)
    (def d (%bl-step-toward g goal?))
    (if (null? d) #f (do (game-key! g (%bl-key-for (first d) (rest d))) #t))))

; --- what the bot sees -------------------------------------------------------

(def %bl-hostile? (fn (_ cr) (not (creature-trait? cr (lit talks)))))
(def %bl-beside
  (fn (_ g pred)
    (def p (game-player g))
    (List find (fn (_ cr) (if (pred cr) (state-adjacent? (creature-r cr) (creature-c cr) (player-r p) (player-c p)) #f))
      (game-creatures g))))
(def %bl-shown-hostile
  (fn (_ g) (List find (fn (_ cr) (if (%bl-hostile? cr) (creatures-shown? g cr) #f)) (game-creatures g))))
(def %bl-toward-creature!
  (fn (_ g cr) (%bl-walk! g (fn (_ r c) (if (= r (creature-r cr)) (= c (creature-c cr)) #f)))))

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
; the cells beside the unseen already stood on here, a vector by cell.

; Where the player stands, as text: the depth, or on a world of screens
; the screen and any interior.
(def %bl-place
  (fn (_ g)
    (if (game-screens? g)
      (Str8 append (game-screen-key (first (game-screen g)) (rest (game-screen g))) "/" (if (null? (game-inside g)) "" (game-inside g)))
      (Str8 str (game-depth g)))))
(def %bl-here? (fn (_ g s) (str=? (Vector ref 1 s) (%bl-place g))))
(def %bl-explored? (fn (_ g s) (if (%bl-here? g s) (Vector ref 0 s) #f)))
(def %bl-explored! (fn (_ g s) (Vector set! 0 #t s) (Vector set! 1 (%bl-place g) s) (Vector set! 4 #f s)))
(def %bl-new-level! (fn (_ g s) (Vector set! 0 #f s) (Vector set! 1 (%bl-place g) s) (Vector set! 4 #f s) (Vector set! 9 () s)))

(def %bl-answer!
  (fn (_ g q)
    (game-key! g (match ((eq? (first q) (lit choose)) "a") ((eq? (first q) (lit yn)) "n") (#t (lit escape))))))

(def %bl-use! (fn (_ g key it) (game-key! g key) (game-key! g (item-letter it))))

; Whether to walk into the giver CR: not yet since the level was reached
; or explored, or holding a token.
(def %bl-talk?
  (fn (_ g s cr)
    (if (not (Vector ref 4 s)) #t (not (null? (%bl-in-pack g (%bl-of-class (lit token))))))))

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
    (game-key! g ",")
    (List for-each (fn (_ it) (Vector set! 8 (pair it (Vector ref 8 s)) s))
      (%bl-wanted-at g s (player-r p) (player-c p)))))

(def %bl-at-stairs?(fn (_ g t) (= (map-tile (game-map g) (player-r (game-player g)) (player-c (game-player g))) t)))
(def %bl-stairs-goal (fn (_ g t) (fn (_ r c) (= (map-tile (game-map g) r c) t))))

; A step toward the nearest seen cell beside the unseen that the player
; has not yet stood on here, or #f with none to reach.  Standing on one
; spends it: some edges never show what lies past them, and a walk back
; to one would go to and fro for good.
(def %bl-to-frontier!
  (fn (_ g s)
    (def m (game-map g))
    (def p (game-player g))
    (def cols (map-cols m))
    (when (null? (Vector ref 9 s)) (Vector set! 9 (Vector make (* (map-rows m) cols) #f) s))
    (def spent (Vector ref 9 s))
    (Vector set! (+ (* (player-r p) cols) (player-c p)) #t spent)
    (%bl-walk! g (fn (_ r c) (if (Vector ref (+ (* r cols) c) spent) #f (game-frontier? m r c))))))

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

; A step that takes the player furthest from CR, or #f when none gains.
(def %bl-away!
  (fn (_ g cr)
    (def p (game-player g))
    (def m (game-map g))
    (def far (fn (_ r c) (state-dist r c (creature-r cr) (creature-c cr))))
    (def best
      (List fold
        (fn (_ best d)
          (def r (+ (player-r p) (first (rest d))))
          (def c (+ (player-c p) (rest (rest d))))
          (match ((not (map-in? m r c)) best) ((not (map-walkable? m r c)) best)
                 ((not (null? (state-creature-at g r c))) best)
                 ((not (null? (traps-found-at g r c))) best)
                 ((< (first best) (far r c)) (pair (far r c) (first d)))
                 (#t best)))
        (pair (far (player-r p) (player-c p)) ()) %bl-dirs))
    (if (null? (rest best)) #f (do (game-key! g (rest best)) #t))))

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

; --- the turn ----------------------------------------------------------------

; To the stairs and down them, or up with the goal: rested to READY first
; with nothing hostile in view; a guardian barring the shaft is fought.
; With no way to the stairs yet, toward what is unseen; with nowhere at
; all to go, toward any hostile in view, and only then rests a turn.
(def %bl-descend!
  (fn (_ g s who shown)
    (def p (game-player g))
    (def up? (items-goal-held? g))
    (def t (if up? tile-up tile-down))
    (match
      ((if (null? shown) (%bl-under? p (%bl-at who (lit ready))) #f) (game-key! g "s"))
      ((%bl-at-stairs? g t)
        (do (game-key! g (if up? "<" ">"))
            (when (List any? (fn (_ m) (Str8 includes? "shaft" m)) (game-messages g))
              (do (def cr (%bl-shown-hostile g)) (if (null? cr) (game-key! g "s") (%bl-toward-creature! g cr))))))
      ((%bl-walk! g (%bl-stairs-goal g t)) ())
      ((%bl-to-frontier! g s) ())
      ((if (null? shown) #f (%bl-toward-creature! g shown)) ())
      (#t (game-key! g "s")))))

(def %bl-turn!
  (fn (_ g s who)
    (def p (game-player g))
    (def q (game-ask g))
    (def foe (%bl-beside g %bl-hostile?))
    (def potion (%bl-in-pack g (fn (_ it) (if (eq? (item-class it) (lit potion)) (Str8 includes? "mending" (item-name it)) #f))))
    (def food (%bl-in-pack g (%bl-of-class (lit food))))
    (def hungry (List ref 1 (game-param g (lit hunger) (list 1300 300 150))))
    (def weapon (%bl-best g (lit weapon) %bl-weapon-worth))
    (def armour (%bl-best g (lit armour) %bl-armour-worth))
    (def shown (%bl-shown-hostile g))
    (unless (%bl-here? g s) (%bl-new-level! g s))
    (match
      ((not (null? q)) (%bl-answer! g q))
      ((if (null? potion) #f (%bl-under? p (%bl-at who (lit quaff))))
        (do (%bl-use! g "q" potion) (Vector set! 2 (+ 1 (Vector ref 2 s)) s)))
      ((not (null? foe))
        (unless (if (%bl-under? p (%bl-at who (lit retreat))) (%bl-away! g foe) #f) (%bl-toward-creature! g foe)))
      ((if (null? food) #f (< (player-food p) hungry))
        (do (%bl-use! g "e" food) (Vector set! 3 (+ 1 (Vector ref 3 s)) s)))
      ((if (null? shown) (%bl-under? p (%bl-at who (lit rest))) #f) (game-key! g "s"))
      ((if (null? weapon) #f (if (same? weapon (player-weapon p)) #f (< 0 (%bl-weapon-worth g weapon))))
        (%bl-use! g "w" weapon))
      ((if (null? armour) #f (if (null? (player-armour p)) #t (< (%bl-armour-worth g (player-armour p)) (%bl-armour-worth g armour))))
        (if (null? (player-armour p)) (%bl-use! g "W" armour) (game-key! g "T")))
      (#t (%bl-onward! g s who shown)))))

; --- a world of screens ------------------------------------------------------

; The errand on a world of screens, in a player's order, or nil with no
; chain: (KIND (X . Y) GIVER).  Outward, talk to each giver not yet
; spoken to, which is when a player learns where the next stands; then
; fetch the last want where it lies; then inward, talk again to each
; giver whose want is held; and with the goal held, home to the hub.
(def %bl-errand
  (fn (_ g)
    (def links (game-chain g))
    (def state (fn (_ f) (game-quest-state g (List ref 1 f))))
    (def at (fn (_ f key) (def v (data-prop f key (list 0 0))) (pair (first v) (List ref 1 v))))
    (def want (fn (_ f) (List ref 1 (data-prop f (lit wants) (list (lit bring) "")))))
    (def held? (fn (_ name) (not (null? (%bl-in-pack g (fn (_ it) (%bl-named? it name)))))))
    (def unopened (List find (fn (_ f) (null? (state f))) links))
    (def back (List find (fn (_ f) (if (eq? (state f) (lit done)) #f (held? (want f)))) (List reverse links)))
    (match ((null? links) ())
           ((items-goal-held? g) (list (lit home) (game-hub g) ""))
           ((not (null? unopened)) (list (lit talk) (at unopened (lit screen)) (List ref 2 unopened)))
           ((not (null? back)) (list (lit talk) (at back (lit screen)) (List ref 2 back)))
           (#t (list (lit fetch) (at (List ref (- (List length links) 1) links) (lit lies)) "")))))

(def %bl-sign (fn (_ n) (match ((< n 0) -1) ((< 0 n) 1) (#t 0))))

; Toward what is left unseen here, or a turn's rest with none left.
(def %bl-look!
  (fn (_ g s)
    (match ((%bl-explored? g s) (game-key! g "s"))
           ((%bl-to-frontier! g s) ())
           (#t (do (%bl-explored! g s) (game-key! g "s"))))))

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
    (match ((edge? (player-r p) (player-c p)) (game-key! g (%bl-key-for dy dx)))
           ((%bl-walk! g edge?) ())
           (#t (%bl-look! g s)))))

; Toward the giver NAME on this screen, a walk into them being a talk.
(def %bl-talk-to!
  (fn (_ g s name)
    (def cr (state-creature-named g name))
    (unless (if (null? cr) #f (if (creatures-shown? g cr) (%bl-toward-creature! g cr) #f)) (%bl-look! g s))))

; The errand's step: across to its screen, then the talk, the fetch, or
; home, where the win comes at the end of the turn.
(def %bl-errand!
  (fn (_ g s errand shown)
    (def to (List ref 1 errand))
    (def there? (if (= (first (game-screen g)) (first to)) (= (rest (game-screen g)) (rest to)) #f))
    (match ((not there?) (%bl-cross! g s to))
           ((eq? (first errand) (lit talk)) (%bl-talk-to! g s (List ref 2 errand)))
           ((eq? (first errand) (lit home)) (game-key! g "."))
           ((not (null? shown)) (unless (%bl-toward-creature! g shown) (%bl-look! g s)))
           (#t (%bl-look! g s)))))

; With nothing pressing: what lies here, an item within reach (within
; GREED with a hostile in view), a foe in view within CHASE when at or
; above COURAGE, the errand on a world of screens, the giver, the level
; until CURIOSITY of it is seen, the stairs.  A foe it cannot reach is
; passed by.
(def %bl-onward!
  (fn (_ g s who shown)
    (def p (game-player g))
    (def giver (%bl-beside g (fn (_ cr) (creature-trait? cr (lit talks)))))
    (def here (%bl-wanted-at g s (player-r p) (player-c p)))
    (def reach (if (null? shown) 9999 (%bl-at who (lit greed))))
    (def to-item (if (if (< 0 reach) (%bl-any-wanted? g s) #f)
                   (%bl-step-within g (fn (_ r c) (not (null? (%bl-wanted-at g s r c)))) reach) ()))
    (def to-foe (if (if (null? shown) #t (%bl-under? p (%bl-at who (lit courage)))) ()
                  (%bl-step-within g (fn (_ r c) (if (= r (creature-r shown)) (= c (creature-c shown)) #f)) (%bl-at who (lit chase)))))
    (def errand (if (game-screens? g) (%bl-errand g) ()))
    (def curious? (if (%bl-explored? g s) #f
                    (if (< 99 (%bl-at who (lit curiosity))) #t (< (%bl-seen-pct g) (%bl-at who (lit curiosity))))))
    (match
      ((not (null? here)) (%bl-pick-up! g s))
      ((not (null? to-item)) (game-key! g (%bl-key-for (first to-item) (rest to-item))))
      ((not (null? to-foe)) (game-key! g (%bl-key-for (first to-foe) (rest to-foe))))
      ((not (null? errand)) (%bl-errand! g s errand shown))
      ((if (null? giver) #f (%bl-talk? g s giver))
        (do (%bl-toward-creature! g giver) (Vector set! 4 #t s)))
      ((if curious? (%bl-to-frontier! g s) #f) ())
      (curious? (do (%bl-explored! g s) (%bl-descend! g s who shown)))
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
          (player-food p))))

; One game from SEED to its end or CAP turns: (SEED HOW EPITAPH DEEPEST
; TURNS POTIONS FOODS ARRIVALS WEAPON-TURN MET), the turn a weapon was
; first held or nil, and the hostile creatures met by then, or by the
; end.  Thirty keys without a turn passing is the bot stuck, and it
; rests one.
(def %bl-trace
  (fn (_ g)
    (def p (game-player g))
    (%bl-line (Str8 str (game-turn g)) " L" (Str8 str (game-depth g)) " hp " (Str8 str (player-hp p)) "/" (Str8 str (player-hpmax p))
              " at " (Str8 str (player-r p)) "," (Str8 str (player-c p)) "  " (Str8 join " | " (game-messages g)))))

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

(def %bl-game
  (fn (_ set seed cap who)
    (def trace? (not (str=? (%bl-env "BALANCE_TRACE" "") "")))
    (Heap collect)
    (def g (game-make set seed 24 80))
    (def s (Vector of #f "" 0 0 #f () () 0 () ()))
    (def arrivals (Vector of (list (%bl-arrival g))))
    (def loop
      (fn (self turn stalled)
        (def depth (game-depth g))
        (unless (if (null? (game-over g)) (< cap (game-turn g)) #t)
          (do (if (< 30 stalled) (game-key! g ".") (%bl-turn! g s who))
              (%bl-met! g s)
              (when trace? (%bl-trace g))
              (Heap collect)
              (unless (= depth (game-depth g)) (Vector set! 0 (pair (%bl-arrival g) (Vector ref 0 arrivals)) arrivals))
              (self (game-turn g) (if (= turn (game-turn g)) (+ stalled 1) 0))))))
    (loop 0 0)
    (list seed (if (null? (game-over g)) (lit capped) (game-over g)) (game-epitaph g) (game-deepest g) (game-turn g)
          (Vector ref 2 s) (Vector ref 3 s) (List reverse (Vector ref 0 arrivals))
          (Vector ref 6 s) (if (null? (Vector ref 6 s)) (List length (Vector ref 5 s)) (Vector ref 7 s)))))

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
                (%bl-num (%bl-mean-of 4 rows)) (%bl-num (%bl-mean-of 5 rows)) (%bl-num (%bl-mean-of 6 rows))))))

(def %bl-arrivals
  (fn (_ set games)
    (%bl-line "On arrival at each level (over the games that got there)")
    (%bl-line " level  games   hp%  turns  weapon armour   food")
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
    (%bl-line "A game, on average: turns " (mean 4) "  potions drunk " (mean 5) "  foods eaten " (mean 6))))

; --- the run -----------------------------------------------------------------

(def %bl-main
  (fn (_)
    (def seeds (%bl-int (%bl-env "BALANCE_SEEDS" "10")))
    (def from (%bl-int (%bl-env "BALANCE_FIRST" "1")))
    (def cap (%bl-int (%bl-env "BALANCE_TURNS" "6000")))
    (def name (%bl-env "BALANCE_SET" "delve"))
    (def ranges (%bl-ranges (%bl-make)))
    (def set (data-load (Str8 append %lang-root "/data/" name)))
    (def games
      (List map (fn (_ seed)
                  (def who (%bl-who ranges seed))
                  (def r (%bl-game set seed cap who))
                  (%bl-say (Str8 append "seed " (Str8 str seed) ": " (symbol->str (List ref 1 r)) " at level " (Str8 str (List ref 3 r))
                                       " after " (Str8 str (List ref 4 r)) " turns"
                                       (if (eq? (List ref 1 r) (lit dead)) (Str8 append ", " (List ref 2 r)) "") "\n"
                                       "  " (%bl-who-text who) "\n"))
                  r)
        (List range from (+ from seeds))))
    (%bl-line "")
    (%bl-line "Archetype: " (%bl-env "BALANCE_ARCHETYPE" "anyone"))
    (%bl-report set games)))

(%bl-main)
