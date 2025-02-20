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
				def self.client(peer)
					self.new(peer, 1)
				end
				
				def self.server(peer)
					self.new(peer, 2)
				end
				
				def initialize(peer, id)
					@peer = peer
					
					@wrapper = Wrapper.new(self)
					@unpacker = @wrapper.unpacker(peer)
					@packer = @wrapper.packer(peer)
					
					@transactions = {}
					@id = id
					
					@objects = {}
					@proxies = ::ObjectSpace::WeakMap.new
					@finalized = ::Thread::Queue.new
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
				# @returns [String] The (unique) name of the object.
				def proxy(object)
					name = "<#{object.class}@#{next_id.to_s(16)}>".freeze
					
					bind(name, object)
					
					return name
				end
				
				def object(name)
					@objects[name]
				end
				
				def bind(name, object)
					@objects[name] = object
				end
				
				private def finalize(name)
					proc{@finalized << name}
				end
				
				def [](name)
					unless proxy = @proxies[name]
						proxy = Proxy.new(self, name)
						@proxies[name] = proxy
						
						ObjectSpace.define_finalizer(proxy, finalize(name))
					end
					
					return proxy
				end
				
				def invoke(name, arguments, options = {}, &block)
					id = self.next_id
					
					transaction = Transaction.new(self, id)
					@transactions[id] = transaction
					
					transaction.invoke(name, arguments, options, &block)
				ensure
					transaction&.close
				end
				
				def run
					finalizer_task = Async do
						while name = @finalized.pop
							@packer.write([:release, name])
						end
					end
					
					@unpacker.each do |message|
						id = message.shift
						
						if id == :release
							name = message.shift
							@objects.delete(name) if name.is_a?(String)
						elsif transaction = @transactions[id]
							transaction.received.enqueue(message)
						elsif message.first == :invoke
							message.shift
							
							transaction = Transaction.new(self, id)
							@transactions[id] = transaction
							
							name = message.shift
							object = @objects[name]
							
							Async do
								transaction.accept(object, *message)
							ensure
								# This will also delete the transaction from @transactions:
								transaction.close
							end
						else
							raise "Out of order message: #{message}"
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
