-- combat #1632 쉘윈 parent 일정 보강 (2026-04-24)
-- 배경: content 522 "챕터4.1 보스" 아래 쉘윈 parent가 2개 존재 (#1632, #1680).
--      #1632는 start_date/end_date NULL, children #1703/#1704만 있음.
--      #1680은 5/25~5/29 범위, child #1834 정상.
--
-- 옵션 A (보수적): #1632 의 일정만 children 범위로 자동 채움.
--   범위: children #1703 (2026-03-31~2026-04-10) + #1704 (2026-04-13~2026-04-17)
--        => start=2026-03-31, end=2026-04-17
--
-- 옵션 B (구조 정리): 전투 파트장과 논의 후 #1632 ↔ #1680 병합 (이 SQL에는 미포함).
--
-- 실행 전 확인:
--   SELECT id, title, start_date, end_date, parent_task_id
--   FROM tasks WHERE content_id=522 AND title LIKE '%쉘윈%' ORDER BY id;

BEGIN;

-- 보수적 옵션 A: #1632 parent 에만 children 범위 주입
UPDATE tasks
SET
  start_date = '2026-03-31',
  end_date = '2026-04-17',
  updated_at = now()
WHERE id = 1632
  AND start_date IS NULL
  AND end_date IS NULL;

-- 검증
DO $$
DECLARE r RECORD;
BEGIN
  SELECT id, start_date, end_date INTO r FROM tasks WHERE id = 1632;
  IF r.start_date IS NULL THEN
    RAISE EXCEPTION '1632 start_date still NULL';
  END IF;
  RAISE NOTICE '1632 updated: start=%, end=%', r.start_date, r.end_date;
END $$;

COMMIT;

-- 후속: 구조 중복 정리는 전투 파트장 판단 후 별도 작업.
--   #1632 와 #1680 중 하나를 정본으로 정하고 다른 하나의 children reparent.
