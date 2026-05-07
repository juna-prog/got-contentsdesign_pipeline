# Phase 6 JIRA 양방향 sync - Operator Workflow

> 파이프라인 트래커는 source-of-truth. 실제 JIRA 호출은 operator (REST 직접 - jira_rest_operator.py) 가 큐 처리. MCP 한계 3종 우회 완료 (P2, 2026-04-28). 자격증명은 env 또는 operator/.jira_creds.json (gitignored).

## 빠른 시작 (운영자)

```
# Windows
operator\run.bat              # pending 전체 처리
operator\run.bat --dry-run    # 실 호출 없이 plan 출력
operator\run.bat --limit 1    # 1건만 (smoketest)
operator\run.bat --log-id 99  # 특정 log id 만

# bash / WSL
cd operator && python jira_rest_operator.py
```

자격증명 미설정 시 `--dry-run` 은 실행되며, 그 외에는 안내 메시지와 함께 종료됩니다.

## 1주 1회 운영 루틴 (권장)

**매주 월요일 오전** (또는 pending 누적 시 즉시):

1. AdminPanel → 🎫 JIRA 큐 탭 진입
2. **대기 (pending)** 카운트 확인
   - 0 건 → 스킵
   - 1 ~ N 건 → 다음 단계
3. **실패 (failed)** 카운트 확인 - 있으면 사유 분석 후 재처리 여부 결정
4. operator 노드에서 `run.bat` 실행 (자격증명 + 네트워크 사내망 OK)
5. 실행 종료 후 트래커 새로고침 → 큐 탭에서 pending → done 전환 확인 + tasks.jira_url / contents.jira_epic_key 백필 확인
6. JIRA 보드에서 생성된 이슈 1~2건 샘플 확인 (reporter / Epic Link / labels / fixVersions 정상)

**모니터링 신호** (pending 누적 = 운영자 부담):
- pending > 30 → 1주 주기를 단축하거나 일감 생성 빈도 조정
- 실패율 > 10% → 자격증명 만료 / JIRA 권한 변경 가능성, 즉시 점검

## Windows Task Scheduler (선택, 자동 실행)

수동 실행이 부담이면 Windows 작업 스케줄러로 등록:

1. 작업 스케줄러 → "기본 작업 만들기"
2. 트리거: 매주 월요일 09:00
3. 동작: 프로그램 시작 → `<repo>\operator\run.bat`
4. 시작 위치: `<repo>\operator`
5. 로그 확인: 작업 스케줄러 기록 탭 + JIRA 큐 탭의 최근 처리 시각

⚠ 자격증명 파일이 잠긴 사용자 계정에 있어야 task account 가 접근 가능. 또는 환경변수 등록.

## 자격증명 갱신 (PAT 만료 등)

JIRA 비밀번호 / Personal Access Token 만료 시:

1. JIRA 웹 → 프로필 → 보안 → API token / 비밀번호 갱신
2. `operator/.jira_creds.json` 의 `pass` 필드 업데이트 (template 은 `.jira_creds.json.template` 참고)
3. `operator\run.bat --dry-run` 으로 자격증명 로딩 확인
4. 정상이면 다음 pending 처리 시 자동 사용

## 데이터 흐름

```
[기획자]                 [파이프라인 웹앱]              [Supabase]              [Operator]              [JIRA]
   |                           |                            |                       |                       |
   | 콘텐츠 Gate 진행           |                            |                       |                       |
   |--------------------------->| JIRA 일감 생성 버튼         |                       |                       |
   |                           |-- insert jira_creation_log>|                       |                       |
   |                           |   (status=pending,         |                       |                       |
   |                           |    operation_type)         |                       |                       |
   |                           |                            |<-- v_jira_pending ----|                       |
   |                           |                            |                       |-- mcp__jira_create_issue->
   |                           |                            |                       |<-- {key, url} --------|
   |                           |                            |<-- update log(done) --|                       |
   |                           |                            |<-- update task/content|                       |
   | 새로고침                   |<--- SELECT ----------------|                       |                       |
   |<-- 🎯/🎫 배지 --           |                            |                       |                       |
```

