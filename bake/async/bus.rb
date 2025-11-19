# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

def server
	require "async"
	require "async/bus/server"
	
	Async do
		server = Async::Bus::Server.new
		things = Array.new
		
		server.accept do |connection|
			connection[:things] = things
		end
	end
end

def client
	require "async"
	require "async/bus/client"
	
	Async do
		client = Async::Bus::Client.new
		
		client.connect do |connection|
			binding.irb
		end
	end
end
