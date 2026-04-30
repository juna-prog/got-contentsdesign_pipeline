-- v17: Sprint config + Work types 마스터 + jira_templates 확장
-- Phase 6 P2 stage B
-- 목적:
--   1. sprint_config: version 별 JIRA Sprint / Fix Version / 기본 Components·Labels 매핑
--      Sprint 자동 투입(Agile API)은 P3 별도 트랙. 본 테이블은 메타 보존 + payload 주입용
--   2. work_types: 작업 유형 마스터. 태스크 생성 시 기본 Est_Days/Priority/Components/Labels 추천
--   3. jira_templates 확장: 템플릿 단위 default_fix_versions / default_components

-- ============================================================================
-- 1. sprint_config (version 1:1)
-- ============================================================================

CREATE TABLE IF NOT EXISTS sprint_config (
  id SERIAL PRIMARY KEY,
  version_id TEXT NOT NULL,
  jira_sprint_id INT,
  jira_sprint_name TEXT,
  jira_board_id INT DEFAULT 1221,
  fix_version TEXT,
  default_components TEXT[] DEFAULT ARRAY[]::TEXT[],
  default_labels TEXT[] DEFAULT ARRAY[]::TEXT[],
  default_priority TEXT,
  is_active BOOLEAN DEFAULT TRUE,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(version_id)
);

CREATE INDEX IF NOT EXISTS idx_sprint_config_version ON sprint_config(version_id);
CREATE INDEX IF NOT EXISTS idx_sprint_config_active ON sprint_config(is_active);

COMMENT ON TABLE sprint_config IS 'version 단위 JIRA Sprint/Fix Version/Components 메타. operator 가 payload 에 주입.';
COMMENT ON COLUMN sprint_config.jira_sprint_id IS 'JIRA Agile API 의 sprint id. P3 자동 투입 트랙에서 사용. 현재는 메타 저장만.';
COMMENT ON COLUMN sprint_config.fix_version IS 'JIRA fixVersions 에 주입할 이름 (예: "Asia CBT", "[T] 업데이트").';
COMMENT ON COLUMN sprint_config.default_components IS 'JIRA components 기본값. work_types/jira_templates 와 합쳐 최종 payload 결정.';

ALTER TABLE sprint_config ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "sprint_config_anon_all" ON sprint_config;
CREATE POLICY "sprint_config_anon_all" ON sprint_config FOR ALL TO anon USING (true) WITH CHECK (true);

-- ============================================================================
-- 2. work_types (part_id 와 직교, 작업 유형 별 권장값)
-- ============================================================================

