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
				
				# Get the name of the remote object.
				# @returns [Symbol] The name of the remote object.
				def __name__
					@name
				end
				
				# Logical negation operator.
				# @returns [Object] The result of the negation.
				def !
					@connection.invoke(@name, [:!])
				end
				
				# Equality operator.
				# @parameter object [Object] The object to compare with.
				# @returns [Boolean] True if equal.
				def == object
					@connection.invoke(@name, [:==, object])
				end
				
				# Inequality operator.
				# @parameter object [Object] The object to compare with.
				# @returns [Boolean] True if not equal.
				def != object
					@connection.invoke(@name, [:!=, object])
				end
				
				# Forward method calls to the remote object.
				# @parameter arguments [Array] The method arguments.
				# @parameter options [Hash] The keyword arguments.
				# @yields {|*args| ...} Optional block to pass to the method.
				# @returns [Object] The result of the method call.
				def method_missing(*arguments, **options, &block)
					@connection.invoke(@name, arguments, options, &block)
				end
				
				# Check if the remote object responds to a method.
				# @parameter name [Symbol] The method name to check.
				# @parameter include_all [Boolean] Whether to include private methods.
				# @returns [Boolean] True if the method exists.
				def respond_to?(name, include_all = false)
					@connection.invoke(@name, [:respond_to?, name, include_all])
				end
				
				# Check if the remote object responds to a missing method.
				# @parameter name [Symbol] The method name to check.
				# @parameter include_all [Boolean] Whether to include private methods.
				# @returns [Boolean] True if the method exists.
				def respond_to_missing?(name, include_all = false)
					@connection.invoke(@name, [:respond_to?, name, include_all])
				end
				
				# Return a string representation of the proxy.
				# @returns [String] A string describing the proxy.
				def inspect
					"#<proxy #{@name}>"
				end
			end
		end
	end
end
