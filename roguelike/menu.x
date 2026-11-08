; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/menu.x -- a list of choices, moved through with keys
;
; The title screen's, the options' and the pause's: a list of items,
; one of them chosen, and the keys the game already takes moving the
; choice and answering it.  Up and down (the arrows, k and j, a pad's
; d-pad or stick) move the choice, going round at the ends; enter,
; space or a pad's A take it; escape or a pad's B goes back; left and
; right change the chosen item, where it is a value.
;
; A menu is [ITEMS CHOSEN], ITEMS (ID . LABEL) each.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(import x/type/vector)
(import x/core/doors int+ int- int<)

(def %mn-key=? (fn (_ a b) (if (str? a) (if (str? b) (str=? a b) #f) (eq? a b))))
(def %mn-in? (fn (_ key keys) (List any? (fn (_ k) (%mn-key=? k key)) keys)))
(def %mn-up (list (lit up) "k"))
(def %mn-down (list (lit down) "j"))
(def %mn-left (list (lit left) "h"))
(def %mn-right (list (lit right) "l"))
(def %mn-take (list (lit enter) " " ","))
(def %mn-back (list (lit escape)))

; A menu of ITEMS, (ID . LABEL) each, the first chosen.
(def menu-make (fn (_ items) (Vector of items 0)))
(def menu-items (fn (_ m) (Vector ref 0 m)))
(def menu-chosen (fn (_ m) (Vector ref 1 m)))
; The id of menu M's chosen item.
(def menu-id (fn (_ m) (first (List ref (Vector ref 1 m) (Vector ref 0 m)))))
; Menu M with its items now ITEMS, the same place chosen where there is one.
(def menu-items!
  (fn (_ m items)
    (Vector set! 0 items m)
    (when (int< (int- (List length items) 1) (Vector ref 1 m)) (Vector set! 1 (int- (List length items) 1) m))
    m))

; KEY taken by menu M: (take . ID) or (change ID . DIR) for the chosen
; item, back, or nil when the key only moved the choice or does nothing.
(def menu-key
  (fn (_ m key)
    (def n (List length (Vector ref 0 m)))
    (def at (Vector ref 1 m))
    (match
      ((%mn-in? key %mn-up) (do (Vector set! 1 (% (int+ at (int- n 1)) n) m) ()))
      ((%mn-in? key %mn-down) (do (Vector set! 1 (% (int+ at 1) n) m) ()))
      ((%mn-in? key %mn-take) (pair (lit take) (menu-id m)))
      ((%mn-in? key %mn-back) (lit back))
      ((%mn-in? key %mn-left) (pair (lit change) (pair (menu-id m) -1)))
      ((%mn-in? key %mn-right) (pair (lit change) (pair (menu-id m) 1)))
      (#t ()))))

(provide roguelike/menu menu-make menu-items menu-chosen menu-id menu-items! menu-key)
