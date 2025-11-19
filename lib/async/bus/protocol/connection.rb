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
		module Protocol
			def self.local_endpoint(path = "bus.ipc")
				::IO::Endpoint.unix(path)
			end
			
			class Connection
				def self.client(peer, **options)
					self.new(peer, 1, **options)
				end
				
				def self.server(peer, **options)
					self.new(peer, 2, **options)
				end
				
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
				
				def flush
					@packer.flush
				end
				
				def write(message)
					# $stderr.puts "Writing: #{message.inspect}"
					@packer.write(message)
					@packer.flush
				end
				
				def close
					@transactions.each do |id, transaction|
						transaction.close
					end
					
					@peer.close
				end
				
				def inspect
					"#<#{self.class} #{@objects.size} objects>"
				end
				
				attr :objects
				attr :proxies
				
				attr :unpacker
				attr :packer
				
				def next_id
					id = @id
					@id += 2
					
					return id
				end
				
				attr :transactions
				
				# Bind a local object to a name, such that it could be accessed remotely.
				#
				# @returns [Proxy] A proxy instance for the bound object.
				def bind(name, object)
					@objects[name] = object
					return self[name]
				end
				
				# Generate a proxy name for an object and bind it.
				#
				# @returns [Proxy] A proxy instance for the bound object.
				def proxy(object)
					name = "<#{object.class}@#{next_id.to_s(16)}>".freeze
					
					return bind(name, object)
				end
				
				# Generate a proxy name for an object and bind it, returning just the name.
				# Used for serialization when you need the name string, not a Proxy instance.
				#
				# @returns [String] The name of the bound object.
				def proxy_name(object)
					name = "<#{object.class}@#{next_id.to_s(16)}>".freeze
					bind(name, object)
					return name
				end
				
				def object(name)
					@objects[name]
				end
				
				private def finalize(name)
					proc do
						@finalized.push(name) rescue nil
					end
				end
				
				def []=(name, object)
					@objects[name] = object
				end
				
				def [](name)
					unless proxy = @proxies[name]
						proxy = Proxy.new(self, name)
						@proxies[name] = proxy
						
						::ObjectSpace.define_finalizer(proxy, finalize(name))
					end
					
					return proxy
				end
				
				def transaction!(id = self.next_id)
					transaction = Transaction.new(self, id, timeout: @timeout)
					@transactions[id] = transaction
					
					return transaction
				end
				
				def invoke(name, arguments, options = {}, &block)
					transaction = self.transaction!
					
					transaction.invoke(name, arguments, options, &block)
				ensure
					transaction&.close
				end
				
				def send_release(name)
					self.write(Release.new(name))
				end
				
				def run(parent: Task.current)
					finalizer_task = parent.async do
						while name = @finalized.pop
							self.send_release(name)
						end
					end
					
					@unpacker.each do |message|
						case message
						when Release
							@objects.delete(message.name)
						when Invoke
							# If the object is not found, send an error response and skip the transaction:
							if object = @objects[message.name]
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
