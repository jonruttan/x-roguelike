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
; a turn, a slow one every other.

(module roguelike/odds)

(import x/num/float)
(import roguelike/combat combat-chance)

(def %od-f (fn (_ n) (Float from n)))
(def %od-sum (fn (_ l) (List fold (fn (_ a b) (+ a b)) (%od-f 0) l)))
(def %od-mean (fn (_ l) (if (null? l) (%od-f 0) (/ (%od-sum l) (List length l)))))
(def %od-upto (fn (_ d) (List range (first d) (+ 1 (List ref 1 d)))))

; The chance, a fraction, that a blow by one of LEVEL lands on DEFENCE.
(def odds-hit (fn (_ level defence) (/ (%od-f (combat-chance level defence)) 100)))

; The middle of DICE, (LO HI).
(def odds-mid (fn (_ d) (/ (%od-f (+ (first d) (List ref 1 d))) 2)))

; The mean swings to take HP hit points at chance P a swing, a hit
; doing DICE plus BONUS.  The list is built from E(0) up, newest first.
(def odds-swings
  (fn (_ p dice bonus hp)
    (def faces (%od-upto dice))
    (def es (fn (self h)
              (if (< h 1) (list (%od-f 0))
                (do (def known (self (- h 1)))
                    (def at (fn (_ k) (if (< k 1) (%od-f 0) (List ref (- (- h 1) k) known))))
                    (pair (+ (/ (%od-f 1) p) (%od-mean (List map (fn (_ x) (at (- h (+ x bonus)))) faces))) known)))))
    (first (es hp))))

; The mean of odds-swings over hit points HP, (LO HI).
(def odds-kill (fn (_ p dice bonus hp) (%od-mean (List map (fn (_ h) (odds-swings p dice bonus h)) (%od-upto hp)))))

; Turns T to take HP hit points from one that regenerates: 999 when it
; heals as fast as it is hurt.
(def odds-regen
  (fn (_ t hp)
    (def rate (/ (%od-f hp) t))
    (if (< rate (/ (%od-f 1) 3)) (%od-f 999) (/ (%od-f hp) (- rate (/ (%od-f 1) 3))))))

; The hurt a turn from one of LEVEL striking (LO HI) at DEFENCE, at SPEED
; fast, slow or nil.
(def odds-hurt
  (fn (_ level attack defence speed)
    (def whole (* (odds-hit level defence) (odds-mid attack)))
    (match ((eq? speed (lit fast)) (* 2 whole)) ((eq? speed (lit slow)) (/ whole 2)) (#t whole))))

(provide roguelike/odds odds-hit odds-mid odds-swings odds-kill odds-regen odds-hurt)
