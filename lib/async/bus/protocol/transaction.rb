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

require 'async/queue'

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