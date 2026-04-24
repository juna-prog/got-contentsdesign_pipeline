-- v13_data_normalize.sql
-- Phase 5 데이터 마이그레이션: ::N suffix 콘텐츠를 root 콘텐츠로 병합
--
-- 전제: v13_task_version_id.sql 완료 후 실행
-- 실행 순서:
--   1. Phase A (리포트): 예상 병합 결과 확인. migration_review_v13 뷰 조회
--   2. 사용자 검토: 예상 결과가 문제 없는지 확인
--   3. Phase B (실제 병합): Phase B 블록 주석 해제 후 재실행
--
-- ========================================================================
-- Phase A: 리포트 (읽기 전용, 안전)
-- ========================================================================

BEGIN;

-- 임시 뷰: ::N suffix 콘텐츠와 root 매핑
DROP VIEW IF EXISTS migration_review_v13 CASCADE;
CREATE VIEW migration_review_v13 AS
WITH suffixed AS (
  SELECT
    c.id AS content_id,
    c.source_key,
    c.name,
    c.version_id AS content_version_id,
    regexp_replace(c.source_key, '::[0-9]+$', '') AS root_key,
    split_part(c.source_key, '::', 1) AS part_id,
    (SELECT COUNT(*) FROM tasks t WHERE t.content_id = c.id) AS task_count
  FROM contents c
  WHERE c.source_key ~ '::[0-9]+$'
),
roots AS (
  SELECT c.id AS root_id, c.source_key AS root_key, c.version_id AS root_version
  FROM contents c
  WHERE c.source_key !~ '::[0-9]+$'
)
SELECT
  s.part_id,
  s.root_key,
  r.root_id,
  r.root_version,
  s.content_id AS suffix_content_id,
  s.source_key AS suffix_source_key,
  s.content_version_id AS suffix_version_id,
  s.task_count
FROM suffixed s
LEFT JOIN roots r ON s.root_key = r.root_key
ORDER BY s.part_id, s.root_key, s.source_key;

-- 요약 통계
DROP VIEW IF EXISTS migration_summary_v13 CASCADE;
CREATE VIEW migration_summary_v13 AS
SELECT
  part_id,
  COUNT(DISTINCT root_key) AS group_count,
  COUNT(*) AS suffix_content_count,
  SUM(task_count) AS tasks_to_migrate,
  COUNT(*) FILTER (WHERE root_id IS NULL) AS orphan_suffixes
FROM migration_review_v13
GROUP BY part_id
ORDER BY part_id;

COMMIT;

-- Phase A 실행 확인용:
-- SELECT * FROM migration_summary_v13;
-- SELECT * FROM migration_review_v13;
--
-- orphan_suffixes > 0 이면 root가 없는 ::N 콘텐츠 존재 → Phase B 전에 해결 필요
-- (보통 root도 삭제되어 고아가 된 케이스. 처리 방법: root_key로 재명명 or 삭제)

-- ========================================================================
-- Phase B: 실제 병합 (아래 블록 주석 해제 후 재실행)
-- ========================================================================

/*
BEGIN;

-- 안전 체크: orphan이 있으면 중단
DO $$
DECLARE orphan_count INT;
BEGIN
  SELECT COUNT(*) INTO orphan_count FROM migration_review_v13 WHERE root_id IS NULL;
  IF orphan_count > 0 THEN
    RAISE EXCEPTION 'v13 migration aborted: % orphan suffix contents (no root). Fix first.', orphan_count;
  END IF;
END $$;

-- 1. Row-by-row 병합: content_id 이동 + version_id 재설정 + source_key 정규화
--    단일 UPDATE 문은 UNIQUE 제약 검사가 문장 내에서 걸려 충돌 시 전체 롤백된다.
--    같은 task title 이 여러 ::N content 에 중복되는 경우 (예: field::세력은신처::웨스터랜드 4.1 작업 x3)
--    루프로 처리하면서 충돌 발견 즉시 ::mig{id} 접미사를 부여한다.
DO $$
DECLARE
  r RECORD;
  target TEXT;
  n_suffix TEXT;
BEGIN
  FOR r IN
    SELECT t.id, t.source_key, m.root_id, m.suffix_version_id, m.root_version, m.suffix_source_key
    FROM tasks t
    JOIN migration_review_v13 m ON t.content_id = m.suffix_content_id
    ORDER BY t.id
  LOOP
    n_suffix := substring(r.suffix_source_key FROM '::([0-9]+)$');
    target := regexp_replace(r.source_key, '::' || n_suffix || '::', '::');
    IF EXISTS (SELECT 1 FROM tasks WHERE source_key = target AND id <> r.id) THEN
      target := target || '::mig' || r.id;
    END IF;
    UPDATE tasks
    SET content_id = r.root_id,
        version_id = COALESCE(r.suffix_version_id, r.root_version),
        source_key = target,
        updated_at = now()
    WHERE id = r.id;
  END LOOP;
END $$;

-- 2. 빈 ::N 콘텐츠 삭제 (task가 모두 이전된 후)
DELETE FROM contents c
WHERE c.source_key ~ '::[0-9]+$'
  AND NOT EXISTS (SELECT 1 FROM tasks t WHERE t.content_id = c.id);

-- 3. 혹시 남은 ::N 콘텐츠 있는지 확인 (task가 안 옮겨진 케이스)
DO $$
DECLARE remaining INT;
BEGIN
  SELECT COUNT(*) INTO remaining FROM contents WHERE source_key ~ '::[0-9]+$';
  IF remaining > 0 THEN
    RAISE WARNING 'v13 migration: % ::N contents still remain with tasks. Investigate manually.', remaining;
  END IF;
END $$;

-- 4. 검증 뷰 정리
DROP VIEW IF EXISTS migration_review_v13 CASCADE;
DROP VIEW IF EXISTS migration_summary_v13 CASCADE;

COMMIT;

-- 검증 쿼리 (COMMIT 후):
-- SELECT COUNT(*) FROM contents WHERE source_key ~ '::[0-9]+$';  -- 0 이어야 함
-- SELECT version_id, COUNT(*) FROM tasks GROUP BY version_id ORDER BY 2 DESC;
-- SELECT c.name, t.title, t.version_id FROM tasks t JOIN contents c ON t.content_id=c.id WHERE c.name = '한계 돌파 던전' ORDER BY t.version_id;
-- SELECT count(*) FROM tasks WHERE source_key LIKE '%::mig%';  -- 이름 중복으로 suffix 붙은 task 수
*/
