-- v11: SCHEMA_STANDARD v1.0 반영
-- Run on Supabase SQL editor (huegoxqcoqealhhlrkww.supabase.co)
--
-- 목적:
--   1) source_key upsert 지원 (부분 UNIQUE 인덱스)
--   2) tasks 테이블에 표준 20열 중 DB 미반영 3종 추가
--      - region_chapter (컬럼 2: 지역/챕터)
--      - issue_type     (컬럼 3: 이슈 타입, Task/Sub-Task)
--      - priority       (컬럼 18: 우선순위)
--
-- 참조: F:/Git/got-contentsdesign_pipeline/SCHEMA_STANDARD.md
-- 롤백: v11_rollback.sql

-- ============================================================================
-- v11.1 source_key 부분 UNIQUE 인덱스
-- ============================================================================
-- 이유: Postgres는 WHERE 절이 있는 부분 제약을 ADD CONSTRAINT로 생성 불가.
--       CREATE UNIQUE INDEX ... WHERE 로 대체.
-- 효과: source_key IS NOT NULL 행에 대해 유일성 보장, NULL은 허용

CREATE UNIQUE INDEX IF NOT EXISTS idx_contents_source_key_unique
  ON contents(source_key)
  WHERE source_key IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_tasks_source_key_unique
  ON tasks(source_key)
  WHERE source_key IS NOT NULL;

-- ============================================================================
-- v11.2 tasks - 표준 20열 중 미반영 컬럼 추가
-- ============================================================================

ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS region_chapter TEXT,
  ADD COLUMN IF NOT EXISTS issue_type TEXT,
  ADD COLUMN IF NOT EXISTS priority INTEGER;

-- issue_type 값 제한 (Task / Sub-Task / NULL)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'tasks_issue_type_check'
  ) THEN
    ALTER TABLE tasks
      ADD CONSTRAINT tasks_issue_type_check
      CHECK (issue_type IN ('Task', 'Sub-Task') OR issue_type IS NULL);
  END IF;
END$$;

-- priority 범위 제한 (1 이상, NULL 허용)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'tasks_priority_check'
  ) THEN
    ALTER TABLE tasks
      ADD CONSTRAINT tasks_priority_check
      CHECK (priority IS NULL OR priority >= 1);
  END IF;
END$$;

-- ============================================================================
-- v11.3 인덱스 (export/필터 성능)
-- ============================================================================

CREATE INDEX IF NOT EXISTS idx_tasks_region_chapter
  ON tasks(region_chapter)
  WHERE region_chapter IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_priority
  ON tasks(priority)
  WHERE priority IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tasks_issue_type
  ON tasks(issue_type)
  WHERE issue_type IS NOT NULL;
