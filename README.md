# exporter_proxy

exporter_proxy lets Prometheus scrape several exporters through one shared network endpoint. Each exporter has its own public metrics path, which forwards requests to its configured upstream URL. This is useful when opening separate ports for every exporter is difficult.

The Go service combines configuration loading and validation, reverse proxy routing, listener management, and optional access and error logging. It supports HTTPS for incoming connections, HTTPS upstreams, inherited listeners through server_starter, and graceful shutdown on SIGTERM.

## Getting started

You need reachable exporter endpoints and a Prometheus instance able to reach the proxy. To build from source, install Go matching the repository's module requirements, Git, and Make; dependency downloads require network access.

From the repository root:

```sh
make build
```

Prepare your own YAML configuration using the [annotated configuration example](config.example.yml). Set the listening address and map each public metrics path to an exporter URL. Replace the sample destinations, remove the example TLS section unless you supply readable certificate and key files, and choose writable log destinations if logging to files.

From the repository root, start the built executable with your prepared configuration:

```sh
./bin/exporter_proxy -config config.yml
```

This starts a network listener and may create or append configured log files. Request one of your configured public metrics paths and confirm that it returns the intended exporter's metrics. In Prometheus, configure a separate scrape job for each exporter, using the shared proxy address as the target and that exporter's public path as its `metrics_path`.

## Example proxy and scrape configuration

The following example maps two exporters through the same proxy listener.


```
listen: "0.0.0.0:9099"

exporters:
  node_exporter:
    path: "/node_exporter/metrics"
    url: "http://localhost:9100/metrics"
  mysqld_exporter:
    path: "/mysqld_exporter/metrics"
    url: "http://localhost:9104/metrics"
```

When you access `http://exporter_proxy_host:9099/node_exporter/metrics`, returns the metrics collected by `node_exporter`.

And of course, `http://exporter_proxy_host:9099/mysqld_exporter/metrics` returns the metrics collected by` mysqld_exporter`.

The part of your `prometheus.yml` is probably as follows.

```
scrape_configs:
  - job_name: "node"
    metrics_path: /node_exporter/metrics
    static_configs:
      - targets: ["exporter_proxy_host:9099"]
  - job_name: "mysqld"
    metrics_path: /mysqld_exporter/metrics
    static_configs:
      - targets: ["exporter_proxy_host:9099"]
```

## Configuration and operation

The annotated example covers listener selection, TLS, LTSV access logging, error logging, and shutdown timing. Keep upstream certificate verification enabled; the self-signed demonstration explicitly disables it. Allow the proxy to reach each upstream and the service account to read any configured TLS material.

The original distribution options are [upstream binaries](https://github.com/rrreeeyyy/exporter_proxy/releases) and the Docker image `rrreeeyyy/exporter_proxy`. The [container demonstration](example/docker-compose.yml) illustrates exporter connectivity and mounted configuration, but its startup setup and the repository's container build need correction before use. Original upstream configuration references remain available for [standalone use](https://github.com/rrreeeyyy/exporter_proxy/blob/master/config.example.yml) and [container use](https://github.com/rrreeeyyy/exporter_proxy/blob/master/example/config/config.yml).

## Development checks

From the repository root, `make test` runs startup and invalid-configuration tests. It builds a temporary executable and starts a local listener, so the configured listening address must be available. `make test-short` skips these integration tests.

## License

[MIT License](LICENSE), Copyright (c) 2017 Yoshikawa Ryota.
