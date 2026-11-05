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
(def data-load
  (fn (_ dir)
    (def names (%dt-sort (List filter %dt-xon? (File list-dir dir)) ()))
    (if (null? names) (Err raise (lit io) "no .xon files in the set" dir)
      (List flat-map (fn (_ n) (%dt-forms (Str8 append dir "/" n))) names))))

; The ARGS of every form of SET headed HEAD, in order.
(def data-all
  (fn (_ set head) (List map rest (List filter (fn (_ f) (if (pair? f) (eq? (first f) head) #f)) set))))

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

; The VALUES of property KEY of record REC, or DEFAULT.
(def data-prop
  (fn (_ rec key default)
    (def p (Assoc find key (rest (rest rec))))
    (if (null? p) default (rest p))))

; The first value of property KEY of REC, or DEFAULT.
(def data-prop1
  (fn (_ rec key default)
    (def vs (data-prop rec key ()))
    (if (null? vs) default (first vs))))

; Whether REC lists FLAG among its (traits ...) values.
(def data-trait? (fn (_ rec flag) (List includes? flag (data-prop rec (lit traits) ()))))

; The glyph the set gives WHAT, as (glyph WHAT "g"), or DEFAULT.
(def data-glyph
  (fn (_ set what default)
    (def hit (List find (fn (_ args) (eq? (first args) what)) (data-all set (lit glyph))))
    (if (null? hit) default (List ref 1 hit))))

(provide roguelike/data data-load data-all data-one data-get data-prop data-prop1 data-trait? data-glyph)