## Operator 처리 절차 (Claude 세션)

### 0. 툴 로드

배포된 Claude 세션에서 mcp__jira 스키마는 deferred. 세션 시작 시:

```
ToolSearch("select:mcp__jira__jira_create_issue,mcp__jira__jira_get_issue,mcp__jira__jira_search,mcp__jira__jira_list_projects,mcp__jira__jira_update_issue,mcp__jira__jira_add_comment,mcp__jira__jira_get_transitions,mcp__jira__jira_transition_issue")
```

### 1. pending 큐 조회

```sql
SELECT * FROM v_jira_pending;
```

또는 python:

```python
import json, urllib.request
SU='https://huegoxqcoqealhhlrkww.supabase.co'
SK='<anon-key>'
H={'apikey':SK,'Authorization':f'Bearer {SK}'}
req=urllib.request.Request(SU+'/rest/v1/v_jira_pending?select=*', headers=H)
pending = json.loads(urllib.request.urlopen(req).read().decode('utf-8'))
```

### 2. create_epic 처리

1. `payload.fields.summary` / `description` / `labels` 를 `mcp__jira__jira_create_issue` 에 전달 (`issueType="Epic"`)
2. 반환 key / url 을 `jira_creation_log.result_key`, `result_url`, `status='done'`, `executed_at=now()`, `executed_by='claude'` 로 업데이트
3. `contents.jira_epic_key` 와 `jira_epic_url` 도 갱신

### 3. create_subtask 처리

두 모드 지원:

**A. Epic Link 모드** (정석, content-level Epic 있는 경우):
- `target_epic_key` 가 있으면 Epic 에 연결
- `issueType="Task"` + Epic Link 커스텀필드 (JIRA 설정별 상이, 필요 시 추가 update_issue)

**B. parent Task 모드** (기존 Task 가 이미 JIRA 연결된 경우):
- `parentKey=<기존 task.jira_url 의 key>` 사용
- `issueType="Sub-Task"` (PROJECTT 표기, 정확한 대소문자 유지)
- Epic 없이도 동작. 기존 400+ task 연결 건에 Sub-Task 추가할 때 사용

JIRA 생성 후:
1. 반환 key / url 을 로그 + `tasks.jira_url` 에 반영
2. 실패 시 `status='failed'`, `error_message=...` 기록

### 4. 실패 처리

- JIRA 인증 실패, 네트워크 오류, 권한 부족 등은 `status='failed'` 로 남기고 다음 건 진행
- 오류 패턴이 반복되면 기획자에게 보고

### 5. Supabase 백필 스니펫 (재사용)

```python
from datetime import datetime, timezone
H={'apikey':SK,'Authorization':f'Bearer {SK}','Content-Type':'application/json','Prefer':'return=representation'}
def patch(p, body):
    req=urllib.request.Request(SU+'/rest/v1/'+p, headers=H, method='PATCH',
                                data=json.dumps(body).encode('utf-8'))
    return json.loads(urllib.request.urlopen(req).read().decode('utf-8'))

now = datetime.now(timezone.utc).isoformat()
# log 백필
patch(f'jira_creation_log?id=eq.{log_id}', {
    'status':'done', 'result_key':key, 'result_url':url,
    'executed_at':now, 'executed_by':'claude'
})
# task 또는 content 백필
patch(f'tasks?id=eq.{task_id}', {'jira_url': url})          # Sub-Task
patch(f'contents?id=eq.{content_id}', {                      # Epic
    'jira_epic_key': key, 'jira_epic_url': url
})
```

## Contents 화면 UX

| 상태 | 표시 |
|------|------|
| Epic 미등록, 대기 없음 | "미등록" + [🔗 기존 Epic 연결] 버튼 |
| Epic 미등록, create_epic pending | ⏳ 생성 대기 |
| Epic 등록됨 | 🎯 PROJECTT-12345 (링크) + ✏️ 수정 |

태스크 행:

| 상태 | 표시 |
|------|------|
| jira_url 없음, 대기 없음 | (표시 없음) |
| create_subtask pending | ⏳대기 (노란 배지) |
| jira_url 있음 | 🎫PROJECTT-99999 (링크) |

