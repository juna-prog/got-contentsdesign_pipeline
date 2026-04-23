# SCHEMA_STANDARD

> 4파트(필드/퀘스트/레벨/전투) 개발 파이프라인 xlsx/csv/JSON 표준 스키마. 웹앱 DB와 운영 시트의 단일 진실 원천. **v1.1 (2026-04-22): Row 값 마스터 + 의존성 모델 + 네이밍 컨벤션 추가**

---

## 1. 목적과 범위

**배경**: 2026-04-22 4파트 xlsx 시트 구조 분석 결과, 시트 이름/컬럼/날짜 포맷/헤더 위치가 파트별로 달라 정합성 체크 및 웹앱 import가 불안정했다.

**원칙**:
- 단일 진실 원천(SSoT)은 웹앱 DB. xlsx는 운영자 view + import 입력.
- 표준 충족 시 파서가 즉시 인식, 4파트 중 어느 파트에서 export해도 동일 컬럼 집합.
- 운영자 가독성(16열) + 트래커 메타데이터(4열) 분리.

**대상**:
- `F:/GOT_Data/작업분배및일정관리/YYYYMMDD_콘텐츠파트_개발파이프라인/` 아래 4파트 xlsx
- `F:/Git/got-contentsdesign_pipeline/` 웹앱 DB 스키마 (v11 이상)
- Export 산출물 (csv/json)

---

## 2. 표준 시트 구조 (7종)

| # | 시트명 | 역할 | 4파트 공통 |
|---|-------|------|:--------:|
| 1 | 대시보드 | 파트별 진행 현황 요약 | ○ |
| 2 | 담당 업무 | 파트원별 정담당/부담당 매트릭스 | ○ |
| 3 | 업무 목록 | 태스크 상세 (본 문서 핵심) | ○ |
| 4 | 월별 일정 | 간트차트 (3월~12월) | ○ |
| 5 | 공휴일 | 한국 공휴일 일자 | ○ (신규 전파) |
| 6 | 기획 프로세스(참고) | 게이트 정의 참조 | ○ |
| 7 | 작업 태스크 별 소요일(작업중) | 태스크별 평균 소요일 | ○ |

**전투 파트 고유 (표준 외 허용)**:
- `분류`, `업데이트`, `업무 리스트 백업`, `간트` - 전투 파트 내부 도구로 유지

**시트 이름 규칙**:
- 업무 목록 시트는 `업무 목록` 으로 통일 (전투의 `업무 리스트`도 리네이밍)
- 공휴일 시트는 모든 파트에 전파

---

## 3. 업무 목록 표준 20열

### 3-1. 운영 컬럼 (16) - xlsx/csv export 노출

| # | 컬럼명 | 필수 | 설명 | 정규화 |
|---|--------|:---:|------|--------|
| 1 | 목표 | Y | 릴리즈 단위 라벨. 예: `론칭`, `1차 업데이트`, `시즌4`, `시즌5` | version 테이블 label 매칭 |
| 2 | 지역/챕터 | N | 콘텐츠 위치. 예: `3.1. 스톰스엔드`, `1.3`, `-` | 공백 trim |
| 3 | 이슈 타입 | N | JIRA 용어 일치: `Task`, `Sub-Task` | 공백 trim |
| 4 | 콘텐츠명 | Y | 콘텐츠 이름 | 공백 trim |
| 5 | 게이트 | Y | `Gate 0~3`, `G0~G7`, `DONE` | normalizeGate() |
| 6 | 분류 | N | 콘텐츠 유형. 예: `메인 퀘스트`, `던전`, `시스템` | normalizeType() |
| 7 | 세부 내용 | Y | 태스크 제목. 서브태스크는 `└ ` 접두어 | indent 감지 |
| 8 | 담당자 | N | 이름. 복수: 쉼표 구분 | workers 매칭 |
| 9 | 유관파트 | N | `필드/퀘스트/전투/레벨/아트/내러티브/UX/클래스` | normalizeRelatedPart() |
| 10 | 상태 | N | `시작 전`, `진행 중`, `완료됨`, `보류`, `중단` | normalizeStatus() |
| 11 | 작업 시작 일정 | N | ISO 날짜 `YYYY-MM-DD` | normalizeDate() |
| 12 | 작업 완료 일정 | N | ISO 날짜 `YYYY-MM-DD` | normalizeDate() |
| 13 | 작업 일수 | N | 정수 (1~365) | parseInt |
| 14 | 기획서 | N | 파일명 또는 URL | - |
| 15 | 지라 일감 | N | `PROJECTT-12345` 또는 full URL | normalizeJiraKey() |
| 16 | 비고 | N | 자유 텍스트 | - |

