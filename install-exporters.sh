#!/bin/bash

# Script to install metrics exporters in K3s cluster

set -e

echo "🚀 Installing metrics exporters for K3s monitoring..."

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "❌ Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo "❌ Error: Cannot connect to Kubernetes cluster"
    echo "   Please ensure kubectl is configured correctly"
    exit 1
fi

echo "✅ Connected to Kubernetes cluster"
kubectl cluster-info | head -1

# Create namespace
echo ""
echo "📦 Creating monitoring namespace..."
kubectl apply -f k8s/namespace.yaml

# Deploy Node Exporter
echo ""
echo "📊 Deploying Node Exporter..."
kubectl apply -f k8s/node-exporter.yaml

# Deploy kube-state-metrics
echo ""
echo "📈 Deploying kube-state-metrics..."
kubectl apply -f k8s/kube-state-metrics.yaml

# Wait for pods to be ready
echo ""
echo "⏳ Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=node-exporter -n monitoring --timeout=120s || true
kubectl wait --for=condition=ready pod -l app=kube-state-metrics -n monitoring --timeout=120s || true

# Show status
echo ""
echo "✅ Installation complete! Current status:"
echo ""
kubectl get pods -n monitoring
echo ""
kubectl get svc -n monitoring
echo ""

# Verify endpoints
echo "🔍 Verifying endpoints..."
echo ""
echo "Node Exporter (should be accessible on port 9100):"
kubectl get pods -n monitoring -l app=node-exporter -o wide
echo ""
echo "kube-state-metrics (NodePort 30800):"
kubectl get svc -n monitoring kube-state-metrics

echo ""
echo "✨ Next steps:"
echo "   1. Verify Node Exporter: curl http://localhost:9100/metrics"
echo "   2. Verify kube-state-metrics: curl http://localhost:30800/metrics"
echo "   3. Start the stack: docker-compose up -d"
echo "   4. Check Prometheus targets: http://localhost:9090/targets"
echo "   5. View Grafana: http://localhost:3000"
