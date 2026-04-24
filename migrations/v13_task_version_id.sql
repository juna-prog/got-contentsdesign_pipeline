-- v13_task_version_id.sql
-- Phase 5: task-level version_id 도입
-- 한 콘텐츠가 여러 빌드/시즌에 걸쳐 단계별 분할되는 케이스 대응
-- content.version_id 는 "기본 버전(첫 행)"으로 축소, 필터는 task 기준으로 전환

BEGIN;

-- 1. tasks.version_id 컬럼 추가 (nullable, 기존 레코드 영향 없음)
ALTER TABLE tasks
  ADD COLUMN version_id TEXT REFERENCES versions(id) ON UPDATE CASCADE ON DELETE SET NULL;

-- 2. 조회 성능 인덱스
CREATE INDEX IF NOT EXISTS idx_tasks_version_id ON tasks(version_id);
CREATE INDEX IF NOT EXISTS idx_tasks_content_version ON tasks(content_id, version_id);

-- 3. 코멘트 (운영 시 의미 명시)
COMMENT ON COLUMN tasks.version_id IS 'Phase 5: task가 속한 빌드/시즌. NULL이면 contents.version_id 상속';

-- 4. 초기 백필: 모든 기존 task의 version_id = 소속 content의 version_id
--    이후 v13_data_normalize.sql에서 ::N 분할 task들은 원 분할 content의 version_id로 재설정
UPDATE tasks t
SET version_id = c.version_id
FROM contents c
WHERE t.content_id = c.id
  AND t.version_id IS NULL;

COMMIT;

-- 검증 쿼리 (COMMIT 후 실행)
-- SELECT COUNT(*) AS tasks_total, COUNT(version_id) AS tasks_with_version FROM tasks;
-- SELECT version_id, COUNT(*) FROM tasks GROUP BY version_id ORDER BY 2 DESC;
