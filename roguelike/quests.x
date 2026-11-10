; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/quests.x -- the people met below, and what they ask
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A set's (quest NAME GIVER . PROPS) puts the creature named GIVER, one
; with the talks trait, on its (level N), and what it wants: (wants
; bring ITEM ...) lays each token on a level, the last on the giver's
; and the rest on those above, or in the keeping of a (carrier "kind")
; creature there; (wants explore) asks for every cell of the giver's
; level seen.  Walking into the giver opens the quest and says its (ask
; LINE ...); with it open, its (again LINE ...), or, once the want is
; met, its (done LINE ...) and the choice of one of its (rewards (CLASS
; NAME) (CLASS NAME)).  Each thing is placed once a game.  In a world
; of screens a quest stands on its (screen X Y) in place of a level,
; and a token it wants lies where its (lies X Y) says; the game's own
; chain, the quests made from the set's scenes (see chain.x), is read
; with the set's.

(module roguelike/quests)

(import x/type/vector)
(import roguelike/data data-all data-prop data-prop1)
(import x/core/doors int/)
(import roguelike/map map-rows map-cols map-tile map-seen? map-each! map-places tile-rock tile-floor)
(import roguelike/dungeon dungeon-spot)
(import roguelike/state
  game-rng game-set game-forms game-turn game-depth game-map game-player game-creatures game-creatures! game-floor game-floor!
  game-pack game-ask! game-quest-state game-quest-state! game-placed? game-placed! game-chain game-screen game-below? game-region game-world-all
  player-r player-c creature-make creature-name creature-carried!
  item-make item-name item-class? item-at! item-letter!
  state-tell! state-roll state-free? state-items-at state-remove-pack!)
(import roguelike/items items-new items-pickup! items-name)
(import roguelike/shops shops-kept? shops-open!)

