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
end

