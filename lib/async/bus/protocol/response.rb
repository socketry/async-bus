# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

module Async
	module Bus
		module Protocol
			class Response
				def initialize(id, result)
					@id = id
					@result = result
				end
				
				attr :id
				attr :result
				
				def pack(packer)
					packer.write(@id)
					packer.write(@result)
				end
				
				def self.unpack(unpacker)
					id = unpacker.read
					result = unpacker.read
					
					return self.new(id, result)
				end
			end
			
			Return = Class.new(Response)
			Yield = Class.new(Response)
			Error = Class.new(Response)
			Next = Class.new(Response)
			Throw = Class.new(Response)
			Close = Class.new(Response)
		end
	end
end
