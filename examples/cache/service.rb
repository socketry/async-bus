#!/usr/bin/env async-service
# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2026, by Samuel Williams.

require "async"
require "async/bus/server"
require "async/bus/client"
require "async/bus/controller"
require "async/service/managed/service"
require "async/service/managed/environment"

# Local cache controller exposed over async-bus.
#
# {#fetch} is the generic entry point: on miss it delegates to {#load_missing},
# which is a dummy placeholder for a real backing store (database, upstream API, etc.).
class CacheController < Async::Bus::Controller
	def initialize
		@store = {}
	end
	
	# Return the cached value for +key+, or compute it via {#load_missing} and store it.
	def fetch(key)
		key = key.to_s
		@store.fetch(key) do
			value = load_missing(key)
			@store[key] = value
			value
		end
	end
	
	# Explicit put (optional; useful for warming or tests).
	def store(key, value)
		key = key.to_s
		@store[key] = value
		value
	end
	
	# Current size of the cache (for logging / metrics).
	def size
		@store.size
	end
	
	# Clear all entries.
	def clear!
		@store.clear
		self
	end
	
	private
	
	# Placeholder for “real” cache miss handling.
	def load_missing(key)
		# In a real service this might query Postgres, call an HTTP API, read from disk, etc.
		"placeholder:#{key}:#{Time.now.to_i}"
	end
end

# Runs the async-bus server and binds a shared {CacheController}.
class CacheServerService < Async::Service::Managed::Service
	def run(instance, evaluator)
		endpoint = evaluator.bus_endpoint
		server = Async::Bus::Server.new(endpoint)
		cache = CacheController.new
		
		Async do
			server.accept do |connection|
				puts "Accepted connection"
				connection.bind(:cache, cache)
			end
		end
		
		return server
	end
	
	private def format_title(evaluator, server)
		"cache-server [#{evaluator.bus_endpoint}]"
	end
end

# Simple worker: connects to the bus and repeatedly fetches keys from the remote cache.
class CacheClientWorkerService < Async::Service::Managed::Service
	def run(instance, evaluator)
		client = Async::Bus::Client.new(evaluator.bus_endpoint)
		keys = evaluator.sample_keys
		
		client.run(transient: false) do |connection|
			cache = connection[:cache] # This returns a proxy, which does RPC to the cache controller service.
			
			loop do
				keys.each do |key|
					value = nil
					
					clock = Async::Clock.measure do
						value = cache.fetch(key)
					end
					
					$stdout.puts "[cache-client] fetch key=#{key.inspect} value=#{value.inspect} size=#{cache.size} time=#{format("%.2fms", clock * 1000.0)}"
				end
				
				sleep(evaluator.pull_interval)
			end
		end
		
		return nil
	end
	
	private def format_title(evaluator, server)
		"cache-client [#{evaluator.bus_endpoint}]"
	end
end

module CacheEnvironment
	include Async::Service::Managed::Environment
	
	def bus_endpoint
		IO::Endpoint.unix(File.expand_path("cache.ipc", root))
	end
	
	# Keys the demo client will request on each pull cycle.
	def sample_keys
		%w[user:1 user:2 config:app]
	end
	
	def pull_interval
		2.0
	end
	
	def count
		1
	end
end

service "cache-server" do
	service_class CacheServerService
	include CacheEnvironment
end

service "cache-client" do
	service_class CacheClientWorkerService
	include CacheEnvironment
end
