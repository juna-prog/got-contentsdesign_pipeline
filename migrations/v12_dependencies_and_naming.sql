-- v12: Row data standardization + dependency model + naming convention
-- Run on Supabase SQL editor (huegoxqcoqealhhlrkww.supabase.co)
--
-- 참조: C:\Users\juna\.claude\plans\compiled-waddling-nova.md
-- 롤백: v12_rollback.sql
--
-- 섹션 구성:
--   A. 네이밍 컨벤션 (task_action_verbs, tasks.action_verb, tasks.title_object)
--   B. 의존성 모델 (task_dependencies + 순환 감지 + 날짜 논리 view)
--   C. Row 값 마스터 (regions, part_categories, tasks.category_id)
--   E. 파생 업무 템플릿 (task_templates)
--   F. jira_templates 확장
--   G. RLS 정책

-- ============================================================================
-- A.1 task_action_verbs 마스터
-- ============================================================================
-- 일감 이름 끝에 붙는 정규 동사. title = {title_object} {action_label}

CREATE TABLE IF NOT EXISTS task_action_verbs (
  code TEXT PRIMARY KEY,
  label TEXT NOT NULL,
  description TEXT,
  sort_order INT DEFAULT 100,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO task_action_verbs (code, label, description, sort_order) VALUES
  ('draft_doc',        '구현 기획서 작성', 'Gate 1a 단계. 구현용 기획 문서 초안 작성', 10),
  ('implement',        '구현',             'Gate 2 단계. 기획서 기반 실제 게임 내 구현', 20),
  ('data_entry',       '데이터 작업',      '테이블 데이터 입력/조정', 30),
  ('resource_request', '리소스 요청',      'Gate 1b. 아트/사운드 리소스 발주', 40),
  ('polish',           '폴리싱',           'Gate 3 전. 품질 개선', 50),
  ('qa_response',      'QA 대응',          'Gate 3. QA 이슈 대응', 60),
  ('fun_review',       '재미검증',         'Gate 2b. 재미 요소 검증', 70),
  ('ip_review',        'IP 검수 대응',     'Gate 0a. IP 홀더 피드백 대응', 80)
ON CONFLICT (code) DO NOTHING;

-- tasks에 action_verb/title_object 추가
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS action_verb TEXT REFERENCES task_action_verbs(code),
  ADD COLUMN IF NOT EXISTS title_object TEXT;

CREATE INDEX IF NOT EXISTS idx_tasks_action_verb
  ON tasks(action_verb)
  WHERE action_verb IS NOT NULL;

-- ============================================================================
-- C.1 regions 마스터
-- ============================================================================
-- 지역/챕터 정규화. code는 "3.1" 형식, display는 "3.1. 스톰스엔드"

CREATE TABLE IF NOT EXISTS regions (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  chapter_id INT NOT NULL,
  location_number INT NOT NULL,
  name TEXT NOT NULL,
  display TEXT GENERATED ALWAYS AS (code || '. ' || name) STORED,
  sort_order INT DEFAULT 100,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_regions_chapter ON regions(chapter_id, location_number);

-- ============================================================================
-- C.2 part_categories 마스터 (파트별 격리)
-- ============================================================================

CREATE TABLE IF NOT EXISTS part_categories (
  id SERIAL PRIMARY KEY,
  part_id TEXT NOT NULL,
  code TEXT NOT NULL,
  label TEXT NOT NULL,
  description TEXT,
  sort_order INT DEFAULT 100,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(part_id, code)
);

CREATE INDEX IF NOT EXISTS idx_part_categories_part ON part_categories(part_id);

-- tasks에 category_id FK 추가 (기존 category TEXT는 그대로 유지, 점진 마이그레이션)
ALTER TABLE tasks
  ADD COLUMN IF NOT EXISTS category_id INT REFERENCES part_categories(id);

CREATE INDEX IF NOT EXISTS idx_tasks_category_id
  ON tasks(category_id)
  WHERE category_id IS NOT NULL;

-- ============================================================================
-- B.1 의존성 enum + task_dependencies
-- ============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'dependency_type') THEN
    CREATE TYPE dependency_type AS ENUM ('finishes_before', 'starts_together');
  END IF;
END$$;

-- tasks.id is INTEGER (int4) in current Supabase schema
-- (was UUID historically per v5_phase_*, but tasks table got recreated with SERIAL)
CREATE TABLE IF NOT EXISTS task_dependencies (
  id BIGSERIAL PRIMARY KEY,
  task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  depends_on_task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  dep_type dependency_type NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  created_by TEXT,
  notes TEXT,
  CONSTRAINT no_self_dep CHECK (task_id <> depends_on_task_id),
  CONSTRAINT uniq_dep UNIQUE (task_id, depends_on_task_id, dep_type)
);

CREATE INDEX IF NOT EXISTS idx_dep_task ON task_dependencies(task_id);
CREATE INDEX IF NOT EXISTS idx_dep_src ON task_dependencies(depends_on_task_id);

-- ============================================================================
-- B.2 순환 의존 감지 (재귀 CTE + BEFORE INSERT trigger)
-- ============================================================================

CREATE OR REPLACE FUNCTION check_no_dep_cycle() RETURNS TRIGGER AS $$
BEGIN
  -- finishes_before만 순환 체크 (starts_together는 대칭 관계라 순환 개념 없음)
  IF NEW.dep_type = 'finishes_before' THEN
    IF EXISTS (
      WITH RECURSIVE dep_graph AS (
        SELECT NEW.depends_on_task_id AS cur, 1 AS depth
        UNION ALL
        SELECT d.depends_on_task_id, g.depth + 1
        FROM task_dependencies d
        JOIN dep_graph g ON d.task_id = g.cur
        WHERE d.dep_type = 'finishes_before' AND g.depth < 100
      )
      SELECT 1 FROM dep_graph WHERE cur = NEW.task_id
    ) THEN
      RAISE EXCEPTION 'Circular dependency detected: task % cannot depend on %',
        NEW.task_id, NEW.depends_on_task_id;
    END IF;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_check_dep_cycle ON task_dependencies;
CREATE TRIGGER trg_check_dep_cycle
  BEFORE INSERT OR UPDATE ON task_dependencies
  FOR EACH ROW EXECUTE FUNCTION check_no_dep_cycle();

-- ============================================================================
-- B.3 날짜 논리 검증 view
-- ============================================================================
-- finishes_before 관계에서 후행 task의 start_date가 선행 task의 end_date보다 빠른 경우

CREATE OR REPLACE VIEW v_dep_date_violations AS
SELECT
  d.id AS dep_id,
  d.task_id,
  t_after.title AS task_title,
  t_after.start_date AS task_start,
  d.depends_on_task_id,
  t_before.title AS depends_on_title,
  t_before.end_date AS depends_on_end,
  d.dep_type
FROM task_dependencies d
JOIN tasks t_after  ON t_after.id  = d.task_id
JOIN tasks t_before ON t_before.id = d.depends_on_task_id
WHERE d.dep_type = 'finishes_before'
  AND t_after.start_date IS NOT NULL
  AND t_before.end_date IS NOT NULL
  AND t_after.start_date < t_before.end_date;

-- ============================================================================
-- E.1 task_templates (파생 업무 자동 연결)
-- ============================================================================

CREATE TABLE IF NOT EXISTS task_templates (
  id SERIAL PRIMARY KEY,
  code TEXT UNIQUE NOT NULL,
  part_id TEXT NOT NULL,
  label TEXT NOT NULL,
  description TEXT,
  steps JSONB NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_task_templates_part ON task_templates(part_id);

-- 기본 템플릿 3종 (예시, 실제 운영은 UI에서 편집)
INSERT INTO task_templates (code, part_id, label, description, steps) VALUES
  (
    'main_quest_boss', 'combat', '메인 퀘스트 보스 (전투)',
    '보스 콘텐츠 표준 4스텝: 기획서 -> 구현 -> 폴리싱 -> QA',
    '[
      {"action_verb":"draft_doc","offset_days":0,"duration":5},
      {"action_verb":"implement","offset_days":5,"duration":10,"depends_on":"draft_doc","dep_type":"finishes_before"},
      {"action_verb":"polish","offset_days":15,"duration":3,"depends_on":"implement","dep_type":"finishes_before"},
      {"action_verb":"qa_response","offset_days":18,"duration":4,"depends_on":"polish","dep_type":"starts_together"}
    ]'::jsonb
  ),
  (
    'field_dungeon', 'field', '필드 던전',
    '던전 콘텐츠 표준 5스텝',
    '[
      {"action_verb":"draft_doc","offset_days":0,"duration":5},
      {"action_verb":"resource_request","offset_days":5,"duration":2,"depends_on":"draft_doc","dep_type":"finishes_before"},
      {"action_verb":"implement","offset_days":7,"duration":12,"depends_on":"resource_request","dep_type":"finishes_before"},
      {"action_verb":"polish","offset_days":19,"duration":4,"depends_on":"implement","dep_type":"finishes_before"},
      {"action_verb":"qa_response","offset_days":23,"duration":5,"depends_on":"polish","dep_type":"starts_together"}
    ]'::jsonb
  ),
  (
    'quest_main', 'quest', '메인 퀘스트',
    '퀘스트 콘텐츠 표준 4스텝',
    '[
      {"action_verb":"draft_doc","offset_days":0,"duration":4},
      {"action_verb":"implement","offset_days":4,"duration":8,"depends_on":"draft_doc","dep_type":"finishes_before"},
      {"action_verb":"polish","offset_days":12,"duration":2,"depends_on":"implement","dep_type":"finishes_before"},
      {"action_verb":"qa_response","offset_days":14,"duration":3,"depends_on":"polish","dep_type":"starts_together"}
    ]'::jsonb
  )
