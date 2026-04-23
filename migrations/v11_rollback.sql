-- v11 rollback: SCHEMA_STANDARD v1.0 반영 되돌리기
--
-- 주의: 실제 데이터가 이미 입력되어 있으면 컬럼 DROP 시 데이터 손실.
--       롤백 전 tasks 테이블 백업 권장:
--         CREATE TABLE tasks_backup_v11 AS SELECT * FROM tasks;

-- ============================================================================
-- 인덱스 제거
-- ============================================================================
DROP INDEX IF EXISTS idx_tasks_issue_type;
DROP INDEX IF EXISTS idx_tasks_priority;
DROP INDEX IF EXISTS idx_tasks_region_chapter;
DROP INDEX IF EXISTS idx_tasks_source_key_unique;
DROP INDEX IF EXISTS idx_contents_source_key_unique;

-- ============================================================================
-- CHECK 제약 제거
-- ============================================================================
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_priority_check;
ALTER TABLE tasks DROP CONSTRAINT IF EXISTS tasks_issue_type_check;

-- ============================================================================
-- 컬럼 제거 (데이터 손실 주의)
-- ============================================================================
ALTER TABLE tasks DROP COLUMN IF EXISTS priority;
ALTER TABLE tasks DROP COLUMN IF EXISTS issue_type;
ALTER TABLE tasks DROP COLUMN IF EXISTS region_chapter;
