# Phase 6 JIRA 양방향 sync - Operator Workflow

> 파이프라인 트래커는 source-of-truth. 실제 JIRA 호출은 operator(Claude + mcp__jira)가 대기열 처리.

## 데이터 흐름

```
[기획자]                      [파이프라인 웹앱]                     [Supabase]                  [Operator]                  [JIRA]
   |                                |                                  |                            |                           |
   | 콘텐츠 Gate 진행                |                                  |                            |                           |
   |------------------------------->| JIRA 일감 생성 버튼               |                            |                           |
   |                                |-- insert jira_creation_log ------>|                            |                           |
   |                                |   (status=pending,                 |                            |                           |
   |                                |    operation_type=create_epic      |                            |                           |
   |                                |    | create_subtask)               |                            |                           |
   |                                |                                  |                            |                           |
   |                                |                                  |<-- v_jira_pending 조회 -----|                           |
   |                                |                                  |                            |-- mcp__jira create_issue-->|
   |                                |                                  |                            |                           |
   |                                |                                  |                            |<--- {key, url} -----------|
   |                                |                                  |<-- update log(status=done, |                           |
   |                                |                                  |    result_key, result_url) |                           |
   |                                |                                  |<-- update contents / tasks |                           |
   |                                |                                  |    (jira_epic_key 또는     |                           |
   |                                |                                  |     jira_url)              |                           |
   | 새로고침                        |<--- SELECT ------------------------|                           |                           |
   |<------- 🎯 Epic / 🎫 Sub-Task 뱃지 표시 ------                      |                           |                           |
```

## Operator 처리 절차 (Claude 세션)

### 1. pending 큐 조회

```sql
SELECT * FROM v_jira_pending;
```

### 2. create_epic 처리

1. `payload.fields` 를 mcp__jira_create_issue 에 전달
2. 반환된 key / url 을 `jira_creation_log.result_key`, `result_url`, `status='done'`, `executed_at=now()`, `executed_by='claude'` 로 업데이트
3. `contents.jira_epic_key` 와 `jira_epic_url` 도 갱신

### 3. create_subtask 처리

1. `target_epic_key` 를 Epic Link 로 설정하여 mcp__jira_create_issue 호출
2. 반환 key / url 을 로그 + `tasks.jira_url` 에 반영
3. 실패 시 `status='failed'`, `error_message=...` 기록

### 4. 실패 처리

- JIRA 인증 실패, 네트워크 오류, 권한 부족 등은 `status='failed'` 로 남기고 다음 건 진행
- 오류 패턴이 반복되면 기획자에게 보고

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

- Sub-Task 생성은 반드시 Epic 키 등록 후 가능 (버튼 disabled)
- Epic 키는 팀장/파트장만 편집
- operator 가 처리하기 전에는 wellNo 실제 JIRA 일감이 없음. 기획자에게 "대기 중"임을 명확히 알려야 함
- JIRA REST API direct 호출(JiraSyncModal) 은 status→tracker 방향만 수행 (사내 CORS 이슈로 일부 환경에서 manual paste 사용)
