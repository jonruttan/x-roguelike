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
(import roguelike/data data-all data-get data-prop data-prop1)
(import x/core/doors int/)
(import roguelike/scale scale-rung)
(import roguelike/chain chain-where chain-compass)
(import roguelike/map map-rows map-cols map-tile map-set! map-walkable? map-seen? map-each! map-places map-roof-at map-floor? tile-rock tile-door tile-counter)
(import roguelike/dungeon dungeon-spot)
(import roguelike/state
  game-rng game-set game-forms game-turn game-depth game-map game-player game-creatures game-creatures! game-floor game-floor!
  game-pack game-ask! game-quest-state game-quest-state! game-placed? game-placed! game-chain game-screen game-below? game-region game-world-all
  game-place
  player-r player-c creature-make creature-name creature-carried creature-carried! creature-r creature-c
  item-make item-name item-class? item-at! item-letter! item-r item-c
  state-tell! state-text state-roll state-free? state-items-at state-remove-pack! state-creature-named state-dist)
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

; Whether the level in hand is Q's (lies-below REGION LEVEL).
(def %qs-below?
  (fn (_ g q)
    (def at (data-prop q (lit lies-below) ()))
    (def region (game-region g))
    (match ((null? at) #f) ((null? region) #f)
           ((str=? (first at) region) (= (game-depth g) (List ref 1 at))) (#t #f))))

; Of Q's N tokens, the Kth lies on level LEVEL - N + 1 + K; a quest on
; a (screen X Y) lays every one on its (lies X Y), or on its (lies-below
; REGION LEVEL), and none without.
(def %qs-place-tokens!
  (fn (_ g q)
    (def names (%qs-items q))
    (def k (- (game-depth g) (+ 1 (- (%qs-level q) (List length names)))))
    (def lay! (fn (_ name) (unless (game-placed? g name) (%qs-place-token! g q name))))
    (match ((not (null? (data-prop q (lit lies-below) ()))) (when (%qs-below? g q) (List for-each lay! names)))
           ((not (null? (data-prop q (lit lies) ()))) (when (%qs-on-screen? g q (lit lies)) (List for-each lay! names)))
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
      (game-ask! g (list (lit choose) "Which will you take?" pick (List append (data-prop q (lit done) ()) (list "" choices))
                     (List map (fn (_ i) (pair (List ref i letters) (List ref i names))) (List range 0 (List length names))))))))

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
; The cells of the place P, (NAME R0 C0 R1 C1), (R . C) each.
(def %qs-cells
  (fn (_ p)
    (List flat-map (fn (_ r) (List map (fn (_ c) (pair r c)) (List range (List ref 2 p) (+ (List ref 4 p) 1))))
      (List range (List ref 1 p) (+ (List ref 3 p) 1)))))
; Whether AT is free floor under a roof.
(def %qs-in?
  (fn (_ g at)
    (def m (game-map g))
    (if (map-floor? m (first at) (rest at))
      (if (< 0 (map-roof-at m (first at) (rest at))) (state-free? g (first at) (rest at)) #f)
      #f)))
; A free floor cell under the roof of the place P, the middle one of
; them, or nil.
(def %qs-inside
  (fn (_ g p)
    (def free (List filter (fn (_ at) (%qs-in? g at)) (%qs-cells p)))
    (if (null? free) () (List ref (int/ (List length free) 2) free))))

; A shop's keeper stands at the back of it, the free floor cell under
; its roof farthest from its doors, a counter on the cell beside them
; nearest a door: (STAND . COUNTER), COUNTER nil where a counter there
; would cut any of the building off, and nil with no door or no floor.
(def %qs-abs (fn (_ n) (if (< n 0) (- 0 n) n)))
(def %qs-key (fn (_ at) (+ (* 1000 (first at)) (rest at))))
(def %qs-four (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1)))
(def %qs-beside (fn (_ at) (List map (fn (_ d) (pair (+ (first at) (first d)) (+ (rest at) (rest d)))) %qs-four)))
; How many steps AT is from the nearest of DOORS, along rows and columns.
(def %qs-far
  (fn (_ doors at)
    (List fold (fn (_ best d) ((fn (_ n) (if (< n best) n best)) (+ (%qs-abs (- (first d) (first at))) (%qs-abs (- (rest d) (rest at))))))
      9999 doors)))
; How many of the cells WALK, keys, can be walked to from START without
; a step on the cell BLOCK.
(def %qs-reach
  (fn (_ walk start block)
    (def on? (fn (_ k l) (List any? (fn (_ x) (= x k)) l)))
    ((fn (self front seen)
       (if (null? front) (List length seen)
         ((fn (_ next) (self (List append (rest front) next) (List append next seen)))
          (List filter (fn (_ k) (if (= k block) #f (if (on? k walk) (not (on? k seen)) #f)))
            (List map (fn (_ d) (+ (first front) (+ (* 1000 (first d)) (rest d)))) %qs-four)))))
     (list start) (list start))))
(def %qs-behind
  (fn (_ g p)
    (def m (game-map g))
    (def cells (%qs-cells p))
    (def doors (List filter (fn (_ at) (= (map-tile m (first at) (rest at)) tile-door)) cells))
    (def free (List filter (fn (_ at) (%qs-in? g at)) cells))
    (if (if (null? free) #t (null? doors)) ()
      ((fn (_ stand)
         (def walk (List map %qs-key (List filter (fn (_ at) (map-walkable? m (first at) (rest at))) cells)))
         (def whole (%qs-reach walk (%qs-key stand) -1))
         (def spots
           (List filter
             (fn (_ at)
               (if (%qs-in? g at)
                 (if (< (%qs-far doors at) (%qs-far doors stand)) (= (%qs-reach walk (%qs-key stand) (%qs-key at)) (- whole 1)) #f)
                 #f))
             (%qs-beside stand)))
         (pair stand
           (if (null? spots) ()
             (List fold (fn (_ best at) (if (< (%qs-far doors at) (%qs-far doors best)) at best)) (first spots) (rest spots)))))
       (List fold (fn (_ best at) (if (< (%qs-far doors best) (%qs-far doors at)) at best)) (first free) (rest free))))))
; Each keeper on the level just made, inside their building: a shop's
; behind its counter, any other in the middle of the floor; then the
; level's traders, near the player.
(def quests-keepers!
  (fn (_ g)
    (List for-each
      (fn (_ bk)
        (def place (List find (fn (_ p) (str=? (first p) (first bk))) (map-places (game-map g))))
        (def kind (%qs-kind g (List ref 1 bk)))
        (unless (if (null? place) #t (if (null? kind) #t (%qs-chain-giver? g (first kind))))
          ((fn (_ behind)
             (if (null? behind)
               ((fn (_ at) (unless (null? at) (%qs-creature! g kind (first at) (rest at)))) (%qs-inside g place))
               (do (%qs-creature! g kind (first (first behind)) (rest (first behind)))
                   (unless (null? (rest behind))
                     (map-set! (game-map g) (first (rest behind)) (rest (rest behind)) tile-counter)))))
           (if (null? (%qs-shop g (List ref 1 bk))) () (%qs-behind g place)))))
      (%qs-keepers g))
    (List for-each
      (fn (_ k) ((fn (_ kind at) (unless (if (null? kind) #t (null? at)) (%qs-creature! g kind (first at) (rest at)))) (%qs-kind g (first k)) (%qs-near g)))
      (%qs-traders g))))

; --- the traders below -------------------------------------------------------

; A set's own (keeper NAME (level N) . PROPS), in no building, stands on
; level N near where the player comes onto it, each time the level is
; made; walked into with nothing to ask, it says one of the LINEs among
; PROPS, over the counter when PROPS sell or buy (shops.x).

; The traders of the level in hand, (NAME . PROPS) each.
(def %qs-traders
  (fn (_ g)
    (List filter (fn (_ k) (= (data-get (rest k) (lit level) 0) (game-depth g))) (data-all (game-forms g) (lit keeper)))))
(def %qs-trader (fn (_ g name) (List find (fn (_ k) (str=? (first k) name)) (%qs-traders g))))
; The free cell with nothing on it nearest the player, two cells off at
; the least, or nil.
(def %qs-near
  (fn (_ g)
    (def m (game-map g))
    (def p (game-player g))
    (def d (fn (_ at) (state-dist (first at) (rest at) (player-r p) (player-c p))))
    (List fold
      (fn (_ best at)
        (if (if (< (d at) 2) #f (if (state-free? g (first at) (rest at)) (null? (state-items-at g (first at) (rest at))) #f))
          (if (null? best) at (if (< (d at) (d best)) at best))
          best))
      () (%qs-cells (list "" 1 1 (- (map-rows m) 2) (- (map-cols m) 2))))))

; --- the people of the streets -----------------------------------------------

; A screen's (folk NAME LINE ...) is one of the people out of doors on
; it: a creature that talks, put on open ground when the level is made,
; unless the game's chain gives NAME a screen of its own; walked into,
; they say a LINE, the next each turn.  One with the strolls trait
; wanders the streets (creatures.x).  They are spread over the open
; ground in the order it is read, with no draw of the dice.
(def %qs-folk (fn (_ g) (data-all (game-forms g) (lit folk))))
(def quests-folk!
  (fn (_ g)
    (def m (game-map g))
    (def folk
      (List filter (fn (_ f) ((fn (_ kind) (if (null? kind) #f (not (%qs-chain-giver? g (first kind))))) (%qs-kind g (first f))))
        (%qs-folk g)))
    (unless (null? folk)
      ((fn (_ open)
         (def n (List length open))
         (unless (= n 0)
           (List for-each
             (fn (_ i)
               ((fn (_ at) (when (state-free? g (first at) (rest at)) (%qs-creature! g (%qs-kind g (first (List ref i folk))) (first at) (rest at))))
                (List ref (int/ (* (+ i 1) n) (+ (List length folk) 1)) open)))
             (List range 0 (List length folk)))))
       (List filter
         (fn (_ at)
           (if (map-floor? m (first at) (rest at))
             (if (= 0 (map-roof-at m (first at) (rest at))) (state-free? g (first at) (rest at)) #f)
             #f))
         (%qs-cells (list "" 1 1 (- (map-rows m) 2) (- (map-cols m) 2))))))))
; The lines of the keeper, or the one of the streets, NAME among the
; forms in force, or nil.
(def %qs-lines
  (fn (_ g name)
    (def bk (List find (fn (_ bk) (str=? (List ref 1 bk) name)) (%qs-keepers g)))
    (def tk (%qs-trader g name))
    (match ((not (null? bk)) (rest (rest bk)))
           ((not (null? tk)) (List filter str? (rest tk)))
           (#t ((fn (_ f) (if (null? f) () (rest f))) (List find (fn (_ f) (str=? (first f) name)) (%qs-folk g)))))))
; The forms of the building the keeper NAME keeps a shop in, or the
; PROPS of the trader NAME, among the forms in force, or nil.
(def %qs-shop
  (fn (_ g name)
    (def b (List find (fn (_ b) (List any? (fn (_ k) (str=? (first k) name)) (data-all (rest b) (lit keeper))))
             (data-all (game-forms g) (lit building))))
    (def tk (%qs-trader g name))
    (match ((not (null? b)) (if (shops-kept? (rest b)) (rest b) ()))
           ((null? tk) ())
           ((shops-kept? (rest tk)) (rest tk))
           (#t ()))))

; --- finding them ------------------------------------------------------------

; An errand with a screen of its own leads somewhere while it is not
; over: the first of the chain, not yet asked, to its giver; one open,
; to what it wants, where that lies or with whoever gives it; one whose
; want is in the pack, back to its giver.  The map marks the screen and
; says the way (quests-leads, quests-errands), and the screen itself,
; come onto, says which way the one looked for stands (quests-sighted!).

; Where Q's giver stands: (REGION X Y FOUND), FOUND the words for it
; from another region of the world.
(def %qs-stands
  (fn (_ q)
    (def at (data-prop q (lit screen) ()))
    (list (data-prop1 q (lit region) "") (first at) (List ref 1 at) (data-prop1 q (lit found) ""))))
; The first of Q's wants not in the pack, or nil.
(def %qs-missing (fn (_ g q) (List find (fn (_ n) (not (%qs-has? g n))) (%qs-items q))))
; Where the thing NAME that Q wants is: where it lies, on the ground or
; below, or with the quest that gives it, or nil.  Below, it is on no
; screen, and the way to it is its words.
(def %qs-source
  (fn (_ g q name)
    (def lies (data-prop q (lit lies) ()))
    (def below (data-prop q (lit lies-below) ()))
    (def giver (List find (fn (_ o) (List any? (fn (_ r) (if (< (List length r) 2) #f (str=? (List ref 1 r) name))) (data-prop o (lit rewards) ())))
                 (%qs-quests g)))
    (match ((not (null? below)) (list (first below) () () (data-prop1 q (lit lies-found) "")))
           ((not (null? lies)) (list "" (first lies) (List ref 1 lies) (data-prop1 q (lit lies-found) "")))
           ((null? giver) ())
           ((null? (data-prop giver (lit screen) ())) ())
           (#t (%qs-stands giver)))))
; Where each errand leads, (KIND Q WANT . PLACE) each: KIND asks, fetch,
; back, or owes with its reward still to choose; PLACE as %qs-stands
; gives it.
(def %qs-leads
  (fn (_ g)
    (def chain (List map rest (game-chain g)))
    (def first? (fn (_ q) (if (null? chain) #f (str=? (%qs-name q) (%qs-name (first chain))))))
    (def lead
      (fn (_ q)
        (def state (game-quest-state g (%qs-name q)))
        (def want (%qs-missing g q))
        (def held (if (null? (%qs-items q)) "" (first (%qs-items q))))
        (match ((null? (data-prop q (lit screen) ())) ())
               ((eq? state (lit done)) ())
               ((null? state) (if (first? q) (pair (lit asks) (pair q (pair "" (%qs-stands q)))) ()))
               ((eq? state (lit reward)) (pair (lit owes) (pair q (pair held (%qs-stands q)))))
               ((null? want) (pair (lit back) (pair q (pair held (%qs-stands q)))))
               (#t ((fn (_ at) (if (null? at) () (pair (lit fetch) (pair q (pair want at))))) (%qs-source g q want))))))
    (List reject null? (List map lead (%qs-quests g)))))
(def %qs-lead-place (fn (_ l) (rest (rest (rest l)))))
; Whether the place P is in the world stood in.
(def %qs-in-world? (fn (_ g p) (if (null? (game-screen g)) #f (str=? (first p) (game-place g)))))

; The screens of the world stood in that an errand leads to, (X . Y) each.
(def quests-leads
  (fn (_ g)
    (List map (fn (_ p) (pair (List ref 1 p) (List ref 2 p)))
      (List filter (fn (_ p) (%qs-in-world? g p)) (List map %qs-lead-place (%qs-leads g))))))

; The way to the place P as it is said from where the player stands: in
; the world stood in, the screen by its name where the set names it and
; which way it lies; from another region, the place's own words.
(def %qs-way
  (fn (_ g p)
    (def here (game-screen g))
    (def to (pair (List ref 1 p) (List ref 2 p)))
    (def named (List find (fn (_ s) (def at (List ref 1 s)) (if (= (first at) (first to)) (= (List ref 1 at) (rest to)) #f))
                 (data-all (game-set g) (lit screen))))
    (match ((not (%qs-in-world? g p)) (List ref 3 p))
           ((if (= (first here) (first to)) (= (rest here) (rest to)) #f) "right here")
           ((null? named) (chain-where g here to))
           (#t (Str8 append "in " (first named) ", " (chain-where g here to))))))

; What the errands in hand are, a line each, for the map.
(def quests-errands
  (fn (_ g)
    (List map
      (fn (_ l)
        (def q (List ref 1 l))
        (def subs (list (pair "giver" (%qs-giver q)) (pair "want" (List ref 2 l)) (pair "where" (%qs-way g (%qs-lead-place l)))))
        (match ((eq? (first l) (lit asks)) (state-text g (lit errand-asks) "! The {giver} is asking for help: {where}." subs))
               ((eq? (first l) (lit back)) (state-text g (lit errand-back) "! The {giver} is waiting for {want}: {where}." subs))
               ((eq? (first l) (lit owes)) (state-text g (lit errand-owes) "! The {giver} has something for you: {where}." subs))
               (#t (state-text g (lit errand-fetch) "! For the {giver}, {want}: {where}." subs))))
      (%qs-leads g))))

; On the screen come onto, which way each one an errand looks for
; stands from the player: a giver whose errand is not over, and what an
; open errand wants, lying here or in a carrier's keeping.  One a step
; away is not pointed at.
(def quests-sighted!
  (fn (_ g)
    (def p (game-player g))
    (def sc (scale-rung (data-get (game-set g) (lit scale) 1)))
    (def abs (fn (_ n) (if (< n 0) (- 0 n) n)))
    (def far? (fn (_ r c) (if (< 1 (abs (- r (player-r p)))) #t (< 1 (abs (- c (player-c p)))))))
    (def way (fn (_ r c) (chain-compass (* (- c (player-c p)) (first sc)) (* (- r (player-r p)) (rest sc)))))
    (def token? (fn (_ it name) (if (null? it) #f (if (item-class? it (lit token)) (str=? (item-name it) name) #f))))
    (def person!
      (fn (_ q)
        (def cr (state-creature-named g (%qs-giver q)))
        (unless (if (null? cr) #t (not (far? (creature-r cr) (creature-c cr))))
          (state-tell! g (lit sought-person) "You make out the {name} to the {way}."
            (list (pair "name" (%qs-giver q)) (pair "way" (way (creature-r cr) (creature-c cr))))))))
    (def thing!
      (fn (_ name)
        (def it (List find (fn (_ it) (token? it name)) (game-floor g)))
        (def cr (List find (fn (_ cr) (token? (creature-carried cr) name)) (game-creatures g)))
        (match
          ((not (null? it))
            (when (far? (item-r it) (item-c it))
              (state-tell! g (lit sought-thing) "You make out {name} to the {way}."
                (list (pair "name" name) (pair "way" (way (item-r it) (item-c it)))))))
          ((not (null? cr))
            (state-tell! g (lit sought-carried) "The {carrier} to the {way} has {name}."
              (list (pair "name" name) (pair "carrier" (creature-name cr)) (pair "way" (way (creature-r cr) (creature-c cr))))))
          (#t ()))))
    (List for-each
      (fn (_ q)
        (def state (game-quest-state g (%qs-name q)))
        (unless (if (null? (data-prop q (lit screen) ())) #t (eq? state (lit done)))
          (do (when (%qs-here? g q) (person! q))
              (when (if (eq? state (lit open)) (%qs-on-screen? g q (lit lies)) #f)
                (List for-each (fn (_ name) (unless (%qs-has? g name) (thing! name))) (%qs-items q))))))
      (%qs-quests g))))

(provide roguelike/quests quests-place! quests-talk! quests-keepers! quests-folk! quests-leads quests-errands quests-sighted!)
