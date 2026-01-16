# ELK + Prometheus + Grafana Stack for K3s Monitoring

This stack provides comprehensive monitoring for your K3s cluster with:
- **ELK Stack**: Log aggregation (Elasticsearch, Logstash, Kibana)
- **Prometheus**: Metrics collection
- **Grafana**: Visualization and dashboards

## Architecture

**Important**: This stack runs entirely via Docker Compose (NOT in Kubernetes).
- All services (Elasticsearch, Logstash, Kibana, Prometheus, Grafana) run in Docker containers
- The K3s cluster runs separately on the same VM
- Prometheus (in Docker) scrapes metrics from K3s exporters via the host network
- Both Docker Compose and Kubernetes run on the same VM

## Prerequisites

- Docker and Docker Compose installed
- K3s cluster running on the same VM as Docker
- `kubectl` configured to access your K3s cluster

## Setup Instructions

### 1. Deploy Metrics Exporters to K3s

First, deploy the required metrics exporters to your K3s cluster:

```bash
# Create monitoring namespace
kubectl apply -f k8s/namespace.yaml

# Deploy Node Exporter (for node-level metrics)
kubectl apply -f k8s/node-exporter.yaml

# Deploy kube-state-metrics (for Kubernetes object metrics)
kubectl apply -f k8s/kube-state-metrics.yaml

# Verify deployments
kubectl get pods -n monitoring
kubectl get svc -n monitoring
```

Expected output:
- `node-exporter-*` pods running (DaemonSet, one per node)
- `kube-state-metrics-*` pod running
- `kube-state-metrics` service with NodePort 30800

### 2. Verify Node Exporter is Accessible

Node Exporter runs on hostPort 9100. Verify it's accessible from your host:

```bash
curl http://localhost:9100/metrics
```

### 3. Verify kube-state-metrics is Accessible

kube-state-metrics is exposed via NodePort 30800. Verify it's accessible:

```bash
curl http://localhost:30800/metrics
```

### 4. Start the Stack

```bash
docker-compose up -d
```

Wait a few moments for all services to start, then verify:

```bash
docker-compose ps
```

### 5. Verify Prometheus is Scraping

1. Open Prometheus UI: http://localhost:9090
2. Go to Status → Targets
3. Verify all targets are UP:
   - `prometheus` (self-monitoring)
   - `node-exporter` (should show k3s-node)
   - `kube-state-metrics`
   - `kubelet` (may need adjustment - see Troubleshooting)

### 6. Import Grafana Dashboard

1. Open Grafana: http://localhost:3000
   - Username: `admin`
   - Password: `admin`
2. Import dashboard ID `315` (Kubernetes Cluster Monitoring)
3. Select the Prometheus datasource
4. You should now see metrics!

## Configuration

### Prometheus Configuration

The Prometheus configuration is in `prometheus/prometheus.yml`. Since Prometheus runs in Docker and K3s runs on the same VM, all endpoints use `host.docker.internal` to access the host network:

- **Node Exporter**: `host.docker.internal:9100` (uses hostPort, accessible from Docker)
- **kube-state-metrics**: `host.docker.internal:30800` (NodePort service, accessible from Docker)
- **kubelet/cAdvisor**: `host.docker.internal:10250` (k3s kubelet on host network)

The `host.docker.internal` hostname is configured in docker-compose.yml via `extra_hosts`.

### Finding Your K3s Kubelet Address

If the kubelet metrics aren't working, find the correct address:

```bash
# Get k3s API server IP
kubectl cluster-info

# Or check kubelet service
kubectl get svc -A | grep kubelet

# Or find the service IP
kubectl get nodes -o wide
```

Then update `prometheus/prometheus.yml` with the correct address.

## Troubleshooting

### No Data in Grafana Dashboard

1. **Check Prometheus Targets**: 
   - Go to http://localhost:9090/targets
   - Ensure all targets show as UP
   - Check for errors in the Status column

