; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/data.x -- a content set, read from xon files
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)
;
; A set is a directory of .xon files: every form in them, in file-name
; order, as one list.  Nothing here knows what a form means; a form is
; (HEAD . ARGS) and the game asks for the heads it understands.  A record
; -- a creature, an item -- is (NAME GLYPH . PROPS) or (CLASS NAME . PROPS):
; two leading atoms, then properties, each (KEY . VALUES).

(module roguelike/data)

(import x/codec/xon)
(import x/sys/file)

(def %dt-xon? (fn (_ name) (Str8 ends? ".xon" name)))

; NAMES in order: an insertion sort, since the names are few.
(def %dt-insert
  (fn (self name l)
    (match ((null? l) (list name))
           ((Str8 <? name (first l)) (pair name l))
           (#t (pair (first l) (self name (rest l)))))))
(def %dt-sort (fn (self l acc) (if (null? l) acc (self (rest l) (%dt-insert (first l) acc)))))

(def %dt-forms (fn (_ path) (Xon parse (File read-all path))))

; Every form of the set at DIR, in file-name order.  A missing directory
; raises.
(def %dt-load
  (fn (_ dir)
    (def names (%dt-sort (List filter %dt-xon? (File list-dir dir)) ()))
    (if (null? names) (Err raise (lit io) "no .xon files in the set" dir)
      (List flat-map (fn (_ n) (%dt-forms (Str8 append dir "/" n))) names))))

; These lookups run thousands of times a turn, so they are plain
; walks: a class send costs some two hundred objects and an Assoc find
; some twenty-five thousand.

; The ARGS of every form of SET headed HEAD, in order.
(def data-all
  (fn (self set head)
    (match ((null? set) ())
           ((if (pair? (first set)) (eq? (first (first set)) head) #f) (pair (rest (first set)) (self (rest set) head)))
           (#t (self (rest set) head)))))

; The ARGS of the first form headed HEAD, or DEFAULT.
(def data-one
  (fn (_ set head default)
    (def l (data-all set head))
    (if (null? l) default (first l))))

; The first argument of the first form headed HEAD, or DEFAULT.
(def data-get
  (fn (_ set head default)
    (def args (data-one set head ()))
    (if (null? args) default (first args))))

; The VALUES of property KEY among PROPS, or DEFAULT.
(def %dt-prop
  (fn (self props key default)
    (match ((null? props) default)
           ((if (pair? (first props)) (eq? (first (first props)) key) #f) (rest (first props)))
           (#t (self (rest props) key default)))))
; The VALUES of property KEY of record REC, or DEFAULT.
(def data-prop (fn (_ rec key default) (%dt-prop (rest (rest rec)) key default)))

; The first value of property KEY of REC, or DEFAULT.
(def data-prop1
  (fn (_ rec key default)
    (def vs (data-prop rec key ()))
    (if (null? vs) default (first vs))))

; Whether REC lists FLAG among its (traits ...) values.
(def %dt-memq (fn (self x l) (match ((null? l) #f) ((eq? (first l) x) #t) (#t (self x (rest l))))))
(def data-trait? (fn (_ rec flag) (%dt-memq flag (data-prop rec (lit traits) ()))))

; The glyph the set gives WHAT, as (glyph WHAT "g"), or DEFAULT.
(def data-glyph
  (fn (self set what default)
    (match ((null? set) default)
           ((if (pair? (first set)) (if (eq? (first (first set)) (lit glyph)) (eq? (first (rest (first set))) what) #f) #f)
             (first (rest (rest (first set)))))
           (#t (self (rest set) what default)))))

; The set at DIR, and after its forms, for each (join NAME) among them,
; the set NAME beside it, as one (region NAME . FORMS): a place in the
; same world made by its own forms (see state.x).
(def data-load
  (fn (_ dir)
    (def forms (%dt-load dir))
    (List append forms
      (List map (fn (_ args) (pair (lit region) (pair (first args) (%dt-load (Str8 append dir "/../" (first args))))))
        (data-all forms (lit join))))))

; The forms of the region NAME of SET, or nil.
(def data-region
  (fn (_ set name)
    (def hit (List find (fn (_ r) (str=? (first r) name)) (data-all set (lit region))))
    (if (null? hit) () (rest hit))))

; --- choices -------------------------------------------------------------------

; A set's (choice GROUP NAME . FORMS) is one way to play it, picked
; from GROUP: its FORMS go in front of the set's, so a knob the set has
; once -- (world ...), (chain ...), (creatures ...) -- is the choice's,
; and a form it has many of -- (scene ...), (band ...) -- is added to.
; A set with choices made carries a (chosen GROUP NAME) for each in front.

; Every (GROUP NAME) SET offers, in order.
(def data-choices (fn (_ set) (List map (fn (_ c) (list (first c) (List ref 1 c))) (data-all set (lit choice)))))

; The (GROUP NAME) choices SET was made with.
(def data-chosen (fn (_ set) (data-all set (lit chosen))))

; A choice (GROUP NAME) as GROUP=NAME.
(def data-choice-text (fn (_ pk) (Str8 append (symbol->str (first pk)) "=" (symbol->str (List ref 1 pk)))))

; SET with each of PICKS, (GROUP NAME) each, made: their forms in front.
; A pick the set does not offer, or a group picked twice, raises.
(def data-choose
  (fn (_ set picks)
    (def offered (data-all set (lit choice)))
    (def find (fn (_ pk) (List find (fn (_ c) (if (eq? (first c) (first pk)) (eq? (List ref 1 c) (List ref 1 pk)) #f)) offered)))
    (def offers (fn (_) (if (null? offered) "none" (Str8 join " " (List map data-choice-text (data-choices set))))))
    (List for-each
      (fn (_ pk)
        (match ((null? (find pk))
                 (Err raise (lit arg) (Str8 append "the set has no choice " (data-choice-text pk) "; it has " (offers)) ()))
               ((< 1 (List count-if (fn (_ q) (eq? (first q) (first pk))) picks))
                 (Err raise (lit arg) (Str8 append (symbol->str (first pk)) " is chosen more than once") ()))
               (#t ())))
      picks)
    (List append
      (List map (fn (_ pk) (list (lit chosen) (first pk) (List ref 1 pk))) picks)
      (List flat-map (fn (_ pk) (List drop 2 (find pk))) picks)
      set)))

(provide roguelike/data data-load data-region data-all data-one data-get data-prop data-prop1 data-trait? data-glyph
  data-choices data-chosen data-choice-text data-choose)
