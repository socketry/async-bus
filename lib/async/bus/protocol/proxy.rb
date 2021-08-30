# Copyright, 2018, by Samuel G. D. Williams. <http://www.codeotaku.com>
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

module Async
	module Bus
		module Protocol
			class Proxy < BasicObject
				def initialize(connection, name)
					@connection = connection
					@name = name
				end
				
				def !
					@connection.invoke(@name, [:!])
				end
				
				def == object
					@connection.invoke(@name, [:==, object])
				end
				
				def != object
					@connection.invoke(@name, [:!=, object])
				end
				
				def eql?(other)
					self.equal?(other)
				end
				
				def methods(all = true)
					@connection.invoke(@name, [:methods, all]) | super
				end
				
				def protected_methods(all = true)
					@connection.invoke(@name, [:protected_methods, all]) | super
				end
				
				def public_methods(all = true)
					@connection.invoke(@name, [:public_methods, all]) | super
				end
				
				def inspect
					"[Proxy (#{@name}) #{method_missing(:inspect)}]"
				end
				
				def method_missing(*arguments, **options, &block)
					@connection.invoke(@name, arguments, options, &block)
				end
				
				def respond_to?(name, include_all = false)
					@connection.invoke(@name, [:respond_to?, name, include_all])
				end
				
				def respond_to_missing?(name, include_all = false)
					@connection.invoke(@name, [:respond_to?, name, include_all]) || super
				end
			end
		end
	end
end
