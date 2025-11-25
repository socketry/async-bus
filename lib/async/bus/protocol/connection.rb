# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async"
require "io/endpoint/unix_endpoint"

require_relative "wrapper"
require_relative "transaction"
require_relative "proxy"
require_relative "response"

module Async
	module Bus
		# @namespace
		module Protocol
			# Create a local Unix domain socket endpoint.
			# @parameter path [String] The path to the socket file.
			# @returns [IO::Endpoint::Unix] The Unix endpoint.
			def self.local_endpoint(path = "bus.ipc")
				::IO::Endpoint.unix(path)
			end
			
			# Represents a connection between client and server for message passing.
			class Connection
				# Create a client-side connection.
				# @parameter peer [IO] The peer connection.
				# @parameter options [Hash] Additional options for the connection.
				# @returns [Connection] A new client connection.
				def self.client(peer, **options)
					self.new(peer, 1, **options)
				end
				
				# Create a server-side connection.
				# @parameter peer [IO] The peer connection.
				# @parameter options [Hash] Additional options for the connection.
				# @returns [Connection] A new server connection.
				def self.server(peer, **options)
					self.new(peer, 2, **options)
				end
				
				# Initialize a new connection.
				# @parameter peer [IO] The peer connection.
				# @parameter id [Integer] The initial transaction ID.
				# @parameter wrapper [Class] The wrapper class for serialization.
				# @parameter timeout [Float] The timeout for transactions.
				def initialize(peer, id, wrapper: Wrapper, timeout: nil)
					@peer = peer
					@id = id
					
					@wrapper = wrapper.new(self)
					@unpacker = @wrapper.unpacker(peer)
					@packer = @wrapper.packer(peer)
					
					@timeout = timeout
					
					@transactions = {}
					
					@objects = {}
					@proxies = ::ObjectSpace::WeakMap.new
					@finalized = ::Thread::Queue.new
				end
				
				# @attribute [Float] The timeout for transactions.
				attr_accessor :timeout
				
				# Flush the packer buffer.
				def flush
					@packer.flush
				end
				
				# Write a message to the connection.
				# @parameter message [Object] The message to write.
				def write(message)
					# $stderr.puts "Writing: #{message.inspect}"
					@packer.write(message)
					@packer.flush
				end
				
				# Close the connection and clean up resources.
				def close
					@transactions.each do |id, transaction|
						transaction.close
					end
					
					@peer.close
				end
				
				# Return a string representation of the connection.
				# @returns [String] A string describing the connection.
				def inspect
					"#<#{self.class} #{@objects.size} objects>"
				end
				
				# @attribute [Hash] The bound objects.
				attr :objects
				
				# @attribute [ObjectSpace::WeakMap] The proxy cache.
				attr :proxies
				
				# @attribute [MessagePack::Unpacker] The message unpacker.
				attr :unpacker
				
				# @attribute [MessagePack::Packer] The message packer.
				attr :packer
				
				# Get the next transaction ID.
				# @returns [Integer] The next transaction ID.
				def next_id
					id = @id
					@id += 2
					
					return id
				end
				
				# @attribute [Hash] Active transactions.
				attr :transactions
				
				Explicit = Struct.new(:object) do
					def temporary?
						false
					end
				end
				
				Implicit = Struct.new(:object) do
					def temporary?
						true
					end
				end
				
				# Explicitly bind an object to a name, such that it could be accessed remotely.
				#
				# This is the same as {bind} but due to the semantics of the `[]=` operator, it does not return a proxy instance.
				#
				# Explicitly bound objects are not garbage collected until the connection is closed.
				#
				# @parameter name [String] The name to bind the object to.
				# @parameter object [Object] The object to bind to the given name.
				def []=(name, object)
					@objects[name] = Explicit.new(object)
				end
				
				# Generate a proxy for a remotely bound object.
				#
				# **This always returns a proxy, even if the object is bound locally.**
				# The object bus is not shared between client and server, so `[]` always
				# returns a proxy to the remote instance.
				#
				# @parameter name [String] The name of the bound object.
				# @returns [Proxy] A proxy instance for the bound object.
				def [](name)
					return proxy_for(name)
				end
				
				# Explicitly bind an object to a name, such that it could be accessed remotely.
				#
				# This method is identical to {[]=} but also returns a {Proxy} instance for the bound object which can be passed by reference.
				#
				# Explicitly bound objects are not garbage collected until the connection is closed.
				#
				# @example Binding an object to a name and accessing it remotely.
				# 	array_proxy = connection.bind(:items, [1, 2, 3])
				# 	connection[:remote].register(array_proxy)
				#
				# @parameter name [String] The name to bind the object to.
				# @parameter object [Object] The object to bind to the given name.
				# @returns [Proxy] A proxy instance for the bound object.
				def bind(name, object)
					# Bind the object into the local object store (explicitly bound, not temporary):
					@objects[name] = Explicit.new(object)
					
					# Always return a proxy for passing by reference, even for locally bound objects:
					return proxy_for(name)
				end
				
				# Implicitly bind an object with a temporary name, such that it could be accessed remotely.
				#
				# Implicitly bound objects are garbage collected when the remote end no longer references them.
				#
				# This method is simliar to {bind} but is designed to be used to generate temporary proxies for objects that are not explicitly bound.
				#
				# @parameter object [Object] The object to bind to a temporary name.
				# @returns [Proxy] A proxy instance for the bound object.
				def proxy(object)
					name = object.__id__
					
					# Bind the object into the local object store (temporary):
					@objects[name] ||= Implicit.new(object)
					
					# Always return a proxy for passing by reference:
					return proxy_for(name)
				end
				
				# Implicitly bind an object with a temporary name, such that it could be accessed remotely.
				#
				# Implicitly bound objects are garbage collected when the remote end no longer references them.
				#
				# This method is similar to {proxy} but is designed to be used to generate temporary names for objects that are not explicitly bound during serialization.
				#
				# @parameter object [Object] The object to bind to a temporary name.
				# @returns [String] The name of the bound object.
				def proxy_name(object)
					name = object.__id__
					
					# Bind the object into the local object store (temporary):
					@objects[name] ||= Implicit.new(object)
					
					# Return the name:
					return name
				end
				
				# Get an object or proxy for a bound object, handling reverse lookup.
				#
				# If the object is bound locally and the proxy is for this connection, returns the actual object.
				# If the object is bound remotely, or the proxy is from a different connection, returns a proxy.
				# This is used when deserializing proxies to handle round-trip scenarios and avoid name collisions.
				#
				# @parameter name [String] The name of the bound object.
				# @parameter local [Boolean] Whether the proxy is for this connection (from serialization). Defaults to true.
				# @returns [Object | Proxy] The object if bound locally and proxy is for this connection, or a proxy otherwise.
				def proxy_object(name)
					# If the proxy is for this connection and the object is bound locally, return the actual object:
					if entry = @objects[name]
						# This handles round-trip scenarios correctly.
						return entry.object
					end
					
					# Otherwise, create a proxy for the remote object:
					return proxy_for(name)
				end
				
				# Get or create a proxy for a named object.
				#
				# @parameter name [String] The name of the object.
				# @returns [Proxy] A proxy instance for the named object.
				private def proxy_for(name)
					unless proxy = @proxies[name]
						proxy = Proxy.new(self, name)
						@proxies[name] = proxy
						
						::ObjectSpace.define_finalizer(proxy, finalize(name))
					end
					
					return proxy
				end
				
				private def finalize(name)
					proc do
						@finalized.push(name) rescue nil
					end
				end
				
				# Create a new transaction.
				# @parameter id [Integer] The transaction ID.
				# @returns [Transaction] A new transaction.
				def transaction!(id = self.next_id)
					transaction = Transaction.new(self, id, timeout: @timeout)
					@transactions[id] = transaction
					
					return transaction
				end
				
				# Invoke a remote procedure.
				# @parameter name [Symbol] The name of the remote object.
				# @parameter arguments [Array] The arguments to pass.
				# @parameter options [Hash] The keyword arguments to pass.
				# @yields {|*args| ...} Optional block for yielding operations.
				# @returns [Object] The result of the invocation.
				def invoke(name, arguments, options = {}, &block)
					transaction = self.transaction!
					
					transaction.invoke(name, arguments, options, &block)
				ensure
					transaction&.close
				end
				
				# Send a release message for a named object.
				# @parameter name [Symbol] The name of the object to release.
				def send_release(name)
					self.write(Release.new(name))
				end
				
				# Run the connection message loop.
				# @parameter parent [Async::Task] The parent task to run under.
				def run(parent: Task.current)
					finalizer_task = parent.async do
						while name = @finalized.pop
							self.send_release(name)
						end
					end
					
					@unpacker.each do |message|
						case message
						when Invoke
							# If the object is not found, send an error response and skip the transaction:
							if object = @objects[message.name]&.object
								transaction = self.transaction!(message.id)
								
								parent.async(annotation: "Invoke #{message.name}") do
									# $stderr.puts "-> Accepting: #{message.name} #{message.arguments.inspect} #{message.options.inspect}"
									transaction.accept(object, message.arguments, message.options, message.block_given)
								ensure
									# $stderr.puts "<- Accepted: #{message.name}"
									# This will also delete the transaction from @transactions:
									transaction.close
								end
							else
								self.write(Error.new(message.id, NameError.new("Object not found: #{message.name}")))
							end
						when Response
							if transaction = @transactions[message.id]
								transaction.push(message)
							else
								# Stale message - transaction already closed (e.g. timeout) or never existed (ignore silently).
							end
						when Release
							name = message.name
							if @objects[name]&.temporary?
								# Only delete temporary objects, not explicitly bound ones:
								@objects.delete(name)
							end
						else
							Console.error(self, "Unexpected message:", message)
						end
					end
				ensure
					finalizer_task&.stop
					
					@transactions.each do |id, transaction|
						transaction.close
					end
					
					@transactions.clear
					@proxies = ::ObjectSpace::WeakMap.new
				end
			end
		end
	end
end
