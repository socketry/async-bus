# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require_relative "protocol/connection"
require "async/queue"

module Async
	module Bus
		class Client
			def initialize(endpoint = nil)
				@endpoint = endpoint || Protocol.local_endpoint
			end
			
			# @parameter persist [Boolean] Whether to keep the connection open indefiniely.
			def connect(persist = false)
				@endpoint.connect do |peer|
					connection = Protocol::Connection.client(peer)
					
					connection_task = Async do
						connection.run
					end
					
					yield(connection) if block_given?
					
					if persist
						connection_task.wait
					end
				ensure
					connection_task&.stop
				end
			end
		end
	end
end
