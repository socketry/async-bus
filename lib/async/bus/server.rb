# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require_relative "protocol/connection"
require "set"

module Async
	module Bus
		class Server
			def initialize(endpoint = nil)
				@endpoint = endpoint || Protocol.local_endpoint
				@connected = {}
			end
			
			attr :connected
			
			def accept
				@endpoint.accept do |peer|
					connection = Protocol::Connection.server(peer)
					@connected[peer] = connection
					
					yield connection
					
					connection.run
				ensure
					connection = @connected.delete(peer)
					connection&.close
				end
			end
		end
	end
end
