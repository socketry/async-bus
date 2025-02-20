# Async::Bus

Provides a distributed client-server bus for executing Ruby code.

[![Development Status](https://github.com/socketry/async-bus/workflows/Test/badge.svg)](https://github.com/socketry/async-bus/actions?workflow=Test)

## Installation

``` shell
bundle add async-bus
```

## Usage

``` ruby
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
	
	puts connection[:counter].count
	# => 3
end
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake spec` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and the created tag, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

We welcome contributions to this project.

1.  Fork it.
2.  Create your feature branch (`git checkout -b my-new-feature`).
3.  Commit your changes (`git commit -am 'Add some feature'`).
4.  Push to the branch (`git push origin my-new-feature`).
5.  Create new Pull Request.

### Developer Certificate of Origin

In order to protect users of this project, we require all contributors to comply with the [Developer Certificate of Origin](https://developercertificate.org/). This ensures that all contributions are properly licensed and attributed.

### Community Guidelines

This project is best served by a collaborative and respectful environment. Treat each other professionally, respect differing viewpoints, and engage constructively. Harassment, discrimination, or harmful behavior is not tolerated. Communicate clearly, listen actively, and support one another. If any issues arise, please inform the project maintainers.