### 3-2. 트래커 메타 (4) - JSON/DB only

| # | 컬럼명 | 필수 | 설명 |
|---|--------|:---:|------|
| 17 | 파트 | Y (export 시) | `field`, `quest`, `combat`, `level` - 4파트 합집합 export에 필수 |
| 18 | 우선순위 | N | 정수 (1=최우선), 웹앱 정렬용 |
| 19 | source_key | Y (import 시) | upsert 고유 키. 형식: `{part}::{content}::{detail}` |
| 20 | parent_source_key | N | 부모 태스크 source_key. 서브태스크 계층 연결 |

**메타 컬럼은 xlsx에 보이지 않음**. Export 시 csv/json에만 포함.

---

## 4. 컬럼 정규화 규칙

### 4-1. 날짜 (ISO 통일)

- 표준: `YYYY-MM-DD` (예: `2026-04-07`)
- 허용 입력 → 변환: `YYYY.MM.DD`, `YYYY/MM/DD`, `YYYY-MM-DD HH:MM:SS`
- 빈 값: 빈 문자열 (null 아님)
- 파싱 실패 → critical 이슈 리포트

### 4-2. 게이트 매핑

| 원본 표기 | 정규화 |
|----------|:-----:|
| `Gate 0 : 설정/방향` | G0 |
| `Gate 1 : 컨셉 기획` | G2 |
| `Gate 1a : 구현 기획`, `Gate 3 : 구현 기획` (레벨 전용) | G3 |
| `Gate 1b : 아트 요청` | G4 |
| `Gate 2 : 구현/제작` | G5 |
| `Gate 3 : QA/폴리싱` | G7 |
| `릴리즈 : 완료`, `DONE` | DONE |

### 4-3. 상태 enum

`시작 전` / `진행 중` / `완료됨` / `보류` / `중단` / (빈 값)

### 4-4. 이슈 타입 enum

`Task` / `Sub-Task` / (빈 값)
- 전투 파트 기존 `작업 타입` → `이슈 타입` 으로 리네이밍
- 서브태스크는 `세부 내용` 필드에 `└ ` 접두어 + `이슈 타입 = Sub-Task` 동시 표기 (중복이지만 가독성 우선)

### 4-5. 유관파트 enum

`필드` / `퀘스트` / `전투` / `레벨` / `아트` / `내러티브` / `UX` / `클래스` / `검증`
- 복수 가능: 쉼표 구분 (예: `필드, 아트`)
- `필드 파트`, `전투 파트` 접미어 제거 후 매칭

### 4-6. 서브태스크 indent 감지

인식 접두어: `└`, `↳`, `ㄴ`, `　└`, `　↳` (전각 공백 포함)
- 파서는 모두 인식
- Export 시 `└ ` (반각 공백)으로 통일

### 4-7. JIRA key

- 표준: `PROJECTT-37946` (key만)
- URL 입력 시: `https://jira.nmn.io/browse/` 접두어 제거 후 key 추출
- 정규식: `^[A-Z]+-\d+$`

---

## 5. 4파트 차이 흡수 규칙

| 항목 | 필드/퀘스트 | 레벨 | 전투 | 표준화 |
|------|:----------:|:---:|:---:|--------|
| 업무 목록 시트명 | `업무 목록` | `(토탈) 업무 목록_Ver3` | `업무 리스트` | → `업무 목록` |
| 헤더 행 위치 | 1 or 3행 | 3행 | 1행 | → 1행 고정 |
| 첫 컬럼명 | `목표 빌드` / `목표` | `목표 빌드` | `목표` | → `목표` |
| 위치 식별 | `지역` | (없음) | `챕터` | → `지역/챕터` 단일 |
| 태스크 구분 | `이슈 타입` | (없음) | `작업 타입` | → `이슈 타입` |
| 날짜 포맷 | `2026.04.07` | `2026.04.07` | `2026-04-07 00:00:00` | → `2026-04-07` |
| 월별 일정 시트 | 있음 | 있음 | `간트` | → `월별 일정` |

**레벨 파트 특례**:
- `(토탈) 업무 목록_Ver1`, `Ver2`, `업무 목록 (Old)` → 아카이브 (Ver3만 정본)
- `담당 업무` 시트의 `주 업무 / 담당 지역` → `콘텐츠명` 구조로 전환
- [대시보드.csv](../GOT_Data/작업분배및일정관리/20260422_콘텐츠파트_개발파이프라인/[아시아 빌드] 레벨 파트 업무 관리_csv_export/대시보드.csv) 제목 `필드 파트 업무 대시보드` → `레벨 파트 업무 대시보드` 정정

