# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

module Async
	module Bus
		module Protocol
			# Represents a response message from a remote procedure call.
			class Response
				# Initialize a new response message.
				# @parameter id [Integer] The transaction ID.
				# @parameter result [Object] The result value.
				def initialize(id, result)
					@id = id
					@result = result
				end
				
				# @attribute [Integer] The transaction ID.
				attr :id
				
				# @attribute [Object] The result value.
				attr :result
				
				# Pack the response into a MessagePack packer.
				# @parameter packer [MessagePack::Packer] The packer to write to.
				def pack(packer)
					packer.write(@id)
					packer.write(@result)
				end
				
				# Unpack a response from a MessagePack unpacker.
				# @parameter unpacker [MessagePack::Unpacker] The unpacker to read from.
				# @returns [Response] A new response instance.
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
