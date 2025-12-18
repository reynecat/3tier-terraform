# PlanB Azure 3-failover

재해 장기화 시: AKS + PetClinic Full Failover

## 포함 리소스

- **AKS Cluster** - Kubernetes 클러스터
- **Node Pool** - Auto Scaling (2-5 노드)
- **Application Gateway Ingress** - AKS 연결

## 배포 시나리오

### 사전 조건

1. **1-always 배포 완료**
2. **2-emergency 배포 완료**
   - MySQL 복구 완료
   - Application Gateway 실행 중

### 배포 절차

```bash
# 1. AKS 클러스터 배포
terraform init
terraform plan
terraform apply

# 배포 시간: 15-20분

# 2. kubectl 설정
az aks get-credentials \
  --resource-group rg-dr-prod \
  --name aks-dr-prod

# 3. 클러스터 확인
kubectl get nodes
kubectl cluster-info

# 4. PetClinic 배포
cd scripts
./deploy-petclinic.sh

# 5. Application Gateway 업데이트
./update-appgw.sh
```

## Kubernetes 매니페스트

```bash
scripts/
├── deploy-petclinic.sh       # PetClinic 배포 자동화
├── update-appgw.sh           # App Gateway → AKS 연결
└── k8s-manifests/
    ├── namespace.yaml
    ├── deployment.yaml
    ├── service.yaml
    └── ingress.yaml
```

## 비용

- AKS Control Plane: 무료
- Node Pool (2x Standard_D2s_v3): ~$200/월
- Load Balancer: ~$20/월
- Public IP: ~$3/월
- **총: ~$223/월**

## 전체 비용 (1+2+3)

- 1-always: $5/월
- 2-emergency: $53/월
- 3-failover: $223/월
- **총: $281/월** (Full Failover 시)

## Auto Scaling

```yaml
min_count: 2
max_count: 5
vm_size: Standard_D2s_v3 (2 vCPU, 8GB RAM)
```

## 모니터링

```bash
# Pod 상태
kubectl get pods -n petclinic

# Service 확인
kubectl get svc -n petclinic

# Ingress 확인
kubectl get ingress -n petclinic

# 로그 확인
kubectl logs -f deployment/petclinic-was -n petclinic
```

## 롤백

```bash
# AKS 삭제 (비용 절감)
terraform destroy

# 2-emergency로 복귀 (점검 페이지)
cd ../2-emergency
# Application Gateway는 그대로 유지
```

## 주의사항

1. **2-emergency 먼저 배포 필수**
2. **MySQL 복구 완료 확인**
3. **배포 시간 15-20분 소요**
4. **비용 주의** (~$300/월)

## 다음 단계

서비스 정상화 후:
1. DNS 업데이트 (도메인 있을 경우)
2. 모니터링 설정
3. 백업 확인
4. AWS 복구 계획
