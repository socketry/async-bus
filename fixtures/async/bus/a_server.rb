# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025-2026, by Samuel Williams.

require "async/bus/server"
require "async/bus/client"

require "sus/fixtures/async"
require "io/endpoint/bound_endpoint"
require "tmpdir"

module Async
	module Bus
		AServer = Sus::Shared("a server") do
			include Sus::Fixtures::Async::SchedulerContext
			
			let(:ipc_path) {File.join(@root, "bus.ipc")}
			let(:endpoint) {Async::Bus::Protocol.local_endpoint(ipc_path)}
			
			def around(&block)
				Dir.mktmpdir do |directory|
					@root = directory
					super(&block)
				end
			end
			
			before do
				@bound_endpoint = endpoint.bound
			end
			
			after do
				if server_task = @server_task
					@server_task = nil
					server_task.stop
					server_task.wait
				end
				
				@bound_endpoint&.close
			end
			
			let(:server) {Async::Bus::Server.new(@bound_endpoint)}
			let(:client) {Async::Bus::Client.new(endpoint)}
			
			def start_server
				@server_task = Async do
					server.accept do |connection|
						yield connection
					end
				end
			end
			
			def restart_server
				@server_task&.stop
				
				start_server(&block)
			end
		end
	end
end
