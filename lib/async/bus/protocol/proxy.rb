# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

module Async
	module Bus
		module Protocol
			# A proxy object that forwards method calls to a remote object.
			#
			# We must be extremely careful not to invoke any methods on the proxy object that would recursively call the proxy object.
			class Proxy < BasicObject
				# Create a new proxy object.
				#
				# @parameter connection [Connection] The connection to the remote object.
				# @parameter name [Symbol] The name (address) of the remote object.
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
				
				def method_missing(*arguments, **options, &block)
					@connection.invoke(@name, arguments, options, &block)
				end
				
				def respond_to?(name, include_all = false)
					@connection.invoke(@name, [:respond_to?, name, include_all])
				end
				
				def respond_to_missing?(name, include_all = false)
					@connection.invoke(@name, [:respond_to?, name, include_all])
				end
				
				def inspect
					"#<proxy #{@name}: #{@connection.invoke(@name, [:inspect])}>"
				end
			end
		end
	end
end