ON CONFLICT (code) DO NOTHING;

-- ============================================================================
-- F.1 jira_templates 확장 (v9 재활용)
-- ============================================================================

ALTER TABLE jira_templates
  ADD COLUMN IF NOT EXISTS action_verb_map JSONB DEFAULT '{}',
  ADD COLUMN IF NOT EXISTS dep_link_mapping JSONB DEFAULT '{"finishes_before":"Blocks","starts_together":"Relates"}';

-- 기존 default 템플릿에 매핑 주입
UPDATE jira_templates
SET action_verb_map = jsonb_build_object(
  'draft_doc', '구현 기획서 작성',
  'implement', '구현',
  'data_entry', '데이터 작업',
  'resource_request', '리소스 요청',
  'polish', '폴리싱',
  'qa_response', 'QA 대응',
  'fun_review', '재미검증',
  'ip_review', 'IP 검수 대응'
)
WHERE template_key = 'default'
  AND (action_verb_map IS NULL OR action_verb_map = '{}'::jsonb);

-- ============================================================================
-- G.1 RLS 정책 (anon 전체 허용 - 기존 패턴 따름)
-- ============================================================================

ALTER TABLE task_action_verbs ENABLE ROW LEVEL SECURITY;
ALTER TABLE regions           ENABLE ROW LEVEL SECURITY;
ALTER TABLE part_categories   ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_dependencies ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_templates    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS task_action_verbs_all ON task_action_verbs;
CREATE POLICY task_action_verbs_all ON task_action_verbs FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS regions_all ON regions;
CREATE POLICY regions_all ON regions FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS part_categories_all ON part_categories;
CREATE POLICY part_categories_all ON part_categories FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS task_dependencies_all ON task_dependencies;
CREATE POLICY task_dependencies_all ON task_dependencies FOR ALL TO anon USING (true) WITH CHECK (true);

DROP POLICY IF EXISTS task_templates_all ON task_templates;
CREATE POLICY task_templates_all ON task_templates FOR ALL TO anon USING (true) WITH CHECK (true);
