# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/protocol/wrapper"
require "async/bus/protocol/response"

class FakeBus
	def initialize
		@objects = {}
		@proxies = {}
	end
	
	attr :objects
	
	def proxy_name(object)
		name = object.__id__
		@objects[name] = object
		
		return name
	end
	
	def proxy_object(name, local = true)
		# If the proxy is for this connection and the object is bound locally, return the actual object:
		if local && (entry = @objects[name])
			# Handle wrapper structs (like Connection uses Explicit/Implicit):
			if entry.respond_to?(:object)
				return entry.object
			else
				return entry
			end
		end
		
		# Otherwise, create a proxy for the remote object:
		unless proxy = @proxies[name]
			proxy = Async::Bus::Protocol::Proxy.new(self, name)
			@proxies[name] = proxy
		end
		
		return proxy
	end
	
	def [](name)
		unless proxy = @proxies[name]
			proxy = Async::Bus::Protocol::Proxy.new(self, name)
			@proxies[name] = proxy
		end
		
		return proxy
	end
end

describe Async::Bus::Protocol::Wrapper do
	let(:bus) {FakeBus.new}
	let(:wrapper) {subject.new(bus)}
	
	let(:pipe) {IO.pipe}
	let(:input) {pipe.first}
	let(:output) {pipe.last}
	
	let(:packer) {wrapper.packer(output)}
	let(:unpacker) {wrapper.unpacker(input)}
	
	let(:transaction_id) {rand(1...1000)}
	
	with Async::Bus::Protocol::Error do
		it "can serialize exceptions" do
			object = Object.new
			error = nil
			
			begin
				object.foo
			rescue NoMethodError => error
				error_response = Async::Bus::Protocol::Error.new(transaction_id, error)
				packer.write(error_response)
				packer.flush
			end
			
			result = unpacker.read
			
			expect(result).to be_a(Async::Bus::Protocol::Error)
			expect(result.id).to be == transaction_id
			expect(result.result).to be_a(NoMethodError)
			expect(result.result.message).to be =~ /undefined method.*foo/
			expect(result.result.backtrace).to be == error.backtrace
		end
	end
	
	with Async::Bus::Protocol::Return do
		it "can serialize return values" do
			return_response = Async::Bus::Protocol::Return.new(transaction_id, :return_value)
			packer.write(return_response)
			packer.flush
			
			result = unpacker.read
			expect(result).to be_a(Async::Bus::Protocol::Return)
			expect(result.id).to be == transaction_id
			expect(result.result).to be == :return_value
		end
	end
	
	with Async::Bus::Protocol::Yield do
		it "can serialize yield values" do
			yield_response = Async::Bus::Protocol::Yield.new(transaction_id, [1, 2, 3])
			packer.write(yield_response)
			packer.flush
			
			result = unpacker.read
			expect(result).to be_a(Async::Bus::Protocol::Yield)
			expect(result.id).to be == transaction_id
			expect(result.result).to be == [1, 2, 3]
		end
		
		it "can serialize yield with multiple arguments" do
			yield_response = Async::Bus::Protocol::Yield.new(transaction_id, [:key, :value])
			packer.write(yield_response)
			packer.flush
			
			result = unpacker.read
			expect(result).to be_a(Async::Bus::Protocol::Yield)
			expect(result.id).to be == transaction_id
			expect(result.result).to be == [:key, :value]
		end
	end
	
	with Async::Bus::Protocol::Next do
		it "can serialize next values" do
			next_response = Async::Bus::Protocol::Next.new(transaction_id, :next_value)
			packer.write(next_response)
			packer.flush
			
			result = unpacker.read
			expect(result).to be_a(Async::Bus::Protocol::Next)
			expect(result.id).to be == transaction_id
			expect(result.result).to be == :next_value
		end
	end
	
	with Async::Bus::Protocol::Throw do
		it "can serialize throw tags" do
			throw_response = Async::Bus::Protocol::Throw.new(transaction_id, :tag_name)
			packer.write(throw_response)
			packer.flush
			
			result = unpacker.read
			expect(result).to be_a(Async::Bus::Protocol::Throw)
			expect(result.id).to be == transaction_id
			expect(result.result).to be == :tag_name
		end
	end
	
	with Async::Bus::Protocol::Close do
		it "can serialize close messages" do
			close_response = Async::Bus::Protocol::Close.new(transaction_id, nil)
			packer.write(close_response)
			packer.flush
			
			result = unpacker.read
			expect(result).to be_a(Async::Bus::Protocol::Close)
			expect(result.id).to be == transaction_id
			expect(result.result).to be_nil
		end
	end
	
	with Async::Bus::Protocol::Proxy do
		it "can serialize a proxy with a symbol name" do
			# Bind an object locally so it can be found during deserialization (round-trip scenario)
			worker_object = Object.new
			# FakeBus stores objects directly, but Connection uses Explicit/Implicit wrappers
			# For FakeBus, we'll create a simple wrapper that responds to .object
			wrapper = Struct.new(:object).new(worker_object)
			bus.objects[:worker] = wrapper
			
			proxy = Async::Bus::Protocol::Proxy.new(bus, :worker)
			
			packer.write(proxy)
			packer.flush
			
			result = unpacker.read
			
			# Should return the actual object (round-trip scenario)
			expect(result).to be_equal(worker_object)
		end
		
		it "can serialize a proxy with a string name" do
			# Bind an object locally so it can be found during deserialization (round-trip scenario)
			worker_object = Object.new
			# FakeBus stores objects directly, but Connection uses Explicit/Implicit wrappers
			# For FakeBus, we'll create a simple wrapper that responds to .object
			wrapper = Struct.new(:object).new(worker_object)
			bus.objects["worker-123"] = wrapper
			
			proxy = Async::Bus::Protocol::Proxy.new(bus, "worker-123")
			
			packer.write(proxy)
			packer.flush
			
			result = unpacker.read
			
			# Should return the actual object (round-trip scenario)
			expect(result).to be_equal(worker_object)
		end
		
		it "creates a proxy when object not found locally" do
			# Create a proxy for a name that doesn't exist in objects
			# This tests the forwarding path in unpack_proxy when @connection.objects[name] returns nil
			# When a proxy is forwarded from another connection, we create a proxy pointing to this connection
			proxy = Async::Bus::Protocol::Proxy.new(bus, :nonexistent)
			
			packer.write(proxy)
			packer.flush
			
			result = unpacker.read
			
			# Should return a proxy pointing to this connection (forwarding scenario)
			expect(result.__name__).to be == :nonexistent
			expect(result.__connection__).to be == bus
		end
	end
end