---

## 6. 린트 규칙

전역 LintRules.md 카테고리 A 준수:

- em dash `—` 사용 금지 → hyphen `-` 치환
  - 현재 위반: 3개 파트 `월별 일정` 시트 1행 제목
- middle dot `·` 사용 금지 → comma `,` 치환
- 한글 파일명 금지 (시트명은 한글 허용, 파일명은 영문 PascalCase)

---

## 7. 아카이브 방침

**아카이브 대상**:
- 레벨 `(토탈) 업무 목록_Ver1.csv`, `Ver2.csv`, `업무 목록 (Old).csv`
- 전투 `업무 리스트 백업.csv`

**아카이브 위치**:
- `{원본폴더}/_archive/{YYYYMMDD}/` 서브폴더로 이동
- 원본 파일은 xlsx 상에서는 탭 숨김 처리 (삭제하지 않음)

---

## 8. 버전 관리

**DB 마이그레이션**:

v11 (컬럼 구조 확장, [v11_schema_standard.sql](migrations/v11_schema_standard.sql)):
- `CREATE UNIQUE INDEX idx_contents_source_key_unique ON contents(source_key) WHERE source_key IS NOT NULL` (부분 UNIQUE)
- `CREATE UNIQUE INDEX idx_tasks_source_key_unique ON tasks(source_key) WHERE source_key IS NOT NULL`
- `ALTER TABLE tasks ADD COLUMN region_chapter TEXT` (컬럼 2)
- `ALTER TABLE tasks ADD COLUMN issue_type TEXT CHECK ...` (컬럼 3)
- `ALTER TABLE tasks ADD COLUMN priority INTEGER CHECK ...` (컬럼 18)

v12 (Row 표준 + 의존성 + 네이밍, [v12_dependencies_and_naming.sql](migrations/v12_dependencies_and_naming.sql)):
- `task_action_verbs` 마스터 (네이밍 동사 enum)
- `regions` 마스터 (지역/챕터 코드)
- `part_categories` 마스터 (파트별 분류 격리)
- `task_dependencies` 테이블 + 순환 감지 trigger + `v_dep_date_violations` view
- `task_templates` 테이블 (파생 업무 자동 생성)
- `tasks` 확장: action_verb, title_object, category_id
- `jira_templates` 확장: action_verb_map, dep_link_mapping

ETL ([v12_data_normalize.sql](migrations/v12_data_normalize.sql)): Phase A(리포트) -> migration_review 검토 -> Phase B(UPDATE)

**Export 포맷 버전**:
- CSV v1.0: 16열 (운영)
- CSV v2.0: 20열 (운영 + 메타, AI 분석용)
- JSON v1.0: 전체 20열 + context 블록 (게이트 정의, 버전 타겟, 일정 역산 규칙)

**하위 호환**:
- 파서는 과거 18열 포맷(플랜 v1)도 인식
- `지역/챕터`, `이슈 타입` 누락 시 빈 값으로 import

---

## 9. 정합성 체크 통합

[pipeline_integrity_check.py](../pipeline_integrity_check.py) 가 검증하는 11개 항목 모두 본 표준과 일치:

1. 날짜 형식 유효성
2. 게이트 유효성
3. 상태 유효성
4. 담당자 DB 매칭
5. 콘텐츠명 중복 (파트 내)
6. 서브태스크 계층 무결성
7. JIRA key 형식
8. 작업 일수 유효성
9. 날짜 논리 (시작 <= 종료)
10. DB vs 시트 커버리지
11. 파트별 분포

v1.1 추가 항목:
12. 지역/챕터 값 분포 (regions 마스터 참조 무결성)
13. 이슈 타입 값 분포 (Task/Sub-Task)
14. action_verb 배정률 (전체 tasks 대비 NULL 비율)
15. 의존성 순환 감지 (`task_dependencies` 재귀 CTE)
16. 날짜 논리 위반 (`v_dep_date_violations` row 수)
17. 콘텐츠명 중복 (파트 내 `::2` suffix 현황)

---

## 10. Row 값 마스터 및 Enum (v1.1)

### 10-1. 목표 (`versions.code`)

| code | label | 설명 |
|------|-------|------|
| launch | 론칭 | 최초 출시 |
| upd1 | 1차 업데이트 | 론칭 이후 첫 번째 업데이트 |
| s1~s10 | 시즌N | 시즌 업데이트 |
| cbt | CBT | Closed Beta Test |
| undecided | 미정 | 공백 자동 매핑 |

