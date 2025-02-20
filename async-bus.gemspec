# frozen_string_literal: true

require_relative "lib/async/bus/version"

Gem::Specification.new do |spec|
	spec.name = "async-bus"
	spec.version = Async::Bus::VERSION
	
	spec.summary = "Transparent Ruby IPC over an asynchronous message bus."
	spec.authors = ["Samuel Williams"]
	spec.license = "MIT"
	
	spec.cert_chain  = ["release.cert"]
	spec.signing_key = File.expand_path("~/.gem/release.pem")
	
	spec.homepage = "https://github.com/socketry/async-bus"
	
	spec.metadata = {
		"source_code_uri" => "https://github.com/socketry/async-bus.git",
	}
	
	spec.files = Dir.glob(["{lib}/**/*", "*.md"], File::FNM_DOTMATCH, base: __dir__)
	
	spec.required_ruby_version = ">= 3.1"
	
	spec.add_dependency "async"
	spec.add_dependency "io-endpoint"
	spec.add_dependency "io-stream"
	spec.add_dependency "msgpack"
end
