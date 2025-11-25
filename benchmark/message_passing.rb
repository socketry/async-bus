# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2025, by Samuel Williams.

require "sus/fixtures/benchmark"
require "async/bus/a_server"

describe "Message Passing Performance" do
	include Sus::Fixtures::Benchmark
	include Async::Bus::AServer
	
	let(:array) {Array.new}
	
	before do
		start_server do |connection|
			connection.bind(:array, array)
			connection.bind(:counter, proc{|value| value + 1})
		end
	end
	
	measure "simple method call" do |repeats|
		client.connect do |connection|
			repeats.times do
				connection[:array].size
			end
		end
	end
	
	measure "method call with arguments" do |repeats|
		client.connect do |connection|
			repeats.times do |i|
				connection[:array] << i
			end
		end
	end
	
	measure "method call with return value" do |repeats|
		client.connect do |connection|
			repeats.times do |i|
				result = connection[:array].size
			end
		end
	end
	
	measure "proc invocation" do |repeats|
		client.connect do |connection|
			repeats.times do
				connection[:counter].call(1)
			end
		end
	end
	
	measure "multiple sequential calls" do |repeats|
		client.connect do |connection|
			repeats.times do |i|
				connection[:array] << i
				connection[:array].size
				connection[:array].last
			end
		end
	end
	
	measure "property access" do |repeats|
		client.connect do |connection|
			repeats.times do
				connection[:array].length
			end
		end
	end
end

