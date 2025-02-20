# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus/server"
require "async/bus/client"

require "sus/fixtures/async"
require "io/endpoint/bound_endpoint"
require "tmpdir"

module Async
	module Bus
		AServer = Sus::Shared("a server") do
			include Sus::Fixtures::Async::ReactorContext
			
			let(:ipc_path) {File.join(@root, "bus.ipc")}
			let(:endpoint) {Async::Bus::Protocol.local_endpoint(ipc_path)}
			
			def around(&block)
				Dir.mktmpdir do |directory|
					@root = directory
					super(&block)
				end
			end
			
			def before
				@bound_endpoint = endpoint.bound
			end
			
			def after(error = nil)
				@bound_endpoint&.close
			end
			
			let(:server) {Async::Bus::Server.new(@bound_endpoint)}
			let(:client) {Async::Bus::Client.new(endpoint)}
		end
	end
end