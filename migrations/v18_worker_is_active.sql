-- v18: workers.is_active 컬럼 추가
-- 사유: 퇴직자/비활성 작업자 이력 보존. task_assignees CASCADE 로 인한 과거 task 매핑 손실 방지.
-- 효과:
--   1. 신규 작업자 INSERT 시 is_active=TRUE 기본값
--   2. 작업자 관리 UI 의 "비활성화" 토글 = is_active=FALSE
--   3. 사용자 선택/할당 드롭다운은 is_active=TRUE 만 표시 (코드에서 필터)

ALTER TABLE workers
  ADD COLUMN IF NOT EXISTS is_active BOOLEAN DEFAULT TRUE NOT NULL;

-- 기존 행은 자동으로 TRUE 가 되지만 명시적으로 한 번 더 적용
UPDATE workers SET is_active = TRUE WHERE is_active IS NULL;

COMMENT ON COLUMN workers.is_active IS
  '활성 작업자 여부. FALSE = 퇴직/비활성. 과거 task_assignees 보존을 위해 hard delete 대신 사용.';

-- 검증: SELECT name, part_id, is_active FROM workers WHERE is_active = FALSE;
-- 초기 적용 직후에는 0 행이 정상.
