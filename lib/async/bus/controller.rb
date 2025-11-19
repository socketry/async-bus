# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

module Async
	module Bus
		# Base class for controller objects designed to be proxied over Async::Bus.
		#
		# Controllers provide an explicit API for remote operations, avoiding the
		# confusion that comes from proxying generic objects like Array or Hash.
		#
		# @example Array Controller
		#   class ArrayController < Async::Bus::Controller
		#     def initialize(array)
		#       @array = array
		#     end
		#
		#     def append(*values)
		#       @array.concat(values)
		#       self  # Return self for chaining
		#     end
		#
		#     def get(index)
		#       @array[index]  # Returns value
		#     end
		#
		#     def size
		#       @array.size
		#     end
		#   end
		#
		# @example Server Setup
		#   server.accept do |connection|
		#     array = []
		#     controller = ArrayController.new(array)
		#     connection.bind(:items, controller)
		#   end
		#
		# @example Client Usage
		#   client.connect do |connection|
		#     items = connection[:items]  # Returns proxy to controller
		#     items.append(1, 2, 3)       # Remote call
		#     expect(items.size).to be == 3
		#   end
		#
		# Controllers are automatically proxied when serialized if registered
		# as a reference type in the Wrapper:
		#
		#   Wrapper.new(connection, reference_types: [Async::Bus::Controller])
		#
		# This allows controller methods to return other controllers and have
		# them automatically proxied.
		class Controller
		end
	end
end

