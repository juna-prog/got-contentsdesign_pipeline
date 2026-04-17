-- v9: JIRA 템플릿 시스템 + 생성 이력 로그
-- Gate 1b → JIRA 일감 자동 생성 파이프라인 Step 1

-- JIRA 일감 템플릿 (콘텐츠 유형별)
CREATE TABLE IF NOT EXISTS jira_templates (
  id SERIAL PRIMARY KEY,
  template_key TEXT UNIQUE NOT NULL,
  name TEXT NOT NULL,
  summary_template TEXT NOT NULL,
  description_template TEXT NOT NULL,
  project_key TEXT DEFAULT 'PROJECTT',
  issue_type TEXT DEFAULT 'Task',
  priority TEXT DEFAULT 'Medium',
  labels TEXT[] DEFAULT ARRAY['auto-generated','from-tracker'],
  component_mapping JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- JIRA 생성 이력 (감사 로그)
CREATE TABLE IF NOT EXISTS jira_creation_log (
  id SERIAL PRIMARY KEY,
  task_id INT REFERENCES tasks(id),
  content_id INT REFERENCES contents(id),
  jira_key TEXT,
  jira_url TEXT,
  template_key TEXT,
  created_by TEXT,
  payload JSONB,
  status TEXT,
  error_message TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- RLS
ALTER TABLE jira_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE jira_creation_log ENABLE ROW LEVEL SECURITY;

CREATE POLICY "jira_templates_anon_all" ON jira_templates FOR ALL TO anon USING (true) WITH CHECK (true);
CREATE POLICY "jira_creation_log_anon_all" ON jira_creation_log FOR ALL TO anon USING (true) WITH CHECK (true);

-- 기본 템플릿 삽입
INSERT INTO jira_templates (template_key, name, summary_template, description_template, project_key, labels, component_mapping) VALUES
('default', '기본 템플릿',
 '[{{content_type_label}}] {{content_name}} - {{task_title}}',
 E'## 콘텐츠\n{{content_name}} ({{content_type_label}})\n\n## 작업 내용\n{{task_title}}\n\n## 목표 버전\n{{version_label}} ({{version_date}})\n\n## 작업 일정\n{{estimated_days}}일 ({{start_date}} ~ {{end_date}})\n\n## 기획서\n{{doc_link}}\n\n## 파이프라인 트래커\n{{tracker_url}}\n\n---\n_이 일감은 Kingsroad Pipeline Tracker에서 자동 생성되었습니다._',
 'PROJECTT',
 ARRAY['auto-generated','from-tracker'],
 '{"art_char_concept":"캐릭터원화","art_char_model":"캐릭터모델링","art_anim":"애니메이션","art_fx":"이펙트","art_bg_concept":"배경원화","art_bg_model":"배경모델링","art_ta":"TA","cutscene":"연출"}'
)
ON CONFLICT (template_key) DO NOTHING;
