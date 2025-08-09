#!/bin/bash
set -e

install_monitoring() {
  NAMESPACE="monitoring"
  GRAFANA_PASS="admin"

  echo "[1/7] 🔹 Creating namespace..."
  kubectl create namespace $NAMESPACE || true

  echo "[2/7] 🔹 Adding Helm repo..."
  helm repo add bitnami https://charts.bitnami.com/bitnami
  helm repo update

  echo "[3/7] 🔹 Installing Prometheus..."
  helm install prometheus bitnami/kube-prometheus \
    --namespace $NAMESPACE \
    --set prometheus.service.type=ClusterIP \
    --set grafana.enabled=false

  PROM_URL="http://prometheus-kube-prometheus-prometheus.$NAMESPACE.svc.cluster.local:9090"

  echo "[4/7] 🔹 Installing Grafana with pre-configured datasource..."
  helm install grafana bitnami/grafana \
    --namespace $NAMESPACE \
    --set admin.user=admin \
    --set admin.password=$GRAFANA_PASS \
    --set service.type=ClusterIP \
    --set persistence.enabled=false \
    --set datasources.secretName=grafana-datasources

  echo "[5/7] 🔹 Creating Secret for datasource..."
  kubectl create secret generic grafana-datasources \
    --namespace $NAMESPACE \
    --from-literal=datasources.yaml="$(cat <<EOF
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    url: ${PROM_URL}
    access: proxy
    isDefault: true
EOF
)"

  echo "[6/7] 🔹 Creating Ingress for Grafana..."
  kubectl apply -n $NAMESPACE -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: grafana-ingress
  annotations:
    nginx.ingress.kubernetes.io/rewrite-target: /
spec:
  ingressClassName: nginx
  rules:
  - host: monitor.${DOMAIN}
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: grafana
            port:
              number: 3000
EOF

  echo "[7/7] ⏳ Waiting for Grafana to become ready..."
  kubectl rollout status deployment/grafana -n $NAMESPACE

  echo "✅ Setup complete!"
  echo "--------------------------------------------------"
  echo "🌐 Grafana via Ingress: http://monitor.localho.st"
  echo "   Username: admin"
  echo "   Password: $GRAFANA_PASS"
  echo ""
  echo "🔄 If Ingress is not working, you can port-forward manually:"
  echo "   kubectl port-forward svc/grafana -n $NAMESPACE 3000:3000"
  echo "   Then open: http://localhost:3000"
  echo "--------------------------------------------------"
}