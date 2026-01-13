# Architecture Overview

## Setup Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                      Single VM                              │
│                                                             │
│  ┌──────────────────────┐    ┌──────────────────────┐     │
│  │   Docker Compose     │    │   K3s Cluster        │     │
│  │                      │    │                      │     │
│  │  ┌──────────────┐    │    │  ┌──────────────┐   │     │
│  │  │ Prometheus   │────┼────┼─→│ node-exporter│   │     │
│  │  │ (Docker)     │    │    │  │ (hostPort    │   │     │
│  │  │              │    │    │  │  9100)       │   │     │
│  │  │              │────┼────┼─→│              │   │     │
│  │  │              │    │    │  └──────────────┘   │     │
│  │  │              │    │    │                      │     │
│  │  │              │────┼────┼─→┌──────────────┐   │     │
│  │  │              │    │    │  │kube-state-   │   │     │
│  │  │              │    │    │  │metrics       │   │     │
│  │  │              │    │    │  │(NodePort     │   │     │
│  │  │              │    │    │  │ 30800)       │   │     │
│  │  │              │────┼────┼─→└──────────────┘   │     │
│  │  │              │    │    │                      │     │
│  │  │              │────┼────┼─→┌──────────────┐   │     │
│  │  │              │    │    │  │ kubelet      │   │     │
│  │  │              │    │    │  │ (port 10250) │   │     │
│  │  └──────────────┘    │    │  └──────────────┘   │     │
│  │                      │    │                      │     │
│  │  ┌──────────────┐    │    │                      │     │
│  │  │   Grafana    │    │    │                      │     │
│  │  │   (Docker)   │    │    │                      │     │
│  │  └──────────────┘    │    │                      │     │
│  │         ↑            │    │                      │     │
│  │         │            │    │                      │     │
│  │         └────────────┼────┼──────────────────────┘     │
│  │                      │    │   (Reads metrics from     │
│  │                      │    │    Prometheus)            │
│  └──────────────────────┘    └──────────────────────┘     │
│                                                             │
│         All services communicate via                        │
│         host.docker.internal (host network)                │
└─────────────────────────────────────────────────────────────┘
```

## Key Points

1. **Docker Compose Stack** (Monitoring Infrastructure):
   - Runs all monitoring services: Elasticsearch, Logstash, Kibana, Prometheus, Grafana
   - Services run in Docker containers on the VM
   - Uses Docker network `monitoring` for inter-container communication

2. **K3s Cluster** (Monitored Infrastructure):
   - Runs separately from Docker Compose
   - Contains your applications and workloads
   - Runs metrics exporters: node-exporter, kube-state-metrics

3. **Communication Flow**:
   - Prometheus (in Docker) scrapes metrics from K3s exporters
   - Uses `host.docker.internal` to access host network
   - `host.docker.internal` resolves to the VM's host IP
   - Enabled via `extra_hosts` in docker-compose.yml

4. **Metrics Endpoints**:
   - **node-exporter**: Exposed on hostPort 9100 → `host.docker.internal:9100`
   - **kube-state-metrics**: NodePort 30800 → `host.docker.internal:30800`
   - **kubelet**: Default port 10250 → `host.docker.internal:10250`

## Network Details

- **Docker Network**: `monitoring` (bridge network)
- **Host Network Access**: Via `host.docker.internal` (configured in docker-compose.yml)
- **K3s Network**: Separate, accessed via host network ports

## Data Flow

1. **Metrics Collection**:
   - K3s exporters (node-exporter, kube-state-metrics, kubelet) expose metrics
   - Prometheus (Docker) scrapes via host network using `host.docker.internal`
   - Metrics stored in Prometheus TSDB

2. **Visualization**:
   - Grafana (Docker) queries Prometheus (Docker) via Docker network
   - Grafana displays dashboards with K3s cluster metrics

3. **Logs** (optional):
   - Filebeat (in K3s) collects logs
   - Sends to Logstash (Docker) via host network
   - Logstash processes and stores in Elasticsearch (Docker)
   - Kibana (Docker) visualizes logs

## Ports Used

| Service | Port | Access |
|---------|------|--------|
| Prometheus | 9090 | VM host:9090 |
| Grafana | 3000 | VM host:3000 |
| Kibana | 5601 | VM host:5601 |
| Elasticsearch | 9200 | VM host:9200 |
| Logstash | 5044 | VM host:5044 |
| node-exporter | 9100 | VM host:9100 (hostPort) |
| kube-state-metrics | 30800 | VM host:30800 (NodePort) |
| kubelet | 10250 | VM host:10250 |
