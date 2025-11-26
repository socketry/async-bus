# Circuit Breaker Demo

This example demonstrates a circuit breaker pattern implemented using `async-bus` to share state between services, with a Falcon web server connecting to the circuit breaker via async-bus.

## Architecture

The example consists of two managed services:

1. **Circuit Breaker Service** - Runs an `Async::Bus::Server` that exposes a `CircuitBreakerController` for remote access
2. **Falcon Service** - Runs a Falcon web server that connects to the circuit breaker via `Async::Bus::Client`

Both services share the same environment configuration and use `Async::Service::Managed::Service` for robust lifecycle management.

## Features

- **Circuit Breaker Pattern**: Implements CLOSED, OPEN, and HALF_OPEN states
- **Shared State**: Circuit breaker state is shared across all Falcon instances via async-bus
- **Managed Services**: Both services use `Async::Service::Managed::Service` for health checking and process management
- **Falcon Integration**: Web server connects to circuit breaker as an async-bus client

## Running

Make the service executable and run it:

```bash
./service.rb
```

This will start both services:
- Circuit breaker bus server on a Unix socket
- Falcon web server on `http://localhost:9292`

## Testing

### Successful Requests

```bash
curl http://localhost:9292/
```

Returns:
```json
{"message":"Operation succeeded","timestamp":"2025-01-XX..."}
```

### Simulating Failures

```bash
curl http://localhost:9292/fail
```

This simulates a failure. After 5 consecutive failures (configurable via `failure_threshold`), the circuit breaker opens and blocks operations.

### Circuit Breaker States

- **CLOSED**: Normal operation, requests pass through
- **OPEN**: Circuit is open, requests are blocked immediately
- **HALF_OPEN**: After timeout period, allows limited attempts to test recovery

### Checking Circuit Breaker Status

When the circuit breaker is open, requests return a 503 status with circuit breaker statistics:

```json
{
  "error": "Circuit breaker is OPEN - operation blocked",
  "circuit_breaker": {
    "state": "open",
    "failure_count": 5,
    "success_count": 0,
    "last_failure_time": "2025-01-XX..."
  }
}
```

## Configuration

The circuit breaker can be configured via the environment:

- `failure_threshold`: Number of failures before opening (default: 5)
- `circuit_timeout`: Seconds before transitioning from OPEN to HALF_OPEN (default: 60)
- `half_open_max_attempts`: Successful attempts needed to close from HALF_OPEN (default: 3)

## How It Works

1. The circuit breaker service creates a `CircuitBreakerController` and exposes it via async-bus
2. Falcon service connects to the bus server and gets a proxy to the circuit breaker
3. Each HTTP request uses the circuit breaker to protect operations
4. Failures increment the failure count; after threshold, circuit opens
5. After timeout, circuit transitions to half-open for testing
6. Successful operations in half-open state eventually close the circuit

This demonstrates how async-bus enables transparent remote procedure calls, allowing multiple services to share state and coordinate behavior.
