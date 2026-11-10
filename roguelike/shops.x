; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/shops.x -- buying and selling at a keeper's counter
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A building keeps a shop when it has (sells (CLASS NAME) ...), the
; goods on its counter, each an item of the world, or (buys CLASS ...),
; the classes its keeper takes.  A thing is worth its item's (price N),
; or else its class's N in the world's (worth (CLASS N) ...), in gold;
; a thing with neither is worth nothing and is not bought.  The shop's
; (rate SELL BUY), 100 and 50 unless given, is the percent of a thing's
; worth asked for it and paid for it, a gold piece at least.
;
; Walked into, the keeper shows the counter: a letter buys the thing
; beside it, s asks what to sell, and anything else leaves.  A thing
; bought goes to the pack, or lies at the player's feet with the pack
; full; one sold is one of a stack; a thing worn or in hand is not sold.
; Each sale takes a turn and the counter stays up, and one that cannot be
; afforded puts it away.

(module roguelike/shops)

(import x/core/doors int/)
(import roguelike/data data-one)
(import roguelike/state
  game-player game-pack game-floor game-floor! game-ask! game-world-all
  player-r player-c player-gold player-gold!
  item-make item-form item-count item-charges item-at! item-class-in?
  state-tell!)
(import roguelike/items items-new items-name items-pickup! items-worn items-use-up!)

(def %sh-letters (list "a" "b" "c" "d" "e" "f" "g" "h"))

; Whether the building's PROPS keep a shop.
(def shops-kept?
  (fn (_ props) (if (null? (data-one props (lit sells) ())) (not (null? (data-one props (lit buys) ()))) #t)))

; The world's item form (CLASS NAME . PROPS) that REF, (CLASS NAME), names, or nil.
(def %sh-form
  (fn (_ g ref)
    (List find (fn (_ f) (if (eq? (first f) (first ref)) (str=? (List ref 1 f) (List ref 1 ref)) #f))
      (game-world-all g (lit item)))))

; What the item FORM is worth in gold: its own (price N), else its
; class's in the world's (worth ...), else nothing.
(def %sh-worth
  (fn (_ g form)
    (def own (Assoc find (lit price) (rest (rest form))))
    (def by-class (List find (fn (_ w) (eq? (first w) (first form))) (List flat-map (fn (_ w) w) (game-world-all g (lit worth)))))
    (match ((not (null? own)) (List ref 1 own)) ((null? by-class) 0) (#t (List ref 1 by-class)))))

; PERCENT of N to the nearest, one at least, nothing of nothing.
(def %sh-part (fn (_ n percent) (if (< n 1) 0 ((fn (_ v) (if (< v 1) 1 v)) (int/ (+ (* n percent) 50) 100)))))

; The counter of the keeper NAME, whose building has PROPS, put up with
; LINE said over it.
(def shops-open!
  (fn (_ g name props line)
    (def p (game-player g))
    (def rate (data-one props (lit rate) (list 100 50)))
    (def buys (data-one props (lit buys) ()))
    (def goods (List take (List length %sh-letters) (List reject null? (List map (fn (_ r) (%sh-form g r)) (data-one props (lit sells) ())))))
    (def asked (fn (_ f) (%sh-part (%sh-worth g f) (first rate))))
    (def paid (fn (_ f) (%sh-part (%sh-worth g f) (List ref 1 rate))))
    (def reopen (fn (_) (shops-open! g name props "")))
    (def buy
      (fn (_ f)
        (def n (asked f))
        (def subs (list (pair "name" (List ref 1 f)) (pair "n" (Str8 str n)) (pair "keeper" name)))
        (if (< (player-gold p) n)
          (do (state-tell! g (lit cannot-afford) "You cannot afford the {name}: {n} gold." subs) #f)
          (do (player-gold! p (- (player-gold p) n))
              (state-tell! g (lit bought) "You pay the {keeper} {n} gold." subs)
              ((fn (_ it) (item-at! it (player-r p) (player-c p)) (game-floor! g (pair it (game-floor g)))) (items-new g f))
              (items-pickup! g)
              (reopen)
              #t))))
    (def sell
      (fn (_ it)
        (def n (paid (item-form it)))
        (def one (if (< 1 (item-count it)) (item-make (item-form it) 1 (item-charges it)) it))
        (def subs (list (pair "name" (items-name g one)) (pair "n" (Str8 str n)) (pair "keeper" name)))
        (match
          ((not (str=? (items-worn g it) ""))
            (do (state-tell! g (lit in-use) "You would have to take that off first." ()) (reopen) #f))
          ((< n 1) (do (state-tell! g (lit not-bought) "The {keeper} has no use for {name}." subs) (reopen) #f))
          (#t (do (items-use-up! g it)
                  (player-gold! p (+ (player-gold p) n))
                  (state-tell! g (lit sold) "You sell {name} for {n} gold." subs)
                  (reopen)
                  #t)))))
    (def pick
      (fn (_ key)
        (def i (if (str? key) (List index-of key %sh-letters) ()))
        (match
          ((if (null? i) #f (< i (List length goods))) (buy (List ref i goods)))
          ((if (str? key) (if (str=? key "s") (not (null? buys)) #f) #f)
            (if (null? (List filter (fn (_ it) (item-class-in? it buys)) (game-pack g)))
              (do (state-tell! g (lit nothing-to-sell) "You have nothing the {keeper} buys." (list (pair "keeper" name))) (reopen) #f)
              (do (game-ask! g (list (lit item) "Sell what?" sell buys)) #f)))
          (#t #f))))
    (def counter
      (List map (fn (_ i)
                  (def f (List ref i goods))
                  (Str8 append (List ref i %sh-letters) ") " (List ref 1 f) ", " (Str8 str (asked f)) " gold"))
        (List range 0 (List length goods))))
    (game-ask! g
      (list (lit choose) (Str8 append "The " name ": what will you have?") pick
        (List append (if (str=? line "") () (list line "")) counter
          (if (null? buys) () (list "s) sell something"))
          (list "" (Str8 append "You have " (Str8 str (player-gold p)) " gold.")))))))

(provide roguelike/shops shops-kept? shops-open!)