CREATE TABLE IF NOT EXISTS work_types (
  id SERIAL PRIMARY KEY,
  work_type_key TEXT UNIQUE NOT NULL,
  label TEXT NOT NULL,
  part_id TEXT,
  default_est_days NUMERIC(4,1),
  default_priority TEXT DEFAULT 'Medium',
  default_components TEXT[] DEFAULT ARRAY[]::TEXT[],
  default_labels TEXT[] DEFAULT ARRAY[]::TEXT[],
  default_action_verb TEXT,
  description TEXT,
  sort_order INT DEFAULT 0,
  is_active BOOLEAN DEFAULT TRUE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_work_types_part ON work_types(part_id);
CREATE INDEX IF NOT EXISTS idx_work_types_active ON work_types(is_active);

COMMENT ON TABLE work_types IS '태스크 유형 마스터. 태스크 생성 UI 가 default_est_days/Priority/Components/Labels 자동 추천.';
COMMENT ON COLUMN work_types.work_type_key IS '고유 키 (예: art_char_concept_draft, design_doc_initial).';
COMMENT ON COLUMN work_types.part_id IS 'tasks.part_id 와 매칭 (art_char_concept / art_ta / cutscene 등). NULL = 공통.';
COMMENT ON COLUMN work_types.default_est_days IS '권장 기본 일수. 태스크 생성 시 estimated_days/days 자동 채움.';

ALTER TABLE work_types ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "work_types_anon_all" ON work_types;
CREATE POLICY "work_types_anon_all" ON work_types FOR ALL TO anon USING (true) WITH CHECK (true);

-- ============================================================================
-- 3. jira_templates 확장 (template 단위 fix_versions + components 보강)
-- ============================================================================

ALTER TABLE jira_templates
  ADD COLUMN IF NOT EXISTS default_fix_versions TEXT[] DEFAULT ARRAY[]::TEXT[],
  ADD COLUMN IF NOT EXISTS default_components TEXT[] DEFAULT ARRAY[]::TEXT[];

COMMENT ON COLUMN jira_templates.default_fix_versions IS 'sprint_config 미설정 시 fallback 용. operator merge 우선순위 = sprint > template > task.';
COMMENT ON COLUMN jira_templates.default_components IS 'sprint_config 미설정 시 fallback 용 components.';

-- ============================================================================
-- 4. work_types seed (기존 component_mapping + action_verb_map 정합)
-- ============================================================================

INSERT INTO work_types (work_type_key, label, part_id, default_est_days, default_priority, default_components, default_action_verb, sort_order)
VALUES
  ('art_char_concept',  '캐릭터 원화',     'art_char_concept', 5.0, 'Medium', ARRAY['캐릭터원화'], 'draft_doc', 10),
  ('art_char_model',    '캐릭터 모델링',   'art_char_model',   8.0, 'Medium', ARRAY['캐릭터모델링'], 'implement', 20),
  ('art_anim',          '애니메이션',     'art_anim',         5.0, 'Medium', ARRAY['애니메이션'], 'implement', 30),
  ('art_fx',            '이펙트',         'art_fx',           3.0, 'Medium', ARRAY['이펙트'], 'implement', 40),
  ('art_bg_concept',    '배경 원화',      'art_bg_concept',   5.0, 'Medium', ARRAY['배경원화'], 'draft_doc', 50),
  ('art_bg_model',      '배경 모델링',    'art_bg_model',     8.0, 'Medium', ARRAY['배경모델링'], 'implement', 60),
  ('art_ta',            'TA',           'art_ta',           3.0, 'Medium', ARRAY['TA'], 'implement', 70),
  ('cutscene',          '연출',          'cutscene',         5.0, 'Medium', ARRAY['연출'], 'implement', 80),
  ('design_doc',        '구현 기획서',    'design',           2.0, 'High',   ARRAY[]::TEXT[], 'draft_doc', 90),
  ('design_data',       '데이터 작업',    'design',           1.0, 'Medium', ARRAY[]::TEXT[], 'data_entry', 100),
  ('design_ip_review',  'IP 검수 대응',   'design',           1.0, 'High',   ARRAY[]::TEXT[], 'ip_review', 110),
  ('design_qa',         'QA 대응',       'design',           1.0, 'Medium', ARRAY[]::TEXT[], 'qa_response', 120),
  ('design_polish',     '폴리싱',        'design',           1.0, 'Low',    ARRAY[]::TEXT[], 'polish', 130),
  ('design_fun_review', '재미 검증',      'design',           1.0, 'Medium', ARRAY[]::TEXT[], 'fun_review', 140)
ON CONFLICT (work_type_key) DO NOTHING;

-- ============================================================================
-- 5. sprint_config seed (현재 활성 version 기본값)
-- ============================================================================

INSERT INTO sprint_config (version_id, fix_version, default_labels, default_priority, notes)
VALUES
  ('UP01', '[T] 업데이트', ARRAY['auto-generated','from-tracker','UP01'], 'Medium', '1차 업뎃 기본값. jira_sprint_id 는 P3 자동 투입 트랙에서 채울 예정.')
ON CONFLICT (version_id) DO NOTHING;

-- ============================================================================
-- 6. 운영 편의 뷰: v_jira_payload_defaults (UI/operator 가 단일 쿼리로 머지값 조회)
-- ============================================================================

CREATE OR REPLACE VIEW v_jira_payload_defaults AS
SELECT
  v.id AS version_id,
  v.label AS version_label,
  sc.id AS sprint_config_id,
  sc.jira_sprint_id,
  sc.jira_sprint_name,
  sc.fix_version,
  sc.default_components AS sprint_components,
  sc.default_labels AS sprint_labels,
  sc.default_priority AS sprint_priority,
  sc.is_active AS sprint_active
FROM versions v
LEFT JOIN sprint_config sc ON sc.version_id = v.id
ORDER BY v.sort_order;

COMMENT ON VIEW v_jira_payload_defaults IS 'version 단위 JIRA payload 기본값 머지뷰. UI 가 컨텐츠 생성/편집 시 참조.';
