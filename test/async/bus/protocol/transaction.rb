# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

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
	end
end

