; # x-roguelike -- a roguelike on x-lang
;
; ## tools/model.x -- what a set's numbers say a fight costs, no bot
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
;   MODEL_SET=delve x -l roguelike -f tools/model.x
;
; The set's own forms, read through the engine's formulas, worked out
; level by level with no game played.  For each level: the player
; there, how many creatures, how many awake at the start and how many
; more wander in, how often a weapon lies there, and for each kind of
; creature what a fight costs, bare-handed and with the best gear the
; level can hold.
;
; The terms, each from the engine:
;
;   hit chance    clamp(70 + 5 level - 5 defence, 5, 95)       combat.x
;   hurt a turn   a = its hit chance x its mean attack x speed (fast 2, slow 1/2)
;   turns to kill T = mean over its hit points of E(h),
;                 E(h) = 1/p + avg over the dice x of E(h - x - bonus)
;   one fight     a T
;   a pack of k   a T k(k+1)/2 all beside, a T k one at a time
;   most beaten   the largest k whose cost stays under the hit points
;   a weapon      1 - (1 - g)^n, the mean over the level's n draws,
;                 g a draw's chance of being one
;   the player    the level the experience of every creature on the
;                 levels above buys, (exp) doubling a level; the hit
;                 points 3 to 8 more a level
;
; Two numbers are the engine's and not the set's: a creature starts
; asleep 60 times in 100 unless wakeful (creatures.x %cr-start), every
; one asleep or wandering by (hunt sight), and a level-up gives 3 to 8
; hit points (combat.x).  On the set's (gentle N) first levels a pack
; is one and none wander in.  An erratic creature
; still strikes every turn it is beside the player; the first blow on
; a sleeper (surprise) is left out.  The player's level is a ceiling:
; it counts every creature killed.  MODEL_LEVEL fixes the player's
; level; MODEL_DEPTH gives one depth, every depth to the goal unless
; given.
;
; lint-known: %lang-root

(import x/sys/posix)
(import x/num/float)
(import roguelike/data data-load data-all data-one data-prop data-prop1 data-trait?)
(import roguelike/state state-covers?)
(import roguelike/odds odds-hit odds-mid odds-kill odds-hurt)
(import roguelike/combat combat-str-bonus combat-chill)

