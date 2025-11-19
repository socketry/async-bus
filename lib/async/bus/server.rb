# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require_relative "protocol/connection"
require "set"

module Async
	module Bus
		class Server
			def initialize(endpoint = nil, **options)
				@endpoint = endpoint || Protocol.local_endpoint
				@options = options
			end
			
			def accept
				@endpoint.accept do |peer|
					connection = Protocol::Connection.server(peer, **@options)
					
					yield connection
					
					connection.run
				ensure
					connection&.close
				end
			end
		end
	end
end
