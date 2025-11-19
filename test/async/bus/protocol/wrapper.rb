# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/protocol/wrapper"
require "async/bus/protocol/response"

class FakeBus
	def initialize
		@objects = {}
	end
	
	def proxy_name(object)
		name = "<#{object.class}@#{object.object_id}>"
		@objects[name] = object
		
		return name
	end
	
	def [](name)
		@objects[name]
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
end
