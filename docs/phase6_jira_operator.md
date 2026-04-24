# Phase 6 JIRA 양방향 sync - Operator Workflow

> 파이프라인 트래커는 source-of-truth. 실제 JIRA 호출은 operator(Claude + mcp__jira)가 대기열 처리.

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
