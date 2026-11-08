; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/dungeon.x -- a level made: rooms, the passages between, stairs
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; Rooms are dropped at random where they fit, a cell apart at least, as
; many as the set asks for or as many as will fit in the tries allowed.
; Sorted left to right, each is joined to the next by a passage with one
; bend, and some to the one after that, so every room can be reached and
; a few have two ways in.  A passage carved through a room's wall leaves
; a door.  The stairs down are in a room other than the one the stairs
; up are in, when there is one.  A room is lit by a chance that falls
; with depth.  A set may ask for caves or open ground instead, below.

(module roguelike/dungeon)

(import x/type/vector)
(import x/num/random)
(import x/core/doors int/ int+ int- int< int= int& int>> obj-ref obj-set!)
(import roguelike/map
  tile-rock tile-floor tile-wall tile-door tile-passage tile-down tile-up
  tile-water tile-pillar tile-fall tile-dressed tile-hedge tile-gate tile-thicket tile-edge tile-bog tile-scar
  map-make map-rows map-cols map-rooms map-rooms! map-down map-down! map-up!
  map-tile map-set! map-in? map-passable? map-opaque? room-r0 room-c0 room-r1 room-c1 room-centre map-each!
  map-fill-unreached!)
(import roguelike/scale scale-rung scale-across scale-down scale-area)

; The set's parameters, (KEY . VALUES) alist, or DEFAULT's values.
(def %dg-p
  (fn (_ params key default)
    (def p (Assoc find key params))
    (if (null? p) default (rest p))))
; A roll from LO to HI; LO when HI is below it, as a size a cell short
; of its room can be at a large scale.
(def %dg-roll (fn (_ rng lo hi) (if (< hi lo) lo (+ lo (rng int (+ 1 (- hi lo)))))))

; The level's scale, (scale N), as (ACROSS . DOWN) metres a cell: 1, a
; metre by two, when the set names none.  Every size a level is carved
; to is in metres, and comes out in cells at its scale.
(def %dg-scale (fn (_ params) (scale-rung (first (%dg-p params (lit scale) (list 1))))))
; A size in metres, (KEY LO HI), as (LO . HI) cells across, down, or of
; ground covered, at SCALE.
(def %dg-metres
  (fn (_ params key lo hi to)
    ((fn (_ v) (pair (to (first v)) (to (List ref 1 v)))) (%dg-p params key (list lo hi)))))
(def %dg-across (fn (_ params scale key lo hi) (%dg-metres params key lo hi (fn (_ m) (scale-across scale m)))))
(def %dg-down (fn (_ params scale key lo hi) (%dg-metres params key lo hi (fn (_ m) (scale-down scale m)))))
(def %dg-area (fn (_ params scale key lo hi) (%dg-metres params key lo hi (fn (_ m) (scale-area scale m)))))
; An extent in metres, (KEY W H), as (W . H) cells at SCALE.
(def %dg-extent
  (fn (_ params scale key w h)
    ((fn (_ v) (pair (scale-across scale (first v)) (scale-down scale (List ref 1 v)))) (%dg-p params key (list w h)))))