; The quests of the set in force, then the chain's, which belong to the
; screens of the world.
(def %qs-quests (fn (_ g) (List append (data-all (game-set g) (lit quest)) (List map rest (game-chain g)))))
(def %qs-name (fn (_ q) (first q)))
(def %qs-giver (fn (_ q) (List ref 1 q)))
(def %qs-level (fn (_ q) (data-prop1 q (lit level) 0)))
; Whether the screen stood on is (X . Y) of PROP's (PROP X Y) in Q: a
; (screen X Y) in the region Q's (region NAME) names, or above with
; none; a (lies X Y) above.
(def %qs-on-screen?
  (fn (_ g q prop)
    (def at (data-prop q prop ()))
    (def here (game-screen g))
    (def region (if (eq? prop (lit screen)) (data-prop1 q (lit region) "") ""))
    (match ((null? at) #f) ((null? here) #f)
           ((not (str=? region ((fn (_ r) (if (null? r) "" r)) (game-region g)))) #f)
           ((= (first at) (first here)) (= (List ref 1 at) (rest here))) (#t #f))))
; Whether Q's giver belongs on the level in hand: its (screen X Y), or
; its (level N) the depth.
(def %qs-here? (fn (_ g q) (if (null? (data-prop q (lit screen) ())) (= (game-depth g) (%qs-level q)) (%qs-on-screen? g q (lit screen)))))
(def %qs-wants (fn (_ q) (data-prop q (lit wants) ())))
(def %qs-items (fn (_ q) (def w (%qs-wants q)) (if (if (null? w) #f (eq? (first w) (lit bring))) (rest w) ())))

; The set's creature kind, or item form of CLASS, named NAME, or nil.
(def %qs-kind (fn (_ g name) (List find (fn (_ k) (str=? (first k) name)) (game-world-all g (lit creature)))))
(def %qs-item-form
  (fn (_ g class name)
    (if (eq? class (lit goal)) (list (lit goal) name)
      (List find (fn (_ f) (if (eq? (first f) class) (str=? (List ref 1 f) name) #f)) (game-world-all g (lit item))))))
; A token's form: the set's, or a bare one.
(def %qs-token (fn (_ g name) (def f (%qs-item-form g (lit token) name)) (if (null? f) (list (lit token) name) f)))

; --- placing -----------------------------------------------------------------

(def %qs-spot (fn (_ g) (dungeon-spot (game-rng g) (game-map g) (fn (_ r c) (if (state-free? g r c) (null? (state-items-at g r c)) #f)) 100)))

; A creature of KIND at R C, awake.
(def %qs-creature!
  (fn (_ g kind r c)
    (def hp (data-prop kind (lit hp) (list 1 1)))
    (def cr (creature-make kind r c (state-roll (game-rng g) (first hp) (List ref 1 hp)) (lit awake)))
    (game-creatures! g (pair cr (game-creatures g)))
    cr))

(def %qs-place-giver!
  (fn (_ g q)
    (def kind (%qs-kind g (%qs-giver q)))
    (def at (%qs-spot g))
    (unless (if (null? kind) #t (null? at))
      (do (%qs-creature! g kind (first at) (rest at))
          (game-placed! g (Str8 append "giver " (%qs-name q)))))))

; The token NAME on the level: in a carrier's keeping, else on the floor.
(def %qs-place-token!
  (fn (_ g q name)
    (def it (item-make (%qs-token g name) 1 0))
    (def carrier (%qs-kind g (data-prop1 q (lit carrier) "")))
    (def at (%qs-spot g))
    (unless (null? at)
      (do (if (null? carrier)
            (do (item-at! it (first at) (rest at)) (game-floor! g (pair it (game-floor g))))
            (creature-carried! (%qs-creature! g carrier (first at) (rest at)) it))
          (game-placed! g name)))))

; Of Q's N tokens, the Kth lies on level LEVEL - N + 1 + K.
; Of Q's N tokens, the Kth lies on level LEVEL - N + 1 + K; a quest on
; a (screen X Y) lays every one on its (lies X Y), and none without.
(def %qs-place-tokens!
  (fn (_ g q)
    (def names (%qs-items q))
    (def k (- (game-depth g) (+ 1 (- (%qs-level q) (List length names)))))
    (def lay! (fn (_ name) (unless (game-placed? g name) (%qs-place-token! g q name))))
    (match ((not (null? (data-prop q (lit lies) ()))) (when (%qs-on-screen? g q (lit lies)) (List for-each lay! names)))
           ((not (null? (data-prop q (lit screen) ()))) ())
           ((if (< k 0) #t (not (< k (List length names)))) ())
           (#t (lay! (List ref k names))))))

; Each quest's giver on its level or screen, and its tokens on theirs,
; once.
(def quests-place!
  (fn (_ g)
    (List for-each
      (fn (_ q)
        (when (if (%qs-here? g q) (not (game-placed? g (Str8 append "giver " (%qs-name q)))) #f)
          (%qs-place-giver! g q))
        (%qs-place-tokens! g q))
      (%qs-quests g))))

; --- what is wanted ----------------------------------------------------------

(def %qs-has? (fn (_ g name) (List any? (fn (_ it) (if (item-class? it (lit token)) (str=? (item-name it) name) #f)) (game-pack g))))

; Whether every cell of the level that is not rock has been seen.
(def %qs-seen-whole?
  (fn (_ g)
    (def m (game-map g))
    (def left (Vector of 0))
    (map-each! 0 0 (- (map-rows m) 1) (- (map-cols m) 1)
      (fn (_ r c) (when (if (= (map-tile m r c) tile-rock) #f (not (map-seen? m r c))) (Vector set! 0 1 left))))
    (= 0 (Vector ref 0 left))))

(def %qs-satisfied?
  (fn (_ g q)
    (def w (%qs-wants q))
    (match ((null? w) #f)
           ((eq? (first w) (lit bring)) (List all? (fn (_ n) (%qs-has? g n)) (rest w)))
           ((eq? (first w) (lit explore)) (%qs-seen-whole? g))
           (#t #f))))

; The tokens Q wanted taken from the pack.
(def %qs-take!
  (fn (_ g q)
    (List for-each
      (fn (_ it) (when (if (item-class? it (lit token)) (List includes? (item-name it) (%qs-items q)) #f)
                   (do (state-remove-pack! g it) (item-letter! it ()))))
      (game-pack g))))

; --- talking -----------------------------------------------------------------

(def %qs-look! (fn (_ g cr lines) (game-ask! g (list (lit look) (creature-name cr) () lines))))

; The reward forms of Q, (CLASS NAME) each, as item forms.
(def %qs-rewards (fn (_ g q) (List reject null? (List map (fn (_ r) (%qs-item-form g (first r) (List ref 1 r))) (data-prop q (lit rewards) ())))))

; The reward FORM given: under the player, and picked up.
(def %qs-give!
  (fn (_ g form)
    (def it (items-new g form))
    (item-at! it (player-r (game-player g)) (player-c (game-player g)))
    (game-floor! g (pair it (game-floor g)))
    (items-pickup! g)))

; The choice of Q's rewards, after its done lines: a or b takes one.
(def %qs-offer!
  (fn (_ g q cr)
    (def forms (%qs-rewards g q))
    (def names (List map (fn (_ f) (items-name g (items-new g f))) forms))
    (def letters (list "a" "b"))
    (def choices (Str8 join "   " (List map (fn (_ i) (Str8 append (List ref i letters) ") " (List ref i names))) (List range 0 (List length names)))))
    (def pick
      (fn (_ key)
        (def i (match ((not (str? key)) ()) ((str=? key "a") 0) ((str=? key "b") 1) (#t ())))
        (if (if (null? i) #t (not (< i (List length forms)))) #f
          (do (%qs-give! g (List ref i forms)) (game-quest-state! g (%qs-name q) (lit done)) #t))))
    (if (null? forms) (do (game-quest-state! g (%qs-name q) (lit done)) (%qs-look! g cr (data-prop q (lit done) ())))
      (game-ask! g (list (lit choose) "Which will you take?" pick (List append (data-prop q (lit done) ()) (list "" choices)))))))

; The giver CR walked into: its quest opened, pressed, met, or over, a
; keeper with no quest or one over saying a line, over the counter when
; their building keeps a shop (shops.x).  A turn passes.
(def quests-talk!
  (fn (_ g cr)
    (def q (List find (fn (_ q) (str=? (%qs-giver q) (creature-name cr))) (%qs-quests g)))
    (def state (if (null? q) (lit done) (game-quest-state g (%qs-name q))))
    (def subs (list (pair "name" (creature-name cr))))
    (def lines (%qs-lines g (creature-name cr)))
    (def shop (%qs-shop g (creature-name cr)))
    (match
      ((if (eq? state (lit done)) (not (null? shop)) #f)
        (shops-open! g (creature-name cr) shop (if (null? lines) "" (List ref (% (game-turn g) (List length lines)) lines))))
      ((if (eq? state (lit done)) (not (null? lines)) #f)
        (%qs-look! g cr (list (List ref (% (game-turn g) (List length lines)) lines))))
      ((null? q) (state-tell! g (lit no-words) "The {name} has nothing to say." subs))
      ((eq? state (lit done)) (state-tell! g (lit quest-over) "The {name} has nothing more to ask." subs))
      ((null? state) (do (game-quest-state! g (%qs-name q) (lit open)) (%qs-look! g cr (data-prop q (lit ask) ()))))
      ((eq? state (lit reward)) (%qs-offer! g q cr))
      ((%qs-satisfied? g q) (do (%qs-take! g q) (game-quest-state! g (%qs-name q) (lit reward)) (%qs-offer! g q cr)))
      (#t (%qs-look! g cr (data-prop q (lit again) ()))))
    #t))

; --- the keepers -------------------------------------------------------------

; A building's (keeper NAME LINE ...) stands inside it on the level that
; lays it, unless the game's chain gives NAME a screen of its own; walked
; into with nothing to ask, the keeper says a LINE, the next each turn.

; The keepers of the buildings among the forms in force, each (BUILDING
; NAME LINE ...).
(def %qs-keepers
  (fn (_ g)
    (List flat-map (fn (_ b) (List map (fn (_ k) (pair (first b) k)) (data-all (rest b) (lit keeper))))
      (data-all (game-forms g) (lit building)))))
(def %qs-chain-giver? (fn (_ g name) (List any? (fn (_ q) (str=? (%qs-giver q) name)) (List map rest (game-chain g)))))
; A free floor cell inside the place P, (NAME R0 C0 R1 C1), the middle
; one of them, or nil.
(def %qs-inside
  (fn (_ g p)
    (def cells (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range (+ (List ref 2 p) 1) (List ref 4 p))))
                 (List range (+ (List ref 1 p) 1) (List ref 3 p))))
    (def free (List filter (fn (_ at) (if (= (map-tile (game-map g) (first at) (rest at)) tile-floor) (state-free? g (first at) (rest at)) #f)) cells))
    (if (null? free) () (List ref (int/ (List length free) 2) free))))
; Each keeper on the level just made, inside their building.
(def quests-keepers!
  (fn (_ g)
    (List for-each
      (fn (_ bk)
        (def place (List find (fn (_ p) (str=? (first p) (first bk))) (map-places (game-map g))))
        (def kind (%qs-kind g (List ref 1 bk)))
        (unless (if (null? place) #t (if (null? kind) #t (%qs-chain-giver? g (first kind))))
          ((fn (_ at) (unless (null? at) (%qs-creature! g kind (first at) (rest at)))) (%qs-inside g place))))
      (%qs-keepers g))))
; The lines of the keeper NAME among the forms in force, or nil.
(def %qs-lines
  (fn (_ g name)
    (def bk (List find (fn (_ bk) (str=? (List ref 1 bk) name)) (%qs-keepers g)))
    (if (null? bk) () (rest (rest bk)))))
; The forms of the building the keeper NAME keeps a shop in, among the
; forms in force, or nil.
(def %qs-shop
  (fn (_ g name)
    (def b (List find (fn (_ b) (List any? (fn (_ k) (str=? (first k) name)) (data-all (rest b) (lit keeper))))
             (data-all (game-forms g) (lit building))))
    (match ((null? b) ()) ((shops-kept? (rest b)) (rest b)) (#t ()))))

(provide roguelike/quests quests-place! quests-talk! quests-keepers!)
