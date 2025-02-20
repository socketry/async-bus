# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async/bus/protocol/wrapper"

class FakeConnection
	def object(data)
	end
	
	def proxy(object)
		object.object_id
	end
	
	def [](id)
		ObjectSpace._id2ref(id)
	end
end

describe Async::Bus::Protocol::Wrapper do
	let(:wrapper) {subject.new(FakeConnection.new)}
	
	let(:pipe) {IO.pipe}
	let(:input) {pipe.first}
	let(:output) {pipe.last}
	
	let(:packer) {wrapper.packer(output)}
	let(:unpacker) {wrapper.unpacker(input)}
	
	it "can serialize exceptions" do
		object = Object.new
		
		begin
			object.foo
		rescue NoMethodError => error
			packer.write([:error, error])
			packer.flush
		end
		
		what, result = unpacker.read
		
		expect(what).to be == :error
		expect(result).to be_a(NoMethodError)
	end
end
