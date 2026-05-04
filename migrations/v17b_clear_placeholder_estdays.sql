-- v17b: work_types.default_est_days placeholder 값 제거
-- 사유: v17 seed 의 일수 (5/8/3/2/1) 는 임의 추정값. 파트장 합의 없이는 자동 채움/권장 표시에 사용하지 않는다.
--      JIRA 일감에 등록된 시작/종료 일자가 정본. 표준 일수 합의가 선행돼야 함.
-- 효과:
--   1. import 시 work_types.default_est_days 자동 채움 미발동 (코드 NULL 가드)
--   2. JIRA preview 의 "Work Type (권장 N일)" 표시 비활성화

UPDATE work_types
SET default_est_days = NULL
WHERE default_est_days IS NOT NULL;

-- 검증: SELECT work_type_key, label, default_est_days FROM work_types ORDER BY sort_order;
-- 모두 NULL 이어야 함.

-- 향후 파트장 합의가 끝나면 work_type 별로 UPDATE 실행:
-- UPDATE work_types SET default_est_days = 5.0 WHERE work_type_key = 'art_char_concept';
