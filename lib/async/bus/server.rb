# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require_relative "protocol/connection"
require "set"

# @namespace
module Async
	# @namespace
	module Bus
		# Represents a server that accepts async-bus connections.
		class Server
			# Initialize a new server.
			# @parameter endpoint [IO::Endpoint] The endpoint to listen on.
			# @parameter options [Hash] Additional options for connections.
			def initialize(endpoint = nil, **options)
				@endpoint = endpoint || Protocol.local_endpoint
				@options = options
			end
			
			# Accept incoming connections.
			# @yields {|connection| ...} Block called with each new connection.
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
