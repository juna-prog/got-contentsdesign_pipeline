-- v16b: 기획팀 신규 파트 5종 + 누락 workers 7명 등록
-- 사용자 확인(2026-04-24):
--   - 김현재 퇴사자 → 제거 (v16 에도 반영)
--   - 김지예 → cutscene (연출) - 기존 파트
--   - 김한나 → PM (신규 파트 planning_pm)
--   - 유예담 → system (신규 파트)
--   - 김도완 → client (신규 파트)
--   - 김덕규 → system (신규 파트)
--   - 한승희 → balance 파트장 (신규 파트)
--   - 최진이 → ui/ux 파트장 (신규 파트 uiux)

-- ============================================================================
-- 1. 기획팀 신규 파트 5종
-- sort_order 5~9: 기존 콘텐츠기획(quest/field/combat/level, sort 1~4) 바로 다음
-- team: '콘텐츠기획팀' 일괄. 세분류는 파트 label 로 구분
-- ============================================================================

INSERT INTO parts (id, label, team, sort_order) VALUES
  ('planning_pm', '기획PM',     '콘텐츠기획팀', 5),
  ('system',      '시스템기획', '콘텐츠기획팀', 6),
  ('client',      '클라기획',   '콘텐츠기획팀', 7),
  ('balance',     '밸런스기획', '콘텐츠기획팀', 8),
  ('uiux',        'UI/UX기획',  '콘텐츠기획팀', 9)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- 2. 누락 workers 7명 등록 (김현재 제외)
-- 한승희: balance 파트장 (is_part_lead=TRUE)
-- 최진이: uiux 파트장 (is_part_lead=TRUE)
-- ============================================================================

INSERT INTO workers (name, part_id, is_part_lead, jira_account_id) VALUES
  ('김지예', 'cutscene',    FALSE, 'jiyea'),
  ('김한나', 'planning_pm', FALSE, 'hannah'),
  ('유예담', 'system',      FALSE, 'youyedam'),
  ('김도완', 'client',      FALSE, 'dowan'),
  ('김덕규', 'system',      FALSE, 'deokgyu'),
  ('한승희', 'balance',     TRUE,  'seunghee'),
  ('최진이', 'uiux',        TRUE,  'choijn')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- 3. 검증
-- ============================================================================

-- SELECT name, part_id, is_part_lead, jira_account_id
-- FROM workers
-- WHERE jira_account_id IN ('jiyea','hannah','youyedam','dowan','deokgyu','seunghee','choijn')
-- ORDER BY part_id, name;

-- SELECT id, label, team, sort_order FROM parts
-- WHERE id IN ('planning_pm','system','client','balance','uiux');
