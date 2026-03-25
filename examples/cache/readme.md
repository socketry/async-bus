# Local Cache Demo

This example demonstrates a small **local cache** shared over `async-bus`: one process runs a bus server with a `CacheController`, and a worker process connects as a client and repeatedly **fetches** keys (RPC through a proxy).

## Architecture

The example defines two managed services:

1. **Cache server** (`cache-server`) — Runs `Async::Bus::Server` on a Unix socket and binds a single shared `CacheController` as `:cache`.
2. **Cache client** (`cache-client`) — Runs `Async::Bus::Client#run` in a loop, calling `fetch` on the remote cache proxy and printing timing and cache size.

Both services use the same environment (`CacheEnvironment`) for the socket path, sample keys, and pull interval.

## Features

- **Controller API** — `CacheController` subclasses `Async::Bus::Controller` with an explicit RPC surface (`fetch`, `store`, `size`, `clear!`).
- **Generic fetch** — `fetch(key)` uses in-memory storage; on a miss it calls `load_missing`, which is a **dummy placeholder** (string like `placeholder:key:timestamp`) standing in for a database, HTTP backend, etc.
- **Shared cache** — All client connections share the same controller instance on the server.
- **Client worker** — Demonstrates long-lived `Client#run` with periodic fetches and simple latency logging (`Async::Clock`).

## Running

From this directory, make the script executable (once) and start the supervisor:

```bash
chmod +x service.rb
./service.rb
```

That starts both `cache-server` and `cache-client`. The Unix socket is created next to the service **root** (typically this folder) as `cache.ipc`.

To run **only** the bus server (for your own client experiments), use your async-service tooling to start the `cache-server` service alone, or temporarily comment out the `cache-client` service block in `service.rb`.

## What you should see

The client prints one line per key per cycle, for example:

```text
[cache-client] fetch key="user:1" value="placeholder:user:1:173..." size=3 time=0.42ms
```

- First time a key is requested, `load_missing` runs (placeholder value).
- Later fetches for the same key hit the in-memory store (still RPC, but the value is stable until the server restarts or you call `clear!`).

## Configuration

Configured on the environment module in `service.rb`:

- **`bus_endpoint`** — Unix socket path (`cache.ipc` under the service root).
- **`sample_keys`** — Keys the worker fetches each cycle (default: `user:1`, `user:2`, `config:app`).
- **`pull_interval`** — Seconds between cycles (default: `2.0`).
- **`count`** — Managed service instance count (default: `1`).

## How it works

1. The server accepts connections and binds `:cache` to one `CacheController` instance.
2. The client connects, obtains `connection[:cache]` (a **proxy**), and calls `fetch`, `size`, etc. Those calls become bus messages; the server dispatches to the real controller.
3. `fetch` behaves like `Hash#fetch`: cache hit returns the stored value; miss runs `load_missing`, stores the result, and returns it.

This shows how async-bus can expose a small, explicit service API (a cache) to separate processes without hand-rolling a custom IPC protocol.
