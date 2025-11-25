# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

module Async
	module Bus
		module Protocol
			# Represents a named object that has been released (no longer available).
			class Release
				# Initialize a new release message.
				# @parameter name [Symbol] The name of the released object.
				def initialize(name)
					@name = name
				end
				
				# @attribute [Symbol] The name of the released object.
				attr :name
				
				# Pack the release into a MessagePack packer.
				# @parameter packer [MessagePack::Packer] The packer to write to.
				def pack(packer)
					packer.write(@name)
				end
				
				# Unpack a release from a MessagePack unpacker.
				# @parameter unpacker [MessagePack::Unpacker] The unpacker to read from.
				# @returns [Release] A new release instance.
				def self.unpack(unpacker)
					name = unpacker.read
					
					return self.new(name)
				end
			end
		end
	end
end
