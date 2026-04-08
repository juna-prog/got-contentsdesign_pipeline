-- Pipeline Tracker v5 - Phase D migration
-- Sheet import 기능을 위한 contents/tasks 컬럼 확장 + import_runs 추적 테이블
-- Run on Supabase SQL editor (huegoxqcoqealhhlrkww.supabase.co)

-- ============================================================================
-- D.1 contents - 시트 필드 수용
-- ============================================================================

ALTER TABLE contents
  ADD COLUMN IF NOT EXISTS category TEXT,
  ADD COLUMN IF NOT EXISTS doc_url TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS source_key TEXT,
  ADD COLUMN IF NOT EXISTS imported_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_contents_source_key ON contents(source_key);

-- ============================================================================
-- D.2 tasks - 시트 필드 수용 + 부모/자식 계층
-- ============================================================================

ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS related_part TEXT,
  ADD COLUMN IF NOT EXISTS jira_url TEXT,
  ADD COLUMN IF NOT EXISTS notes TEXT,
  ADD COLUMN IF NOT EXISTS days INTEGER,
  ADD COLUMN IF NOT EXISTS parent_task_id UUID REFERENCES tasks(id) ON DELETE CASCADE,
  ADD COLUMN IF NOT EXISTS source_key TEXT,
  ADD COLUMN IF NOT EXISTS imported_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_tasks_source_key ON tasks(source_key);
CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks(parent_task_id);

-- ============================================================================
-- D.3 import_runs - 임포트 이벤트 기록
-- ============================================================================

CREATE TABLE IF NOT EXISTS import_runs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  part_id TEXT NOT NULL,
  file_name TEXT,
  imported_by TEXT NOT NULL,
  contents_added INT DEFAULT 0,
  contents_updated INT DEFAULT 0,
  tasks_added INT DEFAULT 0,
  tasks_updated INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE import_runs ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS import_runs_all ON import_runs;
CREATE POLICY import_runs_all ON import_runs FOR ALL USING (true) WITH CHECK (true);
