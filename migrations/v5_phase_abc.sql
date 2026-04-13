-- Pipeline Tracker v5 - Phase A migration
-- Run on Supabase SQL editor (huegoxqcoqealhhlrkww.supabase.co)

-- ============================================================================
-- A.1 Gate system normalization (G0~G7)
-- Old: G0 / G0a / G1 / G1a / G1b / G2 / G3
-- New: G0 / G1  / G2 / G3  / G4  / G5 / G7  (G6 새로 추가)
-- ============================================================================

UPDATE contents SET gate = CASE
  WHEN gate = 'G3'  THEN 'G7'
  WHEN gate = 'G2'  THEN 'G5'
  WHEN gate = 'G1b' THEN 'G4'
  WHEN gate = 'G1a' THEN 'G3'
  WHEN gate = 'G1'  THEN 'G2'
  WHEN gate = 'G0a' THEN 'G1'
  ELSE gate
END
WHERE gate IN ('G0a','G1','G1a','G1b','G2','G3');

UPDATE gate_transitions SET from_gate = CASE
  WHEN from_gate = 'G3'  THEN 'G7'
  WHEN from_gate = 'G2'  THEN 'G5'
  WHEN from_gate = 'G1b' THEN 'G4'
  WHEN from_gate = 'G1a' THEN 'G3'
  WHEN from_gate = 'G1'  THEN 'G2'
  WHEN from_gate = 'G0a' THEN 'G1'
  ELSE from_gate
END
WHERE from_gate IN ('G0a','G1','G1a','G1b','G2','G3');

UPDATE gate_transitions SET to_gate = CASE
  WHEN to_gate = 'G3'  THEN 'G7'
  WHEN to_gate = 'G2'  THEN 'G5'
  WHEN to_gate = 'G1b' THEN 'G4'
  WHEN to_gate = 'G1a' THEN 'G3'
  WHEN to_gate = 'G1'  THEN 'G2'
  WHEN to_gate = 'G0a' THEN 'G1'
  ELSE to_gate
END
WHERE to_gate IN ('G0a','G1','G1a','G1b','G2','G3');

-- Verify
-- SELECT gate, COUNT(*) FROM contents GROUP BY gate ORDER BY gate;

-- ============================================================================
-- A.2 contents - target_build, locked
-- ============================================================================

ALTER TABLE contents
  ADD COLUMN IF NOT EXISTS target_build TEXT,
  ADD COLUMN IF NOT EXISTS locked BOOLEAN DEFAULT FALSE;

-- ============================================================================
-- A.3 schedule_changes
-- ============================================================================

CREATE TABLE IF NOT EXISTS schedule_changes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  content_id UUID REFERENCES contents(id) ON DELETE CASCADE,
  task_id UUID REFERENCES tasks(id) ON DELETE CASCADE,
  field TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  reason TEXT NOT NULL,
  changed_by TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_schedule_changes_content
  ON schedule_changes(content_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_schedule_changes_recent
  ON schedule_changes(created_at DESC);

-- Allow anon read/insert (no auth yet)
ALTER TABLE schedule_changes ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS schedule_changes_all ON schedule_changes;
CREATE POLICY schedule_changes_all ON schedule_changes FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- A.4 parts.category_label
-- ============================================================================

ALTER TABLE parts
  ADD COLUMN IF NOT EXISTS category_label TEXT DEFAULT '카테고리';

UPDATE parts SET category_label = '지역'        WHERE id = 'field';
UPDATE parts SET category_label = '스토리/챕터' WHERE id = 'quest';
UPDATE parts SET category_label = '콘텐츠 타입' WHERE id = 'combat';
UPDATE parts SET category_label = '지역/챕터'   WHERE id = 'level';

-- ============================================================================
-- B.1 workers.is_team_lead
-- ============================================================================

ALTER TABLE workers
  ADD COLUMN IF NOT EXISTS is_team_lead BOOLEAN DEFAULT FALSE;

-- 팀장 지정 (이름 기준 - 실제 환경에 맞게 조정)
UPDATE workers SET is_team_lead = TRUE WHERE name = '신주나';
