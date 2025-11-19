# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async/bus/a_server"

class MyArray
	def initialize
		@values = []
	end
	
	def sum
		@values.sum
	end
	
	def <<(value)
		@values << value
	end
end

describe Async::Bus::Server do
	include Async::Bus::AServer
	
	with "#bind" do
		it "can receive incoming clients and expose a bound object" do
			server_task = Async do
				server.accept do |connection|
					connection.bind(:object, Object.new)
				end
			end
			
			client.connect do |connection|
				expect(connection[:object]).to be_a(Object)
			end
		end
	end
	
	with "a bound Array instance" do
		let(:array) {Array.new}
		
		def before
			super
			
			@server_task = Async do
				server.accept do |connection|
					connection.bind(:array, array)
				end
			end
		end
		
		def after(error = nil)
			@server_task.stop
			
			super
		end
		
		it "can add items to the array" do
			client.connect do |connection|
				connection[:array] << 1
			end
			
			expect(array).to be == [1]
		end
		
		it "can use equality operators" do
			array << 1
			
			client.connect do |connection|
				expect(connection[:array] == [1]).to be_truthy
				expect(connection[:array] != [2]).to be_truthy
			end
		end
		
		it "can enumerate items in the array" do
			array << 1 << 2 << 3
			enumerated = []
			
			client.connect do |connection|
				connection[:array].each do |item|
					enumerated << item
				end
			end
			
			expect(enumerated).to be == [1, 2, 3]
		end
		
		it "can raise an exception" do
			client.connect do |connection|
				expect do
					connection[:array]["one"]
				end.to raise_exception(TypeError, message: be =~ /no implicit conversion of String into Integer/)
			end
		end
		
		it "can get all methods" do
			client.connect do |connection|
				expect(connection[:array].methods).to be == array.methods
				expect(connection[:array].public_methods).to be == array.public_methods
				expect(connection[:array].protected_methods).to be == array.protected_methods
				expect(connection[:array].private_methods).to be == array.private_methods
			end
		end
		
		it "can check if it responds to methods" do
			client.connect do |connection|
				expect(connection[:array].respond_to?(:each)).to be_truthy
				expect(connection[:array].respond_to?(:no_such_method)).to be_falsey
			end
		end
		
		it "has a __name__" do
			client.connect do |connection|
				expect(connection[:array].__name__).to be == :array
			end
		end
	end
	
	with "a bound Hash instance" do
		let(:hash) {Hash.new}
		
		def before
			super
			
			@server_task = Async do
				server.accept do |connection|
					connection.bind(:hash, hash)
					connection.bind(:sum_key, proc{|key| hash[key].sum})
				end
			end
		end
		
		def after(error = nil)
			@server_task.stop
		end
		
		it "can assign a local object to the hash" do
			# We can't use a primitive type here, because it will be serialized and deserialized (e.g. copied), losing the object reference.
			array = MyArray.new
			
			client.connect do |connection|
				# With explicit proxying, we must bind the object first to get a proxy:
				array_proxy = connection.proxy(array)
				connection[:hash][:array] = array_proxy
				
				expect(connection[:sum_key].call(:array)).to be == 0
				
				array << 1 << 2 << 3
				
				expect(connection[:sum_key].call(:array)).to be == 6
				
				expect(connection.transactions).to be(:empty?)
			end
		end
	end
end
