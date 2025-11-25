# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus"
require "async/bus/a_server"
require "tmpdir"

class TestArrayController < Async::Bus::Controller
	def initialize(array)
		@array = array
	end
	
	def append(*values)
		@array.concat(values)
		self
	end
	
	def get(index)
		@array[index]
	end
	
	def size
		@array.size
	end
	
	def subset(start, length)
		TestArrayController.new(@array[start, length])
	end
end

describe Async::Bus::Controller do
	include Async::Bus::AServer
	
	with "reference_types: [Async::Bus::Controller]" do
		let(:server_instance) {Async::Bus::Server.new(@bound_endpoint)}
		let(:client_instance) {Async::Bus::Client.new(endpoint)}
		
		with "an ArrayController" do
			let(:array) {[]}
			
			def before
				super
				
				@server_task = Async do
					server_instance.accept do |connection|
						controller = TestArrayController.new(array)
						connection.bind(:items, controller)
					end
				end
			end
			
			def after(error = nil)
				@server_task.stop
				super
			end
			
			it "can append items" do
				client_instance.connect do |connection|
					items = connection[:items]
					items.append(1, 2, 3)
				end
				
				expect(array).to be == [1, 2, 3]
			end
			
			it "can chain append operations" do
				client_instance.connect do |connection|
					items = connection[:items]
					items.append(1).append(2).append(3)
				end
				
				expect(array).to be == [1, 2, 3]
			end
			
			it "can get size" do
				array << 1 << 2 << 3
				
				client_instance.connect do |connection|
					items = connection[:items]
					expect(items.size).to be == 3
				end
			end
			
			it "can return a controller that is auto-proxied" do
				array << 1 << 2 << 3 << 4 << 5
				
				client_instance.connect do |connection|
					items = connection[:items]
					subset = items.subset(0, 3)  # Returns controller, auto-proxied
					
					expect(subset.size).to be == 3
					subset.append(99)  # Chaining works on returned controller
					expect(subset.size).to be == 4
				end
			end
		end
		
		with "a controller that accepts a proxy as an argument" do
			class RegistrationController < Async::Bus::Controller
				def initialize
					@registered = []
				end
				
				attr :registered
				
				def register(worker, id:)
					@registered << {worker: worker, id: id}
					true
				end
			end
			
			class WorkerController < Async::Bus::Controller
				def hello
					"hello"
				end
			end
			
			let(:registration_controller) {RegistrationController.new}
			
			def before
				super
				
				@server_task = Async do
					server_instance.accept do |connection|
						connection.bind(:registration, registration_controller)
					end
				end
			end
			
			def after(error = nil)
				@server_task.stop
				super
			end
			
			it "can pass a proxy as an argument" do
				client_instance.connect do |connection|
					registration = connection[:registration]
					
					worker_controller = WorkerController.new
					worker_proxy = connection.bind(:worker, worker_controller)
					
					result = registration.register(worker_proxy, id: "worker-1")
					
					expect(result).to be == true
					expect(registration_controller.registered.size).to be == 1
					expect(registration_controller.registered.first[:id]).to be == "worker-1"
				end
			end
		end
		
		with "round-trip proxy behavior" do
			class EchoController < Async::Bus::Controller
				def initialize
					@value = 0
				end
				
				def increment
					@value += 1
					@value
				end
				
				def get_value
					@value
				end
				
				def echo(controller)
					# When a proxy is sent back to its origin, it should resolve to the actual object
					# not a broken proxy pointing in the wrong direction.
					# This allows round-trip scenarios to work correctly.
					controller.get_value
				end
			end
			
			let(:echo_controller) {EchoController.new}
			
			def before
				super
				
				@server_task = Async do
					server_instance.accept do |connection|
						connection.bind(:echo, echo_controller)
					end
				end
			end
			
			def after(error = nil)
				@server_task.stop
				super
			end
			
			it "can send a controller proxy and receive it back as the actual object" do
				client_instance.connect do |connection|
					echo = connection[:echo]
					
					# Get a proxy to the server's controller
					server_controller_proxy = echo
					
					# Increment the value on the server
					echo.increment
					expect(echo.get_value).to be == 1
					
					# Send the proxy back to the server.
					# The server should receive the actual object (not a broken proxy),
					# because connection[] checks for locally bound objects first.
					result = echo.echo(server_controller_proxy)
					
					# The server should be able to call methods on the received object
					expect(result).to be == 1
					
					# Verify the server's controller still works
					echo.increment
					expect(echo.get_value).to be == 2
				end
			end
		end
		
	end
end

