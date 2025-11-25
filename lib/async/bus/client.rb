# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require_relative "protocol/connection"
require "async/queue"

module Async
	module Bus
		# Represents a client that can connect to a server.
		class Client
			# Initialize a new client.
			# @parameter endpoint [IO::Endpoint] The endpoint to connect to.
			# @parameter options [Hash] Additional options for the connection.
			def initialize(endpoint = nil, **options)
				@endpoint = endpoint || Protocol.local_endpoint
				@options = options
			end
			
			# Create a new connection to the server.
			#
			# @returns [Protocol::Connection] The new connection.
			protected def connect!
				peer = @endpoint.connect
				return Protocol::Connection.client(peer, **@options)
			end
			
			# Called when a connection is established.
			# Override this method to perform setup when a connection is established.
			#
			# @parameter connection [Protocol::Connection] The established connection.
			protected def connected!(connection)
				# Do nothing by default.
			end
			
			# Connect to the server.
			#
			# @parameter persist [Boolean] Whether to keep the connection open indefiniely.
			# @yields {|connection| ...} If a block is given, it will be called with the connection, and the connection will be closed afterwards.
			# @returns [Protocol::Connection] The connection if no block is given.
			def connect(parent: Task.current)
				connection = connect!
				
				connection_task = parent.async do
					connection.run
				end
				
				connected!(connection)
				
				return connection unless block_given?
				
				begin
					yield(connection, connection_task)
				ensure
					connection_task&.stop
					connection&.close
				end
			end
			
			# Run the client in a loop, reconnecting if necessary.
			#
			# Automatically reconnects when the connection fails, with random backoff.
			# This is useful for long-running clients that need to maintain a persistent connection.
			#
			# @parameter parent [Async::Task] The parent task to run under.
			def run(parent: Task.current)
				parent.async(annotation: "Bus Client", transient: true) do |task|
					loop do
						connection = connect!
						
						connected_task = task.async do
							connected!(connection)
						end
						
						connection.run
					rescue => error
						Console.error(self, "Connection failed:", exception: error)
						sleep(rand)
					ensure
						# Ensure any tasks that were created during connection are stopped:
						connected_task&.stop
						
						# Close the connection itself:
						connection&.close
					end
				end
			end
		end
	end
end
