# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async/bus/a_server"

describe Async::Bus::Client do
	include Async::Bus::AServer
	
	with "#connect" do
		it "can connect to a server" do
			start_server do |connection|
				connection.bind(:test, Object.new)
			end
			
			client.connect do |connection|
				expect(connection).to be_a(Async::Bus::Protocol::Connection)
			end
		end
	end
	
	with "#run" do
		it "can run the client with automatic reconnection" do
			start_server do |connection|
				connection.bind(:test, Object.new)
			end
			
			connections = Thread::Queue.new
			
			client_instance = Class.new(Async::Bus::Client) do
				def initialize(endpoint, connections)
					super(endpoint)
					@connections = connections
				end
				
				protected def connected!(connection)
					@connections.push(connection)
				end
			end.new(endpoint, connections)
			
			client_task = client_instance.run
			
			expect(connections.pop).to be_a(Async::Bus::Protocol::Connection)
		ensure
			client_task.stop
			client_task.wait
		end
		
		it "reconnects after connection failure" do
			connected_count = {value: 0}
			connection_count = {value: 0}

			# Start server, then stop it after first connection
			start_server do |connection|
				connection.bind(:test, Object.new)
				# Close connection after a short time to simulate failure
				reactor.sleep(0.01)
				connection.close
			end
			
			client_instance = Class.new(Async::Bus::Client) do
				def initialize(endpoint, connected_count, connection_count)
					super(endpoint)
					@connected_count = connected_count
					@connection_count = connection_count
				end
				
				protected def connect!
					@connection_count[:value] += 1
					super
				end
				
				protected def connected!(connection)
					@connected_count[:value] += 1
				end
			end.new(endpoint, connected_count, connection_count)
			
			client_task = client_instance.run
			
			# Wait for initial connection
			reactor.sleep(0.02)
			
			# Stop server to force disconnection
			@server_task.stop
			
			# Wait a bit for reconnection attempts
			reactor.sleep(0.05)
			
			# Should have attempted multiple connections
			expect(connection_count[:value]).to be >= 2
			
			client_task.stop
		end
		
		it "does not leak tasks when connected! creates tasks and reconnection occurs" do
			events = Thread::Queue.new

			start_server do |connection|
				connection.bind(:test, Object.new)
			end
			
			client_instance = Class.new(Async::Bus::Client) do
				def initialize(endpoint, events)
					super(endpoint)
					@events = events
				end
				
				protected def connected!(connection)
					@events.push(:connected)
					
					Async do
						sleep
					ensure
						@events.push(:disconnected)
					end
				end
			end.new(endpoint, events)
			
			client_task = client_instance.run
			
			# Wait for initial connection
			expect(events.pop).to be == :connected
			
			# Stop server to force reconnection
			@server_task.stop
			
			# Wait for disconnection
			expect(events.pop).to be == :disconnected
			
			# Wait for reconnection
			expect(events.pop).to be == :connected
			
			client_task.stop
		end
		
		it "handles connection errors gracefully" do
			error_count = {value: 0}

			start_server do |connection|
				connection.bind(:test, Object.new)
			end
			
			client_instance = Class.new(Async::Bus::Client) do
				def initialize(endpoint, error_count)
					super(endpoint)
					@error_count = error_count
				end
				
				protected def connect!
					@error_count[:value] += 1
					# Fail first attempt, succeed on retry
					raise IOError, "Connection failed" if @error_count[:value] == 1
					super
				end
			end.new(endpoint, error_count)
			
			client_task = client_instance.run
			
			# Wait for reconnection after initial failure
			# The first attempt fails, sleeps (rand, so 0-1 seconds), then retries
			# Wait up to 1.5 seconds to account for random sleep (max 1 second) + retry time
			start_time = Time.now
			while error_count[:value] < 2 && (Time.now - start_time) < 1.5
				reactor.sleep(0.05)
			end
			
			# Should have attempted reconnection after error
			# First attempt fails (error_count = 1), then retries (error_count = 2)
			expect(error_count[:value]).to be >= 2
			
			client_task.stop
		end
	end
end