## 주의

- **Sub-Task 생성 모드 2종 (v16+ UI 에서 선택)**: 
  - Epic Link 모드: content.jira_epic_key 필수. `target_epic_key` 가 로그에 저장됨. operator 는 customfield_10008 로 Epic 연결
  - 부모 Task 모드: payload.fields.parent.key 가 이미 포함됨. Epic 없이 동작
- Epic 키는 팀장/파트장만 편집
- operator 가 처리하기 전에는 실제 JIRA 일감이 없음. 기획자에게 "대기 중"임을 명확히 알려야 함
- JIRA REST API direct 호출(JiraSyncModal) 은 status→tracker 방향만 수행 (사내 CORS 이슈로 일부 환경에서 manual paste 사용)
- PROJECTT 의 Sub-Task issueType 정확 명칭은 `Sub-Task` (대문자 T). JQL 은 case-insensitive 하지만 create 시엔 정확히

## v16+ payload 스펙 (UI 측 생성 완료)

UI 가 `jira_creation_log.payload` 에 이미 다음을 채워 넣어 operator 부담 경감:

- `fields.summary` / `description` (wiki markup 변환 완료)
- `fields.assignee.name` - task.assignee_id 의 workers.jira_account_id (= JIRA username)
- `fields.reporter.name` - content.owner 의 workers.jira_account_id, 미매칭 시 `juna`
- `fields.parent.key` - 부모 Task 모드일 때만 포함
- `fields.priority`, `fields.labels`, `fields.project`, `fields.issuetype`
- `_subtask_mode` - "epic_link" | "parent_task" (operator 가 mcp__jira 호출 분기 시 참고)

operator 는 payload 를 그대로 `mcp__jira__jira_create_issue` 에 전달하면 됨.
추가 후처리:
- Epic Link 모드: Epic 연결 필드가 issuetype 별로 다르면 `mcp__jira__jira_update_issue` 로 `customfield_10008` = target_epic_key 별도 주입
- Sub-Task issueType id 가 프로젝트마다 상이하면 `/rest/api/2/issue/createmeta?projectKeys=PROJECTT&expand=projects.issuetypes` 로 조회 후 id 치환

## description wiki markup 규칙 (UI `formatJiraDescription` 이식본)

index.html 에 `formatJiraDescription(text)` 으로 포팅되어 payload 시점에서 이미 변환된 상태로 로그에 저장됨.
규칙:
- `## 헤더` 또는 `[헤더]` 단독 줄 → `*헤더*`
- `- item` / `• item` / `· item` → `* item`
- `---` → `----` (divider)
- 연속 본문 줄 끝에 `\\` (강제 개행)
- 빈 줄은 유지 (문단 구분)

