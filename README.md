# vector-s3-log-pipeline

온프레미스 Kubernetes 파드 로그를 **Vector**로 수집해 **AWS S3**에 적재하고, **Athena**로 장애를 분석·조치·검증하는 로그 기반 장애대응 파이프라인.

> 🚧 **진행 중 (2026.09~)** — 현재 AWS 인프라(Terraform) 구축 완료, 온프레미스 파이프라인 구축 예정

## 한 줄 정의

단순 "로그를 S3에 보내기"가 아니라, **장애 재현 → 로그 적재/분류 → 분석 → 원인 판단 → 조치 → 검증**의 완결된 장애대응 흐름을 구현합니다.

## 아키텍처

```
[온프레미스 K8s 클러스터 - kubeadm 4노드]
  DB 의존형 Spring Boot 앱 ── MySQL
  (MySQL 파드 삭제 → 앱 500 + ERROR 로그 유발)
      │  파드가 stdout에 로그 → 노드 /var/log/pods 에 기록
      ▼
  Vector DaemonSet (노드마다 1개)
   ├─ source:    /var/log/pods tail
   ├─ transform: 이중 파싱 + 멀티라인 병합 → 정규화 JSON → ERROR 필터
   └─ sink:      S3 (배치·gzip·시간 파티션)
      │
──────── 인터넷 (IAM 키 인증) ────────▶
[AWS]
  S3 버킷  logs/year=/month=/day=/hour=/*.json.gz
      ▼
  Athena (S3 위 SQL 쿼리로 ERROR·예외 분석)
```

## 기술 스택

- **수집**: Vector (DaemonSet, VRL 정규식 파싱, 멀티라인 병합)
- **저장**: AWS S3 (gzip 압축, 시간 파티션)
- **분석**: AWS Athena (파티션 프로젝션)
- **IaC**: Terraform (state 로컬)
- **대상 환경**: Kubernetes (kubeadm), Spring Boot, MySQL

## 주요 설계 결정 (ADR)

| 결정 | 선택 | 이유 |
|---|---|---|
| 로그 수집기 | Vector | 밑바닥 학습 + source→transform→sink 구조 |
| 소스 앱 | DB 의존형 Spring Boot + MySQL | "DB 장애 → 앱 5xx → 로그로 원인추적"이 실무에서 가장 흔한 5xx 원인 |
| 파싱 방식 | VRL 정규식 + 멀티라인 병합 | 예외 스택트레이스를 한 이벤트로 묶는 지점이 실력 증명 포인트 |
| 인증 | IAM 사용자 + 최소권한 키 | 온프레미스라 IRSA 불가 → PutObject만 허용하는 전용 키 |
| 파티션 시각 | 이벤트 시각(ts) 기준 | 수신시각 기준이면 경계 이벤트가 스파이크 분석에서 누락됨 |
| 파티션 인식 | 파티션 프로젝션 | 시간마다 새 파티션 생성 → MSCK 실행 누락 사고 방지 |
| 신뢰성 | disk buffer + 재시도 | 파드 재시작 시 로그 유실 방지 (at-least-once 인지) |

## 보안 설계 (최소권한 3층)

- **IAM 층**: Vector 전용 사용자는 이 버킷에 `PutObject`만 허용
- **버킷 정책 층**: TLS(HTTPS) 아니면 거부, 퍼블릭 액세스 차단
- **저장 층**: 기본 암호화(SSE-S3)
- → "키가 유출돼도 이 버킷에 쓰기밖에 못 하고, 평문 전송·퍼블릭 노출은 버킷이 막는다"

## 진행 상황

- [x] AWS 인프라 (Terraform) — S3 버킷 보안 3층 + Vector 최소권한 IAM
- [ ] 온프레미스 배포 — MySQL(hostPath PV), Spring Boot, Vector DaemonSet
- [ ] 장애 재현(MySQL 파드 삭제) → S3 적재 확인
- [ ] Athena 분석(예외 클래스별 집계) → 조치 → Before/After 검증

## 관련 프로젝트

이 프로젝트는 기존 관측성 프로젝트(메트릭 기반)와 짝을 이룹니다. 메트릭 기반이 "에러율이 올랐다"까지 탐지한다면, 이 로그 기반 파이프라인은 "어느 파드가 어떤 예외로 장애를 냈는지"까지 원인을 규명합니다. → 탐지(메트릭) + 원인규명(로그)의 장애대응 루프.

## 작업 방식

AI 도구(Claude Code)로 코드·설정 초안을 생성하되, 결과물을 그대로 쓰지 않고 실제 환경에서 재현·검증하며 동작 원리를 직접 설명할 수 있는 수준까지 이해한 뒤 반영하는 것을 원칙으로 합니다.

## 정리

학습·단기 실습 프로젝트로, 작업 종료 시 `terraform destroy`로 AWS 리소스를 정리합니다. 규모에 맞춰 변수화·모듈 분리·태그는 생략했습니다. (팀 규모 IaC에서는 변수 네이밍 컨벤션·모듈 인터페이스를 별도 설계한 경험이 있습니다.)
