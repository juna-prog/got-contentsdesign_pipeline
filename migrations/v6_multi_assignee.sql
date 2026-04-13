-- Pipeline Tracker v6 - Multi-assignee support
-- Run on Supabase SQL editor (huegoxqcoqealhhlrkww.supabase.co)

-- ============================================================================
-- V6.1 task_assignees junction table
-- ============================================================================

CREATE TABLE IF NOT EXISTS task_assignees (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  worker_id UUID NOT NULL REFERENCES workers(id) ON DELETE CASCADE,
  role TEXT DEFAULT 'assignee',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(task_id, worker_id)
);

CREATE INDEX IF NOT EXISTS idx_task_assignees_task ON task_assignees(task_id);
CREATE INDEX IF NOT EXISTS idx_task_assignees_worker ON task_assignees(worker_id);

-- RLS: allow anon read/insert (no auth yet)
ALTER TABLE task_assignees ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS task_assignees_all ON task_assignees;
CREATE POLICY task_assignees_all ON task_assignees FOR ALL USING (true) WITH CHECK (true);

-- ============================================================================
-- V6.2 Backfill from existing assignee_id
-- ============================================================================

INSERT INTO task_assignees (task_id, worker_id, role)
SELECT id, assignee_id, 'assignee'
FROM tasks
WHERE assignee_id IS NOT NULL
ON CONFLICT (task_id, worker_id) DO NOTHING;

-- ============================================================================
-- V6.3 Fix team lead name (신준하 -> 신주나) and ensure exists in workers
-- ============================================================================

-- If '신준하' exists, rename to '신주나'
UPDATE workers SET name = '신주나' WHERE name = '신준하';

-- If '신주나' doesn't exist at all, insert as team lead (no specific part - oversees all)
INSERT INTO workers (id, name, part_id, is_team_lead, is_part_lead)
SELECT gen_random_uuid(), '신주나', 'field', TRUE, FALSE
WHERE NOT EXISTS (SELECT 1 FROM workers WHERE name = '신주나');

-- Ensure is_team_lead is set
UPDATE workers SET is_team_lead = TRUE WHERE name = '신주나';
