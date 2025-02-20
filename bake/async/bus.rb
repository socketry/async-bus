
def server
	require "async"
	require "async/bus/server"
	
	Async do
		server = Async::Bus::Server.new
		
		server.accept do |connection|
			binding.irb
		end
	end
end

def client
	require "async"
	require "async/bus/client"
	
	Async do
		client = Async::Bus::Client.new
		
		client.connect do |connection|
			binding.irb
		end
	end
end
