; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/odds.x -- what a fight is likely to cost
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; The means behind combat.x's rolls, for whoever weighs a fight before
; it: tools/model.x for a set's numbers, tools/balance.x for a bot's
; choice.  The chance of a blow is combat.x's own.  A creature that
; regenerates gets a hit point back every third turn (creatures.x), so
; its hit points come off at the player's rate less a third, or never
; when that rate is no more than a third.  A fast creature strikes twice
; a turn, a slow one every other.  A cold blow slows the player for
; combat.x's chill, and slowed, every creature acts twice a turn: a
; cold creature's strikes are counted over the turns it keeps the
; player slowed.  A dazzling blow confuses the player, combat.x's
; dazzle-chance in a hundred, for its dazzle, and confused, a swing goes one of the eight ways at random:
; the player's swings are counted over the turns it keeps them clear.

(module roguelike/odds)

(import x/num/float)
(import x/core/doors int/)
(import roguelike/combat combat-chance combat-dazzle-chance)

(def %od-f (fn (_ n) (Float from n)))
(def %od-sum (fn (_ l) (List fold (fn (_ a b) (+ a b)) (%od-f 0) l)))
(def %od-mean (fn (_ l) (if (null? l) (%od-f 0) (/ (%od-sum l) (List length l)))))
(def %od-upto (fn (_ d) (List range (first d) (+ 1 (List ref 1 d)))))

; The chance, a fraction, that a blow by one of LEVEL lands on DEFENCE.
(def odds-hit (fn (_ level defence) (/ (%od-f (combat-chance level defence)) 100)))

; The middle of DICE, (LO HI).
(def odds-mid (fn (_ d) (/ (%od-f (+ (first d) (List ref 1 d))) 2)))

; The mean swings E(h) to take h hit points at chance P a swing, a hit
; doing DICE plus BONUS, for every h from HP down to 0, newest first.
(def %od-swings
  (fn (_ p dice bonus hp)
    (def faces (%od-upto dice))
    (def es (fn (self h)
              (if (< h 1) (list (%od-f 0))
                (do (def known (self (- h 1)))
                    (def at (fn (_ k) (if (< k 1) (%od-f 0) (List ref (- (- h 1) k) known))))
                    (pair (+ (/ (%od-f 1) p) (%od-mean (List map (fn (_ x) (at (- h (+ x bonus)))) faces))) known)))))
    (es hp)))
(def odds-swings (fn (_ p dice bonus hp) (first (%od-swings p dice bonus hp))))

; The mean of odds-swings over hit points HP, (LO HI), from the one
; list to HI.
(def odds-kill
  (fn (_ p dice bonus hp)
    (def hi (List ref 1 hp))
    (def es (%od-swings p dice bonus hi))
    (%od-mean (List map (fn (_ h) (List ref (- hi h) es)) (%od-upto hp)))))

; Turns T to take HP hit points from one that regenerates: 999 when it
; heals as fast as it is hurt.
(def odds-regen
  (fn (_ t hp)
    (def rate (/ (%od-f hp) t))
    (if (< rate (/ (%od-f 1) 3)) (%od-f 999) (/ (%od-f hp) (- rate (/ (%od-f 1) 3))))))

(def %od-pow (fn (self x n) (if (< n 1) (%od-f 1) (* x (self x (- n 1))))))
; The chance that none lands of HALVES half-strikes at chance H: a half
; is a strike every other turn.
(def %od-miss
  (fn (_ h halves)
    (if (< halves 2) (- (%od-f 1) (/ h 2)) (%od-pow (- (%od-f 1) h) (int/ halves 2)))))

; The share of turns the player is under a condition laid by one
; striking HALVES half-strikes a turn at chance H, each that lands laying
; it for TURNS turns, and striking FASTER times as often while it holds:
; one minus the settled share of turns with none left.  A turn with C
; left goes to C - 1 on a miss, M1 a turn, and back to TURNS on a blow,
; so with L the share at TURNS, the share at C is L M1^(TURNS-C), and
; the share at none, kept on a miss M0, is L M1^TURNS / (1 - M0).
; Floats are x-lang's own, so a few of them, not a chain stepped.
(def %od-held
  (fn (_ h halves turns faster)
    (def m0 (%od-miss h halves))
    (def m1 (%od-miss h (* faster halves)))
    (def held (fn (self k) (if (< k 1) (%od-f 0) (+ (%od-pow m1 (- k 1)) (self (- k 1))))))
    (if (< m0 (%od-f 1))
      ((fn (_ none) (- (%od-f 1) (/ none (+ (held turns) none)))) (/ (%od-pow m1 turns) (- (%od-f 1) m0)))
      (%od-f 0))))

; The share of turns the player is slowed by a cold blow, CHILL turns
; each, slowed, the creature striking twice as often.
(def odds-chilled (fn (_ h halves chill) (%od-held h halves chill 2)))

(def %od-halves (fn (_ speed) (match ((eq? speed (lit fast)) 4) ((eq? speed (lit slow)) 1) (#t 2))))

; The hurt a turn from one of LEVEL striking (LO HI) at DEFENCE, at SPEED
; fast, slow or nil, its blow slowing the player CHILL turns, 0 for none.
(def odds-hurt
  (fn (_ level attack defence speed chill)
    (def h (odds-hit level defence))
    (def halves (%od-halves speed))
    (def slowed (if (< chill 1) (%od-f 0) (odds-chilled h halves chill)))
    (* (* h (odds-mid attack)) (* (/ (%od-f halves) 2) (+ (%od-f 1) slowed)))))

; The share of the player's swings that reach one of LEVEL at DEFENCE
; and SPEED whose blow confuses for DAZZLE turns, 0 for none, as often
; as combat.x's dazzle-chance: a confused step goes one of the eight
; ways at random (game.x), so a swing then reaches it one time in eight.
(def odds-aim
  (fn (_ level defence speed dazzle)
    (def h (* (odds-hit level defence) (/ (%od-f combat-dazzle-chance) 100)))
    (def c (if (< dazzle 1) (%od-f 0) (%od-held h (%od-halves speed) dazzle 1)))
    (- (%od-f 1) (* c (/ (%od-f 7) 8)))))

(provide roguelike/odds odds-hit odds-mid odds-swings odds-kill odds-regen odds-chilled odds-hurt odds-aim)
