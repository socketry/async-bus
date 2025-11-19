# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async"
require "io/endpoint/unix_endpoint"

require_relative "wrapper"
require_relative "transaction"
require_relative "proxy"

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
				
				def initialize(peer, id, wrapper: Wrapper)
					@peer = peer
					
					@wrapper = wrapper.new(self)
					@unpacker = @wrapper.unpacker(peer)
					@packer = @wrapper.packer(peer)
					
					@transactions = {}
					@id = id
					
					@objects = {}
					@proxies = ::ObjectSpace::WeakMap.new
					@finalized = ::Thread::Queue.new
				end
				
				def flush
					@packer.flush
				end
				
				def write(message)
					# $stderr.puts "Writing: #{message.inspect}"
					@packer.write(message)
					@packer.flush
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
					proc {@finalized << name}
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
				
				def invoke(name, arguments, options = {}, &block)
					id = self.next_id
					# $stderr.puts "-> Invoking: #{name} #{arguments.inspect} #{options.inspect}", caller
					
					transaction = Transaction.new(self, id)
					@transactions[id] = transaction
					
					transaction.invoke(name, arguments, options, &block)
				ensure
					transaction&.close
					# $stderr.puts "<- Invoked: #{name}"
				end
				
				def run
					finalizer_task = Async do
						while name = @finalized.pop
							self.write(Release.new(name))
						end
					end
					
					@unpacker.each do |message|
						# $stderr.puts "Message received: #{message.inspect}"
						
						case message
						when Release
							@objects.delete(message.name)
						when Invoke
							transaction = Transaction.new(self, message.id)
							@transactions[message.id] = transaction
							
							object = @objects[message.name]
							
							Async do
								# $stderr.puts "-> Accepting: #{message.name} #{message.arguments.inspect} #{message.options.inspect}"
								transaction.accept(object, message.arguments, message.options, message.block_given)
							ensure
								# $stderr.puts "<- Accepted: #{message.name}"
								# This will also delete the transaction from @transactions:
								transaction.close
							end
						else
							transaction = @transactions[message.id]
							transaction.received.push(message)
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
				
				def close
					@transactions.each do |id, transaction|
						transaction.close
					end
					
					@peer.close
				end
			end
		end
	end
end
