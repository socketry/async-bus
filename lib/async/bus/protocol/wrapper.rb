# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "msgpack"

require_relative "proxy"
require_relative "invoke"
require_relative "response"
require_relative "release"

require_relative "../controller"

module Async
	module Bus
		module Protocol
			class Wrapper < MessagePack::Factory
				def initialize(bus, reference_types: [Controller])
					super()
					
					@bus = bus
					@reference_types = reference_types
					
					# The order here matters.
					
					self.register_type(0x00, Invoke, recursive: true,
						packer: ->(invoke, packer){invoke.pack(packer)},
						unpacker: ->(unpacker){Invoke.unpack(unpacker)},
					)
					
					[Return, Yield, Error, Next, Throw, Close].each_with_index do |klass, index|
						self.register_type(0x01 + index, klass, recursive: true,
							packer: ->(value, packer){value.pack(packer)},
							unpacker: ->(unpacker){klass.unpack(unpacker)},
						)
					end
					
					# Reverse serialize proxies back into proxies:
					# When a Proxy is received, create a proxy pointing back
					self.register_type(0x10, Proxy,
						packer: ->(proxy){proxy.__name__},
						unpacker: @bus.method(:[]),
					)
					
					self.register_type(0x11, Release, recursive: true,
						packer: ->(release, packer){release.pack(packer)},
						unpacker: ->(unpacker){Release.unpack(unpacker)},
					)
					
					self.register_type(0x20, Symbol)
					self.register_type(0x21, Exception,
						packer: self.method(:pack_exception),
						unpacker: self.method(:unpack_exception),
						recursive: true,
					)
					
					self.register_type(0x22, Class,
						packer: ->(klass){klass.name},
						unpacker: ->(name){Object.const_get(name)},
					)
					
					# Serialize objects into proxies:
					reference_types&.each_with_index do |klass, index|
						self.register_type(0x30 + index, klass,
							packer: @bus.method(:proxy_name),
							unpacker: @bus.method(:[]),
						)
					end
				end
				
				def pack_exception(exception, packer)
					packer.write(exception.class.name)
					packer.write(exception.message)
					packer.write(exception.backtrace)
				end
				
				def unpack_exception(unpacker)
					klass = unpacker.read
					message = unpacker.read
					backtrace = unpacker.read
					
					klass = Object.const_get(klass)
					
					exception = klass.new(message)
					exception.set_backtrace(backtrace)
					
					return exception
				end
			end
		end
	end
end
