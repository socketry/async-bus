# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "msgpack"
require_relative "proxy"

module Async
	module Bus
		module Protocol
			class Wrapper < MessagePack::Factory
				def initialize(bus)
					super()
					
					@bus = bus
					
					# The order here matters.
					
					# Reverse serialize proxies back into objects:
					self.register_type(0x01, Proxy,
						packer: ->(proxy){proxy.__name__},
						unpacker: @bus.method(:object),
					)
					
					self.register_type(0x02, Symbol)
					self.register_type(0x03, Exception,
						packer: ->(exception){Marshal.dump(exception)},
						unpacker: ->(data){Marshal.load(data)},
					)
					
					self.register_type(0x04, Class,
						packer: ->(klass){Marshal.dump(klass)},
						unpacker: ->(data){Marshal.load(data)},
					)
					
					# Serialize objects into proxies:
					self.register_type(0x0F, Object,
						packer: @bus.method(:proxy),
						unpacker: @bus.method(:[])
					)
				end
			end
		end
	end
end
