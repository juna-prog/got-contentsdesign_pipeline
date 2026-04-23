-- v12 ETL: 기존 DB 데이터 -> v11/v12 스키마 정규화
-- Run on Supabase SQL editor (huegoxqcoqealhhlrkww.supabase.co)
--
-- 원칙:
--   1) Phase A (이 파일): migration_review에 변경 예정 사항만 기록 (SELECT only).
--      실제 UPDATE는 주석 처리. 사용자가 review 테이블 확인 후 수동으로 UPDATE 실행.
--   2) Phase B (주석 해제 후 실행): UPDATE 쿼리 실제 적용.
--
-- 실행 순서:
--   1) v11_schema_standard.sql 먼저 적용
--   2) v12_dependencies_and_naming.sql 적용
--   3) 이 파일 Phase A 실행 -> migration_review 확인
--   4) Phase B 주석 해제 -> 실제 UPDATE 실행
--
-- 백업 권장:
--   CREATE TABLE tasks_backup_pre_v12 AS SELECT * FROM tasks;

-- ============================================================================
-- 0. migration_review 로그 테이블
-- ============================================================================

-- 이전 실패한 시도에서 row_id UUID로 잘못 만들어진 잔존 테이블 제거 (비어있음)
DROP TABLE IF EXISTS migration_review;

