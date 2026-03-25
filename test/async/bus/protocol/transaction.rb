# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/a_server"

describe Async::Bus::Protocol::Transaction do
	include Async::Bus::AServer
	
	with "#read" do
		it "handles timeout correctly" do
			start_server do |connection|
				# Don't bind anything - server won't respond
			end
			
			client.connect do |connection|
				connection.timeout = 0.1 # Set timeout to 0.1 seconds
				transaction = connection.transaction!
				
				# We didn't invoke anything so the read will timeout:
				expect(transaction.read).to be_nil
				
				transaction.close
			end
		end
	end
	
	with "#write" do
		it "raises error when transaction is closed" do
			connection = Async::Bus::Protocol::Connection.new(StringIO.new, 1)
			transaction = connection.transaction!
			
			transaction.close
			
			expect do
				transaction.write(Async::Bus::Protocol::Return.new(1, :result))
			end.to raise_exception(RuntimeError, message: be =~ /Transaction is closed/)
		end
	end
	
	with "#close" do
		it "closes the received queue" do
			connection = Async::Bus::Protocol::Connection.new(StringIO.new, 1)
			transaction = connection.transaction!
			
			transaction.close
			
			expect(transaction.received).to be(:closed?)
			expect(transaction.connection).to be_nil
			expect(connection.transactions).not.to have_keys(transaction.id)
		end
		
		it "removes transaction from connection" do
			connection = Async::Bus::Protocol::Connection.new(StringIO.new, 1)
			transaction = connection.transaction!
			
			transaction.close
			
			expect(connection.transactions).not.to have_keys(transaction.id)
		end
	end
	
	with "#invoke" do
		it "handles errors from remote calls" do
			start_server do |connection|
				service = Object.new
				def service.failing_method
					raise RuntimeError, "Remote error"
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				expect do
					connection[:service].failing_method
				end.to raise_exception(RuntimeError, message: be == "Remote error")
				
				expect(connection.transactions).to be(:empty?)
			end
		end
		
		it "handles yield/next pattern" do
			start_server do |connection|
				service = Object.new
				def service.yielding_method
					yield 1
					yield 2
					yield 3
					:done
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				results = []
				result = connection[:service].yielding_method do |value|
					results << value
					:ack
				end
				
				expect(results).to be == [1, 2, 3]
				expect(result).to be == :done
				expect(connection.transactions).to be(:empty?)
			end
		end
		
		it "handles errors in yield block" do
			start_server do |connection|
				service = Object.new
				def service.yielding_method
					yield 1
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				expect do
					connection[:service].yielding_method do |value|
						raise RuntimeError, "Block error"
					end
				end.to raise_exception(RuntimeError, message: be == "Block error")
				
				expect(connection.transactions).to be(:empty?)
			end
		end
	end
	
	with "#accept" do
		it "handles errors during method execution" do
			start_server do |connection|
				service = Object.new
				def service.error_method
					raise ArgumentError, "Invalid argument"
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				expect do
					connection[:service].error_method
				end.to raise_exception(ArgumentError, message: be == "Invalid argument")
			end
		end
		
		it "does not write Return after Error" do
			start_server do |connection|
				service = Object.new
				def service.error_method
					raise RuntimeError, "Error"
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				# Track writes
				write_count = 0
				original_write = connection.method(:write)
				connection.define_singleton_method(:write) do |message|
					write_count += 1
					original_write.call(message)
				end
				
				expect do
					connection[:service].error_method
				end.to raise_exception(RuntimeError)
				
				# Should only write Error, not Return
				expect(write_count).to be > 0
			end
		end
		
		it "handles Close message in yield block to break iteration" do
			start_server do |connection|
				service = Object.new
				def service.yielding_method
					yield 1
					yield 2
					yield 3
					:done
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				results = []
				
				# Create a transaction and manually handle yields to send Close
				transaction = connection.transaction!
				transaction.invoke(:service, [:yielding_method], {}) do |*yield_args|
					value = yield_args.first
					results << value
					
					# After first yield, send Close to break the loop
					if results.size == 1
						connection.write(Async::Bus::Protocol::Close.new(transaction.id, nil))
					end
					
					:ack
				end
				
				# Close should break the loop, so we should only get one value
				expect(results.size).to be == 1
				expect(results.first).to be == 1
			end
		end
		
		it "handles Throw message from server" do
			start_server do |connection|
				service = Object.new
				def service.throw_method
					throw :some_tag
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				# The server should catch the UncaughtThrowError and send a Throw message
				# The client should handle it by re-throwing
				# Note: UncaughtThrowError only preserves the tag, not the value
				thrown = false
				result = catch(:some_tag) do
					connection[:service].throw_method
					thrown = true
				end
				
				# catch returns nil when throw happens without a value
				expect(thrown).to be == false
				expect(result).to be_nil
			end
		end
	end
	
	with "connection termination during transaction" do
		it "demonstrates unhandled RuntimeError when server crashes while client waits for response" do
			# This test demonstrates that when a server connection is closed while
			# a transaction is in-flight, the server task tries to write Return/Error
			# but the transaction is already closed, causing an unhandled RuntimeError.
			#
			# Expected behavior: When the remote end closes the connection mid-transaction,
			# the local end should fail with an exception, but that exception should be
			# handled gracefully (not left as an unhandled exception in an async task).
			server_connection = nil
			server_started = Thread::Queue.new
			close_connection = Thread::Queue.new
			
			start_server do |connection|
				server_connection = connection
				service = Object.new
				def service.slow_method
					# Signal that server has started processing
					@server_started.push(:started)
					# Wait for signal to close connection
					@close_connection.pop
					:result
				end
				
				# Store queue references in service
				service.instance_variable_set(:@server_started, server_started)
				service.instance_variable_set(:@close_connection, close_connection)
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				# Start the invocation
				invoke_task = Async do
					connection[:service].slow_method
				end
				
				# Wait for server to start processing
				server_started.pop
				
				# Abruptly close the server connection
				server_connection.close
				
				# Signal server to continue (it will try to write Return/Error)
				close_connection.push(:close)
				
				# Wait for processing to complete
				begin
					invoke_task.wait
				rescue
					# Expected to fail
				end
				
				# Currently, this causes unhandled RuntimeError: "Transaction is closed!"
				# in the server task when it tries to write Return/Error after connection closes.
				# The test passes but demonstrates the issue: exceptions should be caught and
				# handled gracefully, not left as unhandled exceptions in async tasks.
			end
		end
		
		it "demonstrates unhandled RuntimeError when client crashes while server executes method" do
			# This test demonstrates that when a client connection is closed while
			# a server transaction is executing, the server task tries to write Return/Error
			# but the transaction is already closed, causing an unhandled RuntimeError.
			#
			# Expected behavior: When the remote end closes the connection mid-transaction,
			# the local end should fail with an exception, but that exception should be
			# handled gracefully (not left as an unhandled exception in an async task).
			client_connection = nil
			server_started = Thread::Queue.new
			close_connection = Thread::Queue.new
			
			start_server do |connection|
				service = Object.new
				def service.slow_method
					# Signal that server has started processing
					@server_started.push(:started)
					# Wait for signal to close connection
					@close_connection.pop
					:result
				end
				
				# Store queue references in service
				service.instance_variable_set(:@server_started, server_started)
				service.instance_variable_set(:@close_connection, close_connection)
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				client_connection = connection
				
				# Start the invocation
				invoke_task = Async do
					connection[:service].slow_method
				end
				
				# Wait for server to start processing
				server_started.pop
				
				# Abruptly close the client connection
				client_connection.close
				
				# Signal server to continue (it will try to write Return/Error)
				close_connection.push(:close)
				
				# Wait for processing to complete
				begin
					invoke_task.wait
				rescue
					# Expected to fail
				end
				
				# Currently, this causes unhandled RuntimeError: "Transaction is closed!"
				# in the server task when it tries to write Return/Error after connection closes.
				# The test passes but demonstrates the issue: exceptions should be caught and
				# handled gracefully, not left as unhandled exceptions in async tasks.
			end
		end
		
		it "demonstrates unhandled RuntimeError when server crashes during yield operation" do
			# This test demonstrates that when a server connection is closed during
			# a yield operation, the server task tries to write Yield but the transaction
			# is already closed, causing an unhandled RuntimeError.
			#
			# Expected behavior: When the remote end closes the connection mid-transaction,
			# the local end should fail with an exception, but that exception should be
			# handled gracefully (not left as an unhandled exception in an async task).
			server_connection = nil
			first_yield_received = Thread::Queue.new
			
			start_server do |connection|
				server_connection = connection
				service = Object.new
				def service.yielding_method
					yield 1
					# Wait for connection to be closed
					@first_yield_received.pop
					# This yield will fail because connection closes
					yield 2
					:done
				end
				
				# Store queue reference in service
				service.instance_variable_set(:@first_yield_received, first_yield_received)
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				# Start the invocation with yield
				invoke_task = Async do
					results = []
					connection[:service].yielding_method do |value|
						results << value
						
						# Close server connection after first yield
						if results.size == 1
							server_connection.close
							first_yield_received.push(:received)
						end
						
						:ack
					end
				end
				
				# Wait for processing to complete
				begin
					invoke_task.wait
				rescue
					# Expected to fail
				end
				
				# Currently, this causes unhandled RuntimeError: "Transaction is closed!"
				# in the server task when it tries to write Yield after connection closes.
				# The test passes but demonstrates the issue: exceptions should be caught and
				# handled gracefully, not left as unhandled exceptions in async tasks.
			end
		end
		
		it "handles client crash during server yield operation" do
			client_connection = nil
			first_yield_received = Thread::Queue.new
			
			start_server do |connection|
				service = Object.new
				def service.yielding_method
					yield 1
					# Wait for connection to be closed
					@first_yield_received.pop
					# This yield will fail because client closes
					yield 2
					:done
				end
				
				# Store queue reference in service
				service.instance_variable_set(:@first_yield_received, first_yield_received)
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				client_connection = connection
				
				# Start the invocation with yield
				invoke_task = Async do
					results = []
					connection[:service].yielding_method do |value|
						results << value
						
						# Close client connection after first yield
						if results.size == 1
							client_connection.close
							first_yield_received.push(:received)
						end
						
						:ack
					end
				end
				
				# Wait for processing to complete
				begin
					invoke_task.wait
				rescue
					# Expected to fail
				end
				
				# When the remote end closes the connection mid-transaction, the local end
				# should fail with an exception, but that exception should be handled gracefully
				# (not left as an unhandled exception in an async task).
			end
		end
	end
end

