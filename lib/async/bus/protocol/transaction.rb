# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async/queue"

module Async
	module Bus
		module Protocol
			# Represents a transaction for a remote procedure call.
			class Transaction
				# Initialize a new transaction.
				# @parameter connection [Connection] The connection for this transaction.
				# @parameter id [Integer] The transaction ID.
				# @parameter timeout [Float] The timeout for the transaction.
				def initialize(connection, id, timeout: nil)
					@connection = connection
					@id = id
					
					@timeout = timeout
					
					@received = Thread::Queue.new
					@accept = nil
				end
				
				# @attribute [Connection] The connection for this transaction.
				attr :connection
				
				# @attribute [Integer] The transaction ID.
				attr :id
				
				# @attribute [Float] The timeout for the transaction.
				attr_accessor :timeout
				
				# @attribute [Thread::Queue] The queue of received messages.
				attr :received
				
				# @attribute [Object] The accept handler.
				attr :accept
				
				# Read a message from the transaction queue.
				# @returns [Object] The next message.
				def read
					if @received.empty?
						@connection.flush
					end
					
					@received.pop(timeout: @timeout)
				end
				
				# Write a message to the connection.
				# @parameter message [Object] The message to write.
				# @raises [RuntimeError] If the transaction is closed.
				def write(message)
					if @connection
						@connection.write(message)
					else
						raise RuntimeError, "Transaction is closed!"
					end
				end
				
				# Push a message to the transaction's received queue.
				# Silently ignores messages if the queue is already closed.
				# @parameter message [Object] The message to push.
				def push(message)
					@received.push(message)
				rescue ClosedQueueError
					# Queue is closed (transaction already finished/closed) - ignore silently.
				end
				
				# Close the transaction and clean up resources.
				def close
					if connection = @connection
						@connection = nil
						@received.close
						
						connection.transactions.delete(@id)
					end
				end
				
				# Invoke a remote procedure.
				# @parameter name [Symbol] The name of the remote object.
				# @parameter arguments [Array] The positional arguments.
				# @parameter options [Hash] The keyword arguments.
				# @yields {|*args| ...} Optional block for yielding operations.
				# @returns [Object] The result of the invocation.
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
						when Throw
							# Re-throw the tag and value that was thrown on the server side
							# Throw.result contains [tag, value] array
							tag, value = response.result
							throw(tag, value)
						end
					end
				end
				
				# Accept a remote procedure invocation.
				# @parameter object [Object] The object to invoke the method on.
				# @parameter arguments [Array] The positional arguments.
				# @parameter options [Hash] The keyword arguments.
				# @parameter block_given [Boolean] Whether a block was provided.
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
					# UncaughtThrowError has both tag and value attributes
					# Store both in the Throw message: result is tag, we'll add value handling
					self.write(Throw.new(@id, [error.tag, error.value]))
				rescue => error
					self.write(Error.new(@id, error))
				end
			end
		end
	end
end
