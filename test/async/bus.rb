# frozen_string_literal: true

# Released under the MIT License.
# Copyright, 2021-2025, by Samuel Williams.

require "async/bus"

describe Async::Bus do
	it "has a version number" do
		expect(Async::Bus::VERSION).to be =~ /\d+\.\d+\.\d+/
	end
end