; Whether rooms A and B touch or overlap, a cell's margin kept.
(def %dg-apart?
  (fn (_ a b)
    (match ((< (+ (room-r1 a) 1) (room-r0 b)) #t)
           ((< (+ (room-r1 b) 1) (room-r0 a)) #t)
           ((< (+ (room-c1 a) 1) (room-c0 b)) #t)
           ((< (+ (room-c1 b) 1) (room-c0 a)) #t)
           (#t #f))))
(def %dg-fits? (fn (_ room rooms) (List all? (fn (_ other) (%dg-apart? room other)) rooms)))

; A room at random within ROWS by COLS: SIZE is (WLO WHI HLO HHI), the
; floor's extent.
(def %dg-try
  (fn (_ rng rows cols size lit)
    (def w (%dg-roll rng (List ref 0 size) (List ref 1 size)))
    (def h (%dg-roll rng (List ref 2 size) (List ref 3 size)))
    (def r0 (%dg-roll rng 0 (- rows (+ h 3))))
    (def c0 (%dg-roll rng 0 (- cols (+ w 3))))
    (list r0 c0 (+ r0 (+ h 1)) (+ c0 (+ w 1)) lit)))

(def %dg-place
  (fn (self rng rows cols size lit? want tries rooms)
    (match
      ((= (List length rooms) want) rooms)
      ((= tries 0) rooms)
      (#t ((fn (_ room)
             (self rng rows cols size lit? want (- tries 1) (if (%dg-fits? room rooms) (pair room rooms) rooms)))
           (%dg-try rng rows cols size (lit?)))))))

; ROOMS by their left edge, an insertion sort.
(def %dg-insert
  (fn (self room l)
    (match ((null? l) (list room))
           ((< (room-c0 room) (room-c0 (first l))) (pair room l))
           (#t (pair (first l) (self room (rest l)))))))
(def %dg-sort (fn (self l acc) (if (null? l) acc (self (rest l) (%dg-insert (first l) acc)))))

; --- carving -----------------------------------------------------------------

(def %dg-carve-room!
  (fn (_ m room)
    (map-each! (room-r0 room) (room-c0 room) (room-r1 room) (room-c1 room)
      (fn (_ r c)
        (map-set! m r c
          (match ((= r (room-r0 room)) tile-wall) ((= r (room-r1 room)) tile-wall)
                 ((= c (room-c0 room)) tile-wall) ((= c (room-c1 room)) tile-wall)
                 (#t tile-floor)))))))

; A passage cell at R C: rock becomes passage, a wall becomes a door, and
; a room's floor or an earlier passage is left as it is.
(def %dg-carve!
  (fn (_ m r c)
    (def t (map-tile m r c))
    (match ((= t tile-rock) (map-set! m r c tile-passage))
           ((= t tile-wall) (map-set! m r c tile-door))
           (#t ()))))
(def %dg-step (fn (_ a b) (match ((< a b) 1) ((< b a) -1) (#t 0))))
(def %dg-hline!
  (fn (self m r c c1)
    (%dg-carve! m r c)
    (unless (= c c1) (self m r (+ c (%dg-step c c1)) c1))))
(def %dg-vline!
  (fn (self m r c r1)
    (%dg-carve! m r c)
    (unless (= r r1) (self m (+ r (%dg-step r r1)) c r1))))

; A passage from room A's centre to room B's, bending once, the way of
; the bend by a coin.
(def %dg-join!
  (fn (_ m rng a b)
    (def p (room-centre a))
    (def q (room-centre b))
    (if (rng bool)
      (do (%dg-hline! m (first p) (rest p) (rest q)) (%dg-vline! m (first p) (rest q) (first q)))
      (do (%dg-vline! m (first p) (rest p) (first q)) (%dg-hline! m (first q) (rest p) (rest q))))))

(def %dg-chain!
  (fn (self m rng rooms)
    (unless (null? (rest rooms))
      (do (%dg-join! m rng (first rooms) (List ref 1 rooms))
          (when (if (null? (rest (rest rooms))) #f (rng bool))
            (%dg-join! m rng (first rooms) (List ref 2 rooms)))
          (self m rng (rest rooms))))))

; A random floor cell of ROOM.
(def %dg-spot
  (fn (_ rng room)
    (pair (%dg-roll rng (+ (room-r0 room) 1) (- (room-r1 room) 1))
          (%dg-roll rng (+ (room-c0 room) 1) (- (room-c1 room) 1)))))

; A level of rooms: (rooms LO HI), (room-size WLO WHI HLO HHI) metres
; of floor, (lit PERCENT STEP), the percent a room is lit at depth 1 and
; what that gains a level.
(def %dg-rooms!
  (fn (_ rng m depth params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def scale (%dg-scale params))
    (def want (%dg-roll rng (List ref 0 (%dg-p params (lit rooms) (list 6 9))) (List ref 1 (%dg-p params (lit rooms) (list 6 9)))))
    (def lit-pct (+ (List ref 0 (%dg-p params (lit lit) (list 95 -4)))
                    (* (- depth 1) (List ref 1 (%dg-p params (lit lit) (list 95 -4))))))
    (def size (%dg-p params (lit room-size) (list 4 12 6 12)))
    (def cells (list (scale-across scale (List ref 0 size)) (scale-across scale (List ref 1 size))
                     (scale-down scale (List ref 2 size)) (scale-down scale (List ref 3 size))))
    (def rooms (%dg-sort (%dg-place rng rows cols cells
                                    (fn (_) (< (rng int 100) lit-pct)) want 200 ())
                         ()))
    (List for-each (fn (_ room) (%dg-carve-room! m room)) rooms)
    (%dg-chain! m rng rooms)
    (map-rooms! m rooms)
    (def up (%dg-spot rng (first rooms)))
    (def down (%dg-spot rng (if (null? (rest rooms)) (first rooms) (List ref (%dg-roll rng 1 (- (List length rooms) 1)) rooms))))
    (%dg-stairs! m up down)))

(def %dg-stairs!
  (fn (_ m up down)
    (map-set! m (first up) (rest up) tile-up)
    (map-set! m (first down) (rest down) tile-down)
    (map-up! m up)
    (map-down! m down)
    m))

; --- caves -------------------------------------------------------------------

; A cave: walkers carve floor from the middle, each step a random way,
; now and then jumping to a cell already carved, until (cave-fill
; PERCENT) of the level is floor; then every rock cell beside floor is
; wall.  A cave has no rooms, so it is lit by sight, (view N).

(def %dg-inside?
  (fn (_ m r c)
    (match ((int< r 1) #f) ((int< c 1) #f) ((int< r (int- (map-rows m) 1)) (int< c (int- (map-cols m) 1))) (#t #f))))

; CELLS is a vector of the carved cells, (R . C), COUNT of them so far;
; a pick from it is one draw, where a pick from a list walks it twice.
(def %dg-cell (fn (_ cells i) (obj-ref cells (int+ i 1))))
(def %dg-pick (fn (_ rng cells count) (%dg-cell cells (rng int count))))

; A draw costs a fifth of a millisecond, so the walk spends one on
; fifteen steps: BITS holds what is left of a 30-bit draw, two bits a
; way, LEFT the ways still in it.  JUMP counts the steps to the next
; jump, drawn from 0 to 99 after each, one step in fifty on average.
; The walk stops once CELLS is full.
(def %dg-draw-span 1073741824)
(def %dg-walk!
  (fn (self rng m r c cells count want bits left jump)
    (match
      ((not (int< count want)) ())
      ((int= (map-tile m r c) tile-rock)
        (do (map-set! m r c tile-floor)
            (obj-set! cells (int+ count 1) (pair r c))
            (self rng m r c cells (int+ count 1) want bits left jump)))
      ((int= left 0) (self rng m r c cells count want (rng int %dg-draw-span) 15 jump))
      ((int= jump 0)
        (do (def at (%dg-pick rng cells count))
            (self rng m (first at) (rest at) cells count want bits left (rng int 100))))
      (#t
        (do (def way (int& bits 3))
            (def nr (match ((int= way 0) (int- r 1)) ((int= way 1) (int+ r 1)) (#t r)))
            (def nc (match ((int= way 2) (int- c 1)) ((int= way 3) (int+ c 1)) (#t c)))
            (if (%dg-inside? m nr nc)
              (self rng m nr nc cells count want (int>> bits 2) (int- left 1) (int- jump 1))
              (self rng m r c cells count want (int>> bits 2) (int- left 1) (int- jump 1))))))))

; Every rock cell beside a carved one is wall.
(def %dg-around
  (list (pair -1 -1) (pair -1 0) (pair -1 1) (pair 0 -1) (pair 0 1) (pair 1 -1) (pair 1 0) (pair 1 1)))
(def %dg-wall-around!
  (fn (self m r c ds)
    (unless (null? ds)
      (do (def wr (int+ r (first (first ds))))
          (def wc (int+ c (rest (first ds))))
          (when (int= (map-tile m wr wc) tile-rock) (map-set! m wr wc tile-wall))
          (self m r c (rest ds))))))
(def %dg-wall-up!
  (fn (self m cells i)
    (when (int< 0 i)
      (do (def at (%dg-cell cells (int- i 1)))
          (%dg-wall-around! m (first at) (rest at) %dg-around)
          (self m cells (int- i 1))))))

(def %dg-abs (fn (_ n) (if (< n 0) (- 0 n) n)))
(def %dg-max (fn (_ a b) (if (< a b) b a)))
(def %dg-dist (fn (_ a b) (%dg-max (%dg-abs (- (first a) (first b))) (%dg-abs (- (rest a) (rest b))))))
; The farthest from FROM of TRIES cells drawn from the COUNT in CELLS.
(def %dg-farthest
  (fn (self rng cells count from tries best bestd)
    (if (= tries 0) best
      ((fn (_ at)
         (if (< bestd (%dg-dist at from)) (self rng cells count from (- tries 1) at (%dg-dist at from))
           (self rng cells count from (- tries 1) best bestd)))
       (%dg-pick rng cells count)))))

; The carved cells of a cave walked from the middle, (CELLS . COUNT),
; walled.
(def %dg-cave!
  (fn (_ rng m params)
    (def want (int/ (* (* (map-rows m) (map-cols m)) (first (%dg-p params (lit cave-fill) (list 40)))) 100))
    (def cells (Vector make want ()))
    (%dg-walk! rng m (int/ (map-rows m) 2) (int/ (map-cols m) 2) cells 0 want 0 0 (rng int 100))
    (%dg-wall-up! m cells want)
    (pair cells want)))
(def %dg-caves!
  (fn (_ rng m params)
    (def cave (%dg-cave! rng m params))
    (def up (%dg-pick rng (first cave) (rest cave)))
    (map-rooms! m ())
    (%dg-stairs! m up (%dg-farthest rng (first cave) (rest cave) up 40 up 0))))

; --- open ground -------------------------------------------------------------

; Open ground: every cell floor, then (clumps LO HI) thickets, each a
; walk over (clump-size LO HI) square metres from a cell within the
; border, so the outermost ring stays floor and every edge can be
; walked to from every other; a pocket of floor a clump closes is
; filled in.  No rooms and no stairs: a screen is left by its edges.

(def %dg-four (list (pair -1 0) (pair 1 0) (pair 0 -1) (pair 0 1)))
(def %dg-clump!
  (fn (self rng m r c k)
    (when (< 0 k)
      (do (when (%dg-inside? m r c) (map-set! m r c tile-thicket))
          (def d (rng choice %dg-four))
          (self rng m (+ r (first d)) (+ c (rest d)) (- k 1))))))

; Every cell a creature can stand on that cannot be walked to from R C,
; a step at a time across a side, made FILL (see map.x).
(def %dg-reach! (fn (_ m r0 c0 fill) (map-fill-unreached! m r0 c0 fill)))
(def %dg-pockets! (fn (_ m) (%dg-reach! m 0 0 tile-thicket)))

(def %dg-open!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (map-each! 0 0 (- rows 1) (- cols 1) (fn (_ r c) (map-set! m r c tile-floor)))
    (def clumps (%dg-p params (lit clumps) (list 6 12)))
    (def size (%dg-area params (%dg-scale params) (lit clump-size) 16 48))
    ((fn (self n)
       (when (< 0 n)
         (do (%dg-clump! rng m (%dg-roll rng 1 (- rows 2)) (%dg-roll rng 1 (- cols 2)) (%dg-draw rng size))
             (self (- n 1)))))
     (%dg-roll rng (first clumps) (List ref 1 clumps)))
    (%dg-pockets! m)
    (map-rooms! m ())
    m))

; --- a town ------------------------------------------------------------------

; A town: streets and terraces.  Every cell is street; then rows of
; terraces, each (terrace-depth LO HI) metres deep, walls included,
; with (street LO HI) metres of street between one row and the next;
; along a row, terraces of (terrace-length LO HI) metres with (lane LO
; HI) metres of lane between.  A terrace is houses side by side, each
; (house-width LO HI) metres along, its own wall included, with one
; door in its front or its back, onto the street.  Two cells round the
; edge are street, and the (square W H) metres in the middle is left
; clear, a cell of street round it.  A terrace too shallow at its scale
; for a room inside its walls is drawn solid, each house a door in its
; front or its back.  No rooms and no stairs: a screen is left by its
; edges.

; The houses of the terrace walled from R0 C0 to R1 C1, from column X:
; a wall at the end of each but the last, and each a door.
(def %dg-houses!
  (fn (self rng m r0 c0 r1 c1 x width)
    (def w (+ x (%dg-draw rng width)))
    (def end (if (< (- c1 3) w) c1 w))
    (when (< end c1) (map-each! (+ r0 1) end (- r1 1) end (fn (_ r c) (map-set! m r c tile-wall))))
    (map-set! m (if (rng bool) r0 r1) (%dg-roll rng (+ x 1) (- end 1)) tile-door)
    (when (< end c1) (self rng m r0 c0 r1 c1 end width))))
; The houses of the solid terrace from R0 C0 to R1 C1, from column X:
; each a door.
(def %dg-fronts!
  (fn (self rng m r0 r1 x c1 width)
    (unless (< c1 x)
      (do (def end (%dg-min c1 (+ x (- (%dg-draw rng width) 1))))
          (map-set! m (if (rng bool) r0 r1) (%dg-roll rng x end) tile-door)
          (self rng m r0 r1 (+ end 1) c1 width)))))
(def %dg-terrace!
  (fn (_ rng m r0 c0 r1 c1 width)
    (when (< 4 (- c1 c0))
      (if (< (- r1 r0) 2)
        (do (%dg-fill! m r0 c0 r1 c1 tile-wall)
            (%dg-fronts! rng m r0 r1 c0 c1 width))
        (do (%dg-carve-room! m (list r0 c0 r1 c1 #f))
            (%dg-houses! rng m r0 c0 r1 c1 c0 (pair (%dg-max 2 (first width)) (%dg-max 2 (rest width)))))))))
; A row of terraces from R0 to R1, from column C, kept off the columns
; SC0 to SC1 when SQUARE? (the row reaches the square).
(def %dg-terraces!
  (fn (self rng m params scale r0 r1 c square? sc0 sc1)
    (def last (- (map-cols m) 3))
    (when (< (+ c 4) last)
      (do (def len (%dg-across params scale (lit terrace-length) 14 28))
          (def e ((fn (_ e) (if (< last e) last e)) (+ c (- (%dg-draw rng len) 1))))
          (def width (%dg-across params scale (lit house-width) 4 8))
          (def lane (%dg-across params scale (lit lane) 1 3))
          (if (if square? (if (< c (+ sc1 2)) (< (- sc0 2) e) #f) #f)
            (do (%dg-terrace! rng m r0 c r1 (- sc0 2) width)
                (self rng m params scale r0 r1 (+ sc1 2) square? sc0 sc1))
            (do (%dg-terrace! rng m r0 c r1 e width)
                (self rng m params scale r0 r1 (+ e (+ 1 (%dg-draw rng lane))) square? sc0 sc1)))))))
(def %dg-town!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (map-each! 0 0 (- rows 1) (- cols 1) (fn (_ r c) (map-set! m r c tile-floor)))
    (def scale (%dg-scale params))
    (def sq (%dg-extent params scale (lit square) 14 8))
    (def sr0 (int/ (- rows (rest sq)) 2))
    (def sc0 (int/ (- cols (first sq)) 2))
    (def sr1 (+ sr0 (- (rest sq) 1)))
    (def sc1 (+ sc0 (- (first sq) 1)))
    (def depth (%dg-down params scale (lit terrace-depth) 8 12))
    (def street (%dg-down params scale (lit street) 2 4))
    ((fn (self r)
       (def r1 (+ r (- (%dg-draw rng depth) 1)))
       (when (< r1 (- rows 2))
         (do (%dg-terraces! rng m params scale r r1 2 (if (< r (+ sr1 2)) (< (- sr0 2) r1) #f) sc0 sc1)
             (self (+ r1 (+ 1 (%dg-draw rng street)))))))
     2)
    (map-rooms! m ())
    m))

; --- shared ------------------------------------------------------------------

(def %dg-min (fn (_ a b) (if (< a b) a b)))
(def %dg-clamp (fn (_ lo x hi) (match ((< x lo) lo) ((< hi x) hi) (#t x))))
(def %dg-chance? (fn (_ rng pct) (< (rng int 100) pct)))
; A two-number knob, (KEY LO HI), as (LO . HI).
(def %dg-range (fn (_ params key lo hi) ((fn (_ v) (pair (first v) (List ref 1 v))) (%dg-p params key (list lo hi)))))
(def %dg-draw (fn (_ rng lohi) (%dg-roll rng (first lohi) (rest lohi))))

; Every cell from R0 C0 to R1 C1 made T.
(def %dg-fill! (fn (_ m r0 c0 r1 c1 t) (map-each! r0 c0 r1 c1 (fn (_ r c) (map-set! m r c t)))))
; A box from R0 C0 to R1 C1: walls of WALL round floor.
(def %dg-box!
  (fn (_ m r0 c0 r1 c1 wall)
    (map-each! r0 c0 r1 c1
      (fn (_ r c)
        (map-set! m r c (if (match ((= r r0) #t) ((= r r1) #t) ((= c c0) #t) ((= c c1) #t) (#t #f)) wall tile-floor))))))
; Every rock cell beside one that does not stop sight made WALL.
(def %dg-walls!
  (fn (_ m wall)
    (map-each! 0 0 (- (map-rows m) 1) (- (map-cols m) 1)
      (fn (_ r c)
        (when (if (= (map-tile m r c) tile-rock)
                (List any? (fn (_ d) (not (map-opaque? (map-tile m (+ r (first d)) (+ c (rest d)))))) %dg-around)
                #f)
          (map-set! m r c wall))))))

; --- a pit: bord and pillar --------------------------------------------------

; A coal pit worked bord and pillar.  A haulage road two cells wide
; runs the length of the level along the middle, from the shaft at one
; end to the dip at the other.  Off it, above and below, panels of the
; seam (panel LO HI) metres long were worked into bords a cell wide
; with pillars of coal (pillar W H) metres between; (worked PERCENT) of
; panels were worked, and the rest left whole or driven by a single
; heading.  Of a worked panel's pillars, (robbed PERCENT) were taken out
; as it was worked back, and (crushed PERCENT) of the rest have come
; down.  Rock beside the workings is wall.  The stairs up are at the
; shaft, the stairs down at the dip; which end is which, by a coin.

; A panel's pillar block from row R0 to R1, column C0 to C1: robbed,
; crushed or standing.
(def %dg-block!
  (fn (_ rng m r0 c0 r1 c1 robbed crushed)
    (%dg-fill! m r0 c0 r1 c1
      (match ((%dg-chance? rng robbed) tile-floor) ((%dg-chance? rng crushed) tile-fall) (#t tile-pillar)))))
; A panel from column C0 to C1 between rows NEAR (beside the road) and
; FAR, STEP 1 or -1 away from the road: bords and pillars.
(def %dg-panel!
  (fn (_ rng m c0 c1 near far step pw ph robbed crushed)
    (%dg-fill! m (%dg-min near far) c0 (%dg-max near far) c1 tile-floor)
    ((fn (self d)
       (def ra (+ near (* step d)))
       (def rb (+ near (* step (+ d (- ph 1)))))
       (unless (< (* step far) (* step rb))
         (do ((fn (self2 x)
                (unless (< c1 x)
                  (do (%dg-block! rng m (%dg-min ra rb) x (%dg-max ra rb) (%dg-min c1 (+ x (- pw 1))) robbed crushed)
                      (self2 (+ x (+ pw 1))))))
              (+ c0 1))
             (self (+ d (+ ph 1))))))
     1)))
(def %dg-pit!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def mr (int/ rows 2))
    (def scale (%dg-scale params))
    (def pillar (%dg-extent params scale (lit pillar) 4 4))
    (def panel (%dg-across params scale (lit panel) 10 22))
    (def worked (first (%dg-p params (lit worked) (list 75))))
    (def robbed (first (%dg-p params (lit robbed) (list 20))))
    (def crushed (first (%dg-p params (lit crushed) (list 10))))
    (%dg-fill! m (- mr 1) 2 mr (- cols 3) tile-floor)
    ((fn (self c)
       (when (< (+ c 4) (- cols 3))
         (do (def e (%dg-min (- cols 4) (+ c (- (%dg-draw rng panel) 1))))
             (List for-each
               (fn (_ side)
                 (def near (if (< 0 side) (+ mr 1) (- mr 2)))
                 (def far (if (< 0 side) (- rows 3) 2))
                 (match ((%dg-chance? rng worked)
                          (%dg-panel! rng m c e near far side (first pillar) (rest pillar) robbed crushed))
                        ((rng bool) (%dg-fill! m (%dg-min near far) (int/ (+ c e) 2) (%dg-max near far) (int/ (+ c e) 2) tile-floor))
                        (#t ())))
               (list -1 1))
             (self (+ e 2)))))
     3)
    (%dg-walls! m tile-wall)
    (map-rooms! m ())
    (if (rng bool)
      (%dg-stairs! m (pair mr 2) (pair (- mr 1) (- cols 3)))
      (%dg-stairs! m (pair mr (- cols 3)) (pair (- mr 1) 2)))))

; --- a flooded reach ---------------------------------------------------------

; A flooded reach: a channel the water runs along from the west edge to
; the east, its course wandering a row at a time, (channel LO HI) metres
; deep; along stretches of it the lower part is deep water, three rows of
; the upper part always shallow enough to wade.  Pockets the water
; washed out of the rock open off it, (pockets LO HI) of them, each a
; wander over (pocket-size LO HI) square metres.  Rock beside is wall.
; The stairs up are at the west end, the stairs down at the east: the
; water runs one way.

; A wander of K steps from R C carving rock to floor, kept off the edge;
; it never steps into water, so what it carves is reached from where it
; began.
(def %dg-wash!
  (fn (self rng m r c k)
    (when (< 0 k)
      (do (when (if (%dg-inside? m r c) (= (map-tile m r c) tile-rock) #f) (map-set! m r c tile-floor))
          (def d (rng choice %dg-four))
          (def nr (+ r (first d)))
          (def nc (+ c (rest d)))
          (if (if (%dg-inside? m nr nc) (not (= (map-tile m nr nc) tile-water)) #f) (self rng m nr nc (- k 1)) (self rng m r c (- k 1)))))))
(def %dg-flood!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def scale (%dg-scale params))
    (def deep (%dg-down params scale (lit channel) 10 16))
    (def pockets (%dg-range params (lit pockets) 4 8))
    (def size (%dg-area params scale (lit pocket-size) 40 120))
    ; Each column's top and bottom rows of the channel, and whether its
    ; bottom is dry.
    (def tops (Vector make cols 0))
    (def bottoms (Vector make cols 0))
    (def dry (Vector make cols #t))
    ((fn (self c y w pool?)
       (when (< c (- cols 2))
         (do (def t (%dg-clamp 1 (- y (int/ w 2)) (- rows (+ w 1))))
             (def b (+ t (- w 1)))
             ; A channel a row or two deep, at a large scale, can step
             ; clear of the column before; the floor reaches back to it.
             (if (< 2 c)
               (%dg-fill! m (%dg-min t (Vector ref (- c 1) bottoms)) c (%dg-max b (Vector ref (- c 1) tops)) c tile-floor)
               (%dg-fill! m t c b c tile-floor))
             (when pool? (%dg-fill! m (+ t 3) c b c tile-water))
             (Vector set! c t tops)
             (Vector set! c b bottoms)
             (Vector set! c (not pool?) dry)
             (self (+ c 1)
                   (%dg-clamp 5 (+ y (if (= (rng int 3) 0) (- (rng int 3) 1) 0)) (- rows 6))
                   (%dg-clamp (first deep) (+ w (if (= (rng int 4) 0) (- (rng int 3) 1) 0)) (rest deep))
                   (if (= (rng int (if pool? 12 5)) 0) (not pool?) pool?)))))
     2 (%dg-roll rng 6 (- rows 7)) (first deep) #f)
    ((fn (self n)
       (when (< 0 n)
         (do (def c (%dg-roll rng 3 (- cols 4)))
             (def up? (if (Vector ref c dry) (rng bool) #t))
             (%dg-wash! rng m (if up? (- (Vector ref c tops) 1) (+ (Vector ref c bottoms) 1)) c (%dg-draw rng size))
             (self (- n 1)))))
     (%dg-draw rng pockets))
    (%dg-walls! m tile-wall)
    (map-rooms! m ())
    (%dg-stairs! m (pair (+ (Vector ref 2 tops) 1) 2) (pair (+ (Vector ref (- cols 3) tops) 1) (- cols 3)))))

; --- the well-keepers' works -------------------------------------------------

; The well-keepers' works: dressed stone laid without mortar, built to a
; plan.  A stair runs the length of the level along the middle, a cell
; wide; vaults open off it in pairs, one above and one below, alike,
; each (vault-width LO HI) by (vault-height LO HI) metres inside, a door
; in the middle of the side facing the stair; where no vault opens,
; (niches PERCENT) of the stair's wall is cut back a cell, for the dead.
; The stairs up are at the west end, the stairs down at the east.
(def %dg-works!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def mr (int/ rows 2))
    (def scale (%dg-scale params))
    (def vw (%dg-across params scale (lit vault-width) 5 11))
    (def vh (%dg-down params scale (lit vault-height) 4 10))
    (def niches (first (%dg-p params (lit niches) (list 30))))
    (%dg-fill! m mr 2 mr (- cols 3) tile-floor)
    ((fn (self c)
       (def w (%dg-draw rng vw))
       (def h (%dg-min (%dg-draw rng vh) (- mr 3)))
       (def c1 (+ c (+ w 1)))
       (if (< c1 (- cols 3))
         (do (def cm (int/ (+ c c1) 2))
             (%dg-box! m (- mr (+ h 2)) c (- mr 1) c1 tile-dressed)
             (%dg-box! m (+ mr 1) c (+ mr (+ h 2)) c1 tile-dressed)
             (map-set! m (- mr 1) cm tile-door)
             (map-set! m (+ mr 1) cm tile-door)
             (self (+ c1 (%dg-roll rng (scale-across scale 2) (scale-across scale 6)))))
         ()))
     (%dg-roll rng (scale-across scale 3) (scale-across scale 6)))
    (map-each! mr 3 mr (- cols 4)
      (fn (_ r c)
        (List for-each
          (fn (_ d) (when (if (= (map-tile m (+ r d) c) tile-rock) (%dg-chance? rng niches) #f) (map-set! m (+ r d) c tile-floor)))
          (list -1 1))))
    (%dg-walls! m tile-dressed)
    (map-rooms! m ())
    (%dg-stairs! m (pair mr 2) (pair mr (- cols 3)))))

; --- the well-house ----------------------------------------------------------

; The well-house: a cave round the court the well-keepers walled about
; the stone's pool.  The cave is carved as caves are; in its middle the
; court, (court W H) metres outside, its walls dressed, a door in the
; middle of each side and a passage from each door out into the cave;
; in the court the pool, deep water, with a walk two cells wide round
; it.  Whatever the court cut off is filled.  The stairs up are in the
; cave, the stairs down on the walk by the pool: the way on is through
; the well-house.
(def %dg-out!
  (fn (self m r c dr dc)
    (when (if (%dg-inside? m r c) (not (map-passable? (map-tile m r c))) #f)
      (do (map-set! m r c tile-floor) (self m (+ r dr) (+ c dc) dr dc)))))
(def %dg-well!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (%dg-cave! rng m params)
    (def court (%dg-extent params (%dg-scale params) (lit court) 31 22))
    (def r0 (int/ (- rows (rest court)) 2))
    (def c0 (int/ (- cols (first court)) 2))
    (def r1 (+ r0 (- (rest court) 1)))
    (def c1 (+ c0 (- (first court) 1)))
    (def rm (int/ (+ r0 r1) 2))
    (def cm (int/ (+ c0 c1) 2))
    (%dg-fill! m (- r0 1) (- c0 1) (+ r1 1) (+ c1 1) tile-rock)
    (%dg-box! m r0 c0 r1 c1 tile-dressed)
    (%dg-fill! m (+ r0 3) (+ c0 3) (- r1 3) (- c1 3) tile-water)
    (map-set! m r0 cm tile-door)
    (map-set! m r1 cm tile-door)
    (map-set! m rm c0 tile-door)
    (map-set! m rm c1 tile-door)
    (%dg-out! m (- r0 1) cm -1 0)
    (%dg-out! m (+ r1 1) cm 1 0)
    (%dg-out! m rm (- c0 1) 0 -1)
    (%dg-out! m rm (+ c1 1) 0 1)
    (def down (pair (+ r0 1) (%dg-roll rng (+ c0 2) (- c1 2))))
    (%dg-reach! m (first down) (rest down) tile-wall)
    (%dg-walls! m tile-wall)
    ; The stairs up: the floor farthest from the court, the passage out
    ; of its east door when the court has cut off the rest.
    (def best (Vector make 2 ()))
    (Vector set! 0 (pair rm (+ c1 1)) best)
    (Vector set! 1 0 best)
    (map-each! 0 0 (- rows 1) (- cols 1)
      (fn (_ r c)
        (def d (%dg-dist (pair r c) (pair rm cm)))
        (when (if (= (map-tile m r c) tile-floor) (< (Vector ref 1 best) d) #f)
          (do (Vector set! 0 (pair r c) best) (Vector set! 1 d best)))))
    (def up (Vector ref 0 best))
    (map-rooms! m ())
    (%dg-stairs! m up down)))

; --- fields ------------------------------------------------------------------

; Fields: closes hedged about either side of a road.  The road runs the
; width of the level along the middle row, so that it meets the road on
; the next screen, a hedge each side of it, its first gate (gate-first
; LO HI) metres in and each after it (gate-gap LO HI) metres on.
; Above and below it, inside a headland two cells wide round the edge,
; the ground is cut into closes: a piece longer than (close W H) metres
; is halved across its longer side by a hedge with a gate in it.  Of
; the hedges' cells, (trees PERCENT) are hedgerow trees.

; A hedge from R0 C0 to R1 C1, short of any gate it would close: a
; cell beside a gate is left open, so the gate still leads somewhere.
(def %dg-hedge!
  (fn (_ m r0 c0 r1 c1)
    (map-each! r0 c0 r1 c1
      (fn (_ r c)
        (unless (List any? (fn (_ d) (= (map-tile m (+ r (first d)) (+ c (rest d))) tile-gate)) %dg-four)
          (map-set! m r c tile-hedge))))))
; The piece from R0 C0 to R1 C1 hedged into closes.
(def %dg-closes!
  (fn (self rng m r0 c0 r1 c1 cw ch)
    (def w (+ (- c1 c0) 1))
    (def h (+ (- r1 r0) 1))
    (match
      ((if (< (%dg-max cw 6) w) (< (* 2 h) (+ w 1)) #f)
        (do (def x (%dg-roll rng (+ c0 3) (- c1 3)))
            (%dg-hedge! m r0 x r1 x)
            (map-set! m (%dg-roll rng r0 r1) x tile-gate)
            (self rng m r0 c0 r1 (- x 1) cw ch)
            (self rng m r0 (+ x 1) r1 c1 cw ch)))
      ((< (%dg-max ch 4) h)
        (do (def y (%dg-roll rng (+ r0 2) (- r1 2)))
            (%dg-hedge! m y c0 y c1)
            (map-set! m y (%dg-roll rng c0 c1) tile-gate)
            (self rng m r0 c0 (- y 1) c1 cw ch)
            (self rng m (+ y 1) c0 r1 c1 cw ch)))
      (#t ()))))
(def %dg-trees!
  (fn (_ rng m pct)
    (map-each! 0 0 (- (map-rows m) 1) (- (map-cols m) 1)
      (fn (_ r c) (when (if (= (map-tile m r c) tile-hedge) (%dg-chance? rng pct) #f) (map-set! m r c tile-thicket))))))
(def %dg-fields!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def mr (int/ rows 2))
    (def scale (%dg-scale params))
    (def close (%dg-extent params scale (lit close) 16 10))
    (def trees (first (%dg-p params (lit trees) (list 8))))
    (def gap (%dg-across params scale (lit gate-gap) 10 24))
    (def gate (%dg-across params scale (lit gate-first) 3 12))
    (%dg-fill! m 0 0 (- rows 1) (- cols 1) tile-floor)
    (List for-each
      (fn (_ r)
        (%dg-fill! m r 2 r (- cols 3) tile-hedge)
        ((fn (self c)
           (when (< c (- cols 3))
             (do (map-set! m r c tile-gate) (self (+ c (%dg-draw rng gap))))))
         (%dg-draw rng gate)))
      (list (- mr 1) (+ mr 1)))
    (%dg-closes! rng m 2 2 (- mr 2) (- cols 3) (first close) (rest close))
    (%dg-closes! rng m (+ mr 2) 2 (- rows 3) (- cols 3) (first close) (rest close))
    (%dg-trees! rng m trees)
    (map-rooms! m ())
    m))

; --- hills -------------------------------------------------------------------

; Hills: heath with gritstone edges across it, boulders fallen off them,
; and bog in the low ground.  (edges LO HI) edges, each a line of rock
; (edge-length LO HI) metres long running east, a row up or down now
; and then, with a gap here and there where a sheep track climbs
; through, and boulders (boulder-drop LO HI) metres below it; (bogs LO
; HI) bogs, each a wander over (bog-size LO HI) square metres of wet
; ground with pools in it; (gorse LO HI) clumps of gorse, each a wander
; over (gorse-size LO HI) square metres.  Two cells round the edge are
; left clear, and ground cut off is filled.
(def %dg-hills!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def edges (%dg-range params (lit edges) 2 4))
    (def scale (%dg-scale params))
    (def span (%dg-across params scale (lit edge-length) 20 50))
    (def fall (%dg-down params scale (lit boulder-drop) 4 6))
    (def bogs (%dg-range params (lit bogs) 1 3))
    (def bog (%dg-area params scale (lit bog-size) 40 120))
    (def gorse (%dg-range params (lit gorse) 3 6))
    (def furze (%dg-area params scale (lit gorse-size) 16 40))
    (def inner? (fn (_ r c) (if (< 1 r) (if (< r (- rows 2)) (if (< 1 c) (< c (- cols 2)) #f) #f) #f)))
    (%dg-fill! m 0 0 (- rows 1) (- cols 1) tile-floor)
    ((fn (self n)
       (when (< 0 n)
         (do ((fn (self2 r c k)
                (when (if (< 0 k) (inner? r c) #f)
                  (do (unless (= (rng int 14) 0) (map-set! m r c tile-edge))
                      (when (= (rng int 7) 0)
                        ((fn (_ br bc) (when (inner? br bc) (map-set! m br bc tile-edge)))
                         (+ r (%dg-draw rng fall)) (+ c (- (rng int 3) 1))))
                      (self2 (%dg-clamp 2 (+ r (if (= (rng int 9) 0) (- (rng int 3) 1) 0)) (- rows 3)) (+ c 1) (- k 1)))))
              (%dg-roll rng 3 (- rows 6)) (%dg-roll rng 2 (- cols 20)) (%dg-draw rng span))
             (self (- n 1)))))
     (%dg-draw rng edges))
    (def wander
      (fn (_ n size cell)
        ((fn (self n)
           (when (< 0 n)
             (do ((fn (self2 r c k)
                    (when (< 0 k)
                      (do (when (inner? r c) (map-set! m r c (cell)))
                          (def d (rng choice %dg-four))
                          (self2 (%dg-clamp 2 (+ r (first d)) (- rows 3)) (%dg-clamp 2 (+ c (rest d)) (- cols 3)) (- k 1)))))
                  (%dg-roll rng 3 (- rows 4)) (%dg-roll rng 3 (- cols 4)) (%dg-draw rng size))
                 (self (- n 1)))))
         (%dg-draw rng n))))
    (wander bogs bog (fn (_) (if (= (rng int 6) 0) tile-water tile-bog)))
    (wander gorse furze (fn (_) tile-thicket))
    (%dg-reach! m 0 0 tile-edge)
    (map-rooms! m ())
    m))

; --- the rim -----------------------------------------------------------------

; The rim: short grass on the limestone, with scars, shakeholes and the
; well-keepers' ruins.  (scars LO HI) scars, each a straight cliff of
; bare rock, (scar-across LO HI) metres along a row or (scar-down LO
; HI) down a column, a gap or two in it; (holes LO HI) shakeholes,
; round hollows open to the dark; (ruins LO HI) ruins, each the dressed
; walls of a building (ruin-width LO HI) by (ruin-depth LO HI) metres,
; (fallen PERCENT) of them down; (stones LO HI) rows of standing
; stones, (stone-gap M) metres apart.  Two cells round the edge are
; left clear, and ground cut off is filled.
(def %dg-rim!
  (fn (_ rng m params)
    (def rows (map-rows m))
    (def cols (map-cols m))
    (def scars (%dg-range params (lit scars) 2 4))
    (def holes (%dg-range params (lit holes) 2 5))
    (def ruins (%dg-range params (lit ruins) 1 3))
    (def stones (%dg-range params (lit stones) 0 2))
    (def fallen (first (%dg-p params (lit fallen) (list 30))))
    (def scale (%dg-scale params))
    (def scar-w (%dg-across params scale (lit scar-across) 15 40))
    (def scar-h (%dg-down params scale (lit scar-down) 10 24))
    (def rw (%dg-across params scale (lit ruin-width) 6 14))
    (def rd (%dg-down params scale (lit ruin-depth) 8 14))
    (def apart (scale-across scale (first (%dg-p params (lit stone-gap) (list 2)))))
    (def times (fn (_ n f) ((fn (self n) (when (< 0 n) (do (f) (self (- n 1))))) n)))
    (%dg-fill! m 0 0 (- rows 1) (- cols 1) tile-floor)
    (times (%dg-draw rng scars)
      (fn (_)
        (if (rng bool)
          (do (def r (%dg-roll rng 3 (- rows 4)))
              (def c0 (%dg-roll rng 2 (int/ cols 2)))
              (def c1 (%dg-min (- cols 3) (+ c0 (%dg-draw rng scar-w))))
              (def gap (%dg-roll rng c0 c1))
              (map-each! r c0 r c1 (fn (_ r c) (unless (if (< (- gap 1) c) (< c (+ gap 2)) #f) (map-set! m r c tile-scar)))))
          (do (def c (%dg-roll rng 4 (- cols 5)))
              (def r0 (%dg-roll rng 2 (int/ rows 2)))
              (def r1 (%dg-min (- rows 3) (+ r0 (%dg-draw rng scar-h))))
              (map-each! r0 c r1 c (fn (_ r c) (map-set! m r c tile-scar)))))))
    (times (%dg-draw rng holes)
      (fn (_)
        (def r (%dg-roll rng 3 (- rows 4)))
        (def c (%dg-roll rng 4 (- cols 5)))
        (map-set! m r c tile-rock)
        (when (rng bool)
          (List for-each (fn (_ d) (map-set! m (+ r (first d)) (+ c (rest d)) tile-rock)) %dg-four))))
    (times (%dg-draw rng ruins)
      (fn (_)
        (def w (%dg-draw rng rw))
        (def h (%dg-draw rng rd))
        (def r0 (%dg-roll rng 2 (- rows (+ h 2))))
        (def c0 (%dg-roll rng 2 (- cols (+ w 2))))
        (def r1 (+ r0 (- h 1)))
        (def c1 (+ c0 (- w 1)))
        (%dg-box! m r0 c0 r1 c1 tile-dressed)
        (map-each! r0 c0 r1 c1
          (fn (_ r c) (when (if (= (map-tile m r c) tile-dressed) (%dg-chance? rng fallen) #f) (map-set! m r c tile-floor))))
        (map-set! m r1 (int/ (+ c0 c1) 2) tile-floor)))
    (times (%dg-draw rng stones)
      (fn (_)
        (def r (%dg-roll rng 3 (- rows 4)))
        ((fn (self c n) (when (< 0 n) (do (map-set! m r c tile-dressed) (self (+ c apart) (- n 1)))))
         (%dg-roll rng 3 (- cols 20)) (%dg-roll rng 4 7))))
    (%dg-reach! m 0 0 tile-scar)
    (map-rooms! m ())
    m))

; A level of ROWS by COLS at DEPTH, by PARAMS: rooms, or caves with
; (level-style caves), open ground with (level-style open), or a town
; with (level-style town); in the Delve, a pit (pit), a flooded reach
; (flood), the well-keepers' works (works) or the well-house (well); in
; the valley, fields (fields), hills (hills) or the rim (rim).  With
; (stairs up) the stairs down are floor: a level with a way back and
; none on.
(def dungeon-generate
  (fn (_ rng rows cols depth params)
    (def m (map-make rows cols))
    (def style (first (%dg-p params (lit level-style) (list (lit rooms)))))
    (match ((eq? style (lit caves)) (%dg-caves! rng m params))
           ((eq? style (lit open)) (%dg-open! rng m params))
           ((eq? style (lit town)) (%dg-town! rng m params))
           ((eq? style (lit pit)) (%dg-pit! rng m params))
           ((eq? style (lit flood)) (%dg-flood! rng m params))
           ((eq? style (lit works)) (%dg-works! rng m params))
           ((eq? style (lit well)) (%dg-well! rng m params))
           ((eq? style (lit fields)) (%dg-fields! rng m params))
           ((eq? style (lit hills)) (%dg-hills! rng m params))
           ((eq? style (lit rim)) (%dg-rim! rng m params))
           (#t (%dg-rooms! rng m depth params)))
    (def down (map-down m))
    (when (if (null? down) #f (eq? (first (%dg-p params (lit stairs) (list (lit both)))) (lit up)))
      (do (map-set! m (first down) (rest down) tile-floor) (map-down! m ())))
    m))

; A random floor cell of M that FREE? allows -- of a random room, or
; anywhere on a level without rooms -- or nil after TRIES tries.
(def dungeon-spot
  (fn (self rng m free? tries)
    (if (= tries 0) ()
      ((fn (_ at)
         (if (if (= (map-tile m (first at) (rest at)) tile-floor) (free? (first at) (rest at)) #f) at
           (self rng m free? (- tries 1))))
       (if (null? (map-rooms m)) (pair (rng int (map-rows m)) (rng int (map-cols m)))
         (%dg-spot rng (rng choice (map-rooms m))))))))

(provide roguelike/dungeon dungeon-generate dungeon-spot)
