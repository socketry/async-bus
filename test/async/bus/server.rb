# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async/bus/server"
require "async/bus/client"

require "sus/fixtures/async"
require "tmpdir"
require "io/endpoint/bound_endpoint"

class Counter
	def initialize(count = 0)
		@count = count
	end
	
	attr :count
	
	def increment
		@count += 1
	end
	
	def each
		@count.times do
			yield Object.new
		end
	end
	
	def make
		Object.new
	end
	
	def itself(object)
		return object
	end
	
	def error(message)
		raise message
	end
end

describe Async::Bus::Server do
	include Sus::Fixtures::Async::ReactorContext
	
	let(:ipc_path) {File.join(@root, "bus.ipc")}
	let(:endpoint) {Async::Bus::Protocol.local_endpoint(ipc_path)}
	
	def around(&block)
		Dir.mktmpdir do |directory|
			@root = directory
			super(&block)
		end
	end
	
	def before
		@bound_endpoint = endpoint.bound
	end
	
	def after(error = nil)
		@bound_endpoint&.close
	end
	
	let(:server) {Async::Bus::Server.new(@bound_endpoint)}
	let(:client) {Async::Bus::Client.new(endpoint)}
	
	it "can receive incoming clients" do
		server_task = Async do
			server.accept do |connection|
				connection.bind(:counter, Counter.new)
			end
		end
		
		client.connect do |connection|
			3.times do
				connection[:counter].increment
			end
			
			expect(connection[:counter].count).to be == 3
		end
	end
	
	it "can return proxy objects" do
		server_task = Async do
			server.accept do |connection|
				connection.bind(:counter, Counter)
			end
		end
		
		client.connect do |connection|
			counter = connection[:counter].new
			
			3.times do
				counter.increment
			end
			
			expect(counter.count).to be == 3
		end
	end
	
	it "can return the original object" do
		server_task = Async do
			server.accept do |connection|
				connection.bind(:counter, Counter)
			end
		end
		
		client.connect do |connection|
			counter = connection[:counter].new
			object = Object.new
			
			object2 = counter.itself(object)
			
			expect(object).to be_equal(object2)
		end
	end
	
	it "can raise error" do
		server_task = Async do
			server.accept do |connection|
				connection.bind(:counter, Counter)
			end
		end
		
		client.connect do |connection|
			counter = connection[:counter].new
			
			expect do
				counter.error("Hello")
			end.to raise_exception(RuntimeError, message: be =~ /Hello/)
		end
	end
	
	it "can release proxy objects" do
		server_task = Async do
			server.accept do |connection|
				connection.bind(:counter, Counter)
				
				connection.bind(:objects, connection.objects)
			end
		end
		
		client.connect do |connection|
			counter = connection[:counter].new(10)
			
			10.times do
				counter.make
				GC.start
			end
			
			expect(connection[:objects].size).to be < 10
		end
	end
end
