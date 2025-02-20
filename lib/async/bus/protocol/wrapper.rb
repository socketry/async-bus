# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "msgpack"
require_relative "proxy"

module Async
	module Bus
		module Protocol
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
					arguments = Array.new(unpacker.read) {unpacker.read}
					options = Array.new(unpacker.read) {[unpacker.read, unpacker.read]}.to_h
					block_given = unpacker.read
					
					return self.new(id, name, arguments, options, block_given)
				end
			end
			
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
			
			class Return < Response
				REFERENCE_TYPES = {Object => true, Hash => true, Array => true}
				
				def pack(packer, bus)
					packer.write(@id)
					if REFERENCE_TYPES[@result.class]
						packer.write(true)
						packer.write(bus.proxy(@result))
					else
						packer.write(false)
						packer.write(@result)
					end
				end
				
				def self.unpack(unpacker, bus)
					id = unpacker.read
					reference = unpacker.read
					result = unpacker.read
					
					if reference
						result = bus[result]
					end
					
					return self.new(id, result)
				end
			end
			
			Yield = Class.new(Response)
			Error = Class.new(Response)
			Next = Class.new(Response)
			Throw = Class.new(Response)
			Close = Class.new(Response)
			
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
			
			class Wrapper < MessagePack::Factory
				def initialize(bus)
					super()
					
					@bus = bus
					
					# The order here matters.
					
					self.register_type(0x00, Invoke, recursive: true,
						packer: ->(invoke, packer){invoke.pack(packer)},
						unpacker: ->(unpacker){Invoke.unpack(unpacker)},
					)
					
					self.register_type(0x01, Return, recursive: true,
						packer: ->(response, packer){response.pack(packer, @bus)},
						unpacker: ->(unpacker){Return.unpack(unpacker, @bus)},
					)
					
					[Yield, Error, Next, Throw, Close].each_with_index do |klass, index|
						self.register_type(0x02 + index, klass, recursive: true,
							packer: ->(value, packer){value.pack(packer)},
							unpacker: ->(unpacker){klass.unpack(unpacker)},
						)
					end
					
					# Reverse serialize proxies back into objects:
					self.register_type(0x10, Proxy,
						packer: ->(proxy){proxy.__name__},
						unpacker: @bus.method(:object),
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
					[Object, Hash, Array].each_with_index do |klass, index|
						self.register_type(0x30 + index, klass,
							packer: @bus.method(:proxy),
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
