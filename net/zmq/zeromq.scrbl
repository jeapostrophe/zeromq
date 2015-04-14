#lang scribble/doc
@(require scribble/manual
          scribble/basic
          scribble/extract
          (for-label (except-in ffi/unsafe ->)
                     racket
                     net/zmq))

@title[#:tag "top"]{ZeroMQ}
@author[(author+email "Jay McCarthy" "jay@racket-lang.org")]

@defmodule[net/zmq]

This package provides a binding for the
@link["http://www.zeromq.org/"]{ZeroMQ} library.

This documentation does not describe meaning of API calls; it only describes their Racket calling conventions. For details on API semantics, refer to the documentation at the @link["http://api.zeromq.org/zmq.html"]{ZeroMQ site}.

@litchar{zmq_msg_init_data} is not supported, because Racket pointers may be moved by the garbage collector before the ZeroMQ library is done with them.

@local-table-of-contents[]

@include-extracted[net/zmq]
