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
			# Represents a MessagePack factory wrapper for async-bus serialization.
			class Wrapper < MessagePack::Factory
				# Initialize a new wrapper.
				# @parameter connection [Connection] The connection for proxy resolution.
				# @parameter reference_types [Array(Class)] Types to serialize as proxies.
				def initialize(connection, reference_types: [Controller])
					super()
					
					@connection = connection
					@reference_types = reference_types
					
					# Store the peer connection for forwarding proxies:
					# When a proxy is forwarded (local=false), it should point back to the sender
					# (the peer connection), not the receiver (this connection).
					@peer_connection = nil
					
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
					# When a Proxy is received, use proxy_object to handle reverse lookup
					self.register_type(0x10, Proxy, recursive: true,
							packer: self.method(:pack_proxy),
							unpacker: self.method(:unpack_proxy),
						)
					
					self.register_type(0x11, Release, recursive: true,
							packer: ->(release, packer){release.pack(packer)},
							unpacker: ->(unpacker){Release.unpack(unpacker)},
						)
					
					self.register_type(0x20, Symbol)
					self.register_type(0x21, Exception, recursive: true,
							packer: self.method(:pack_exception),
							unpacker: self.method(:unpack_exception),
						)
					
					self.register_type(0x22, Class,
							packer: ->(klass){klass.name},
							unpacker: ->(name){Object.const_get(name)},
						)
					
					reference_packer = self.method(:pack_reference)
					reference_unpacker = self.method(:unpack_reference)
					
					# Serialize objects into proxies:
					reference_types&.each_with_index do |klass, index|
						self.register_type(0x30 + index, klass, recursive: true,
								packer: reference_packer,
								unpacker: reference_unpacker,
							)
					end
				end
				
				# Pack a proxy into a MessagePack packer.
				#
				# Validates that the proxy is for this connection and serializes the proxy name.
				# Multi-hop proxy forwarding is not supported, so proxies can only be serialized
				# from the same connection they were created for (round-trip scenarios).
				#
				# @parameter proxy [Proxy] The proxy to serialize.
				# @parameter packer [MessagePack::Packer] The packer to write to.
				# @raises [ArgumentError] If the proxy is from a different connection (multi-hop forwarding not supported).
				def pack_proxy(proxy, packer)
					# Check if the proxy is for this connection:
					if proxy.__connection__ != @connection
						proxy = @connection.proxy(proxy)
					end
					
					packer.write(proxy.__name__)
				end
				
				# Unpack a proxy from a MessagePack unpacker.
				#
				# When deserializing a proxy:
				# - If the object is bound locally, return the actual object (round-trip scenario)
				# - If the object is not found locally, create a proxy pointing to this connection
				#   (the proxy was forwarded from another connection and should point back to the sender)
				#
				# @parameter unpacker [MessagePack::Unpacker] The unpacker to read from.
				# @returns [Object | Proxy] The actual object if bound locally, or a proxy pointing to this connection.
				def unpack_proxy(unpacker)
					@connection.proxy_object(unpacker.read)
				end
				
				# Pack an exception into a MessagePack packer.
				# @parameter exception [Exception] The exception to pack.
				# @parameter packer [MessagePack::Packer] The packer to write to.
				def pack_exception(exception, packer)
					packer.write(exception.class.name)
					packer.write(exception.message)
					packer.write(exception.backtrace)
				end
				
				# Unpack an exception from a MessagePack unpacker.
				# @parameter unpacker [MessagePack::Unpacker] The unpacker to read from.
				# @returns [Exception] A reconstructed exception.
				def unpack_exception(unpacker)
					klass = unpacker.read
					message = unpacker.read
					backtrace = unpacker.read
					
					klass = Object.const_get(klass)
					
					exception = klass.new(message)
					exception.set_backtrace(backtrace)
					
					return exception
				end
				
				# Pack a reference type object (e.g., Controller) into a MessagePack packer.
				#
				# Serializes the object as a proxy by generating a temporary name and writing it to the packer.
				# The object is implicitly bound to the connection with a temporary name.
				#
				# @parameter object [Object] The reference type object to serialize.
				# @parameter packer [MessagePack::Packer] The packer to write to.
				def pack_reference(object, packer)
					packer.write(@connection.proxy_name(object))
				end
				
				# Unpack a reference type object from a MessagePack unpacker.
				#
				# Reads a proxy name and returns the corresponding object or proxy.
				# If the object is bound locally, returns the actual object; otherwise returns a proxy.
				#
				# @parameter unpacker [MessagePack::Unpacker] The unpacker to read from.
				# @returns [Object | Proxy] The actual object if bound locally, or a proxy otherwise.
				def unpack_reference(unpacker)
					@connection.proxy_object(unpacker.read)
				end
			end
		end
	end
end
