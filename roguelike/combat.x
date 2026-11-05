; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/combat.x -- blows struck, and what follows them
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A blow lands by a percentage: seventy, five more a level of the one
; striking, five less a point of the other's defence, never under five
; nor over ninety-five.  Damage is a roll of the weapon's dice, or the
; creature's (attack LO HI).  A creature's traits act when its blow
; lands: venom weakens, sticky holds, dazzle confuses, cold slows, drain
; takes vigour, thief takes a thing from the pack and runs.

(module roguelike/combat)

(import x/type/vector)
(import roguelike/state
  game-rng game-player game-pack game-over game-over! game-epitaph! game-param game-param1
  player-hp player-hp! player-hpmax player-hpmax! player-str player-str! player-strmax
  player-level player-level! player-exp player-exp! player-weapon player-condition!
  creature-hp creature-hp! creature-name creature-prop creature-prop1 creature-trait? creature-state!
  creature-carried! creature-carried item-prop item-enchant item-letter!
  state-say! state-tell! state-roll state-chance? state-remove-creature! state-remove-pack!
  state-defence state-strength game-floor! game-floor item-at! creature-r creature-c)

(def %cb-clamp (fn (_ n lo hi) (match ((< n lo) lo) ((< hi n) hi) (#t n))))

; Whether a blow by one of LEVEL lands on a defence of DEFENCE.
(def combat-hit?
  (fn (_ rng level defence)
    (< (rng int 100) (%cb-clamp (+ 70 (- (* 5 level) (* 5 defence))) 5 95))))

(def %cb-dice (fn (_ rng dice) (state-roll rng (List ref 0 dice) (List ref 1 dice))))

; The strength bonus to damage: one at 17, two at 19.
(def %cb-str-bonus (fn (_ str) (match ((< str 17) 0) ((< str 19) 1) (#t 2))))

; What the player's blow does: the weapon's dice and enchantment, or
; the set's unarmed dice, and the strength bonus.
(def %cb-player-damage
  (fn (_ g)
    (def w (player-weapon (game-player g)))
    (+ (if (null? w) (%cb-dice (game-rng g) (game-param g (lit unarmed) (list 1 2)))
         (+ (%cb-dice (game-rng g) (item-prop w (lit damage) (list 1 2))) (item-enchant w)))
       (%cb-str-bonus (state-strength g)))))

(def %cb-pow2 (fn (self n) (if (< n 1) 1 (* 2 (self (- n 1))))))
; Experience LEVEL needs: the set's first threshold, doubling a level.
(def combat-exp-for
  (fn (_ g level)
    (if (< level 2) 0 (* (game-param1 g (lit exp) 10) (%cb-pow2 (- level 2))))))

(def %cb-level-up!
  (fn (self g)
    (def p (game-player g))
    (when (not (< (player-exp p) (combat-exp-for g (+ (player-level p) 1))))
      (do (def gain (state-roll (game-rng g) 3 8))
          (player-level! p (+ (player-level p) 1))
          (player-hpmax! p (+ (player-hpmax p) gain))
          (player-hp! p (+ (player-hp p) gain))
          (state-tell! g (lit level-up) "Welcome to level {level}." (list (pair "level" (Str8 str (player-level p)))))
          (self g)))))

; CR slain by the player: its worth in experience, what it carried
; dropped, and it gone.
(def combat-kill!
  (fn (_ g cr)
    (def p (game-player g))
    (state-tell! g (lit kill) "You have slain the {name}." (list (pair "name" (creature-name cr))))
    (player-exp! p (+ (player-exp p) (creature-prop1 cr (lit exp) 1)))
    (unless (null? (creature-carried cr))
      (do (item-at! (creature-carried cr) (creature-r cr) (creature-c cr))
          (item-letter! (creature-carried cr) ())
          (game-floor! g (pair (creature-carried cr) (game-floor g)))
          (creature-carried! cr ())))
    (state-remove-creature! g cr)
    (%cb-level-up! g)))

; The player strikes CR.
(def combat-player-attacks!
  (fn (_ g cr)
    (def subs (list (pair "name" (creature-name cr))))
    (if (not (combat-hit? (game-rng g) (player-level (game-player g)) (creature-prop1 cr (lit defence) 3)))
      (state-tell! g (lit miss) "You miss the {name}." subs)
      (do (creature-hp! cr (- (creature-hp cr) (%cb-player-damage g)))
          (creature-state! cr (lit awake))
          (if (< (creature-hp cr) 1) (combat-kill! g cr)
            (state-tell! g (lit hit) "You hit the {name}." subs))))))

; N taken from the player's hit points; dead when they run out, of CAUSE.
(def combat-hurt-player!
  (fn (_ g n cause)
    (def p (game-player g))
    (player-hp! p (- (player-hp p) n))
    (when (< (player-hp p) 1)
      (do (player-hp! p 0)
          (when (null? (game-over g))
            (do (game-epitaph! g cause)
                (game-over! g (lit dead))
                (state-tell! g (lit died) "You die..." ())))))))

(def %cb-weaken!
  (fn (_ g n)
    (def p (game-player g))
    (when (< 3 (player-str p))
      (do (player-str! p (- (player-str p) n))
          (state-tell! g (lit weakened) "You feel weaker." ())))))

; The pack's item taken by CR, which runs with it.
(def %cb-steal!
  (fn (_ g cr)
    (unless (null? (game-pack g))
      (do (def it ((game-rng g) choice (game-pack g)))
          (state-remove-pack! g it)
          (creature-carried! cr it)
          (creature-state! cr (lit fleeing))
          (state-tell! g (lit stolen) "The {name} snatches something from your pack and runs!"
            (list (pair "name" (creature-name cr))))))))

; CR's traits, after its blow lands.
(def %cb-trait!
  (fn (_ g cr trait)
    (def rng (game-rng g))
    (def p (game-player g))
    (match
      ((eq? trait (lit venom)) (when (state-chance? rng 30) (%cb-weaken! g 1)))
      ((eq? trait (lit sticky)) (do (player-condition! p (lit held) 3) (state-tell! g (lit held) "You are held fast!" ())))
      ((eq? trait (lit dazzle)) (do (player-condition! p (lit confused) 4) (state-tell! g (lit dazzled) "Your head swims." ())))
      ((eq? trait (lit cold)) (do (player-condition! p (lit slowed) 4) (state-tell! g (lit chilled) "A chill slows your limbs." ())))
      ((eq? trait (lit drain))
        (when (< 5 (player-hpmax p))
          (do (player-hpmax! p (- (player-hpmax p) 1)) (state-tell! g (lit drained) "You feel your vigour ebb." ()))))
      ((eq? trait (lit thief)) (%cb-steal! g cr))
      (#t ()))))

; CR strikes the player.
(def combat-creature-attacks!
  (fn (_ g cr)
    (def subs (list (pair "name" (creature-name cr))))
    (if (not (combat-hit? (game-rng g) (creature-prop1 cr (lit level) 1) (state-defence g)))
      (state-tell! g (lit creature-miss) "The {name} misses you." subs)
      (do (state-tell! g (lit creature-hit) "The {name} hits you." subs)
          (List for-each (fn (_ t) (%cb-trait! g cr t)) (creature-prop cr (lit traits) ()))
          (combat-hurt-player! g (%cb-dice (game-rng g) (creature-prop cr (lit attack) (list 1 2)))
            (Str8 append "killed by a " (creature-name cr)))))))

(provide roguelike/combat
  combat-hit? combat-exp-for combat-kill! combat-player-attacks! combat-hurt-player! combat-creature-attacks!)
