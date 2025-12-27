# Kubernetes 매니페스트

EKS 클러스터에 애플리케이션을 배포하기 위한 매니페스트 파일입니다.

## 배포 순서

### 1. AWS Load Balancer Controller 설치
```bash
cd scripts
./install-lb-controller.sh

k8s-manifests$ kubectl apply -f namespaces.yaml
```


배포 시 입력 필요:
- RDS Endpoint: Terraform output에서 확인
- DB Password: Terraform apply 시 사용한 비밀번호

### 3. 접속 확인
```bash
# Ingress ALB DNS 확인
kubectl get ingress -n web web-ingress

# 브라우저에서 접속
# http://k8s-web-webingre-xxxxx.ap-northeast-2.elb.amazonaws.com
```

## 구조
```
k8s-manifests/
├── namespaces.yaml          # Namespace 정의
├── was/
│   ├── deployment.yaml      # Spring Boot 애플리케이션
│   └── service.yaml         # WAS Service
├── web/
│   ├── deployment.yaml      # Nginx + ConfigMap
│   └── service.yaml         # Web Service
└── ingress/
    └── ingress.yaml         # ALB Ingress
```

## 특징

- **Ingress 방식**: AWS Load Balancer Controller가 ALB를 자동 생성
- **IP 타겟 타입**: Pod IP가 자동으로 ALB Target Group에 등록
- **Health Check**: `/health` 엔드포인트로 Pod 상태 확인
- **리버스 프록시**: Nginx가 모든 요청을 WAS로 전달