operator 가 수동으로 payload 를 편집해야 할 때는 이 규칙을 따라야 JIRA 렌더링이 깨지지 않음.
사용자가 DB 에 markdown 으로 적은 설명을 그대로 mcp__jira 에 넘기면 `##` 이 plain text 로 들어감 (과거 #39215/#39216 에서 발생한 버그).

## 실행 이력

### 2026-04-24 - 첫 operator 배치 실행

**대상**: log#1 / log#2 (content 674 "읽을거리", parent task #1943 = PROJECTT-38075 이미 연결됨)

**선택 모드**: B (parent Task 모드) — content-level Epic 소급 생성 생략

**결과**:
- #1999 "웨스터랜드 읽을거리 작성" → PROJECTT-39215 (parentKey=PROJECTT-38075, Sub-Task)
- #2000 "웨스터랜드 읽을거리 데이터 작업" → PROJECTT-39216 (parentKey=PROJECTT-38075, Sub-Task)
- 양쪽 log status=done, tasks.jira_url 백필 완료
- PROJECTT-38075 Subtasks 2건 정상 노출 확인

**교훈**:
- 파일 저장된 payload 의 `issuetype.name="Task"` 는 UI 가 Epic Link 모드 전제로 생성한 것. parent Task 모드에서는 `Sub-Task` 로 치환 필요
- assignee username 미확보 시 일단 생성만 하고 JIRA 에서 수동 배정. 추후 `workers` 테이블에 jira_username 컬럼 추가 검토

### 2026-04-25 - P1 실전 검증 (log#3)

**대상**: 테스트 task #2418 (content 674 "읽을거리", parent=PROJECTT-38075, 2모드=parent_task)

**결과**:
- PROJECTT-39226 생성 완료. PROJECTT-38075 subtasks 2→3
- assignee=juna 자동 주입 ✓ (payload.fields.assignee.name → MCP assignee 파라미터)
- wiki markup 렌더링 ✓ (`*헤더*` / `* bullet` / `----` 모두 정상)
- log#3 status=done / result_key / executed_by=claude 백필 + tasks.jira_url 반영

**신규 교훈 (MCP 한계)**:
- `mcp__jira__jira_create_issue` 는 `reporter` 파라미터를 노출하지 않음. payload 에 `fields.reporter.name=hycho` 를 넣어도 실제 생성된 issue 의 reporter 는 MCP 인증 사용자(juna) 로 고정됨
- `mcp__jira__jira_update_issue` 도 reporter 미지원. 진짜 reporter 변경이 필요하면 JIRA 웹에서 수동 전환 또는 JIRA REST API `/rest/api/2/issue/{key}` PUT 직접 호출 필요
- 실무상 reporter 는 대부분 `juna` 로 무방하므로 현재는 제약 수용. payload 의 `reporter.name` 필드는 감사/회계용으로 유지

### 2026-04-25 - P1 Epic Link 모드 검증 (log#4, UI→log 경로 한정)

**대상**: 테스트 task #2419 (content 674 mock Epic `PROJECTT-TEST-EPIC-MOCK`, 2모드=epic_link)

**결과 (UI → log payload 경로)**: ✓
- `_subtask_mode="epic_link"` 정상 기록
- `fields.parent` 부재 ✓ (parent_task 모드와 구분됨)
- `fields.issuetype.name="Task"` ✓ (template default, Sub-Task 아님)
- `jira_creation_log.target_epic_key` 컬럼에 Epic key 저장 ✓

**결과 (operator 실행 경로)**: ✗ 실행 불가 (MCP 한계)

**MCP 한계 2종 발견**:
1. **Epic 생성 불가**: `mcp__jira__jira_create_issue` 가 `customfield_13102` (Epic Name) 필수 필드를 받지 못함. 400 `"Epic Name is required."` 에러. 
2. **Epic Link 설정 불가**: `mcp__jira__jira_update_issue` 가 임의의 customfield (e.g. `customfield_10008` Epic Link) 를 지원하지 않음. 생성 후 Epic 에 연결하는 방법 없음.

**실사용 대안 경로**:
- **Epic 생성**: JIRA 웹 수동 생성 → key 복사 → UI `[🔗 기존 Epic 연결]` 로 content.jira_epic_key 등록
- **Epic Link 설정**: 두 가지 중 선택
  - (a) operator 가 Task 를 MCP 로 생성 후, JIRA 웹에서 Epic Link 수동 추가
  - (b) JIRA REST API 직접 호출: `PUT /rest/api/2/issue/{key}` with `{"fields":{"customfield_10008":"<EPIC_KEY>"}}` + Basic Auth 헤더

**권장 운영 방식 (현재)**:
- parent_task 모드 우선 사용 (기존 400+ task 이미 JIRA 연결, 추가 Sub-Task 처리에 유리)
- Epic 신규 생성이 필요한 content 는 기획자가 JIRA 웹에서 선생성 후 UI 에 등록
- 그 다음에만 Epic Link 모드 활용

**검증 후 정리**: log #4 DELETE, task #2419 DELETE, contents.jira_epic_key 롤백 완료. JIRA 에는 실제 데이터 생성 안됨.

### 2026-04-25 - P1 검증 후 정리

parent_task 검증 Supabase 잔존: log #3 DELETE, task #2418 DELETE 완료.

**JIRA 측 수동 정리 필요** (MCP 한계로 자동 삭제 불가):
- `PROJECTT-39226` (test Sub-Task) → JIRA 웹에서 수동 삭제 권장. `auto-generated`, `from-tracker`, `test-p1` 라벨로 식별 가능.

### P1 → P2 이관 요약

**검증 완료**:
- parent_task 모드 E2E (MCP create + backfill 정상 동작)
- epic_link 모드 UI → log payload shape (parent 부재 / issuetype=Task / target_epic_key 컬럼)

**MCP 스키마 한계 (P2 또는 별도 개선 대상)**:
1. `reporter` 지정 불가 → payload 감사 용도 한정
2. Epic `customfield_13102` (Epic Name) 누락 → Epic 생성 불가
3. `customfield_10008` (Epic Link) 등 임의 customfield 설정 불가 → 생성 후 Epic 연결 불가

**단기 운영 권장**:
- parent_task 모드 우선 (기존 400+ task 재활용)
- Epic 신규는 기획자 수동 생성 후 UI [🔗 기존 Epic 연결] 로 등록
- 실사용 때 MCP 한계가 병목이 되면 JIRA REST API 직접 호출 operator 경로 신설

### 2026-04-28 - P2 진입 - REST API 직접 operator 신설

**배경**: P1 검증 결과 MCP 한계 3종 (reporter / Epic Name / Epic Link) 으로 인해 epic_link 모드 자동화 차단 + Epic 자동 생성 차단. REST 직접 호출 경로로 우회.

**산출물**: `operator/jira_rest_operator.py` (단일 파일, urllib stdlib only)

**자격 증명**:
- 우선순위: env (`JIRA_USER` / `JIRA_PASS`) > 파일 (`operator/.jira_creds.json`)
- 파일 형식: `{"user":"juna","pass":"<password-or-PAT>"}` (gitignored)
- env 한 가지 빠지면 파일 fallback 시도

**Custom field override (env)**:
- `JIRA_EPIC_NAME_FIELD` 기본 `customfield_13102` (jira.nmn.io 실측)
- `JIRA_EPIC_LINK_FIELD` 기본 `customfield_13101` (jira.nmn.io 실측. JIRA Cloud 기본값 customfield_10008 과 다름)
- 신규 JIRA 인스턴스 사용 시 `GET /rest/api/2/field` 로 ID 확인 후 env 로 override
- 참고: customfield_13100 = Sprint (P3 Agile API 트랙용)

**처리 흐름**:
1. `create_epic`: payload.fields 에 `customfield_13102=summary` 자동 주입 + assignee 미설정 시 `juna` 기본값 (JIRA 자동 배정 회피) → POST `/rest/api/2/issue` → `contents.jira_epic_key`/`jira_epic_url` 백필
2. `create_subtask` (parent_task 모드): payload 그대로 POST → `tasks.jira_url` 백필
3. `create_subtask` (epic_link 모드): POST → 후처리 PUT `/rest/api/2/issue/{key}` `{customfield_13101: target_epic_key}` → `tasks.jira_url` 백필
4. 모든 case: payload 의 `reporter.name` 이 인증 사용자와 다르면 후처리 PUT 으로 reporter 변경 (권한 부족 시 경고만 남기고 계속)

**CLI 옵션**:
- `--dry-run`: 실제 호출 없이 plan 출력 (자격 증명 없어도 실행 가능)
- `--log-id N`: 특정 log 1건만 처리
- `--limit N`: 최대 N건 처리

**검증 (2026-04-28 dry-run smoketest)**:
- 합성 pending log 2건 (parent_task / epic_link) 삽입 → dry-run 양 모드 분기 정상 → log 삭제

**E2E 실전 검증 (2026-04-28 Round 1+2)**:
- **MCP 한계 1 우회 (reporter)**: log#7 → PROJECTT-39403 생성, payload reporter=hycho → JIRA 실제 reporter=hycho 확인 ✓
- **MCP 한계 2 우회 (Epic 생성)**: log#8 → PROJECTT-39404 (Epic) 생성, customfield_13102 (Epic Name) 자동 주입 정상 ✓
- **MCP 한계 3 우회 (Epic Link)**: log#9 → PROJECTT-39405 (Task) 생성, 처음엔 customfield_10008 사용으로 400 에러 → `GET /rest/api/2/field` 로 실제 ID 조사 → `customfield_13101` 로 코드 수정 후 PUT 성공, Epic Link → PROJECTT-39404 정상 설정 ✓

**신규 운영 한계 발견**:
- **JIRA REST DELETE 권한 부족 (403)**: `DELETE /rest/api/2/issue/{key}` 시 `"You do not have permission to delete issues in this project."` 응답. test artifact 자동 정리 불가 → 사용자 수동 삭제 필요
- jira.nmn.io 의 Epic Link customfield ID 가 JIRA Cloud 기본값(10008)과 다름 → 실측 13101. 다른 JIRA Server 인스턴스마다 ID 달라질 수 있어 env 로 override 가능하게 설계됨

**MCP 와의 차이**:
| 항목 | MCP (`mcp__jira__jira_create_issue`) | REST (`jira_rest_operator.py`) |
|------|---|---|
| reporter 지정 | 미지원 | 후처리 PUT 으로 가능 (권한 필요) |
| Epic 생성 (Epic Name) | 400 | `customfield_13102` 자동 주입 |
| Epic Link (customfield_13101) | 미지원 | 후처리 PUT 으로 가능 |
| 자격 증명 관리 | MCP 인증 (juna 고정) | env / file (사용자 지정) |
| CORS | 영향 없음 (서버측) | 영향 없음 (서버측, 같은 패턴) |
| `_subtask_mode` 분기 | 후처리 분기 불가 | 모드별 자동 분기 |

**잔여 한계**:
- reporter 변경은 JIRA 권한에 따라 실패 가능 → 운영 중 권한 부족 발생하면 관리자에게 grant 요청
- JIRA REST DELETE 권한 부족 → test artifact 정리는 수동
- Sprint 자동 투입 (Agile API `/rest/agile/1.0/...`) 은 P3 별도 트랙 (현재는 수동)

**JIRA 측 수동 정리 필요**:
- PROJECTT-39403 (test Sub-Task, parent=PROJECTT-38075, reporter=hycho)
- PROJECTT-39404 (test Epic)
- PROJECTT-39405 (test Task, Epic Link → PROJECTT-39404)
- 라벨 `test-p2` 로 식별 가능

### 2026-04-30 - P2 stage B - SprintConfig + WorkTypes + payload 보강

**스키마 변경 (v17)**: `migrations/v17_sprint_worktypes.sql`

신규 테이블:
- `sprint_config(version_id UNIQUE, jira_sprint_id, jira_sprint_name, jira_board_id, fix_version, default_components[], default_labels[], default_priority, is_active, notes)`
- `work_types(work_type_key UNIQUE, label, part_id, default_est_days, default_priority, default_components[], default_labels[], default_action_verb, sort_order, is_active)`

확장:
- `jira_templates.default_fix_versions TEXT[]`
- `jira_templates.default_components TEXT[]`

뷰: `v_jira_payload_defaults` (versions × sprint_config 머지뷰)

Seed:
- `work_types` 14건: art_char_concept~art_ta + cutscene + design_doc/data/ip_review/qa/polish/fun_review
- `sprint_config` UP01 1건 (fix_version="[T] 업데이트")

**적용 방법**: Supabase 웹 SQL editor 에서 `v17_sprint_worktypes.sql` 전체 실행.

**UI 변경 (index.html)**:

신규 db helper:
- `db.workTypes()` → `work_types?is_active=eq.true`
- `db.sprintConfigs()` → `sprint_config?is_active=eq.true`

`JiraPreviewModal` 머지 로직 (`mergeFields(task, baseLabels)`):
- priority 우선순위: `task.priority` > `sprint_config.default_priority` > `work_type.default_priority` > `jira_templates.priority` > "Medium"
- labels: `jira_templates.labels` ∪ `work_type.default_labels` ∪ `sprint_config.default_labels` ∪ baseLabels (unique 보존)
- components: `jira_templates.default_components` ∪ `work_type.default_components` ∪ `sprint_config.default_components` (unique → `[{name}]`)
- fixVersions: `sprint_config.fix_version` 우선, 없으면 `jira_templates.default_fix_versions` (unique → `[{name}]`)

`resolveWorkType(task)`: `content.source_key` 프리픽스로 partId 도출 후, 동일 part 내에 여러 work_type 이 있으면 `task.action_verb` 로 추가 매칭. (tasks 테이블에 part_id 컬럼 없음에 주의)

Epic / Sub-Task 모두 동일 `mergeFields` 통해 payload 구성. 미리보기 grid 에 sprint config 출처 + Work Type 권장 일수 + Components / Fix Versions 표시.

**operator 무수정**: `payload.fields` 그대로 POST 하므로 components/fixVersions 자동 전달 (JIRA REST 표준 필드).

## 2026-05-04 - Track 4 - import 시 work_types.default_est_days 자동 채움

**범위**: `buildTaskPayload(t, contentIdByKey, workerByName, parentId, now, workTypes)` 시그니처에 6번째 파라미터 `workTypes` 추가. `t.days` 가 null/empty 일 때 `pickWorkType(workTypes, partId, t.action_verb)` 로 매칭해 `default_est_days` 를 round 후 주입. partId 는 `t._content_source_key` 프리픽스로 도출.

`pickWorkType` 모듈 레벨 헬퍼로 분리하여 import + JIRA preview 양쪽에서 공용. JiraPreviewModal 의 기존 `resolveWorkType` 도 이 헬퍼 호출로 단순화. 이전 코드의 `task.part_id` 직접 비교는 tasks 테이블에 part_id 컬럼이 없어 항상 null 반환하던 미발견 버그 - content.source_key 프리픽스 기반으로 교정.

ImportModal.run 흐름에 `db.workTypes()` 1회 호출 추가 + 진단 로그 (`[import] days 미입력 N건 -> work_types.default_est_days 자동 채움`).

**적용 범위 한계**: v17 seed 의 work_types 는 `art_*`, `cutscene`, `design_*` part_id 만 등록됨. 4파트 (`combat`/`level`/`field`/`quest`) 는 work_type 미정의 → `pickWorkType` null → days 미변경. 4파트도 자동 채움 원하면 work_types seed 확장 필요.

**v17b - default_est_days placeholder 제거 (2026-05-04)**: v17 의 일수값(5/8/3/2/1)은 임의 추정이라 파트장 합의 전엔 자동 채움/권장 표시 비활성. 마이그레이션 `v17b_clear_placeholder_estdays.sql` 적용으로 14건 전부 NULL 처리. 코드는 `wt.default_est_days != null` 가드로 동작 → 자동 채움 미발동 + UI "(권장 N일)" 미표시. 향후 파트장 표준 일수 합의 후 work_type 별 UPDATE 로 복원. 정본 일정은 JIRA 일감에 등록된 시작/종료 일자.

**TemplateApplyModal**: 변경 없음. step.duration 은 템플릿 정의 시 이미 설계자가 정한 값이므로 work_types 우선 적용은 보류.

**잔여 (별도 트랙)**:
- Sprint 자동 투입 (`/rest/agile/1.0/board/1221/sprint`) - P3 (사용자 합의: 추후 설계)
- work_types seed 4파트 확장 (필요 시)

## 2026-05-07 - close_epic / close_subtask op_type 명세 (큐 적재만, operator 미구현)

**배경**: 콘텐츠 카드 삭제 (commit f29e342) 시 사용자가 "JIRA 일감도 같이 닫기" 옵션 선택하면 `jira_creation_log` 에 `close_epic` / `close_subtask` pending 적재. 현재 operator v1 은 미처리 → AdminPanel JIRA 큐 탭에 ⚠ 배지 표시.

**큐 row shape** (UI 가 INSERT):
```
{
  status: "pending",
  operation_type: "close_epic" | "close_subtask",
  content_id: null,                  // FK 회피 (콘텐츠는 이미 DELETE)
  task_id: null,                     // 동일
  payload: {
    jira_key: "PROJECTT-39403",
    jira_url: "https://jira.nmn.io/browse/PROJECTT-39403",
    reason: "사용자 입력 사유",
    deleted_content_name: "...",
    deleted_content_type: "...",
    actor_email: "..."
  }
}
```

**operator 처리 안 (v2 후속)**:
1. `GET /rest/api/2/issue/{key}/transitions` → 가능한 transition 조회
2. "Done" / "Closed" / "Resolved" 중 하나의 transition id 선택
3. `POST /rest/api/2/issue/{key}/transitions` body `{transition:{id}, fields:{resolution:{name:"Done"}}}` 또는 fields 없이
4. 코멘트 추가: `POST /rest/api/2/issue/{key}/comment` body `{body: "트래커에서 콘텐츠 삭제. 사유: {reason}"}`
5. 백필: log status=done / executed_at / executed_by

**현재 운영 한계**:
- v1 operator 가 `미지원 operation_type` 으로 fail 처리 → status=failed 로 빠짐 (큐는 정리됨)
- 또는 사용자가 큐를 그대로 두고 JIRA 웹에서 수동 닫기 + 큐 row 수동 삭제

**임시 회피**:
- 카드 삭제 시 "JIRA 같이 닫기" 옵션 미사용 (트래커만 삭제) → JIRA 일감은 관리자가 별도로 처리
- 또는 닫을 일감이 적으면 JIRA 웹에서 수동 transition

**v2 우선순위**: 닫기 누적 빈도 보고 결정. 현 시점 (2026-05-07) 운영 진입 직후라 데이터 부족.

## 2026-05-04 - Track 3 - workers 편집 UI (팀장 전용)

**범위**: `WorkersAdminModal` 신규. 헤더 우측 `👥 작업자` 버튼 (is_team_lead 만 노출) → 모달 오픈.

**기능**:
- 좌측 리스트: 검색(이름/JIRA ID) + 파트 필터 + "비활성 포함" 체크박스 + 신규 추가 버튼. 정렬 = team_lead → part_lead → 일반, 그 안에서 part_id+name. 비활성 행은 회색 + `[비활성]` 배지.
- 우측 편집 패널: name (필수) / part_id 드롭다운 (parts 테이블 + PART_LABELS 머지 후 정렬) / jira_account_id (jira.nmn.io username) / is_part_lead / is_team_lead / is_active.
- dirty 상태 추적, 미저장 변경 시 모달 닫기/행 전환 시 confirm.
- 저장 = `editing==="new"` ? `db.insWorker(payload)` : `db.updWorker(editing.id, payload)`. 성공 시 `reload()` + `onDone()` (App.load(true)).

**신규 db helper**:
- `db.insWorker(d)` → POST `/workers`
- `db.updWorker(i,d)` → PATCH `/workers?id=eq.{i}`
- 의도적으로 `delWorker` 미추가. `task_assignees` 가 ON DELETE CASCADE 라 hard delete 시 과거 일감 매핑 손실. 퇴직자는 `is_active=false` 토글로만 처리.

**v18 마이그레이션 (workers.is_active 추가)**:
- `migrations/v18_worker_is_active.sql` - `ALTER TABLE workers ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE NOT NULL`.
- 적용 전엔 모달의 "활성" 토글 저장 시 PostgREST 가 unknown column 에러 → 코드는 메시지를 감지해 안내 문구 표시 (`v18 마이그레이션 미적용. migrations/v18_worker_is_active.sql 을 Supabase 에 먼저 실행해 주세요.`).
- 적용 후엔 신규/기존 모두 `is_active=TRUE` 기본값.

**적용 범위 한계 (의도적 비범위)**:
- UserModal 의 사용자 선택 드롭다운 / JIRA preview assignee 후보 / TaskSheet assignee 표시 등 다른 UI 의 "is_active=false 워커 숨기기" 처리는 후속. 현재 모달은 CRUD + 비활성 표시만 담당.
- 권한: 헤더 버튼이 is_team_lead 한정으로 노출되며, 모달 자체에는 추가 권한 가드 없음 (헤더 게이트로 충분).
