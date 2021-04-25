(define-module (smc puml)
  #:use-module (oop goops)
  #:use-module (ice-9 receive)
  #:use-module (ice-9 textual-ports)
  #:use-module (smc core state)
  #:use-module (smc fsm)
  #:use-module (smc core log)
  #:use-module (smc core context)
  #:use-module (smc guards char)
  #:export (<parser>
            <puml-context>
            context-fsm
            context-module
            puml->fsm
            parser-run))



(define-class <puml-context> (<context>)
  (fsm
   #:init-value (make <fsm>)
   #:getter     puml-context-fsm)

  ;; A module which contains state machine procedures.
  (module
   #:init-keyword #:module
   #:getter     puml-context-module))


(define (buffer->string buffer)
  (list->string (reverse buffer)))

(define (state-name-symbol? char)
  (or (char-set-contains? char char-set:letter)
      (char-set-contains? char char-set:digit)
      (char=? #\_)))

(define (guard:dash? ch ctx)
  (char=? ch #\-))

(define (guard:arrow-left-end? ch ctx)
  (char=? ch #\<))

(define (guard:arrow-right-end? ch ctx)
  (char=? ch #\>))



(define (action:store-symbol ch ctx)
  (log-debug "action:store-symbol: ch: ~a, buf: ~a" ch (context-buffer ctx))
  (context-buffer-set! ctx (cons ch (context-buffer ctx)))
  ctx)

(define (action:add-state ch ctx)
  (let ((fsm (puml-context-fsm ctx))
        (buf (context-buffer ctx)))
    (log-debug "action:add-state: buffer: ~a" buf)
    (let ((state (make <state>
                   #:name (list->symbol (reverse buf)))))
      (log-debug "action:add-state: state: ~a" state)
      (unless (fsm-current-state fsm)
        (fsm-current-state-set! fsm state))
      (fsm-state-add! fsm state)
      (context-buffer-set! ctx '())
      ctx)))

(define (action:add-buffer-to-stanza ch ctx)
  (let ((fsm (puml-context-fsm ctx))
        (buf (context-buffer ctx)))
    (unless (null? buf)
      (log-debug "action:add-buffer-to-stanza: buffer: ~a" buf)
      (log-debug "action:add-buffer-to-stanza: stanza: ~a" (context-stanza ctx))
      (context-stanza-set! ctx (append (context-stanza ctx)
                                       (list (list->symbol (reverse buf)))))
      (log-debug "action:add-buffer-to-stanza: stanza: ~a" (context-stanza ctx))
      (context-buffer-set! ctx '()))
    ctx))

;; This procedure tries to resolve a procedure PROC-NAME in the provided
;; modules. When no procedure available with the given name, returns DEFAULT
;; procedure.
(define (resolve-procedure ctx proc-name default)
  (let ((module (puml-context-module ctx)))
    (cond
     ((not proc-name)
      default)
     ((list? module)
      (let loop ((mods module))
        (let ((proc (catch
                      #t
                      (lambda ()
                        (module-ref (car mods) proc-name))
                      (const #f))))
          (cond
           (proc
            proc)
           ((and (not proc) (null? mods))
            (error "Could not find procedure in provided modules"
                   proc-name))
           (else
            (loop (cdr mods)))))))
     (else
      (module-ref module proc-name)))))

(define (action:add-state-transition ch ctx)

  (when (not (null? (context-buffer ctx)))
    (action:add-buffer-to-stanza ch ctx))

  (let* ((fsm     (puml-context-fsm ctx))
         (stanza  (context-stanza ctx))
         (module  (puml-context-module ctx))
         (from    (list-ref stanza 0))
         (to      (list-ref stanza 1))
         (tguard  (and (> (length stanza) 2)
                       (list-ref stanza 2)))
         (action  (and (= (length stanza) 4)
                       (list-ref stanza 3))))
    (log-debug "action:add-state-transition: [~a] -> [~a]: ~a -> ~a"
               from to
               tguard action)
    (cond
     ((equal? from '*)
      (log-debug "action:add-state-transition: Adding first state...")
      (let ((state (make <state> #:name to)))
        (fsm-state-add! fsm state)
        (fsm-current-state-set! fsm state)))
     ((and (equal? from '*) (equal? to '*))
      (error "Meaningless transition: [*] -> [*]"))
     (else
      (fsm-transition-add! fsm
                           from
                           (resolve-procedure ctx tguard guard:#t)
                           (resolve-procedure ctx action action:no-op)
                           (if (equal? to '*)
                               #f
                               to))))

    (context-stanza-set! ctx '())

    ctx))

(define (action:add-state-description ch ctx)
  (let* ((fsm             (puml-context-fsm ctx))
         (stanza          (context-stanza ctx))
         (buf             (context-buffer ctx))
         (state-name      (list-ref stanza 0))
         (description     (and (fsm-state fsm state-name)
                               (state-description
                                (fsm-state fsm state-name))))
         (new-description (list->string (reverse buf))))

    (when (equal? state-name (string->symbol "*"))
      (error "[*] cannot have description"))

    (if description
        (fsm-state-description-add! fsm
                                    state-name
                                    (string-append
                                     description
                                     new-description))
        (fsm-state-description-add! fsm
                                    state-name
                                    new-description))
    (context-buffer-set! ctx '())
    (context-stanza-set! ctx '())
    ctx))

(define (action:check-start-tag ch ctx)
  (let* ((buf (context-buffer ctx))
         (str (list->string (reverse buf))))
    (unless (string=? str "@startuml")
      (error "Misspelled @startuml" str))
    (context-buffer-set! ctx '())
    ctx))

(define (action:no-start-tag-error ch ctx)
  (error "No start tag found"))

(define (action:syntax-error ch ctx)
  (error "Syntax error"))

(define (action:unexpected-end-of-file-error ch ctx)
  (error "Unexpected end of file"))



(define %transition-table
  `((search-start-tag
     (,guard:eof-object?     ,action:no-op              #f)
     (,guard:at-symbol?      ,action:store-symbol       read-start-tag)
     (,guard:single-quote?   ,action:no-op              search-start-tag/skip-comment)
     (,guard:letter?         ,action:no-start-tag-error #f)
     (,guard:#t              ,action:no-op              search-start-tag))
    (search-start-tag/skip-comment
     (,guard:eof-object?     ,action:no-op              #f)
     (,guard:newline?        ,action:no-op              search-start-tag)
     (,guard:#t              ,action:no-op              search-start-tag/skip-comment))
    (read-start-tag
     (,guard:eof-object?     ,action:no-op              #f)
     (,guard:space?          ,action:check-start-tag    read)
     (,guard:newline?        ,action:check-start-tag    read)
     (,guard:#t              ,action:store-symbol       read-start-tag))
    (read
     (,guard:eof-object?          ,action:no-op        #f)
     (,guard:at-symbol?           ,action:no-op        read-end-tag)
     (,guard:single-quote?        ,action:no-op        read/skip-comment)
     (,guard:left-square-bracket? ,action:no-op        read-state)
     (,guard:letter?              ,action:store-symbol read-state)
     (,guard:#t                   ,action:no-op        read))
    (read-end-tag
     (,guard:eof-object?     ,action:no-op             #f)
     (,guard:newline?        ,action:no-op             #f)
     (,guard:#t              ,action:no-op             read-end-tag))
    (read/skip-comment
     (,guard:eof-object?     ,action:no-op             #f)
     (,guard:newline?        ,action:no-op             read)
     (,guard:#t              ,action:no-op             read/skip-comment))
    (read-state
     (,guard:eof-object?           ,action:no-op                #f)
     (,guard:newline?              ,action:syntax-error         #f)
     (,guard:right-square-bracket? ,action:add-buffer-to-stanza search-state-transition)
     (,guard:space?                ,action:add-buffer-to-stanza search-state-transition)
     (,guard:colon?                ,action:add-buffer-to-stanza read-state-description)
     (,guard:#t                    ,action:store-symbol         read-state))
    (search-state-transition
     (,guard:eof-object?     ,action:no-op        #f)
     (,guard:colon?          ,action:no-op        read-state-description)
     (,guard:dash?           ,action:no-op        read-state-right-arrow)
     (,guard:arrow-left-end? ,action:no-op        read-state-left-arrow)
     (,guard:#t              ,action:no-op        search-state-transition))
    (read-state-description
     (,guard:eof-object?     ,action:no-op                 #f)
     (,guard:newline?        ,action:add-state-description read)
     (,guard:#t              ,action:store-symbol          read-state-description))
    (read-state-right-arrow
     (,guard:eof-object?     ,action:no-op        #f)
     (,guard:space?          ,action:no-op        search-state-transition-to)
     (,guard:#t              ,action:no-op        read-state-right-arrow))
    (search-state-transition-to
     (,guard:eof-object?          ,action:no-op        #f)
     (,guard:letter?              ,action:store-symbol read-state-transition-to)
     (,guard:left-square-bracket? ,action:no-op        read-state-transition-to)
     (,guard:#t                   ,action:no-op        search-state-transition-to))
    (read-state-transition-to
     (,guard:eof-object?           ,action:no-op                #f)
     ;; (,guard:space?          ,action:no-op                        read-state-transition-guard)
     (,guard:right-square-bracket? ,action:no-op                read-state-transition-to)
     (,guard:colon?                ,action:add-buffer-to-stanza search-state-transition-guard)
     (,guard:newline?              ,action:add-state-transition read)
     (,guard:#t                    ,action:store-symbol         read-state-transition-to))
    (search-state-transition-guard
     (,guard:eof-object?     ,action:no-op                      #f)
     (,guard:letter?         ,action:store-symbol               read-state-transition-guard)
     (,guard:#t              ,action:no-op                      search-state-transition-guard))
    (read-state-transition-guard
     (,guard:eof-object?     ,action:no-op                      #f)
     (,guard:space?          ,action:add-buffer-to-stanza       search-state-action-arrow)
     (,guard:newline?        ,action:add-state-transition       read)
     (,guard:#t              ,action:store-symbol               read-state-transition-guard))
    (search-state-action-arrow
     (,guard:eof-object?     ,action:no-op                      #f)
     (,guard:newline?        ,action:no-op                      read)
     (,guard:dash?           ,action:no-op                      read-state-action-arrow)
     (,guard:#t              ,action:no-op                      search-state-action-arrow))
    (read-state-action-arrow
     (,guard:eof-object?      ,action:unexpected-end-of-file-error #f)
     (,guard:newline?         ,action:no-op                        #f)
     (,guard:arrow-right-end? ,action:no-op                        search-state-transition-action))
    (search-state-transition-action
     (,guard:eof-object?      ,action:unexpected-end-of-file-error #f)
     (,guard:letter?          ,action:store-symbol                 read-state-transition-action)
     (,guard:newline?         ,action:no-op                        #f)
     (,guard:#t               ,action:no-op                        search-state-transition-action))
    (read-state-transition-action
     (,guard:eof-object?      ,action:unexpected-end-of-file-error #f)
     (,guard:newline?         ,action:add-state-transition         read)
     (,guard:#t               ,action:store-symbol                 read-state-transition-action))))



(define* (puml->fsm port
                    #:key
                    (module (current-module))
                    (debug-mode? #f))
  (log-use-stderr! debug-mode?)
  (let ((reader-fsm
         (make <fsm>
           #:debug-mode? debug-mode?
           #:transition-table %transition-table)))

    (let loop ((context (make <puml-context> #:module module)))
      (receive (new-state new-context)
          (fsm-run! reader-fsm (get-char port) context)
        (if new-state
            (loop new-context)
            (puml-context-fsm context))))))

