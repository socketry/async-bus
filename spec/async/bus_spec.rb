# frozen_string_literal: true

RSpec.describe Async::Bus do
	it "has a version number" do
		expect(Async::Bus::VERSION).not_to be nil
	end
end
