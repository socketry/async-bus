# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/a_server"

describe Async::Bus::Protocol::Proxy do
	include Async::Bus::AServer
	
	with "operators" do
		it "can use logical negation operator" do
			start_server do |connection|
				service = Object.new
				def service.!
					false
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				proxy = connection[:service]
				result = !proxy
				
				expect(result).to be == false
			end
		end
	end
	
	with "#respond_to_missing?" do
		it "can check if remote object responds to method" do
			start_server do |connection|
				service = Object.new
				def service.test_method
					:result
				end
				
				connection.bind(:service, service)
			end
			
			client.connect do |connection|
				proxy = connection[:service]
				
				# Call respond_to_missing? using instance_eval since Proxy inherits from BasicObject
				# which doesn't have send/__send__/method
				# (respond_to? is defined on Proxy, so Ruby won't call respond_to_missing? automatically)
				result1 = proxy.instance_eval { respond_to_missing?(:test_method, false) }
				result2 = proxy.instance_eval { respond_to_missing?(:nonexistent_method, false) }
				
				expect(result1).to be == true
				expect(result2).to be == false
			end
		end
	end
end