CREATE TABLE IF NOT EXISTS migration_review (
  id BIGSERIAL PRIMARY KEY,
  migration_code TEXT NOT NULL,     -- 'v12_etl'
  table_name TEXT NOT NULL,
  row_id BIGINT,                    -- tasks.id / contents.id (int4 → BIGINT 수용)
  column_name TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  status TEXT DEFAULT 'planned',    -- planned/applied/skipped/conflict
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_migration_review_status
  ON migration_review(migration_code, status);

-- 기존 v12_etl 리뷰 로그 삭제 (재실행 허용)
DELETE FROM migration_review WHERE migration_code = 'v12_etl';

-- ============================================================================
-- PHASE A: 변경 예정 사항 기록 (SELECT -> INSERT INTO migration_review)
-- ============================================================================

-- ------------------------------------------------------------
-- A.1 action_verb 역추론 (title LIKE 매칭)
-- ------------------------------------------------------------
-- 패턴 우선순위: 긴 패턴 먼저 매칭 (CASE 순서로 결정)

INSERT INTO migration_review (migration_code, table_name, row_id, column_name, old_value, new_value, notes)
SELECT
  'v12_etl', 'tasks', id, 'action_verb',
  action_verb,
  CASE
    -- 고유 키워드 먼저 (가장 구체적)
    WHEN title ILIKE '%IP 검수%' OR title ILIKE '%IP홀더%' THEN 'ip_review'
    WHEN title ILIKE '%재미검증%' OR title ILIKE '%재미 검증%' THEN 'fun_review'
    WHEN title ILIKE '%리소스 요청%' OR title ILIKE '%리소스 교체%'
      OR title ILIKE '%리소스 정리%' THEN 'resource_request'
    WHEN title ILIKE '%QA 대응%' OR title ILIKE '%QA대응%'
      OR title ILIKE '%QA 피드백%' OR title ILIKE '%QA%' THEN 'qa_response'
    WHEN title ILIKE '%폴리싱%' THEN 'polish'
    -- data_entry: implement 이전에 (데이터 X 작업 충돌 방지)
    WHEN title ILIKE '%데이터 작업%' OR title ILIKE '%초벌 데이터%'
      OR title ILIKE '%데이터 작성%' OR title ILIKE '%로 등록%'
      OR title ILIKE '%더미 리소스로%' THEN 'data_entry'
    -- draft_doc: 기획서 catch-all + 검토/문서 계열
    WHEN title ILIKE '%기획서%' OR title ILIKE '%검토%'
      OR title ILIKE '%문서 작성%' OR title ILIKE '%문서화%'
      OR title ILIKE '%문서 수정%' OR title ILIKE '%문서 정리%'
      OR title ILIKE '%문서 수정/정리%' THEN 'draft_doc'
    -- implement: 구현/제작/설정/배치/목업/작업
    WHEN title ILIKE '%구현%' OR title ILIKE '%제작%'
      OR title ILIKE '%설정%' OR title ILIKE '%배치%'
      OR title ILIKE '%목업%' OR title ILIKE '%추가 작업%'
      OR title ILIKE '%작업%' THEN 'implement'
    ELSE NULL
  END AS inferred,
  'auto-inferred from title LIKE pattern'
FROM tasks
WHERE action_verb IS NULL
  AND title IS NOT NULL
  AND (
    title ILIKE '%기획서%' OR title ILIKE '%구현%' OR title ILIKE '%폴리싱%'
    OR title ILIKE '%QA%'  OR title ILIKE '%데이터%' OR title ILIKE '%리소스%'
    OR title ILIKE '%재미검증%' OR title ILIKE '%IP 검수%' OR title ILIKE '%IP홀더%'
    OR title ILIKE '%검토%' OR title ILIKE '%문서%'
    OR title ILIKE '%제작%' OR title ILIKE '%설정%' OR title ILIKE '%배치%'
    OR title ILIKE '%등록%' OR title ILIKE '%목업%' OR title ILIKE '%작업%'
  );

-- ------------------------------------------------------------
-- A.2 issue_type 역추론 (parent_task_id 유무)
-- ------------------------------------------------------------

INSERT INTO migration_review (migration_code, table_name, row_id, column_name, old_value, new_value, notes)
SELECT
  'v12_etl', 'tasks', id, 'issue_type',
  issue_type,
  CASE WHEN parent_task_id IS NULL THEN 'Task' ELSE 'Sub-Task' END,
  'auto-inferred from parent_task_id'
FROM tasks
WHERE issue_type IS NULL;

-- ------------------------------------------------------------
-- A.3 related_part 정규화 (한글/접미어 제거 -> enum code)
-- ------------------------------------------------------------

INSERT INTO migration_review (migration_code, table_name, row_id, column_name, old_value, new_value, notes)
SELECT
  'v12_etl', 'tasks', id, 'related_part',
  related_part,
  CASE
    WHEN related_part IS NULL OR TRIM(related_part) = '' THEN NULL
    -- 한국어 -> enum code (복수 표기는 수동 리뷰 필요)
    WHEN related_part IN ('필드 파트','필드')                        THEN 'field'
    WHEN related_part IN ('전투 파트','전투')                        THEN 'combat'
    WHEN related_part IN ('퀘스트(내러티브)','퀘스트','퀘스트 파트')     THEN 'quest'
    WHEN related_part IN ('레벨 파트','레벨')                        THEN 'level'
    WHEN related_part IN ('아트','아트 파트')                        THEN 'art'
    WHEN related_part IN ('내러티브','내러티브 파트')                 THEN 'narrative'
    WHEN related_part IN ('UX','UX 파트')                           THEN 'ux'
    WHEN related_part IN ('클래스','클래스 파트')                     THEN 'class'
    WHEN related_part IN ('검증','검증 파트','밸런스','시스템')          THEN 'validation'
    -- 복수 표기 (슬래시/쉼표 포함) - 정규화 불가, 수동 리뷰
    WHEN related_part LIKE '%/%' OR related_part LIKE '%,%' THEN related_part
    ELSE related_part
  END,
  CASE
    WHEN related_part LIKE '%/%' OR related_part LIKE '%,%' THEN 'MANUAL: multi-part value needs split/remap'
    WHEN related_part NOT IN (
      '필드 파트','필드','전투 파트','전투','퀘스트(내러티브)','퀘스트','퀘스트 파트',
      '레벨 파트','레벨','아트','아트 파트','내러티브','내러티브 파트',
      'UX','UX 파트','클래스','클래스 파트','검증','검증 파트','밸런스','시스템'
    ) THEN 'MANUAL: unmapped value'
    ELSE 'auto-mapped'
  END
FROM tasks
WHERE related_part IS NOT NULL AND TRIM(related_part) <> '';

-- ------------------------------------------------------------
-- A.4 목표 -> versions 매핑 (contents 테이블 대상)
-- ------------------------------------------------------------
-- contents.version_id가 이미 FK로 있으므로 별도 매핑 불필요 (조회용 리포트만)

INSERT INTO migration_review (migration_code, table_name, row_id, column_name, old_value, new_value, notes)
SELECT
  'v12_etl', 'contents', id, 'version_id',
  COALESCE(version_id::text, ''),
  '',
  CASE
    WHEN version_id IS NULL THEN 'MANUAL: undecided version, needs 파트장 배정'
    ELSE 'ok'
  END
FROM contents
WHERE version_id IS NULL;

-- ============================================================================
-- PHASE A 완료: migration_review 조회
-- ============================================================================
-- 사용자는 아래 쿼리로 변경 예정 내역 확인 후 Phase B 실행:
--
--   SELECT column_name, status, notes, COUNT(*)
--   FROM migration_review
--   WHERE migration_code = 'v12_etl'
--   GROUP BY column_name, status, notes
--   ORDER BY column_name;
--
--   SELECT * FROM migration_review
--   WHERE migration_code = 'v12_etl' AND notes LIKE 'MANUAL:%'
--   ORDER BY column_name;

-- ============================================================================
-- PHASE B: 실제 UPDATE (주석 해제 후 실행)
-- ============================================================================
-- 주의: 아래 블록은 migration_review 검토 후에만 실행.
--       각 UPDATE는 독립 transaction으로 실행 가능.

/*
-- B.1 action_verb 일괄 UPDATE
UPDATE tasks t
SET action_verb = r.new_value
FROM migration_review r
WHERE r.migration_code = 'v12_etl'
  AND r.table_name = 'tasks'
  AND r.column_name = 'action_verb'
  AND r.row_id = t.id
  AND r.new_value IS NOT NULL
  AND t.action_verb IS DISTINCT FROM r.new_value;

UPDATE migration_review
SET status = 'applied'
WHERE migration_code = 'v12_etl' AND column_name = 'action_verb'
  AND new_value IS NOT NULL;

-- B.2 issue_type 일괄 UPDATE
UPDATE tasks t
SET issue_type = r.new_value
FROM migration_review r
WHERE r.migration_code = 'v12_etl'
  AND r.table_name = 'tasks'
  AND r.column_name = 'issue_type'
  AND r.row_id = t.id
  AND t.issue_type IS DISTINCT FROM r.new_value;

UPDATE migration_review
SET status = 'applied'
WHERE migration_code = 'v12_etl' AND column_name = 'issue_type';

-- B.3 related_part 일괄 UPDATE (MANUAL 플래그 제외)
UPDATE tasks t
SET related_part = r.new_value
FROM migration_review r
WHERE r.migration_code = 'v12_etl'
  AND r.table_name = 'tasks'
  AND r.column_name = 'related_part'
  AND r.row_id = t.id
  AND r.notes = 'auto-mapped'
  AND t.related_part IS DISTINCT FROM r.new_value;

UPDATE migration_review
SET status = 'applied'
WHERE migration_code = 'v12_etl' AND column_name = 'related_part'
  AND notes = 'auto-mapped';
*/
