# frozen_string_literal: true

# Copyright, 2021, by Samuel G. D. Williams. <http://www.codeotaku.com>
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
# 
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
# THE SOFTWARE.

require 'async'
require 'async/io/unix_endpoint'

require_relative 'wrapper'
require_relative 'transaction'
require_relative 'proxy'

module Async
	module Bus
		module Protocol
			def self.local_endpoint(path = "bus.ipc")
				Async::IO::Endpoint.unix(path)
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
					@finalized = Thread::Queue.new
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
				
				def proxy(object)
					name = next_id.to_s(16).freeze
					
					bind(name, object)
					
					return name
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
								transaction.close
							end
						else
							raise "Out of order message: #{message}"
						end
					end
				ensure
					finalizer_task.stop
					
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