# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async/bus/a_server"
require "stringio"

describe Async::Bus::Protocol::Connection do
	include Async::Bus::AServer
	
	with "#write" do
		it "handles write failures gracefully" do
			# Create a connection with a mock peer that fails on write
			peer = StringIO.new
			expect(peer).to receive(:write).and_raise(IOError, "Write error")
			
			connection = Async::Bus::Protocol::Connection.new(peer, 1)
			
			expect do
				connection.write(Async::Bus::Protocol::Return.new(1, :result))
			end.to raise_exception(IOError, message: be =~ /Write error/)
		end
	end
	
	with "#invoke" do
		it "closes transaction even when write fails" do
			start_server do |connection|
				connection.bind(:test, Object.new)
			end
			
			client.connect do |connection|
				# Mock write to fail
				expect(connection).to receive(:write).and_raise(IOError, "Write error")
				
				expect do
					connection.invoke(:test, [:some_method])
				end.to raise_exception(IOError)
				
				# Transaction should be cleaned up
				expect(connection.transactions).to be(:empty?)
			end
		end
	end
	
	with "#run" do
		it "handles stale messages (responses for non-existent transactions)" do
			# This tests the message handling logic directly
			connection = Async::Bus::Protocol::Connection.new(StringIO.new, 1)
			
			# Create a transaction and close it:
			transaction = connection.transaction!
			transaction.close
			
			# Simulate receiving a stale message:
			stale_response = Async::Bus::Protocol::Return.new(transaction.id, :stale_result)
			
			# The connection's run loop would handle this, but we test the logic directly
			# Since transaction is closed, it should not be in @transactions
			expect(connection.transactions).not.to have_keys(transaction.id)
			
			# If we manually push to a closed transaction's queue, it should be closed
			expect(transaction.received).to be(:closed?)
		end
		
		it "handles invoke for non-existent object" do
			start_server do |connection|
				# Don't bind anything - object doesn't exist.
			end
			
			client.connect do |connection|
				# Try to invoke a method on an object that was never bound
				expect do
					connection[:nonexistent].some_method
				end.to raise_exception(NameError, message: be =~ /Object not found: nonexistent/)
			end
		end
		
		it "handles stale messages arriving after transaction timeout" do
			start_server do |connection|
				service = Object.new
				
				def service.slow_method
					sleep(0.01)
					:result
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				connection.timeout = 0.001
				expect(connection[:service].slow_method).to be_nil
				
				connection.timeout = 0.1
				expect(connection[:service].slow_method).to be == :result
			end
		end
	end
	
	with "#close" do
		it "closes all pending transactions" do
			connection = Async::Bus::Protocol::Connection.new(StringIO.new, 1)
			
			t1 = connection.transaction!
			t2 = connection.transaction!
			
			# Close the connection and thus all transactions:
			connection.close
			
			expect(t1.connection).to be_nil
			expect(t2.connection).to be_nil
			
			expect(t1.received).to be(:closed?)
			expect(t2.received).to be(:closed?)
			expect(connection.transactions).to be(:empty?)
		end
	end
	
	with "#next_id" do
		it "increments id by 2" do
			connection = Async::Bus::Protocol::Connection.new(StringIO.new, 1)
			
			first_id = connection.next_id
			second_id = connection.next_id
			
			expect(second_id).to be == first_id + 2
		end
	end
	
	with "concurrent transactions" do
		it "handles multiple concurrent transactions" do
			start_server do |connection|
				service = Object.new
				def service.slow_method
					sleep(0.01)
					:slow_result
				end
				
				def service.fast_method
					:fast_result
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				# Start multiple concurrent calls
				results = Thread::Queue.new
				
				Async do
					results << connection[:service].slow_method
				end
				
				Async do
					results << connection[:service].fast_method
				end
				
				expect(results.pop).to be == :fast_result
				expect(results.pop).to be == :slow_result
				expect(connection.transactions).to be(:empty?)
			end
		end
	end
	
	with "proxy garbage collection" do
		it "sends release message when proxy is garbage collected" do
			temporary_object = Object.new
			server_connection = nil
			
			# Controller that returns an implicitly bound object
			controller = Class.new(Async::Bus::Controller) do
				def initialize(connection, temporary_object)
					@connection = connection
					@temporary_object = temporary_object
				end
				
				def get_temporary_object
					# Create an implicit binding and return the proxy:
					@connection.proxy(@temporary_object)
				end
			end
			
			start_server do |connection|
				server_connection = connection
				controller_instance = controller.new(connection, temporary_object)
				connection.bind(:controller, controller_instance)
			end
			
			client.connect do |connection|
				controller_proxy = connection[:controller]
				
				# Get the proxy to the temporary object
				temporary_proxy = controller_proxy.get_temporary_object
				name = temporary_proxy.__name__
				
				# Verify the object exists on the server and is marked as temporary
				expect(server_connection.objects).to have_keys(name)
				expect(server_connection.objects[name]).to be(:temporary?)
				
				temporary_proxy = nil
				
				# Give some time for the finalizer to run:
				10.times do
					GC.start
					Fiber.scheduler.yield
					
					# Break as soon as the object is no longer in the server's objects:
					break unless server_connection.objects.key?(name)
				end
				
				expect(server_connection.objects).not.to have_keys(name)
			end
		end
	end
	
	with "#[]=" do
		it "can bind objects explicitly" do
			server_connection = nil
			
			start_server do |connection|
				server_connection = connection
				object = Object.new
				connection[:test] = object
			end
			
			client.connect do |connection|
				# Connect to trigger server's accept block
				expect(server_connection.objects[:test]).to be_a(Async::Bus::Protocol::Connection::Explicit)
				expect(server_connection.objects[:test].object).to be_a(Object)
				expect(server_connection.objects[:test]).not.to be(:temporary?)
			end
		end
	end
	
	with "#run" do
		it "handles unexpected messages" do
			error_logged = false
			error_args = nil
			
			# Intercept Console.error to verify it's called
			original_error = Console.method(:error)
			Console.define_singleton_method(:error) do |*args|
				error_logged = true
				error_args = args
				original_error.call(*args)
			end
			
			begin
				# Create a connection directly with a mock peer
				peer = StringIO.new
				connection = Async::Bus::Protocol::Connection.server(peer)
				connection.bind(:test, Object.new)
				
				# Create an unexpected message object
				unexpected_message = Object.new
				
				# Mock the unpacker to yield the unexpected message
				original_unpacker = connection.instance_variable_get(:@unpacker)
				mock_enumerator = Enumerator.new do |yielder|
					yielder.yield(unexpected_message)
					# Raise to stop the loop
					raise IOError, "End of stream"
				end
				
				connection.instance_variable_set(:@unpacker, mock_enumerator)
				
				# Run the connection in a task
				task = Async do
					begin
						connection.run
					rescue IOError
						# Expected when enumerator raises
					end
				end
				
				# Wait for it to process
				sleep(0.05)
				
				# Stop the task
				task.stop
				
				expect(error_logged).to be_truthy
				expect(error_args).not.to be_nil
			ensure
				# Restore original Console.error
				Console.define_singleton_method(:error, original_error)
			end
		end
		
		it "closes pending transactions in ensure block when run loop exits" do
			transactions_closed_count = 0
			
			# Create a connection directly to test the ensure block
			peer = StringIO.new
			connection = Async::Bus::Protocol::Connection.server(peer)
			
			# Create some transactions manually
			transaction1 = connection.transaction!
			transaction2 = connection.transaction!
			
			# Mock transaction.close to track calls
			[transaction1, transaction2].each do |transaction|
				original_close = transaction.method(:close)
				transaction.define_singleton_method(:close) do
					transactions_closed_count += 1
					original_close.call
				end
			end
			
			# Verify transactions exist
			expect(connection.transactions.size).to be == 2
			
			# Mock the unpacker to immediately raise (simulating connection close)
			# This will trigger the ensure block
			mock_enumerator = Enumerator.new do |yielder|
				raise IOError, "Connection closed"
			end
			
			connection.instance_variable_set(:@unpacker, mock_enumerator)
			
			# Run the connection - it will immediately hit the error and run ensure block
			task = Async do
				begin
					connection.run
				rescue IOError
					# Expected
				end
			end
			
			# Wait for it to process
			sleep(0.05)
			
			# Stop the task
			task.stop
			
			# Verify transactions were closed in ensure block
			expect(transactions_closed_count).to be == 2
			expect(connection.transactions).to be(:empty?)
		end
		
		it "closes pending transactions on connection close" do
			start_server do |connection|
				service = Object.new
				def service.slow_method
					sleep(0.1)
					:result
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				# Start a transaction
				transaction = connection.transaction!
				
				# Start an async call that will take time
				Async do
					connection[:service].slow_method
				end
				
				# Close the connection immediately
				connection.close
				
				# Verify transaction was closed
				expect(transaction.connection).to be_nil
				expect(transaction.received).to be(:closed?)
			end
		end
	end
end

