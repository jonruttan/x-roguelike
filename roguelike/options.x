; # x-roguelike -- a roguelike on x-lang
;
; ## roguelike/options.x -- the window's options, kept between games
;
; What a player sets in the window and keeps from one game to the next:
; the zoom the level is shown at, fullscreen or not, how loud the music
; and the sounds are, and whether both are muted; and the keys and the
; gamepad's buttons, each bound to a command.  They are the window's,
; not a set's, so one file keeps them for every set:
; ~/.x-roguelike/options, a form a line.
;
;     (zoom 2) (fullscreen 0) (music 80) (effects 100) (mute 0)
;     (key "f" "s") (button left-trigger "s") (button west none)
;
; Options are an association list, (NAME . VALUE) each, every option
; there: one read from a file missing some takes the rest from the
; defaults, and a value out of range is brought back into it.  Two more
; entries hold the bindings: keys, ((KEY . COMMAND) ...), a key that
; does a command's key; and buttons, ((BUTTON . COMMAND) ...), a button
; that does a command, nil for none (none in the file).  A key bound to
; nothing does what it always does.
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
        (list (lit effects) "Sounds" 0 100 10 100)
        (list (lit mute) "Mute" 0 1 1 0)))
(def %op-of (fn (_ name) (List find (fn (_ o) (eq? (first o) name)) %op-all)))
(def %op-held (fn (_ o v) (if (int< v (List ref 2 o)) (List ref 2 o) (if (int< (List ref 3 o) v) (List ref 3 o) v))))

; The options' names, in the order the options screen lists them.
(def options-names (List map first %op-all))

; Every option at its default, and no key or button bound.
(def options-default
  (fn (_) (List append (List map (fn (_ o) (pair (first o) (List ref 5 o))) %op-all) (list (pair (lit keys) ()) (pair (lit buttons) ())))))

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

; The options kept at PATH, the defaults for any missing or unreadable:
; an option's form (NAME VALUE), a key's (key KEY COMMAND) and a
; button's (button BUTTON COMMAND).
(def options-read
  (fn (_ path)
    (def kept (if (File exists? path) (guard (e ()) (Xon parse (File read-all path))) ()))
    (def form-of (fn (_ form n) (if (pair? form) (if (int= (List length form) n) (first form) ()) ())))
    (List fold
      (fn (_ o form)
        (def head (form-of form 2))
        (match
          ((if (null? head) #f (if (%op-of head) (number? (first (rest form))) #f)) (options-set o head (first (rest form))))
          ((eq? (form-of form 3) (lit key))
            (if (if (%op-key? (List ref 1 form)) (%op-key? (List ref 2 form)) #f) (options-key-bind o (List ref 1 form) (List ref 2 form)) o))
          ((eq? (form-of form 3) (lit button))
            (match ((not (symbol? (List ref 1 form))) o)
                   ((eq? (List ref 2 form) (lit none)) (options-button-bind o (List ref 1 form) ()))
                   ((str? (List ref 2 form)) (options-button-bind o (List ref 1 form) (List ref 2 form)))
                   (#t o)))
          (#t o)))
      (options-default) kept)))

; Options O kept at PATH.
(def options-write!
  (fn (_ o path)
    (File write-all path
      (Xon emit
        (List append
          (List map (fn (_ name) (list name (options-get o name))) options-names)
          (List map (fn (_ e) (list (lit key) (first e) (rest e))) (List reverse (options-keys o)))
          (List map (fn (_ e) (list (lit button) (first e) (if (null? (rest e)) (lit none) (rest e)))) (List reverse (options-buttons o))))))))

; --- the bindings --------------------------------------------------------------

; Whether keys A and B are the same: a letter, or a name such as up.
(def %op-key=? (fn (_ a b) (if (str? a) (if (str? b) (str=? a b) #f) (if (str? b) #f (eq? a b)))))
(def %op-key? (fn (_ k) (if (str? k) #t (symbol? k))))
(def %op-without (fn (_ alist k) (List filter (fn (_ e) (not (%op-key=? (first e) k))) alist)))
(def %op-entry! (fn (_ o name v) (List map (fn (_ e) (if (eq? (first e) name) (pair name v) e)) o)))

; The keys bound in options O, ((KEY . COMMAND) ...).
(def options-keys (fn (_ o) (options-get o (lit keys))))
; The command's key KEY does under options O: the one it is bound to,
; else its own.
(def options-key
  (fn (_ o key)
    ((fn (_ hit) (if (null? hit) key (rest hit)))
     (List find (fn (_ e) (%op-key=? (first e) key)) (options-keys o)))))
; The keys that do COMMAND's key under options O: those bound to it,
; then its own while it is bound to nothing else.
(def options-keys-for
  (fn (_ o command)
    (def bound (List map first (List filter (fn (_ e) (%op-key=? (rest e) command)) (options-keys o))))
    (if (List any? (fn (_ e) (%op-key=? (first e) command)) (options-keys o)) bound (List append bound (list command)))))
; Options O with KEY doing COMMAND's key, and no other key bound to it;
; a key bound to its own command is bound to nothing.
(def options-key-bind
  (fn (_ o key command)
    (def rest-of (%op-without (List filter (fn (_ e) (not (%op-key=? (rest e) command))) (options-keys o)) key))
    (%op-entry! o (lit keys) (if (%op-key=? key command) rest-of (pair (pair key command) rest-of)))))

; The buttons bound in options O, ((BUTTON . COMMAND) ...).
(def options-buttons (fn (_ o) (options-get o (lit buttons))))
; Options O with BUTTON doing COMMAND, nil for nothing.
(def options-button-bind
  (fn (_ o button command)
    (%op-entry! o (lit buttons) (pair (pair button command) (%op-without (options-buttons o) button)))))

; Options O with no key, or no button, bound: WHICH keys or buttons.
(def options-unbind-all (fn (_ o which) (%op-entry! o which ())))

(provide roguelike/options
  options-names options-default options-get options-set options-step options-line options-path options-read options-write!
  options-keys options-key options-keys-for options-key-bind options-buttons options-button-bind options-unbind-all)
