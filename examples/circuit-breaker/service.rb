#!/usr/bin/env async-service
# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "async"
require "async/bus/server"
require "async/bus/client"
require "async/bus/controller"
require "async/service/managed/service"
require "async/service/managed/environment"
require "async/http"
require "protocol/http"
require "falcon"
require "json"

# Circuit breaker controller that can be proxied over async-bus
class CircuitBreakerController < Async::Bus::Controller
	# Circuit breaker states
	CLOSED = :closed
	OPEN = :open
	HALF_OPEN = :half_open
	
	def initialize(failure_threshold: 5, timeout: 60, half_open_max_attempts: 3)
		@state = CLOSED
		@failure_count = 0
		@failure_threshold = failure_threshold
		@timeout = timeout
		@last_failure_time = nil
		@half_open_attempts = 0
		@half_open_max_attempts = half_open_max_attempts
		@success_count = 0
	end
	
	attr :state
	attr :failure_count
	attr :success_count
	
	# Call a protected operation through the circuit breaker
	def call(&block)
		if @state == OPEN
			# Check if timeout has elapsed
			if @last_failure_time && (Time.now - @last_failure_time) >= @timeout
				@state = HALF_OPEN
				@half_open_attempts = 0
			else
				raise "Circuit breaker is OPEN - operation blocked"
			end
		end
		
		begin
			result = yield
			
			# Success - reset failure count
			if @state == HALF_OPEN
				@half_open_attempts += 1
				if @half_open_attempts >= @half_open_max_attempts
					@state = CLOSED
					@failure_count = 0
					@half_open_attempts = 0
				end
			else
				@failure_count = 0
			end
			
			@success_count += 1
			return result
		rescue => error
			@failure_count += 1
			@last_failure_time = Time.now
			
			if @failure_count >= @failure_threshold
				@state = OPEN
			end
			
			raise error
		end
	end
	
	# Reset the circuit breaker
	def reset!
		@state = CLOSED
		@failure_count = 0
		@half_open_attempts = 0
		@last_failure_time = nil
	end
	
	# Get current statistics
	def statistics
		{
			state: @state,
			failure_count: @failure_count,
			success_count: @success_count,
			last_failure_time: @last_failure_time,
		}
	end
end

# Service that runs the async-bus server with circuit breaker
class CircuitBreakerService < Async::Service::Managed::Service
	def run(instance, evaluator)
		endpoint = evaluator.bus_endpoint
		
		server = Async::Bus::Server.new(endpoint)
		circuit_breaker = CircuitBreakerController.new(
			failure_threshold: evaluator.failure_threshold,
			timeout: evaluator.circuit_timeout,
			half_open_max_attempts: evaluator.half_open_max_attempts
		)
		
		Async do |task|
			server.accept do |connection|
				# Bind the circuit breaker controller so clients can access it
				connection.bind(:circuit_breaker, circuit_breaker)
			end
		end
		
		return server
	end
	
	private def format_title(evaluator, server)
		"circuit-breaker [#{evaluator.bus_endpoint}]"
	end
end

# Falcon app that uses the circuit breaker via async-bus
class CircuitBreakerApp
	def initialize(bus_endpoint)
		@bus_endpoint = bus_endpoint
		@client = Async::Bus::Client.new(@bus_endpoint)
		@connection = nil
		@circuit_breaker = nil
	end
	
	def call(request)
		# Ensure we have a connection
		ensure_connection
		
		begin
			# Use circuit breaker to protect an operation
			result = @circuit_breaker.call do
				# Simulate an operation that might fail
				simulate_operation(request)
			end
			
			Protocol::HTTP::Response[200, {"content-type" => "application/json"}, [result]]
		rescue => error
			stats = @circuit_breaker&.statistics || {}
			body = {
				error: error.message,
				circuit_breaker: stats
			}.to_json
			
			Protocol::HTTP::Response[503, {"content-type" => "application/json"}, [body]]
		end
	end
	
	private
	
	def ensure_connection
		unless @connection
			@connection = @client.connect
			@circuit_breaker = @connection[:circuit_breaker]
		end
	rescue
		# If connection fails, try to reconnect
		@connection = nil
		@circuit_breaker = nil
		raise
	end
	
	def simulate_operation(request)
		# Simulate a potentially failing operation
		# In a real app, this would be an external API call, database query, etc.
		if request.path == "/fail"
			raise "Simulated failure"
		end
		
		{
			message: "Operation succeeded",
			timestamp: Time.now.iso8601
		}.to_json
	end
end

# Falcon service that runs the web server
class FalconService < Async::Service::Managed::Service
	def run(instance, evaluator)
		bus_endpoint = evaluator.bus_endpoint
		app = CircuitBreakerApp.new(bus_endpoint)
		
		# Create Falcon server
		server = Falcon::Server.new(
			app,
			Async::HTTP::Endpoint.parse(evaluator.falcon_endpoint)
		)
		
		server.run
		
		return server
	end
	
	private def format_title(evaluator, server)
		"falcon [#{evaluator.falcon_endpoint}]"
	end
end

module CircuitBreakerEnvironment
	include Async::Service::Managed::Environment
	
	def bus_endpoint
		IO::Endpoint.unix(File.expand_path("circuit-breaker.ipc", root))
	end
	
	def falcon_endpoint
		"http://localhost:9292"
	end
	
	def failure_threshold
		5
	end
	
	def circuit_timeout
		60
	end
	
	def half_open_max_attempts
		3
	end
	
	def count
		1
	end
end

# Define the circuit breaker service
service "circuit-breaker" do
	service_class CircuitBreakerService
	include CircuitBreakerEnvironment
end

# Define the Falcon web service
service "falcon" do
	service_class FalconService
	include CircuitBreakerEnvironment
end
