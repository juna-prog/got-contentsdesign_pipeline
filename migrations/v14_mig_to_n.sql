-- v14_mig_to_n.sql
-- Phase B에서 중복 타이틀 task에 부여된 ::mig{id} suffix를 파서 출력 형식 ::N 으로 재매핑
-- 목적: 재-import 시 new 파서가 ::2 ::3 으로 생성하는 키와 충돌 없이 UPDATE 되도록
--
-- 처리: 각 base(::mig 제거) 그룹에서 id 순으로 ::2, ::3, ... 부여
--       원본 base key를 가진 task는 건드리지 않음 (이미 ::1 슬롯)

BEGIN;

DO $$
DECLARE
  r RECORD;
  base_key TEXT;
  cnt INT;
BEGIN
  -- base 그룹별로 id 순 순회하며 번호 부여
  FOR r IN
    WITH base_with_n AS (
      SELECT
        id, source_key,
        regexp_replace(source_key, '::mig\d+$', '') AS base,
        ROW_NUMBER() OVER (
          PARTITION BY regexp_replace(source_key, '::mig\d+$', '')
          ORDER BY id
        ) + 1 AS n  -- ::2 부터 시작
      FROM tasks
      WHERE source_key ~ '::mig\d+$'
    )
    SELECT id, source_key, base, n FROM base_with_n ORDER BY id
  LOOP
    -- 안전 체크: target key가 이미 존재하면 경고 (이 경우는 없어야 정상)
    IF EXISTS (SELECT 1 FROM tasks WHERE source_key = r.base || '::' || r.n AND id <> r.id) THEN
      RAISE EXCEPTION '충돌: % 로 재매핑할 수 없음 (이미 존재). task id=%', r.base || '::' || r.n, r.id;
    END IF;
    UPDATE tasks
    SET source_key = r.base || '::' || r.n,
        updated_at = now()
    WHERE id = r.id;
  END LOOP;
END $$;

-- 검증: ::mig 가 하나도 남지 않아야 함
DO $$
DECLARE remaining INT;
BEGIN
  SELECT COUNT(*) INTO remaining FROM tasks WHERE source_key ~ '::mig\d+$';
  IF remaining > 0 THEN
    RAISE EXCEPTION 'v14 migration 실패: ::mig task % 건이 남아있음', remaining;
  END IF;
END $$;

COMMIT;

-- 사후 검증:
-- SELECT COUNT(*) FROM tasks WHERE source_key ~ '::mig\d+$';  -- 0 이어야 함
-- SELECT source_key FROM tasks WHERE source_key ~ '::\d+$' ORDER BY source_key LIMIT 40;
