# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async/queue"

module Async
	module Bus
		module Protocol
			class Transaction
				def initialize(connection, id)
					@connection = connection
					@id = id
					
					@received = Async::Queue.new
					@accept = nil
				end
				
				attr :id
				attr :received
				
				def read
					if @received.empty?
						@connection.packer.flush
					end
					
					@received.dequeue
				end
				
				def write(*arguments)
					@connection.packer.write([id, *arguments])
					@connection.packer.flush
				end
				
				def close
					if @connection
						@received.enqueue(nil)
						
						connection = @connection
						@connection = nil
						
						connection.transactions.delete(@id)
					end
				end
				
				# Invoke a remote procedure.
				def invoke(name, arguments, options, &block)
					Console.logger.debug(self) {[name, arguments, options, block]}
					
					self.write(:invoke, name, arguments, options, block_given?)
					
					while response = self.read
						what, result = response
						
						case what
						when :error
							raise(result)
						when :return
							return(result)
						when :yield
							begin
								result = yield(*result)
								self.write(:next, result)
							rescue => error
								self.write(:error, error)
							end
						end
					end
					
					# ensure
					# 	self.write(:close)
				end
				
				# Accept a remote procedure invokation.
				def accept(object, arguments, options, block)
					if block
						result = object.public_send(*arguments, **options) do |*yield_arguments|
							self.write(:yield, yield_arguments)
							what, result = self.read
							
							case what
							when :next
								result
							when :close
								return
							when :error
								raise(result)
							end
						end
					else
						result = object.public_send(*arguments, **options)
					end
					
					self.write(:return, result)
				rescue UncaughtThrowError => error
					self.write(:throw, error.tag)
				rescue => error
					self.write(:error, error)
					# ensure
					# 	self.write(:close)
				end
			end
		end
	end
end
