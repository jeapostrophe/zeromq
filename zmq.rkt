#lang at-exp racket/base
(require ffi/unsafe
         racket/list
         racket/stxparam
         racket/splicing
         (for-syntax racket/base
                     racket/stxparam-exptime)
         (prefix-in c: racket/contract)
         scribble/srcdoc)
(require/doc racket/base
             scribble/manual)

(define zmq-lib (ffi-lib "libzmq"))

(define-syntax-rule (define-zmq* (external internal) type)
  (define external
    (get-ffi-obj 'internal zmq-lib type)))

(define-syntax-parameter current-zmq-fun #f) 
(define-syntax-rule (define-zmq (external internal)
                      (-> [name name/c] ...
                          result/c)
                      type)
  (splicing-syntax-parameterize 
   ([current-zmq-fun 'external])
   (define-zmq* (external internal) type)
   (provide/doc
    [proc-doc/names
     external (c:-> name/c ... result/c)
     (name ...) @{An FFI binding for @litchar[(symbol->string 'internal)].}])))

;;

; XXX Export/doc
(define-cpointer-type _context)
(define-cpointer-type _socket)

(define-syntax-rule (define-zmq-symbols _type type?
                      [sym = num] ...)
  (begin 
    (define _type
      (_enum (append '[sym = num] ...) _int))
    (define type?
      (c:symbols 'sym ...))
    (provide/doc
     [thing-doc
      type? c:contract?
      @{A contract for the symbols @racket['(sym ...)]}])))
(define-syntax-rule (define-zmq-bitmask _base _type type?
                      [sym = num] ...)
  (begin 
    (define _type
      (_bitmask (append '[sym = num] ...) _base))
    (define type-symbol?
      (c:symbols 'sym ...))
    (define type?
      (c:or/c type-symbol? (c:listof type-symbol?)))
    (provide/doc
     [thing-doc
      type? c:contract?
      @{A contract for any symbol in @racket['(sym ...)] or any list of those symbols.}])))

(define-zmq-symbols _socket-type socket-type?
  [PAIR = 0]
  [PUB = 1]
  [SUB = 2]
  [REQ = 3]
  [REP = 4]
  [XREQ = 5]
  [XREP = 6]
  [PULL = 7]
  [PUSH = 8])
(define-zmq-symbols _option-name option-name?
  [HWM = 1]
  [SWAP = 3]
  [AFFINITY = 4]
  [IDENTITY = 5]
  [SUBSCRIBE = 6]
  [UNSUBSCRIBE = 7]
  [RATE = 8]
  [RECOVERY_IVL = 9]
  [MCAST_LOOP = 10]
  [SNDBUF = 11]
  [RCVBUF = 12]
  [RCVMORE = 13])
(define-zmq-bitmask _int _send/recv-flags send/recv-flags?
  [NOBLOCK = 1]
  [SNDMORE = 2])
(define-zmq-bitmask _short _poll-status poll-status?
  [POLLIN = 1]
  [POLLOUT = 2]
  [POLLERR = 4])

(define _size_t _int)
(define _uchar _uint8)

(require (for-syntax racket/base syntax/parse unstable/syntax))
(define-syntax (define-cvector-type stx)
  (syntax-parse 
   stx
   [(_ name:id _type:expr size:number)
    (with-syntax
        ([(field ...)
          (for/list ([i (in-range (syntax->datum #'size))])
            (format-id #f "f~a" i))])
      (syntax/loc stx
        (define-cstruct name
          ([field _type]
           ...))))]))
    
(define-cvector-type _ucharMAX _uchar 30)
(define-cstruct _msg
  ([content _pointer]
   [flags _uchar]
   [vsm_size _uchar]
   [vsm_data _ucharMAX]))

(define-cstruct _poll-item
  ([socket _socket]
   [fd _int]
   [events _poll-status]
   [revents _poll-status]))
(provide (rename-out [make-poll-item poll-item])
         poll-item-revents)
  
;; Errors
(define-zmq*
  [errno zmq_errno]
  (_fun -> _int))
(define-zmq*
  [strerro zmq_strerror]
  (_fun _int -> _string))

(define-syntax (zmq-error stx)
  (syntax-case stx ()
    [(_)
     (quasisyntax/loc stx
       (error '#,(syntax-parameter-value #'current-zmq-fun) (strerro (errno))))]))

;; Context
(define-zmq 
  [context zmq_init]
  (-> [io_threads exact-nonnegative-integer?]
      context?)
  (_fun [io_threads : _int]
        -> [context : _context/null]
        -> (or context (zmq-error))))

(define-zmq
  [context-close! zmq_term]
  (-> [context context?] void)
  (_fun [context : _context]
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

;; Message
(define-zmq
  [msg-init! zmq_msg_init]
  (-> [msg msg?] void)
  (_fun _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))
(define-zmq
  [msg-init-size! zmq_msg_init_size]
  (-> [msg msg?] [size exact-nonnegative-integer?] void)
  (_fun _msg-pointer _size_t
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define *zmq-data* (make-hasheq))
(define (make-free-er in)
  (hash-set! *zmq-data* in #t)
  free-er)
(define (free-er out)
  (hash-remove! *zmq-data* out))

(define _zmq_free_fn (_fun _bytes _pointer -> _void))
(define-zmq
  [msg-init-data! zmq_msg_init_data]
  (-> [msg msg?] [data bytes?] void)
  (_fun _msg-pointer [data : _bytes] [size : _size_t = (bytes-length data)]
        [ffn : _zmq_free_fn = (make-free-er data)] [hint : _pointer = #f]
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [msg-close! zmq_msg_close]
  (-> [msg msg?] void)
  (_fun _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [msg-data-pointer zmq_msg_data]
  (-> [msg msg?] cpointer?)
  (_fun _msg-pointer -> _pointer))
(define-zmq
  [msg-size zmq_msg_size]
  (-> [msg msg?] exact-nonnegative-integer?)
  (_fun _msg-pointer -> _size_t))

; xxx export/doc
(define (msg-data m)
  (make-sized-byte-string (msg-data-pointer m) (msg-size m)))

(define-zmq
  [msg-copy! zmq_msg_copy]
  (-> [dest msg?] [src msg?] void)
  (_fun _msg-pointer _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))
(define-zmq
  [msg-move! zmq_msg_move]
  (-> [dest msg?] [src msg?] void)
  (_fun _msg-pointer _msg-pointer
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

;; Socket
(define-zmq
  [socket zmq_socket]
  (-> [ctxt context?] [type socket-type?] socket?)
  (_fun _context _socket-type
        -> [sock : _socket] -> (or sock (zmq-error))))
(define-zmq
  [socket-close! zmq_close]
  (-> [socket socket?] void)
  (_fun _socket
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-syntax (define-zmq-socket-options stx)
  (syntax-case stx ()
    [(_ [external internal]
        ([_type after type? opt ...] ...)
        (byte-opt ...))
     (with-syntax ([(_type-external ...) (generate-temporaries #'(_type ...))])
       (syntax/loc stx
         (splicing-syntax-parameterize 
          ([current-zmq-fun 'external])
          (define-zmq* [_type-external internal]
            (_fun _socket _option-name 
                  [option-value : (_ptr o _type)]
                  [option-size : (_ptr o _size_t)]
                  -> [err : _int]
                  -> (if (zero? err)
                         option-value
                         (zmq-error))))
          ...
          (define-zmq* [byte-external internal]
            (_fun _socket _option-name
                  [option-value : (_bytes o 255)]
                  [option-size : (_ptr o _size_t)]
                  -> [err : _int]
                  -> (if (zero? err)
                         (subbytes option-value 0 option-size)
                         (zmq-error))))
          (define (external sock opt-name)
            (case opt-name
              [(opt ...) (after (_type-external sock opt-name))]
              ...
              [(byte-opt ...) (byte-external sock opt-name)]))
          (provide/doc
           [proc-doc/names
            external (c:-> socket? option-name? (c:or/c type? ... bytes?))
            (socket option-name) @{XXX}]))))]))

(define-zmq-socket-options
  [socket-option zmq_getsockopt]
  ([_int64 zero? boolean? 
           RCVMORE MCAST_LOOP]
   [_int64 (λ (x) x) exact-integer?
           SWAP RATE RECOVERY_IVL]
   [_uint64 (λ (x) x) exact-nonnegative-integer?
            HWM AFFINITY SNDBUF RCVBUF])
  (IDENTITY))

(define-syntax (define-zmq-set-socket-options! stx)
  (syntax-case stx ()
    [(_ [external internal]
        ([type? before _type opt ...] ...)
        (byte-opt ...))
     (with-syntax ([(_type-external ...) (generate-temporaries #'(_type ...))])
       (syntax/loc stx
         (splicing-syntax-parameterize 
          ([current-zmq-fun 'external])
          (define-zmq* [_type-external internal]
            (_fun _socket _option-name 
                  [option-value : _type]
                  [option-size : _size_t = (ctype-sizeof _type)]
                  -> [err : _int] -> (unless (zero? err) (zmq-error))))
          ...
          (define-zmq* [byte-external internal]
            (_fun _socket _option-name
                  [option-value : _bytes]
                  [option-size : _size_t = (bytes-length option-value)]
                  -> [err : _int] -> (unless (zero? err) (zmq-error))))
          (define (external sock opt-name opt-val)
            (case opt-name
              [(opt ...) (_type-external sock opt-name (before opt-val))]
              ...
              [(byte-opt ...) (byte-external sock opt-name opt-val)]))
          (provide/doc
           [proc-doc/names
            external (c:-> socket? option-name? (c:or/c type? ... bytes?) void)
            (socket option-name option-value) @{XXX}]))))]))

(define-zmq-set-socket-options!
  [set-socket-option! zmq_setsockopt]
  ([exact-nonnegative-integer? (λ (x) x) _uint64
                               HWM AFFINTY SNDBUF RCVBUF]
   [exact-integer? (λ (x) x) _int64
                   SWAP RATE RECOVER_IVL]
   [boolean? (λ (x) (if x 1 0)) _int64
             MCAST_LOOP])
  (IDENTITY SUBSCRIBE UNSUBSCRIBE))

(define-zmq
  [socket-bind! zmq_bind]
  (-> [socket socket?] [endpoint string?] void)
  (_fun _socket _string
        -> [err : _int] -> (unless (zero? err) (zmq-error))))
(define-zmq
  [socket-connect! zmq_connect]
  (-> [socket socket?] [endpoint string?] void)
  (_fun _socket _string
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [socket-send-msg! zmq_send]
  (-> [socket socket?] [msg msg?] [flags send/recv-flags?] void)
  (_fun _socket _msg-pointer _send/recv-flags
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

; XXX
(define (socket-send! s bs)
  (define m (malloc _msg 'raw))
  (set-cpointer-tag! m msg-tag)
  (define len (bytes-length bs))
  (msg-init-size! m len)
  (memcpy (msg-data-pointer m) bs len)
  (dynamic-wind
   void
   (λ () (socket-send-msg! s m empty))
   (λ ()
     (msg-close! m)
     (free m))))
(provide socket-send!)

(define-zmq
  [socket-recv-msg! zmq_recv]
  (-> [socket socket?] [msg msg?] [flags send/recv-flags?] void)
  (_fun _socket _msg-pointer _send/recv-flags
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

; XXX
(define (socket-recv! s)
  (define m (malloc _msg 'raw))
  (set-cpointer-tag! m msg-tag)
  (msg-init! m)
  (socket-recv-msg! s m empty)
  (dynamic-wind
   void
   (λ () (msg-data m))
   (λ ()
     (msg-close! m)
     (free m))))
(provide socket-recv!)

(define-zmq
  [poll! zmq_poll]
  (-> [items (c:vectorof poll-item?)] [timeout exact-integer?] void)
  (_fun [items : (_vector i _poll-item)] [nitems : _int = (vector-length items)]
        [timeout : _long]
        -> [err : _int] -> (unless (zero? err) (zmq-error))))

(define-zmq
  [version zmq_version]
  (-> (values exact-nonnegative-integer? exact-nonnegative-integer? exact-nonnegative-integer?))
  (_fun [major : (_ptr o _int)] [minor : (_ptr o _int)] [patch : (_ptr o _int)]
        -> [err : _int] -> (if (zero? err) (values major minor patch) (zmq-error))))