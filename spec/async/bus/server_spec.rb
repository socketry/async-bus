# frozen_string_literal: true

require 'async/bus/server'
require 'async/bus/client'

class Counter
	def initialize(count = 0)
		@count = count
	end
	
	attr :count
	
	def increment
		@count += 1
	end
end

RSpec.describe Async::Bus::Server do
	include_context Async::RSpec::Reactor
	
	it "can receive incoming clients" do
		server = Async::Bus::Server.new
		client = Async::Bus::Client.new
		
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
end
