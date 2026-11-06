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
; A bot plays a game a seed: it fights what is beside it, drinks mending
; under a third of its hit points, eats when hungry, rests by searching
; under two thirds with nothing in view, wields and wears the best it
; can lift, picks up what it sees with nothing hostile in view, talks
; to whoever it meets, explores the level, takes
; the stairs down, and with the goal in hand climbs.  It is not clever,
; so what it reaches is a floor under a player's reach.  The report:
; where games end, what ends them by band, the standing on arrival at
; each level, and what each game used.  BALANCE_TURNS caps a game, 6000
; unless given.  BALANCE_TRACE, set to anything, writes a line a key:
; the turn, level, hit points, place and what was said.  An instrument,
; not a gate: nothing here is a spec.
;
; lint-known: %lang-root

(import x/type/vector)
(import x/sys/posix)
(import x/sys/gc)
(import x/core/doors int/)
(import roguelike/data data-load data-one)
(import roguelike/map map-rows map-cols map-in? map-walkable? map-seen? map-down map-up map-tile tile-down tile-up)
(import roguelike/state
  game-set game-depth game-deepest game-map game-player game-creatures game-pack game-over game-epitaph game-turn
  game-ask game-exploring? game-messages game-band band-name game-param
  player-r player-c player-hp player-hpmax player-str player-food player-weapon player-armour
  item-class item-name item-prop item-prop1 item-enchant item-letter
  creature-r creature-c creature-trait? state-adjacent? state-shortfall state-creature-at state-items-at
  game-quest-state)
