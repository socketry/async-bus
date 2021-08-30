# Async::Bus

Provides a distributed client-server bus for executing Ruby code.

[![Development Status](https://github.com/socketry/supervisor/workflows/Development/badge.svg)](https://github.com/socketry/supervisor/actions?workflow=Development)

## Installation

``` shell
bundle add async-bus
```

## Usage

```ruby
class Counter
	def initialize(count = 0)
		@count = count
	end
	
	attr :count
	
	def increment
		@count += 1
	end
end

server = Async::Bus::Server.new
client = Async::Bus::Client.new

# Server Process
server_task = Async do
	server.accept do |connection|
		connection.bind(:counter, Counter.new)
	end
end

# Client Process
client.connect do |connection|
	3.times do
		connection[:counter].increment
	end
	
	expect(connection[:counter].count).to be == 3
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/\[USERNAME\]/supervisor.
