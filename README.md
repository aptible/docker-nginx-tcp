# ![](https://gravatar.com/avatar/11d3bc4c3163e3d238d558d5c9d98efe?s=64) aptible/nginx-tcp

NGiNX TCP reverse proxy server.

## Usage

The proxy is configured via the `PROXY_CONFIGURATION` configuration. Its
structure should look like this:

```
[
  [
    LISTENER_PORT,
    [
      [UPSTREAM_HOST, UPSTREAM_PORT] (UPSTREAM), (UPSTREAM), ...
    ]
  ] (LISTENER), (LISTENER), ...
]
```

Additionally, the `IDLE_TIMEOUT` controls the proxy idle timeout, in seconds.

## Copyright and License

MIT License, see [LICENSE](LICENSE.md) for details.

Copyright (c) 2019 [Aptible](https://www.aptible.com) and contributors.
