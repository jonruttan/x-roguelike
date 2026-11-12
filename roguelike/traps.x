; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/traps.x -- what lies hidden in the floor
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A level with the set's (traps LO HI) gets that many of its (trap NAME
; MESSAGE . PROPS) kinds on floor cells, hidden.  Stepping on one finds
; it, says its message and takes its (effect hurt LO HI), (effect hold
; N), (effect aggravate) or (effect teleport); searching finds every
; one beside the player.  A found trap is drawn, and auto-explore walks
; around it.  Creatures never set one off.  One that throws the player
; elsewhere is never laid where it would leave no way from the stairs up
; to the stairs down.

(module roguelike/traps)

(import x/type/vector)
(import roguelike/data data-all data-prop)
(import roguelike/map map-floor? map-up map-down map-way?)
(import roguelike/dungeon dungeon-spot)
(import roguelike/state
  game-rng game-set game-map game-player game-traps game-traps! game-param
  player-r player-c player-condition! state-tell! state-roll state-adjacent? state-items-at state-gentle?)
(import roguelike/combat combat-hurt-player!)
(import roguelike/creatures creatures-wake-all!)
(import roguelike/items items-teleport!)

; A trap is a vector: 0 row, 1 column, 2 its kind, (NAME MESSAGE .
; PROPS), 3 whether it has been found.
(def trap-make (fn (_ r c kind found?) (Vector of r c kind found?)))
(def trap-r (fn (_ t) (Vector ref 0 t)))
(def trap-c (fn (_ t) (Vector ref 1 t)))
(def trap-kind (fn (_ t) (Vector ref 2 t)))
(def trap-name (fn (_ t) (first (Vector ref 2 t))))
(def trap-found? (fn (_ t) (Vector ref 3 t)))
(def trap-found! (fn (_ t) (Vector set! 3 #t t)))

(def %tr-at (fn (_ g r c) (List find (fn (_ t) (if (= (trap-r t) r) (= (trap-c t) c) #f)) (game-traps g))))
; The found trap at R C, or nil.
(def traps-found-at (fn (_ g r c) (def t (%tr-at g r c)) (if (null? t) () (if (trap-found? t) t ()))))

; A floor cell with nothing on it, or nil.
(def %tr-spot
  (fn (_ g)
    (dungeon-spot (game-rng g) (game-map g)
      (fn (_ r c) (match ((not (map-floor? (game-map g) r c)) #f)
                         ((not (null? (state-items-at g r c))) #f)
                         ((not (null? (%tr-at g r c))) #f)
                         (#t #t)))
      100)))
; Whether a trap of KIND throws the player elsewhere: such a one cannot
; be walked over, as the others can at their price.
(def %tr-throws?
  (fn (_ kind) ((fn (_ e) (if (null? e) #f (eq? (first e) (lit teleport)))) (data-prop kind (lit effect) ()))))
; Whether a trap of KIND at AT, (R . C), would close the level: one that
; throws, leaving no way from the stairs up to the stairs down round it
; and the others that throw.  Never, on a level without both stairs.
(def %tr-closes?
  (fn (_ g kind at)
    (def m (game-map g))
    (def throwers (List filter (fn (_ t) (%tr-throws? (trap-kind t))) (game-traps g)))
    (match ((not (%tr-throws? kind)) #f) ((null? (map-up m)) #f) ((null? (map-down m)) #f)
           (#t (not (map-way? m (map-up m) (map-down m)
                      (pair at (List map (fn (_ t) (pair (trap-r t) (trap-c t))) throwers))))))))
(def %tr-place!
  (fn (self g kinds n)
    (unless (< n 1)
      (do (def at (%tr-spot g))
          (def kind (if (null? at) () ((game-rng g) choice kinds)))
          (unless (if (null? at) #t (%tr-closes? g kind at))
            (game-traps! g (pair (trap-make (first at) (rest at) kind #f) (game-traps g))))
          (self g kinds (- n 1))))))
; The set's (traps LO HI) of its kinds, hidden, on floor cells with
; nothing on them, one that would close the level left out; none on a
; gentle level.
(def traps-place!
  (fn (_ g)
    (def kinds (data-all (game-set g) (lit trap)))
    (def spec (game-param g (lit traps) ()))
    (unless (match ((null? kinds) #t) ((null? spec) #t) (#t (state-gentle? g)))
      (%tr-place! g kinds (state-roll (game-rng g) (first spec) (List ref 1 spec))))))

(def %tr-effect!
  (fn (_ g t)
    (def e (data-prop (trap-kind t) (lit effect) ()))
    (match ((null? e) ())
           ((eq? (first e) (lit hurt))
             (combat-hurt-player! g (state-roll (game-rng g) (List ref 1 e) (List ref 2 e)) (Str8 append "killed by a " (trap-name t))))
           ((eq? (first e) (lit hold)) (player-condition! (game-player g) (lit held) (List ref 1 e)))
           ((eq? (first e) (lit aggravate)) (creatures-wake-all! g))
           ((eq? (first e) (lit teleport)) (items-teleport! g))
           (#t ()))))

; The trap under the player, if any, set off: found, its message said,
; its effect taken.
(def traps-step!
  (fn (_ g)
    (def p (game-player g))
    (def t (%tr-at g (player-r p) (player-c p)))
    (unless (null? t)
      (do (trap-found! t)
          (state-tell! g (lit trapped) (List ref 1 (trap-kind t)) ())
          (%tr-effect! g t)))))

; Every hidden trap beside the player found.
(def traps-search!
  (fn (_ g)
    (def p (game-player g))
    (List for-each
      (fn (_ t)
        (when (if (trap-found? t) #f (state-adjacent? (trap-r t) (trap-c t) (player-r p) (player-c p)))
          (do (trap-found! t)
              (state-tell! g (lit found-trap) "You find a {name}." (list (pair "name" (trap-name t)))))))
      (game-traps g))))

(provide roguelike/traps
  trap-make trap-r trap-c trap-kind trap-name trap-found? trap-found!
  traps-found-at traps-place! traps-step! traps-search!)
