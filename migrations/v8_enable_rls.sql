-- Pipeline Tracker v8 - Enable RLS on remaining public tables
-- Supabase 보안 경고 대응: rls_disabled_in_public
-- Run on Supabase SQL editor (huegoxqcoqealhhlrkww.supabase.co)
--
-- 정책: anon 전체 허용 (현재 기능 유지). 추후 인증 도입 시 USING 절 강화 예정.

-- contents
ALTER TABLE contents ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS contents_all ON contents;
CREATE POLICY contents_all ON contents FOR ALL USING (true) WITH CHECK (true);

-- tasks
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS tasks_all ON tasks;
CREATE POLICY tasks_all ON tasks FOR ALL USING (true) WITH CHECK (true);

-- workers
ALTER TABLE workers ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS workers_all ON workers;
CREATE POLICY workers_all ON workers FOR ALL USING (true) WITH CHECK (true);

-- parts
ALTER TABLE parts ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS parts_all ON parts;
CREATE POLICY parts_all ON parts FOR ALL USING (true) WITH CHECK (true);

-- versions
ALTER TABLE versions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS versions_all ON versions;
CREATE POLICY versions_all ON versions FOR ALL USING (true) WITH CHECK (true);

-- milestones
ALTER TABLE milestones ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS milestones_all ON milestones;
CREATE POLICY milestones_all ON milestones FOR ALL USING (true) WITH CHECK (true);

-- gate_transitions
ALTER TABLE gate_transitions ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS gate_transitions_all ON gate_transitions;
CREATE POLICY gate_transitions_all ON gate_transitions FOR ALL USING (true) WITH CHECK (true);
