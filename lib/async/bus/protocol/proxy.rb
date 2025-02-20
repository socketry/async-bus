# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

module Async
	module Bus
		module Protocol
			class Proxy < BasicObject
				def initialize(connection, name)
					@connection = connection
					@name = name
				end
				
				def __name__
					@name
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
					@connection.invoke(@name, [:methods, all])
				end
				
				def protected_methods(all = true)
					@connection.invoke(@name, [:protected_methods, all])
				end
				
				def public_methods(all = true)
					@connection.invoke(@name, [:public_methods, all])
				end
				
				def method_missing(*arguments, **options, &block)
					$stderr.puts "invoke #{@name}.#{arguments}"
					@connection.invoke(@name, arguments, options, &block)
				end
				
				def respond_to?(name, include_all = false)
					@connection.invoke(@name, [:respond_to?, name, include_all])
				end
				
				def respond_to_missing?(name, include_all = false)
					@connection.invoke(@name, [:respond_to?, name, include_all])
				end
			end
		end
	end
end