(import roguelike/creatures creatures-shown? creatures-door-diagonal?)
(import roguelike/items items-goal-held?)
(import roguelike/traps traps-found-at)
(import roguelike/game game-make game-key! game-explore!)

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
; GOAL? allows, or nil: a breadth-first search.
(def %bl-step-toward
  (fn (_ g goal?)
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
      (fn (self front back)
        (match
          ((null? front) (if (null? back) () (self (List reverse back) ())))
          (#t (do (def r (first (first front)))
                  (def c (rest (first front)))
                  (def step (Vector ref (at r c) came))
                  (if (if (eq? step #t) #f (goal? r c)) step
                    (self (rest front) (List append (reach r c (if (eq? step #t) () step)) back))))))))
    (Vector set! (at (player-r p) (player-c p)) #t came)
    (search (list (pair (player-r p) (player-c p))) ())))

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

; --- one turn of the bot -----------------------------------------------------

; S, the bot's own state for a game: 0 whether the level is explored, 1
; the depth that was for, 2 potions drunk, 3 foods eaten, 4 whether the
; giver here has been talked to since the level was explored, 5 the
; hostile creatures met, 6 the turn a weapon was first held, 7 the count
; met by then, 8 the items left lying because they would not come up.
(def %bl-explored? (fn (_ g s) (if (= (Vector ref 1 s) (game-depth g)) (Vector ref 0 s) #f)))
(def %bl-explored! (fn (_ g s) (Vector set! 0 #t s) (Vector set! 1 (game-depth g) s) (Vector set! 4 #f s)))
(def %bl-new-level! (fn (_ g s) (Vector set! 0 #f s) (Vector set! 1 (game-depth g) s) (Vector set! 4 #f s)))

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
(def %bl-wanted-at
  (fn (_ g s r c) (List reject (fn (_ it) (List any? (fn (_ x) (same? x it)) (Vector ref 8 s))) (state-items-at g r c))))

; Picks up what lies here; what stays put is left for good.
(def %bl-pick-up!
  (fn (_ g s)
    (def p (game-player g))
    (game-key! g ",")
    (List for-each (fn (_ it) (Vector set! 8 (pair it (Vector ref 8 s)) s))
      (%bl-wanted-at g s (player-r p) (player-c p)))))

(def %bl-at-stairs?(fn (_ g t) (= (map-tile (game-map g) (player-r (game-player g)) (player-c (game-player g))) t)))
(def %bl-stairs-goal (fn (_ g t) (fn (_ r c) (= (map-tile (game-map g) r c) t))))

(def %bl-explore!
  (fn (_ g s)
    (game-key! g "o")
    (when (if (game-exploring? g) #f (List any? (fn (_ m) (Str8 starts? "Nothing left" m)) (game-messages g)))
      (%bl-explored! g s))))

; Toward the stairs, and down or up them; waiting when barred.
(def %bl-descend!
  (fn (_ g s)
    (def up? (items-goal-held? g))
    (def t (if up? tile-up tile-down))
    (if (%bl-at-stairs? g t)
      (do (game-key! g (if up? "<" ">"))
          (when (List any? (fn (_ m) (Str8 includes? "shaft" m)) (game-messages g))
            (do (def cr (%bl-shown-hostile g)) (if (null? cr) (game-key! g ".") (%bl-toward-creature! g cr)))))
      (unless (%bl-walk! g (%bl-stairs-goal g t)) (game-key! g ".")))))

(def %bl-turn!
  (fn (_ g s)
    (def p (game-player g))
    (def q (game-ask g))
    (def foe (%bl-beside g %bl-hostile?))
    (def giver (%bl-beside g (fn (_ cr) (creature-trait? cr (lit talks)))))
    (def potion (%bl-in-pack g (fn (_ it) (if (eq? (item-class it) (lit potion)) (Str8 includes? "mending" (item-name it)) #f))))
    (def food (%bl-in-pack g (%bl-of-class (lit food))))
    (def hungry (List ref 1 (game-param g (lit hunger) (list 1300 300 150))))
    (def weapon (%bl-best g (lit weapon) %bl-weapon-worth))
    (def armour (%bl-best g (lit armour) %bl-armour-worth))
    (def shown (%bl-shown-hostile g))
    (def here (%bl-wanted-at g s (player-r p) (player-c p)))
    (def to-item (if (null? shown) (%bl-step-toward g (fn (_ r c) (not (null? (%bl-wanted-at g s r c))))) ()))
    (unless (= (Vector ref 1 s) (game-depth g)) (%bl-new-level! g s))
    (match
      ((not (null? q)) (%bl-answer! g q))
      ((if (null? potion) #f (< (* 3 (player-hp p)) (player-hpmax p)))
        (do (%bl-use! g "q" potion) (Vector set! 2 (+ 1 (Vector ref 2 s)) s)))
      ((not (null? foe)) (%bl-toward-creature! g foe))
      ((if (null? food) #f (< (player-food p) hungry))
        (do (%bl-use! g "e" food) (Vector set! 3 (+ 1 (Vector ref 3 s)) s)))
      ((if (null? shown) (< (* 3 (player-hp p)) (* 2 (player-hpmax p))) #f) (game-key! g "s"))
      ((if (null? weapon) #f (if (same? weapon (player-weapon p)) #f (< 0 (%bl-weapon-worth g weapon))))
        (%bl-use! g "w" weapon))
      ((if (null? armour) #f (if (null? (player-armour p)) #t (< (%bl-armour-worth g (player-armour p)) (%bl-armour-worth g armour))))
        (if (null? (player-armour p)) (%bl-use! g "W" armour) (game-key! g "T")))
      ((not (null? here)) (%bl-pick-up! g s))
      ((not (null? to-item)) (game-key! g (%bl-key-for (first to-item) (rest to-item))))
      ((if (null? giver) #f (%bl-talk? g s giver))
        (do (%bl-toward-creature! g giver) (Vector set! 4 #t s)))
      ((game-exploring? g) (game-explore! g))
      ((not (null? shown)) (unless (%bl-toward-creature! g shown) (if (%bl-explored? g s) (%bl-descend! g s) (%bl-explored! g s))))
      ((not (%bl-explored? g s)) (%bl-explore! g s))
      (#t (%bl-descend! g s)))))

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
  (fn (_ set seed cap)
    (def trace? (not (str=? (%bl-env "BALANCE_TRACE" "") "")))
    (Heap collect)
    (def g (game-make set seed 24 80))
    (def s (Vector of #f 0 0 0 #f () () 0 ()))
    (def arrivals (Vector of (list (%bl-arrival g))))
    (def loop
      (fn (self n turn stalled)
        (def depth (game-depth g))
        (unless (if (null? (game-over g)) (< cap (game-turn g)) #t)
          (do (if (< 30 stalled) (game-key! g ".") (%bl-turn! g s))
              (%bl-met! g s)
              (when trace? (%bl-trace g))
              (when (= 0 (% n 20)) (Heap collect))
              (unless (= depth (game-depth g)) (Vector set! 0 (pair (%bl-arrival g) (Vector ref 0 arrivals)) arrivals))
              (self (+ n 1) (game-turn g) (if (= turn (game-turn g)) (+ stalled 1) 0))))))
    (loop 0 0 0)
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
(def %bl-levels (fn (_ set) (List range 1 (+ 1 (List ref 2 (data-one set (lit goal) (list "" "" 1)))))))
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
    (List for-each (fn (_ d) (%bl-ends-row games d)) (%bl-levels set))))

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
                (%bl-num (if (< d 2) 0 (- (%bl-mean-of 1 rows) (%bl-mean-of 1 (%bl-arrivals-at games (- d 1))))))
                (%bl-num (%bl-mean-of 4 rows)) (%bl-num (%bl-mean-of 5 rows)) (%bl-num (%bl-mean-of 6 rows))))))

(def %bl-arrivals
  (fn (_ set games)
    (%bl-line "On arrival at each level (over the games that got there)")
    (%bl-line " level  games   hp%  turns  weapon armour   food")
    (List for-each (fn (_ d) (%bl-arrival-row games d)) (%bl-levels set))))

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
    (def cap (%bl-int (%bl-env "BALANCE_TURNS" "6000")))
    (def name (%bl-env "BALANCE_SET" "delve"))
    (def set (data-load (Str8 append %lang-root "/data/" name)))
    (def games
      (List map (fn (_ seed)
                  (def r (%bl-game set seed cap))
                  (%bl-say (Str8 append "seed " (Str8 str seed) ": " (symbol->str (List ref 1 r)) " at level " (Str8 str (List ref 3 r))
                                       " after " (Str8 str (List ref 4 r)) " turns"
                                       (if (eq? (List ref 1 r) (lit dead)) (Str8 append ", " (List ref 2 r)) "") "\n"))
                  r)
        (List range 1 (+ 1 seeds))))
    (%bl-line "")
    (%bl-report set games)))

(%bl-main)
