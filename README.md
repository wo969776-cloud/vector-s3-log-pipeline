# vector-s3-log-pipeline

온프레미스 Kubernetes 파드 로그를 **Vector**로 수집해 **AWS S3**에 적재하고, **Athena**로 장애를 분석·조치·검증하는 로그 기반 장애대응 파이프라인.

> **기간**: 2026.09.06 ~ 2026.09.11 · **상태**: 완료 (장애 재현 → 분석 → 조치 → 검증 루프 실증)

## 한 줄 정의

단순 "로그를 S3에 보내기"가 아니라, **장애 재현 → 로그 적재/분류 → 분석 → 원인 판단 → 조치 → 검증**의 완결된 장애대응 흐름을 구현하고 실제 데이터로 검증했습니다.

## 왜 이 프로젝트인가

기존 포트폴리오가 온프레미스(K8s 구축·관측성)에 편중되어 AWS 실전 경험이 약했습니다. 이 프로젝트로 **"온프레미스와 클라우드 양쪽을 다룰 수 있다"**를 증명하고, 동시에 단순 적재가 아닌 **완결된 장애대응 흐름**을 구현해 실무 역량을 보이는 것이 목표입니다.

## 아키텍처

```
[온프레미스 K8s 클러스터 - kubeadm 4노드]
  DB 의존형 Spring Boot 앱 ── MySQL
  (MySQL replicas=0으로 중지 → 앱 500 + ERROR 로그 유발)
      │  파드가 stdout에 로그 → 노드 /var/log/pods 에 기록
      ▼
  Vector DaemonSet (노드마다 1개)
   ├─ source:    kubernetes_logs (containerd 껍질 제거 + K8s 메타 부착)
   ├─ transform: allowlist → 멀티라인 병합 → VRL 파싱 → 이벤트시각 정규화
   └─ sink:      S3 (NDJSON, gzip, 이벤트시각 파티션, disk buffer)
      │
──────── 인터넷 (IAM 키 인증) ────────▶
[AWS]
  S3 버킷  logs/year=/month=/day=/hour=/*.log.gz
      ▼
  Athena (파티션 프로젝션, SQL로 ERROR·예외 분석)
```

## 기술 스택과 선택 이유

### 수집: Vector
로그 수집기로 Vector를 선택했습니다. `source → transform → sink`의 명확한 파이프라인 구조라 각 단계를 밑바닥부터 이해하며 다룰 수 있고, Datadog SaaS 같은 완성형 도구보다 학습 깊이가 큽니다. 컨테이너 로그의 이중 구조(containerd 껍질 + 앱 로그)를 벗기고, 예외 스택트레이스를 멀티라인 병합으로 한 이벤트로 묶는 과정이 이 프로젝트에서 가장 실력이 드러나는 지점입니다.

### 소스 앱: DB 의존형 Spring Boot + MySQL
관측 대상 앱은 "DB에서 데이터를 읽어 응답하는 최소 Spring Boot 앱"으로 두고, **MySQL을 `replicas=0`으로 내려 장애를 유발**합니다. "DB 장애 → 애플리케이션 5xx → 로그로 원인추적"은 실무에서 가장 흔한 5xx 패턴이라, 인위적인 500 엔드포인트보다 장애 서사가 현실적입니다. 인프라 엔지니어 관점에서 앱은 "관측 대상"이지 본체가 아니므로, 최소 규모로 유지해 파이프라인에 집중했습니다.

### AWS 스택: S3 + Athena + IAM (서버리스 중심)
클라우드 분석 계층을 **서버리스 조합**으로 설계했습니다.

- **S3 (저장)** — 로그처럼 계속 쌓이는 데이터에 적합한 오브젝트 스토리지. 시간 파티션 + gzip으로 Athena 스캔량과 저장 비용을 줄일 수 있는 구조입니다. (이번 분석 쿼리는 데이터가 수 KB 규모라 파티션 조건 없이 실행했습니다)
- **Athena (분석)** — S3 데이터를 옮기거나 별도 DB를 띄우지 않고, S3 위에 스키마만 얹어 SQL로 조회하는 서버리스 쿼리 서비스입니다. 상시 서버 비용이 없고(쿼리 스캔량과 S3 저장·요청에만 과금), 장애 발생 시 엔지니어가 직접 쿼리로 원인을 파고드는 애드혹 분석에 적합합니다.
- **IAM (인증·보안)** — 온프레미스 클러스터라 EKS의 IRSA나 EC2 인스턴스 프로파일을 쓸 수 없어, PutObject만 허용하는 최소권한 IAM 사용자 + 장기 액세스 키로 인증합니다. 장기 키 없이 인증하는 IAM Roles Anywhere는 다음 단계입니다. 액세스 키의 secret은 Terraform state에 기록되므로 state는 로컬에 두고 `.gitignore`로 제외했습니다.

