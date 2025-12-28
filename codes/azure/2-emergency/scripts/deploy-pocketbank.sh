#!/bin/bash
# PlanB/azure/3-failover/scripts/deploy-pocketbank.sh
# AKS에 PocketBank 배포

set -e

echo "=========================================="
echo "PocketBank 배포 (AKS - Full Failover)"
echo "시작 시간: $(date)"
echo "=========================================="

# Terraform outputs에서 정보 가져오기
cd ..
AKS_NAME=$(terraform output -raw aks_cluster_name)
RESOURCE_GROUP=$(terraform output -raw resource_group_name 2>/dev/null || echo "rg-dr-blue")
MYSQL_FQDN=$(terraform output -raw mysql_fqdn)

cd scripts

echo ""
echo "[1/6] kubectl 설정 확인..."
az aks get-credentials \
  --resource-group $RESOURCE_GROUP \
  --name $AKS_NAME \
  --overwrite-existing

kubectl cluster-info

echo ""
echo "[2/6] Namespace 생성..."
kubectl create namespace pocketbank --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "[3/6] MySQL Secret 생성..."
read -sp "MySQL Password: " DB_PASSWORD
echo ""

kubectl create secret generic db-credentials \
  --from-literal=url="jdbc:mysql://${MYSQL_FQDN}:3306/pocketbank" \
  --from-literal=username="mysqladmin" \
  --from-literal=password="${DB_PASSWORD}" \
  --namespace=pocketbank \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "[4/6] PocketBank Deployment 생성..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: pocketbank-config
  namespace: pocketbank
data:
  SPRING_PROFILES_ACTIVE: "mysql"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: pocketbank
  namespace: pocketbank
  labels:
    app: pocketbank
spec:
  replicas: 2
  selector:
    matchLabels:
      app: pocketbank
  template:
    metadata:
      labels:
        app: pocketbank
    spec:
      containers:
      - name: pocketbank
        image: springio/pocketbank:latest
        ports:
        - containerPort: 8080
          name: http
          protocol: TCP
        env:
        - name: SPRING_PROFILES_ACTIVE
          valueFrom:
            configMapKeyRef:
              name: pocketbank-config
              key: SPRING_PROFILES_ACTIVE
        - name: SPRING_DATASOURCE_URL
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: url
        - name: SPRING_DATASOURCE_USERNAME
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: username
        - name: SPRING_DATASOURCE_PASSWORD
          valueFrom:
            secretKeyRef:
              name: db-credentials
              key: password
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        startupProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 12
        livenessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 5
          failureThreshold: 3
        readinessProbe:
          httpGet:
            path: /
            port: 8080
          initialDelaySeconds: 0
          periodSeconds: 5
          timeoutSeconds: 3
          failureThreshold: 3
EOF

echo ""
echo "[5/6] LoadBalancer Service 생성..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: pocketbank
  namespace: pocketbank
  labels:
    app: pocketbank
spec:
  type: LoadBalancer
  selector:
    app: pocketbank
  ports:
  - name: http
    port: 8080
    targetPort: 8080
    protocol: TCP
  sessionAffinity: None
EOF

echo ""
echo "[6/6] Pod 및 LoadBalancer IP 대기..."
echo "Pod 시작 대기 중..."
kubectl wait --for=condition=ready pod \
  -l app=pocketbank \
  -n pocketbank \
  --timeout=300s

echo ""
echo "LoadBalancer IP 할당 대기 중 (최대 3분)..."
for i in {1..36}; do
  EXTERNAL_IP=$(kubectl get svc pocketbank -n pocketbank -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
  
  if [ -n "$EXTERNAL_IP" ]; then
    echo ""
    echo "LoadBalancer IP 할당 완료: $EXTERNAL_IP"
    break
  fi
  
  echo -n "."
  sleep 5
done

if [ -z "$EXTERNAL_IP" ]; then
  echo ""
  echo "WARNING: LoadBalancer IP가 할당되지 않았습니다."
  echo "수동으로 확인하세요: kubectl get svc pocketbank -n pocketbank"
fi

echo ""
echo "=========================================="
echo "PocketBank 배포 완료!"
echo "=========================================="
echo ""
kubectl get pods -n pocketbank
echo ""
kubectl get svc pocketbank -n pocketbank
echo ""
echo "다음 단계:"
echo "  ./update-appgw.sh  # Application Gateway 업데이트"
echo ""
