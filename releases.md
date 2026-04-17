# Releases

## Unreleased

  - Fix handling of inspect on Ruby 4+.
  - `Client#run(**options)` are passed through to `Async(**options)`.
  - On the server side, if a transaction raises an exception, ignore the exception if the connection is closed.

## v0.3.1

  - `Client#run` now returns an `Async::Task` (as it did in earlier releases).

## v0.3.0

  - Add support for multi-hop proxying.
  - Fix proxying of throw/catch value.
  - `Client#run` now takes a block.
  - `Server#run` delegates to `Server#connected!`.

## v0.2.0

  - Fix handling of temporary objects.