2. **Verify Metrics are Being Scraped**:
   - In Prometheus UI, go to Graph
   - Try querying: `up` - should show all targets as 1
   - Try: `node_cpu_seconds_total` - should return node metrics
   - Try: `kube_pod_info` - should return pod metrics

3. **Check Node Exporter**:
   ```bash
   # On your host machine
   curl http://localhost:9100/metrics | head -20
   ```

4. **Check kube-state-metrics**:
   ```bash
   # On your host machine
   curl http://localhost:30800/metrics | head -20
   ```

5. **Check kubelet/cAdvisor**:
   ```bash
   # May need to access from within the cluster or adjust firewall rules
   # Try finding the correct IP:
   kubectl get nodes -o wide
   ```

### kubelet Metrics Not Working

Since k3s and Docker run on the same VM, the kubelet should be accessible via `host.docker.internal:10250`:

1. **Verify kubelet is accessible from host**:
   ```bash
   # On the VM (not in Docker), test if kubelet responds
   curl -k https://localhost:10250/metrics/cadvisor
   ```

2. **If direct access doesn't work, check k3s kubelet port**:
   ```bash
   # Check what port kubelet is actually using
   sudo netstat -tlnp | grep kubelet
   # Or check k3s configuration
   ```

3. **Alternative: Access via k3s API server proxy**:
   ```bash
   # Get node name
   kubectl get nodes
   
   # Test proxy access
   kubectl get --raw "/api/v1/nodes/<node-name>/proxy/metrics/cadvisor"
   ```
   If this works, you may need to configure Prometheus to use the API server proxy instead of direct kubelet access.

4. **Check k3s firewall/network settings** - k3s might be binding to localhost only

### Network Connectivity Issues

Since both Docker and k3s run on the same VM, connectivity should work via `host.docker.internal`:

1. **Verify host.docker.internal works from Prometheus container**:
   ```bash
   docker exec prometheus ping -c 1 host.docker.internal
   docker exec prometheus wget -qO- http://host.docker.internal:9100/metrics | head -5
   ```

2. **Verify Node Exporter is accessible on host**:
   ```bash
   # On the VM host (not in Docker)
   curl http://localhost:9100/metrics | head -5
   ```

3. **Verify kube-state-metrics NodePort is accessible**:
   ```bash
   # On the VM host
   curl http://localhost:30800/metrics | head -5
   ```

4. **If host.docker.internal doesn't work on Linux**, the docker-compose.yml already includes:
   ```yaml
   extra_hosts:
     - "host.docker.internal:host-gateway"
   ```
   This should resolve to the host's IP automatically.

## Service URLs

- **Grafana**: http://localhost:3000
- **Prometheus**: http://localhost:9090
- **Kibana**: http://localhost:5601
- **Elasticsearch**: http://localhost:9200
- **Loki**: http://localhost:3100

## Logs (Loki)

Docker Compose logs are shipped to Loki via `promtail`. In Grafana → **Explore** → select **Loki**, try:
- `{compose_service="prometheus"}`
- `{container="grafana"}`

### Shipping K3s Kubernetes Logs to Loki

Apply the DaemonSet manifest `k8s/promtail-loki.yaml`:

```bash
kubectl apply -f k8s/promtail-loki.yaml
```

## OpenTelemetry Collector (OTLP)

The stack includes an OpenTelemetry Collector (`otel-collector`) that forwards:
- OTLP **logs → Loki**
- OTLP **metrics → Prometheus** (scrape job `otel-collector:8889`)

Send OTLP to:
- gRPC: `http://localhost:4317`
- HTTP: `http://localhost:4318`

## Additional Resources

- [Kubernetes Dashboard 315](https://grafana.com/grafana/dashboards/315)
- [Node Exporter Documentation](https://github.com/prometheus/node_exporter)
- [kube-state-metrics Documentation](https://github.com/kubernetes/kube-state-metrics)
