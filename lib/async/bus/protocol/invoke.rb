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
				def initialize(id, name, arguments, options, block_given)
					@id = id
					@name = name
					@arguments = arguments
					@options = options
					@block_given = block_given
				end
				
				attr :id
				attr :name
				attr :arguments
				attr :options
				attr :block_given
				
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
