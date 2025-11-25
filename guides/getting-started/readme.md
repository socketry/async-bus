# Getting Started

This guide explains how to get started with `async-bus` to build asynchronous message-passing systems with transparent remote procedure calls in Ruby.

## Installation

Add the gem to your project:

```bash
$ bundle add async-bus
```

## Core Concepts

`async-bus` has several core concepts:

- {ruby Async::Bus::Server}: Accepts incoming connections and exposes objects for remote access.
- {ruby Async::Bus::Client}: Connects to a server and accesses remote objects.
- {ruby Async::Bus::Controller}: Base class for objects designed to be proxied remotely.
- {ruby Async::Bus::Protocol::Connection}: Low-level connection handling message serialization and routing.
- {ruby Async::Bus::Protocol::Proxy}: Transparent proxy objects that forward method calls to remote objects.

## Usage

### Server Setup

Create a server that exposes objects for remote access. The server accepts connections and binds objects that clients can access. Any object can be bound and proxied:

```ruby
require "async"
require "async/bus"

Async do
	server = Async::Bus::Server.new
	
	# Shared mutable state:
	items = Array.new

	server.accept do |connection|
		# Bind any object - it will be proxied to clients:
		connection.bind(:items, items)
	end
end
```

### Client Connection

Connect to the server and use remote objects. The client gets proxies to remote objects that behave like local objects:

```ruby
require "async"
require "async/bus"

Async do
	client = Async::Bus::Client.new
	
	client.connect do |connection|
		# Get a proxy to the remote object:
		items = connection[:items]
		
		# Use it like a local object - method calls are transparently forwarded:
		items.push(1, 2, 3)
		puts items.size  # => 3
	end
end
```

### Persistent Clients

For long-running clients that need to maintain a connection, use the `run` method which automatically reconnects on failure. Override `connected!` to perform setup when a connection is established. This is useful for worker processes or monitoring systems that need to stay connected:

```ruby
require "async"
require "async/bus"

class PersistentClient < Async::Bus::Client
	protected def connected!(connection)
		# Setup code runs when connection is established:
		items = connection[:items]
		items.push("Hello")
		
		# You can also register controllers for bidirectional communication:
		worker = WorkerController.new
		connection.bind(:worker, worker)
	end
end

client = PersistentClient.new

# This will automatically reconnect if the connection fails:
client.run
```

The `run` method handles connection lifecycle automatically, making it ideal for production services that need resilience. It will:
- Automatically reconnect when the connection fails.
- Use random backoff between reconnection attempts.
- Call `connected!` each time a new connection is established.
- Run indefinitely until the task is stopped.
