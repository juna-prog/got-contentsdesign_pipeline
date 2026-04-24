-- v15: Content 레벨 JIRA Epic + jira_creation_log 확장
-- Phase 6 JIRA 양방향 sync 1단계
-- 설계:
--   contents.jira_epic_key  - Epic JIRA 키 (예: PROJECTT-12345)
--   contents.jira_epic_url  - Epic 전체 URL (UI 편의, 파생 가능하지만 저장)
--   jira_creation_log.operation_type  - create_epic | create_subtask | update_status
--   jira_creation_log.target_epic_key - Sub-Task 생성 시 부모 Epic 키
--   jira_creation_log.result_key      - 실행 후 생성된 JIRA 키 (이전엔 jira_key 필드 존재, 명시적 rename)
-- 목적: 파이프라인 트래커가 source-of-truth, Claude(mcp__jira)가 배치 실행 후 결과 기록

-- ============================================================================
-- 1. contents 확장
-- ============================================================================

ALTER TABLE contents
  ADD COLUMN IF NOT EXISTS jira_epic_key TEXT,
  ADD COLUMN IF NOT EXISTS jira_epic_url TEXT;

CREATE INDEX IF NOT EXISTS idx_contents_jira_epic_key ON contents(jira_epic_key);

COMMENT ON COLUMN contents.jira_epic_key IS 'JIRA Epic key (예: PROJECTT-12345). 해당 콘텐츠 산하 태스크의 JIRA Sub-Task 부모.';
COMMENT ON COLUMN contents.jira_epic_url IS 'JIRA Epic 전체 URL. 버튼 링크 용.';

-- ============================================================================
-- 2. jira_creation_log 확장
-- ============================================================================

ALTER TABLE jira_creation_log
  ADD COLUMN IF NOT EXISTS operation_type TEXT DEFAULT 'create_subtask',
  ADD COLUMN IF NOT EXISTS target_epic_key TEXT,
  ADD COLUMN IF NOT EXISTS result_key TEXT,
  ADD COLUMN IF NOT EXISTS result_url TEXT,
  ADD COLUMN IF NOT EXISTS executed_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS executed_by TEXT;

-- 기존 jira_key/jira_url 컬럼은 유지 (backward-compat). 새 필드를 우선 사용.
-- operation_type 허용 값: create_epic, create_subtask, update_status, update_fields

CREATE INDEX IF NOT EXISTS idx_jira_log_status ON jira_creation_log(status);
CREATE INDEX IF NOT EXISTS idx_jira_log_op_status ON jira_creation_log(operation_type, status);
CREATE INDEX IF NOT EXISTS idx_jira_log_content ON jira_creation_log(content_id);

COMMENT ON COLUMN jira_creation_log.operation_type IS 'create_epic | create_subtask | update_status | update_fields';
COMMENT ON COLUMN jira_creation_log.target_epic_key IS 'Sub-Task 생성 시 부모 Epic key. Epic 생성 시 NULL.';
COMMENT ON COLUMN jira_creation_log.result_key IS '실행 완료 후 JIRA가 반환한 key (create 성공 시).';
COMMENT ON COLUMN jira_creation_log.status IS 'pending | executing | done | failed. pending 이 실행 대기.';

-- ============================================================================
-- 3. 운영 편의 뷰: v_jira_pending
-- ============================================================================

CREATE OR REPLACE VIEW v_jira_pending AS
SELECT
  l.id AS log_id,
  l.operation_type,
  l.content_id,
  c.name AS content_name,
  c.jira_epic_key AS content_epic_key,
  l.task_id,
  t.title AS task_title,
  t.assignee_id,
  l.target_epic_key,
  l.template_key,
  l.payload,
  l.created_by,
  l.created_at
FROM jira_creation_log l
LEFT JOIN contents c ON c.id = l.content_id
LEFT JOIN tasks t    ON t.id = l.task_id
WHERE l.status = 'pending'
ORDER BY l.created_at ASC;

COMMENT ON VIEW v_jira_pending IS 'Claude mcp__jira 배치가 처리할 pending 큐. 시간 오름차순.';
