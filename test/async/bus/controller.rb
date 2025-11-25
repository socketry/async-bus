# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async/bus"
require "async/bus/a_server"

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
	end
end

