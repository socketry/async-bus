# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

module Async
	module Bus
		module Protocol
			# Represents a named object that has been released (no longer available).
			class Release
				def initialize(name)
					@name = name
				end
				
				attr :name
				
				def pack(packer)
					packer.write(@name)
				end
				
				def self.unpack(unpacker)
					name = unpacker.read
					
					return self.new(name)
				end
			end
		end
	end
end
