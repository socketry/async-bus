# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus"
require "async/bus/a_server"
require "tmpdir"

class WorkerController < Async::Bus::Controller
	def initialize(name)
		@name = name
		@calls = []
	end
	
	def do_work(task)
		@calls << task
		"#{@name} completed #{task}"
	end
	
	attr :calls
end

class ServerController < Async::Bus::Controller
	def initialize
		@workers = {}
	end
	
	def register_worker(worker_id, worker)
		@workers[worker_id] = worker
		"registered #{worker_id}"
	end
	
	def get_worker(worker_id)
		@workers[worker_id]
	end
end

describe Async::Bus::Controller do
	include Async::Bus::AServer
	
	with "multi-hop proxy forwarding" do
		let(:server_controller) {ServerController.new}
		let(:worker_controller) {WorkerController.new("worker-1")}
		let(:worker_registered) {Thread::Queue.new}
		
		before do
			# Main server: Accepts connections from both client and worker
			start_server do |connection|
				connection.bind(:server, server_controller)
			end
			
			# Worker: Connects to main server and registers itself
			@worker_task = Async do
				worker_client = Async::Bus::Client.new(endpoint)
				worker_client.run do |connection|
					server_proxy = connection[:server]
					
					# Register the worker controller with the server
					worker_proxy = connection.bind(:worker, worker_controller)
					result = server_proxy.register_worker("worker-1", worker_proxy)
					expect(result).to be == "registered worker-1"
					
					# Signal that registration is complete:
					worker_registered.push(true)
				end
			end
			
			# Wait for worker to register:
			worker_registered.pop
		end
		
		after do
			@worker_task&.stop
		end
		
		it "can forward proxy from different connection (multi-hop)" do
			# Client: Connects to server, gets proxy to worker controller, and invokes method
			client.connect do |connection|
				server_proxy = connection[:server]
				
				# Get the worker controller proxy from the server
				# This proxy was originally registered by the worker on a different connection
				worker_proxy = server_proxy.get_worker("worker-1")
				
				# Invoke a method on the worker controller
				# This should route back to the worker's connection, even though
				# the proxy was forwarded through the server
				result = worker_proxy.do_work("task-1")
				
				# Verify the call was routed to the original worker controller
				expect(result).to be == "worker-1 completed task-1"
				expect(worker_controller.calls).to be == ["task-1"]
			end
		end
	end
end
