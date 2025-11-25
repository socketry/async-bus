# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "msgpack"
require_relative "proxy"

module Async
	module Bus
		module Protocol
			# Represents a method invocation.
			class Invoke
				# Initialize a new invocation message.
				# @parameter id [Integer] The transaction ID.
				# @parameter name [Symbol] The method name to invoke.
				# @parameter arguments [Array] The positional arguments.
				# @parameter options [Hash] The keyword arguments.
				# @parameter block_given [Boolean] Whether a block was provided.
				def initialize(id, name, arguments, options, block_given)
					@id = id
					@name = name
					@arguments = arguments
					@options = options
					@block_given = block_given
				end
				
				# @attribute [Integer] The transaction ID.
				attr :id
				
				# @attribute [Symbol] The method name.
				attr :name
				
				# @attribute [Array] The positional arguments.
				attr :arguments
				
				# @attribute [Hash] The keyword arguments.
				attr :options
				
				# @attribute [Boolean] Whether a block was provided.
				attr :block_given
				
				# Pack the invocation into a MessagePack packer.
				# @parameter packer [MessagePack::Packer] The packer to write to.
				def pack(packer)
					packer.write(@id)
					packer.write(@name)
					
					packer.write(@arguments.size)
					@arguments.each do |argument|
						packer.write(argument)
					end
					
					packer.write(@options.size)
					@options.each do |key, value|
						packer.write(key)
						packer.write(value)
					end
					
					packer.write(@block_given)
				end
				
				# Unpack an invocation from a MessagePack unpacker.
				# @parameter unpacker [MessagePack::Unpacker] The unpacker to read from.
				# @returns [Invoke] A new invocation instance.
				def self.unpack(unpacker)
					id = unpacker.read
					name = unpacker.read
					arguments = Array.new(unpacker.read){unpacker.read}
					options = Array.new(unpacker.read){[unpacker.read, unpacker.read]}.to_h
					block_given = unpacker.read
					
					return self.new(id, name, arguments, options, block_given)
				end
			end
		end
	end
end
