; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/options.x -- the window's options, kept between games
;
; What a player sets in the window and keeps from one game to the next:
; the zoom the level is shown at, fullscreen or not, and how loud the
; music and the sounds are.  They are the window's, not a set's, so one
; file keeps them for every set: ~/.x-roguelike/options, a form a line.
;
;     (zoom 2) (fullscreen 0) (music 80) (effects 100)
;
; Options are an association list, (NAME . VALUE) each, every option
; there: one read from a file missing some takes the rest from the
; defaults, and a value out of range is brought back into it.
;
; @author [Jon Ruttan](jonruttan@gmail.com)
; @copyright 2026 Jon Ruttan
; @license MIT No Attribution (MIT-0)

(import x/sys/posix)
(import x/sys/file)
(import x/codec/xon)
(import x/core/doors int+ int- int* int< int=)

; Each option: (NAME LABEL LEAST MOST STEP DEFAULT), a switch from 0 to
; 1 by 1.  In the order the options screen lists them.
(def %op-all
  (list (list (lit zoom) "Zoom" 1 4 1 2)
        (list (lit fullscreen) "Fullscreen" 0 1 1 0)
        (list (lit music) "Music" 0 100 10 80)
        (list (lit effects) "Sounds" 0 100 10 100)))
(def %op-of (fn (_ name) (List find (fn (_ o) (eq? (first o) name)) %op-all)))
(def %op-held (fn (_ o v) (if (int< v (List ref 2 o)) (List ref 2 o) (if (int< (List ref 3 o) v) (List ref 3 o) v))))

; The options' names, in the order the options screen lists them.
(def options-names (List map first %op-all))

; Every option at its default.
(def options-default (fn (_) (List map (fn (_ o) (pair (first o) (List ref 5 o))) %op-all)))

; Option NAME of options O.
(def options-get (fn (_ o name) (rest (List find (fn (_ e) (eq? (first e) name)) o))))

; Options O with NAME set to V, held in its range.
(def options-set
  (fn (_ o name v)
    (List map (fn (_ e) (if (eq? (first e) name) (pair name (%op-held (%op-of name) v)) e)) o)))

; Options O with NAME moved DIR steps, -1 or 1: held at its ends, a
; switch turned over.
(def options-step
  (fn (_ o name dir)
    (def op (%op-of name))
    (def v (options-get o name))
    (if (int= (List ref 3 op) 1)
      (options-set o name (int- 1 v))
      (options-set o name (int+ v (int* dir (List ref 4 op)))))))

; Option NAME of options O as the screen shows it: its label and its
; value, a switch On or Off and a loudness a percentage.
(def options-line
  (fn (_ o name)
    (def op (%op-of name))
    (def v (options-get o name))
    (def shown
      (match ((int= (List ref 3 op) 1) (if (int= v 1) "On" "Off"))
             ((int= (List ref 3 op) 100) (Str8 append (Str8 str v) "%"))
             (#t (Str8 str v))))
    (def label (List ref 1 op))
    (Str8 append label (Str8 sub 0 (int- 13 (Str8 length label)) "             ") shown)))

; The options file, ~/.x-roguelike/options, its directory made.
(def options-path
  (fn (_)
    (def home (Sys getenv "HOME"))
    (def dir (Str8 append (if (null? home) "." home) "/.x-roguelike"))
    (unless (File exists? dir) (guard (e ()) (File mkdir dir)))
    (Str8 append dir "/options")))

; The options kept at PATH, the defaults for any missing or unreadable.
(def options-read
  (fn (_ path)
    (def kept (if (File exists? path) (guard (e ()) (Xon parse (File read-all path))) ()))
    (List fold
      (fn (_ o form)
        (if (if (pair? form) (if (pair? (rest form)) (if (%op-of (first form)) (number? (first (rest form))) #f) #f) #f)
          (options-set o (first form) (first (rest form)))
          o))
      (options-default) kept)))

; Options O kept at PATH.
(def options-write!
  (fn (_ o path)
    (File write-all path (Xon emit (List map (fn (_ e) (list (first e) (rest e))) o)))))

(provide roguelike/options
  options-names options-default options-get options-set options-step options-line options-path options-read options-write!)
