# Controllers

This guide explains how to use controllers in `async-bus` to build explicit remote interfaces with pass-by-reference semantics, enabling bidirectional communication and shared state across connections.

## Why Controllers?

While any object can be bound and proxied directly (like `Array` or `Hash`), controllers provide important advantages:

1. **Pass by Reference**: Controllers are always passed by reference when serialized as arguments or return values, enabling bidirectional communication.
2. **Explicit Interface**: Controllers wrap objects with a well-defined interface, making the remote API clear and preventing confusion about what methods are available.
3. **Automatic Proxying**: When controllers are registered as reference types, they are automatically proxied when serialized, enabling chaining and composition.

## Pass by Reference vs Pass by Value

The key difference between controllers and regular objects:

- **Controllers**: Passed by reference - when serialized as arguments or return values, both sides share the same object.
- **Other objects**: Copied by value - when serialized, each side gets its own copy.

Note that when you bind an object directly (like `connection.bind(:items, array)`), clients can still access it via a proxy (`connection[:items]`). The difference only matters when objects are serialized as arguments or return values (or as a part thereof).

## Creating Controllers

Controllers inherit from {ruby Async::Bus::Controller} and define methods that can be called remotely:

```ruby
class ChatRoomController < Async::Bus::Controller
	def initialize(name)
		@name = name
		@messages = []
		@subscribers = []
	end
	
	def send_message(author, text)
		message = {author: author, text: text, time: Time.now}
		@messages << message
		
		# Notify all subscribers:
		@subscribers.each do |subscriber|
			subscriber.on_message(message)
		end
		
		message
	end
	
	def subscribe(subscriber)
		@subscribers << subscriber
		@messages.size  # Return message count
	end
	
	def get_messages(count = 10)
		@messages.last(count)
	end
end
```

To use a controller, bind it instead of the raw object:

```ruby
# Server:
room = ChatRoomController.new("general")

server.accept do |connection|
	connection.bind(:room, room)
end

# Client:
client.connect do |connection|
	room = connection[:room]
	room.send_message("Alice", "Hello, world!")
	messages = room.get_messages(5)
end
```

## Returning Controllers

Controllers can return other controllers, and they are automatically proxied when registered as reference types. This enables sharing the same controller instance across multiple clients:

```ruby
class ChatServerController < Async::Bus::Controller
	def initialize
		@rooms = {}
	end
	
	def get_room(name)
		# Return existing room or create new one - automatically proxied:
		@rooms[name] ||= ChatRoomController.new(name)
	end
	
	def list_rooms
		@rooms.keys
	end
end

class ChatRoomController < Async::Bus::Controller
	def initialize(name)
		@name = name
		@messages = []
	end
	
	def send_message(author, text)
		@messages << {author: author, text: text, time: Time.now}
	end
	
	def name
		@name
	end
end
```

When a controller method returns another controller, the client receives a proxy to that controller. Multiple clients accessing the same room will share the same controller instance:

```ruby
# Server:
chat = ChatServerController.new

server.accept do |connection|
	connection.bind(:chat, chat)
end

# Client 1:
client1.connect do |connection|
	chat = connection[:chat]
	room = chat.get_room("general")  # Returns controller, auto-proxied
	room.send_message("Alice", "Hello!")
end

# Client 2:
client2.connect do |connection|
	chat = connection[:chat]
	room = chat.get_room("general")  # Returns same controller instance
	# Can see messages from Client 1 because they share the same room
end
```

## Passing Controllers as Arguments

Because controllers are passed by reference, you can pass them as arguments to enable bidirectional communication. When a client passes a proxy as an argument, the server receives a proxy that points back to the client's controller. This enables the server to call methods on the client's controller. This pattern is useful for event handlers, callbacks, or subscription systems:

```ruby
class ChatRoomController < Async::Bus::Controller
	def initialize(name)
		@name = name
		@messages = []
		@subscribers = []
	end
	
	def subscribe(subscriber)
		# subscriber is a proxy to the client's controller:
		@subscribers << subscriber
		# Send existing messages to the new subscriber:
		@messages.each{|msg| subscriber.on_message(msg)}
		true
	end
	
	def send_message(author, text)
		message = {author: author, text: text, time: Time.now}
		@messages << message
		
		# Notify all subscribers by calling back to their controllers:
		@subscribers.each do |subscriber|
			subscriber.on_message(message)
		end
		
		message
	end
end

# Client: Subscribes to room messages
class MessageSubscriberController < Async::Bus::Controller
	def initialize
		@received = []
	end
	
	def on_message(message)
		@received << message
		puts "#{message[:author]}: #{message[:text]}"
	end
	
	attr :received
end

# Server setup:
room = ChatRoomController.new("general")

server.accept do |connection|
	connection.bind(:room, room)
end

# Client subscription:
client.connect do |connection|
	room = connection[:room]
	
	# Create a subscriber controller:
	subscriber = MessageSubscriberController.new
	subscriber_proxy = connection.bind(:subscriber, subscriber)
	
	# Pass the proxy as an argument - the server can now call back:
	room.subscribe(subscriber_proxy)
	
	# Now when messages are sent, subscriber.on_message will be called:
	room.send_message("Bob", "Hello, everyone!")
end
```