(def %md-env
  (fn (_ name default)
    (def v (Sys getenv name))
    (if (if (null? v) #t (str=? v "")) default v)))
(def %md-int (fn (_ s) ((prim-ref (lit convert) (lit to)) s (Type named INTEGER) 10)))
(def %md-line (fn (_ . parts) (Sys fd-write 1 (Str8 append (Str8 join "" parts) "\n"))))
(def %md-pad (fn (_ n s) (if (< (Str8 length s) n) (Str8 append (Str8 repeat (- n (Str8 length s)) " ") s) s)))
(def %md-rpad (fn (_ n s) (if (< (Str8 length s) n) (Str8 append s (Str8 repeat (- n (Str8 length s)) " ")) s)))

(def %md-f (fn (_ n) (Float from n)))
(def %md-round (fn (_ x) (Float ->int (Float round x))))
; X to one place: 3.18 is "3.2".
(def %md-dec
  (fn (_ x)
    (def tenths (%md-round (* x 10)))
    (Str8 append (Str8 str (Float ->int (Float trunc (/ (%md-f tenths) 10)))) "." (Str8 str (% tenths 10)))))
(def %md-col (fn (_ w x) (%md-pad w (%md-dec x))))
(def %md-pct (fn (_ w x) (%md-pad w (Str8 append (Str8 str (%md-round (* x 100))) "%"))))
(def %md-span (fn (_ l) (Str8 join "-" (List map (fn (_ n) (Str8 str n)) l))))

(def %md-clamp (fn (_ n lo hi) (match ((< n lo) lo) ((< hi n) hi) (#t n))))
(def %md-hit odds-hit)
(def %md-mid odds-mid)
(def %md-sum (fn (_ l) (List fold (fn (_ a b) (+ a b)) (%md-f 0) l)))
(def %md-mean (fn (_ l) (if (null? l) (%md-f 0) (/ (%md-sum l) (List length l)))))
(def %md-upto (fn (_ d) (List range (first d) (+ 1 (List ref 1 d)))))

; --- a fight -----------------------------------------------------------------

; T: the mean swings to kill, over the creature's hit points (odds.x).
(def %md-kill odds-kill)

; The largest K, to twenty, whose cost (COST K) stays under HP.
(def %md-most
  (fn (_ cost hp)
    ((fn (self k) (if (if (< k 20) (< (cost (+ k 1)) hp) #f) (self (+ k 1)) k)) 0)))

; How often a pack of LO..HI runs past K.
(def %md-beyond
  (fn (_ pack k)
    (def sizes (%md-upto pack))
    (/ (%md-f (List length (List filter (fn (_ n) (< k n)) sizes))) (List length sizes))))

; Hurt a turn from KIND beside a player of DEFENCE.
(def %md-hurt
  (fn (_ kind defence)
    (odds-hurt (data-prop1 kind (lit level) 1) (data-prop kind (lit attack) (list 1 2)) defence
               (match ((data-trait? kind (lit fast)) (lit fast)) ((data-trait? kind (lit slow)) (lit slow)) (#t ()))
               (if (data-trait? kind (lit cold)) combat-chill 0))))

; --- a level's creatures and items ----------------------------------------------

(def %md-covers? (fn (_ form depth) (state-covers? (data-prop form (lit depth) (list 1 99)) depth)))
(def %md-kinds
  (fn (_ set depth)
    (List filter (fn (_ k) (if (data-trait? k (lit talks)) #f (%md-covers? k depth))) (data-all set (lit creature)))))
; Whether the set hunts by sight; whether DEPTH is one of its gentle
; first levels.
(def %md-sight? (fn (_ set) (eq? (first (data-one set (lit hunt) (list (lit anywhere)))) (lit sight))))
(def %md-gentle?
  (fn (_ set depth) (def n (first (data-one set (lit gentle) (list 0)))) (if (< 0 n) (not (< n depth)) #f)))
; KIND's pack at DEPTH: one on a gentle level.
(def %md-pack (fn (_ set depth kind) (if (%md-gentle? set depth) (list 1 1) (data-prop kind (lit pack) (list 1 1)))))
(def %md-pack-mid (fn (_ set depth) (fn (_ kind) (%md-mid (%md-pack set depth kind)))))

; The level's creatures: (EACH AWAKE WANDER), how many at the start, how
; many of those awake and hunting, and how many more come in a hundred
; turns.  By sight none starts hunting, and on a gentle level none
; comes.
(def %md-numbers
  (fn (_ set depth kinds)
    (def placements (%md-mid (data-one set (lit creatures) (list 3 6))))
    (def mid (%md-pack-mid set depth))
    (def awake (fn (_ k) (* (match ((%md-sight? set) (%md-f 0)) ((data-trait? k (lit wakeful)) (%md-f 1)) (#t (/ (%md-f 40) 100)))
                            (mid k))))
    (list (* placements (%md-mean (List map mid kinds)))
          (* placements (%md-mean (List map awake kinds)))
          (if (%md-gentle? set depth) (%md-f 0)
            (/ (* 100 (%md-mean (List map mid kinds))) (first (data-one set (lit wander) (list 60))))))))

; The experience the level's creatures hold, all of them killed.
(def %md-exp-at
  (fn (_ set depth)
    (def kinds (%md-kinds set depth))
    (def mid (%md-pack-mid set depth))
    (* (first (%md-numbers set depth kinds))
       (%md-mean (List map (fn (_ k) (* (%md-f (data-prop1 k (lit exp) 0)) (mid k))) kinds))
       (/ (%md-f 1) (%md-mean (List map mid kinds))))))

; The chance a draw at DEPTH is of GROUP, gold aside.
(def %md-draw
  (fn (_ set depth group)
    (def forms (List filter (fn (_ f) (%md-covers? f depth)) (data-all set (lit item))))
    (def weight (fn (_ f) (data-prop1 f (lit rarity) 1)))
    (def total (%md-sum (List map weight forms)))
    (def mine (%md-sum (List map weight (List filter (fn (_ f) (eq? (first f) group)) forms))))
    (def gold (/ (%md-f (first (data-one set (lit gold) (list 35)))) 100))
    (if (< total 1) (%md-f 0) (* (- 1 gold) (/ mine total)))))

; The chance a level holds one of GROUP: 1 - (1 - g)^n over its draws.
(def %md-on-level
  (fn (_ set depth group)
    (def miss (- (%md-f 1) (%md-draw set depth group)))
    (- 1 (%md-mean (List map (fn (_ n) (Float pow miss (%md-f n))) (%md-upto (data-one set (lit items) (list 4 8))))))))

; --- the player and the gear -------------------------------------------------

; The level EXP buys: (exp) for level 2, doubling each level after.
(def %md-level-for
  (fn (_ set exp)
    (def step (%md-f (first (data-one set (lit exp) (list 10)))))
    ((fn (self level need) (if (< exp need) level (self (+ level 1) (* need 2)))) 1 step)))

; (HP STR LEVEL UNARMED): the set's player at DEPTH, MODEL_LEVEL or the
; level the experience above it buys.
(def %md-player
  (fn (_ set depth)
    (def spec (data-one set (lit player) (list 12 16)))
    (def fixed (%md-env "MODEL_LEVEL" ""))
    (def level (if (str=? fixed "") (%md-level-for set (%md-sum (List map (fn (_ d) (%md-exp-at set d)) (List range 1 depth))))
                 (%md-int fixed)))
    (list (+ (%md-f (first spec)) (* (/ (%md-f 11) 2) (- level 1))) (List ref 1 spec) level
          (data-one set (lit unarmed) (list 1 2)))))

(def %md-forms-at
  (fn (_ set group depth)
    (List filter (fn (_ f) (if (eq? (first f) group) (if (< 0 (data-prop1 f (lit rarity) 1)) (%md-covers? f depth) #f) #f))
      (data-all set (lit item)))))
(def %md-best
  (fn (_ forms worth)
    (List fold (fn (_ best f) (if (if (null? best) #t (< (worth best) (worth f))) f best)) () forms)))

; The best weapon and armour that may lie at DEPTH and that STR lifts.
(def %md-gear
  (fn (_ set depth str)
    (def liftable (fn (_ f) (not (< str (data-prop1 f (lit strength) 0)))))
    (list (%md-best (List filter liftable (%md-forms-at set (lit weapon) depth))
                    (fn (_ f) (+ (first (data-prop f (lit damage) (list 1 2))) (List ref 1 (data-prop f (lit damage) (list 1 2))))))
          (%md-best (List filter liftable (%md-forms-at set (lit armour) depth))
                    (fn (_ f) (data-prop1 f (lit armour) 0))))))

; --- the report --------------------------------------------------------------

(def %md-gear-text
  (fn (_ f key) (if (null? f) "none" (Str8 append (first (rest f)) " " (%md-span (data-prop f key (list 0)))))))

(def %md-head
  (fn (_ set depth who gear)
    (def regen (%md-clamp (- (first (data-one set (lit regen) (list 20))) (* 2 (- (List ref 2 who) 1))) 4 999))
    (%md-line "Level " (Str8 str depth) " -- the player at level " (Str8 str (List ref 2 who)) ": " (%md-dec (first who))
              " hp, strength " (Str8 str (List ref 1 who)) ", bare " (%md-span (List ref 3 who))
              ", a hit point back every " (Str8 str regen) " turns")
    (%md-line " best here: " (%md-gear-text (first gear) (lit damage)) ", " (%md-gear-text (List ref 1 gear) (lit armour)))))

(def %md-level-lines
  (fn (_ set depth kinds)
    (def n (%md-numbers set depth kinds))
    (%md-line " creatures " (%md-dec (first n)) " at the start, " (%md-dec (List ref 1 n)) " of them hunting, "
              (%md-dec (List ref 2 n)) " more every hundred turns")
    (%md-line " items " (%md-dec (%md-mid (data-one set (lit items) (list 4 8)))) " a level: a weapon on "
              (%md-pct 0 (%md-on-level set depth (lit weapon))) " of levels, armour on "
              (%md-pct 0 (%md-on-level set depth (lit armour))))))

(def %md-titles
  (fn (_)
    (%md-line " " (%md-rpad 18 "") "              hurt   turns to kill   one fight's hurt           most beaten (bare armed)   packs")
    (%md-line " " (%md-rpad 18 "kind") "  you%   it%  a turn     bare  armed       bare  armed   pack     in the open   in a line   too many")))

; KIND's row against WHO bare and with GEAR.
(def %md-kind-row
  (fn (_ set depth kind who gear)
    (def bonus (combat-str-bonus (List ref 1 who)))
    (def hp (first who))
    (def kh (data-prop kind (lit hp) (list 1 6)))
    (def you (%md-hit (List ref 2 who) (data-prop1 kind (lit defence) 3)))
    (def armour (if (null? (List ref 1 gear)) 0 (data-prop1 (List ref 1 gear) (lit armour) 0)))
    (def t-bare (%md-kill you (List ref 3 who) bonus kh))
    (def t-armed (if (null? (first gear)) t-bare (%md-kill you (data-prop (first gear) (lit damage) (list 1 2)) bonus kh)))
    (def one-bare (* (%md-hurt kind 0) t-bare))
    (def one-armed (* (%md-hurt kind armour) t-armed))
    (def open (fn (_ one) (%md-most (fn (_ k) (/ (* one (* k (+ k 1))) 2)) hp)))
    (def line (fn (_ one) (%md-most (fn (_ k) (* one k)) hp)))
    (def pack (%md-pack set depth kind))
    (%md-line " " (%md-rpad 18 (first kind)) (%md-pct 6 you) (%md-pct 6 (%md-hit (data-prop1 kind (lit level) 1) 0))
              (%md-col 8 (%md-hurt kind 0)) (%md-col 9 t-bare) (%md-col 7 t-armed) (%md-col 11 one-bare) (%md-col 7 one-armed)
              (%md-pad 7 (%md-span pack))
              (%md-pad 12 (Str8 str (open one-bare))) (%md-pad 4 (Str8 str (open one-armed)))
              (%md-pad 8 (Str8 str (line one-bare))) (%md-pad 4 (Str8 str (line one-armed)))
              (%md-pct 11 (%md-beyond pack (open one-armed))))))

(def %md-level
  (fn (_ set depth)
    (def who (%md-player set depth))
    (def gear (%md-gear set depth (List ref 1 who)))
    (def kinds (%md-kinds set depth))
    (%md-head set depth who gear)
    (%md-level-lines set depth kinds)
    (%md-titles)
    (List for-each (fn (_ k) (%md-kind-row set depth k who gear)) kinds)
    (%md-line "")))

(def %md-main
  (fn (_)
    (def name (%md-env "MODEL_SET" "delve"))
    (def set (data-load (Str8 append %lang-root "/data/" name)))
    (def last (List ref 2 (data-one set (lit goal) (list "" "" 1))))
    (def one (%md-env "MODEL_DEPTH" ""))
    (%md-line "The " name " set, by its numbers")
    (%md-line "")
    (List for-each (fn (_ d) (%md-level set d)) (if (str=? one "") (List range 1 (+ 1 last)) (list (%md-int one))))))

(%md-main)
