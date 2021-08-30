
require_relative "lib/async/bus/version"

Gem::Specification.new do |spec|
	spec.name = "async-bus"
	spec.version = Async::Bus::VERSION
	
	spec.summary = "Transparent Ruby IPC over an asynchronous message bus."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.homepage = "https://github.com/socketry/async-bus"
	
	spec.files = Dir.glob('{lib}/**/*', File::FNM_DOTMATCH, base: __dir__)
	
	spec.add_dependency "async"
	spec.add_dependency "msgpack"
	
	spec.add_development_dependency "rspec"
	spec.add_development_dependency "async-rspec"
end