> **상시 과금 리소스(NAT Gateway·EKS·ALB·EC2)를 의도적으로 배제**했습니다. 다만 실습 후 리소스를 3주간 켜둔 사이 실패 로그까지 계속 적재되어 약 3,000원이 청구됐습니다(예상 200원 이내). 아래 [비용 / 정리](#비용--정리) 참고.

### IaC: Terraform
S3·IAM·Glue·Athena workgroup을 전부 Terraform으로 선언합니다. 손으로 만든 리소스가 없어야 `terraform destroy` 한 번으로 깨끗이 정리되고, 비용 안전장치가 됩니다. 콘솔에서 설정하기 쉬운 Athena 결과 저장 위치조차 workgroup 리소스로 코드화해 IaC 일관성을 지켰습니다.

## 디렉터리 구조

```
vector-s3-log-pipeline/
├── terraform/              # AWS 인프라 (전부 IaC)
│   ├── s3.tf               #   버킷 + 암호화 + 퍼블릭차단 + TLS 강제 정책
│   ├── iam.tf              #   Vector 전용 사용자 + PutObject-only 정책
│   ├── athena.tf           #   Glue 테이블(파티션 프로젝션) + Athena workgroup
│   └── outputs.tf
├── app/                    # DB 의존형 Spring Boot 앱 (관측 대상)
│   ├── src/                #   /items(DB 조회), /health
│   └── Dockerfile
├── k8s/
│   ├── infra/              # 네임스페이스, MySQL(hostPath PV/PVC)
│   └── apps/
│       ├── spring/         # Spring 앱 배포
│       └── vector/         # Vector RBAC, ConfigMap(파이프라인), DaemonSet
└── .github/workflows/      # Spring 앱 빌드 → DockerHub
```

## 장애대응 시나리오 (실증 결과)

**1. 장애 재현** — `kubectl scale deploy mysql --replicas=0`으로 DB 다운 → Spring 앱이 커넥션 실패로 HTTP 500 + `ERROR` 로그(JDBC 예외 스택트레이스) 발생.

**2. 분석 (Athena)** — 3종 쿼리로 원인을 좁힘:

| 분석 축 | 쿼리 | 결과 |
|---|---|---|
| 무엇 | `GROUP BY exception WHERE level='ERROR'` | `CannotGetJdbcConnectionException` 단독 |
| 언제 | 분 단위 ERROR 집계 | ERROR 5건이 1분 구간(2026-09-09T13:57 UTC)에 집중 |
| 어디서 | `GROUP BY service, pod` | 해당 Spring 파드로 특정 |

→ **"어느 파드가, 언제, 어떤 예외(JDBC 커넥션 실패)로 500을 냈는지" 로그만으로 특정.** (DB 중지는 재현 조건이므로, 로그로 확인한 것은 장애의 위치·시각·예외 유형)

**3. 조치 & 검증** — MySQL 복구·앱 재기동 후 Before/After 비교:

| 구간 | ERROR | WARN | INFO |
|---|---|---|---|
| 장애 시각 (2026-09-09) | **5** | 13 | 6 |
| 복구 후 (2026-09-11) | **0** | 3 | 38 |

→ 장애 구간에는 `HikariPool` 커넥션 획득 실패가 ERROR로 남았고, 복구 후 구간에는 ERROR가 0건. 앱을 재기동했기 때문에, 앱 재시작 없이 HikariCP가 자동 재연결되는지는 검증하지 않았습니다(다음 단계).

## 주요 설계 결정 (ADR)

| 결정 | 선택 | 이유 |
|---|---|---|
| 로그 수집기 | Vector | 밑바닥 학습 + source→transform→sink 구조 |
| 소스 앱 | DB 의존형 Spring Boot + MySQL | "DB 장애 → 앱 5xx → 로그로 원인추적"이 실무에서 가장 흔한 5xx 패턴 |
| 파싱 방식 | VRL 정규식 + 멀티라인 병합 | 예외 스택트레이스를 한 이벤트로 묶는 지점이 실력 증명 포인트 |
| 인증 | IAM 사용자 + 최소권한 키 | 온프레미스라 IRSA 불가 → PutObject만 허용하는 전용 키 (Roles Anywhere는 다음 단계) |
| 파티션 시각 | 이벤트 시각(ts) 기준, 전 구간 UTC | 수신시각 기준이면 경계 이벤트가 스파이크 분석에서 누락됨 |
| 파티션 인식 | 파티션 프로젝션 | 시간마다 새 파티션 생성 → MSCK 실행 누락 사고 방지 |
| 신뢰성 | disk buffer + 재시도 | 파드 재시작 시 로그 유실 방지 (at-least-once 인지) |

## 보안 설계 (최소권한 3층)

- **IAM 층**: Vector 전용 사용자는 이 버킷에 `PutObject`만 허용
- **버킷 정책 층**: TLS(HTTPS) 아니면 거부, 퍼블릭 액세스 4종 차단
- **저장 층**: 기본 암호화(SSE-S3)
- → "키가 유출돼도 이 버킷에 쓰기밖에 못 하고, 평문 전송·퍼블릭 노출은 버킷이 막는다"

## 트러블슈팅 (실제 해결 기록)

- **S3 전송 실패 — 원인을 확정하지 못한 사례** — S3 sink 전환 후 전송 실패 로그와 `Healthcheck failed. error=Invalid credentials`가 지속. 키 유효성(`sts get-caller-identity`)·Secret 값·env 주입·노드 시계를 차례로 배제했고, 디스크 버퍼 디렉터리를 삭제하고 파드를 롤아웃한 뒤부터 전송이 시작됨. 원인은 확정하지 못했고 가설은 두 가지: ① 버퍼에 남은 상태가 재시도에 영향 ② Vector S3 헬스체크는 HeadBucket을 호출하고 403을 'Invalid credentials'로 표시하는데, 이 정책은 PutObject만 허용(s3:ListBucket 없음)하므로 키가 정상이어도 헬스체크 에러는 날 수 있음. → 에러 메시지가 가리키는 원인과 실제 실패 지점을 분리해서 확인해야 한다는 것을 배움.
- **S3 출력이 JSON 배열로 저장돼 Athena가 못 읽음** — Vector `aws_s3` sink의 기본 framing이 이벤트를 JSON 배열(`[{},{}]`)로 묶음. `framing.method: newline_delimited`로 NDJSON 전환해 Athena 호환 확보.
- **파티션이 수신시각 기준으로 잡히는 문제** — Vector가 파티션 경로(`key_prefix`)에 자동으로 쓰는 `timestamp`는 수신시각. transform에서 이벤트시각(`ts`)을 파싱해 `timestamp` 필드를 덮어써, 파티션이 이벤트시각 기준이 되도록 함. S3 적재를 시작하기 전에 공식 문서로 확인해 설계 단계에서 반영.
- **파티션 컬럼 타입** — `month=09`처럼 zero-padded 값은 Glue 파티션 컬럼을 `int`로 두면 매칭 실패. `string` + `projection.type=integer, digits=2`로 해결.

## 관련 프로젝트

기존 관측성 프로젝트(메트릭 기반)와 짝을 이룹니다. 메트릭 기반이 "에러율이 올랐다"까지 **탐지**한다면, 이 로그 기반 파이프라인은 "어느 파드가 어떤 예외로 장애를 냈는지"까지 **원인을 규명**합니다. → 탐지(메트릭) + 원인규명(로그)의 장애대응 루프. (Vector `internal_metrics`를 Prometheus로 수집해 두 프로젝트를 연결하는 것은 다음 단계)

## 작업 방식

AI 도구(Claude Code)로 코드·설정 초안을 생성하되, 결과물을 그대로 쓰지 않고 실제 환경에서 재현·검증하며 동작 원리를 직접 설명할 수 있는 수준까지 이해한 뒤 반영하는 것을 원칙으로 합니다.

## 비용 / 정리

- 상시 과금 리소스(NAT Gateway·EKS·ALB·EC2)는 쓰지 않았지만, 실습 후 리소스를 3주간 켜둔 사이 실패 로그까지 계속 적재되어 약 3,000원이 청구됐습니다(예상 200원 이내). `destroy`는 실행해야 안전장치가 된다는 것을 배웠습니다.
- 이후 `terraform destroy`로 AWS 리소스를 일괄 정리했습니다. 비용 알림(AWS Budgets)과 S3 수명주기 규칙은 다음 단계입니다. 규모에 맞춰 변수화·모듈 분리는 생략했습니다.
