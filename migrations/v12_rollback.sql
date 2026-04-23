-- v12 rollback: Row data standardization + dependency model + naming convention 되돌리기
--
-- 주의:
--   1) 실제 데이터가 이미 task_dependencies/task_templates에 들어있으면 전량 소실
--   2) tasks.action_verb, title_object, category_id 컬럼 DROP 시 데이터 손실
--   3) 롤백 전 전체 백업 권장:
--        CREATE TABLE tasks_backup_v12       AS SELECT * FROM tasks;
--        CREATE TABLE task_dependencies_bkp  AS SELECT * FROM task_dependencies;
--        CREATE TABLE task_templates_bkp     AS SELECT * FROM task_templates;
--   4) jira_templates 확장 컬럼(action_verb_map, dep_link_mapping)도 DROP

-- ============================================================================
-- RLS 정책 제거
-- ============================================================================
DROP POLICY IF EXISTS task_templates_all    ON task_templates;
DROP POLICY IF EXISTS task_dependencies_all ON task_dependencies;
DROP POLICY IF EXISTS part_categories_all   ON part_categories;
DROP POLICY IF EXISTS regions_all           ON regions;
DROP POLICY IF EXISTS task_action_verbs_all ON task_action_verbs;

-- ============================================================================
-- Trigger + Function 제거
-- ============================================================================
DROP TRIGGER  IF EXISTS trg_check_dep_cycle ON task_dependencies;
DROP FUNCTION IF EXISTS check_no_dep_cycle();

-- ============================================================================
-- View 제거
-- ============================================================================
DROP VIEW IF EXISTS v_dep_date_violations;

-- ============================================================================
-- tasks 확장 컬럼 제거 (FK 먼저)
-- ============================================================================
DROP INDEX IF EXISTS idx_tasks_category_id;
DROP INDEX IF EXISTS idx_tasks_action_verb;
ALTER TABLE tasks DROP COLUMN IF EXISTS category_id;
ALTER TABLE tasks DROP COLUMN IF EXISTS title_object;
ALTER TABLE tasks DROP COLUMN IF EXISTS action_verb;

-- ============================================================================
-- jira_templates 확장 컬럼 제거
-- ============================================================================
ALTER TABLE jira_templates DROP COLUMN IF EXISTS dep_link_mapping;
ALTER TABLE jira_templates DROP COLUMN IF EXISTS action_verb_map;

-- ============================================================================
-- 신규 테이블 제거 (FK 역순)
-- ============================================================================
DROP TABLE IF EXISTS task_templates;
DROP TABLE IF EXISTS task_dependencies;
DROP TABLE IF EXISTS part_categories;
DROP TABLE IF EXISTS regions;
DROP TABLE IF EXISTS task_action_verbs;

-- ============================================================================
-- Enum 타입 제거
-- ============================================================================
DROP TYPE IF EXISTS dependency_type;
