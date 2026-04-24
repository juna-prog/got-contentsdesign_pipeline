-- v13_rollback.sql
-- Phase 5 DDL 롤백
-- 주의: v13_data_normalize.sql Phase B가 실행된 후에는 ::N 콘텐츠 병합이 되돌려지지 않는다
--       데이터 복구는 별도 백업(backup/supabase_YYYYMMDD_HHMM/)에서 진행할 것

BEGIN;

-- 인덱스 제거
DROP INDEX IF EXISTS idx_tasks_content_version;
DROP INDEX IF EXISTS idx_tasks_version_id;

-- 컬럼 제거
ALTER TABLE tasks DROP COLUMN IF EXISTS version_id;

COMMIT;
