# Async::Bus

When building distributed systems or multi-process applications, you need a way for processes to communicate and invoke methods on objects in other processes. `async-bus` provides a lightweight message-passing system for inter-process communication (IPC) using Unix domain sockets, enabling transparent remote procedure calls (RPC) where remote objects feel like local objects.

Use `async-bus` when you need:

- **Inter-process communication**: Connect multiple Ruby processes running on the same machine.
- **Transparent RPC**: Call methods on remote objects as if they were local.
- **Type-safe serialization**: Automatically serialize and deserialize Ruby objects using MessagePack.
- **Asynchronous operations**: Non-blocking message passing built on the Async framework.

[![Development Status](https://github.com/socketry/async-bus/workflows/Test/badge.svg)](https://github.com/socketry/async-bus/actions?workflow=Test)

## Usage

Please see the [project documentation](https://socketry.github.io/async-bus/) for more details.

## Releases

Please see the [project releases](https://socketry.github.io/async-bus/releases/index) for all releases.

### v0.2.0

  - Fix handling of temporary objects.

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
