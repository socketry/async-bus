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
end

