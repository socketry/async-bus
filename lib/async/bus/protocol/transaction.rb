# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async/queue"

module Async
	module Bus
		module Protocol
			class Transaction
				def initialize(connection, id, timeout: nil)
					@connection = connection
					@id = id
					
					@timeout = timeout
					
					@received = Thread::Queue.new
					@accept = nil
				end
				
				attr :connection
				attr :id
				
				attr_accessor :timeout
				
				attr :received
				attr :accept
				
				def read
					if @received.empty?
						@connection.flush
					end
					
					@received.pop(timeout: @timeout)
				end
				
				def write(message)
					if @connection
						@connection.write(message)
					else
						raise RuntimeError, "Transaction is closed!"
					end
				end
				
				# Push a message to the transaction's received queue.
				# Silently ignores messages if the queue is already closed.
				def push(message)
					@received.push(message)
				rescue ClosedQueueError
					# Queue is closed (transaction already finished/closed) - ignore silently.
				end
				
				def close
					if connection = @connection
						@connection = nil
						@received.close
						
						connection.transactions.delete(@id)
					end
				end
				
				# Invoke a remote procedure.
				def invoke(name, arguments, options, &block)
					Console.debug(self){[name, arguments, options, block]}
					
					self.write(Invoke.new(@id, name, arguments, options, block_given?))
					
					while response = self.read
						case response
						when Return
							return response.result
						when Yield
							begin
								result = yield(*response.result)
								self.write(Next.new(@id, result))
							rescue => error
								self.write(Error.new(@id, error))
							end
						when Error
							raise(response.result)
						end
					end
				end
				
				# Accept a remote procedure invokation.
				def accept(object, arguments, options, block_given)
					if block_given
						result = object.public_send(*arguments, **options) do |*yield_arguments|
							self.write(Yield.new(@id, yield_arguments))
							
							response = self.read
							
							case response
							when Next
								response.result
							when Error
								raise(response.result)
							when Close
								break
							end
						end
					else
						result = object.public_send(*arguments, **options)
					end
					
					self.write(Return.new(@id, result))
				rescue UncaughtThrowError => error
					self.write(Throw.new(@id, error.tag))
				rescue => error
					self.write(Error.new(@id, error))
				end
			end
		end
	end
end