자동 매핑: `1차` → `upd1`, `론칭` → `launch`, `시즌N` → `sN`, 공백 → `undecided`

### 10-2. 지역/챕터 (`regions` 마스터)

| 컬럼 | 형식 | 예 |
|------|------|-----|
| code | `{chapter}.{num}` | `3.1` |
| chapter_id | 정수 | 3 |
| location_number | 정수 | 1 |
| name | 텍스트 | 스톰스엔드 |
| display | 생성 컬럼 | `3.1. 스톰스엔드` |

`tasks.region_chapter`는 `code`만 저장. Export 시 `display`로 결합.

### 10-3. 이슈 타입 (enum)

`Task` / `Sub-Task` / NULL. 역추론: `parent_task_id IS NULL` → Task, else Sub-Task.

### 10-4. 상태 (기존 enum)

`시작 전` / `진행 중` / `완료됨` / `보류` / `중단`

### 10-5. 유관파트 (enum code)

`field` / `quest` / `combat` / `level` / `art` / `narrative` / `ux` / `class` / `validation`

복수: `,` + space 구분 (parser는 `/` 도 수용). 접미어 `파트` 자동 제거.

### 10-6. action_verb (`task_action_verbs` 마스터)

| code | label | 게이트 단계 |
|------|-------|-------------|
| draft_doc | 구현 기획서 작성 | G3 |
| implement | 구현 | G5 |
| data_entry | 데이터 작업 | G5 |
| resource_request | 리소스 요청 | G4 |
| polish | 폴리싱 | G7 직전 |
| qa_response | QA 대응 | G7 |
| fun_review | 재미검증 | G6 |
| ip_review | IP 검수 대응 | G0a |

### 10-7. 분류 (`part_categories` 파트별 격리)

파트 간 분류 축이 다름 -> 단일 테이블이지만 `(part_id, code)` 유일성. 파트 간 이름 충돌 허용.

---

## 11. 네이밍 컨벤션 (v1.1)

### 11-1. 토큰 구조

```
task.title = {title_object} {action_label}   (title_object 선택)
```

예:
- `하렌홀의 비명 구현 기획서 작성`
- `폴리싱` (title_object 생략)
- `챕터4.1 메인 퀘스트 보스 - 쉘윈 구현`

### 11-2. 금지 규칙

- 괄호 `( )` 금지 (JIRA summary 파싱 깨짐) → 하이픈 `-` 사용
- em dash `—` 금지 (전역 LintRules A 준수)
- 전각 괄호 `（）`, 이모지, 연속 공백 금지
- title 길이 3~60자
- `action_verb` non-null일 때 title 끝이 해당 label로 끝나야 함

### 11-3. JIRA summary 연동

기존 템플릿: `[{{content_type_label}}] {{content_name}} - {{task_title}}`

v12 `jira_templates.action_verb_map` 통해 task_title 내부 action 치환 가능.

### 11-4. 파생 업무 자동 생성

`task_templates.steps` JSONB 에 action_verb + offset_days + depends_on 정의. 콘텐츠 생성 시 template 선택 → tasks + task_dependencies 일괄 생성.

---

## 12. 의존성 모델 (v1.1)

### 12-1. 타입

- `finishes_before`: A 완료 후 B 시작 가능 (JIRA `is blocked by`)
- `starts_together`: A와 B 동시 시작 (JIRA `relates to` + label `starts-together`)

### 12-2. 제약

- Self-dependency 금지 (`CHECK task_id <> depends_on_task_id`)
- 동일 (task_id, depends_on, dep_type) 중복 금지 (UNIQUE)
- 순환 의존 감지: `trg_check_dep_cycle` BEFORE INSERT/UPDATE trigger
- 날짜 논리: `v_dep_date_violations` view (finishes_before인데 B.start < A.end)

### 12-3. 크로스 파트/콘텐츠 허용

파트/콘텐츠 다른 task 간 의존성 허용. UI에서 오렌지 배지로 표시.

---

## 13. 변경 이력

| 일자 | 버전 | 변경 |
|------|:----:|------|
| 2026-04-22 | 1.0 | 초기 작성. 20열 표준 확정 (운영 16 + 메타 4). 플랜 18열 → 20열 흡수. |
| 2026-04-22 | 1.1 | Row 값 마스터 테이블 + 의존성 모델 + 네이밍 컨벤션 추가. v12 마이그레이션 정의. 섹션 10~12 신설. |
