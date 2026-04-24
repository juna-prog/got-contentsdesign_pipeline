-- Pipeline Tracker v7 - Art team parts & workers
-- Run on Supabase SQL editor (huegoxqcoqealhhlrkww.supabase.co)

-- ============================================================================
-- V7.1 Art parts registration
-- ============================================================================

INSERT INTO parts (id, label, team, sort_order) VALUES
  ('art_team_1',       '아트1팀장',     '아트1팀', 10),
  ('art_char_concept', '캐릭터원화',    '아트1팀', 11),
  ('art_char_model',   '캐릭터모델링',  '아트1팀', 12),
  ('art_anim',         '애니메이션',    '아트1팀', 13),
  ('art_fx',           '이펙트',        '아트1팀', 14),
  ('art_team_2',       '아트2팀장',     '아트2팀', 20),
  ('art_bg_concept',   '배경원화',      '아트2팀', 21),
  ('art_bg_model',     '배경모델링',    '아트2팀', 22),
  ('art_ta',           'TA',            '아트2팀', 23),
  ('cutscene',         '연출',          '연출',    30)
ON CONFLICT (id) DO NOTHING;

-- ============================================================================
-- V7.2 Art workers registration (43 members)
-- 파트장은 is_part_lead = TRUE, 팀장은 is_team_lead = TRUE
-- ============================================================================

-- Art 1 Team Lead
INSERT INTO workers (name, part_id, is_part_lead, is_team_lead) VALUES
  ('서민석', 'art_team_1', FALSE, TRUE)
ON CONFLICT DO NOTHING;

-- Character Concept (캐원) - 3
INSERT INTO workers (name, part_id, is_part_lead) VALUES
  ('우승훈', 'art_char_concept', FALSE),
  ('김선우', 'art_char_concept', FALSE),
  ('최세린', 'art_char_concept', FALSE)
ON CONFLICT DO NOTHING;

-- Character Modeling (캐모) - 9, lead: 원근식
INSERT INTO workers (name, part_id, is_part_lead) VALUES
  ('원근식', 'art_char_model', TRUE),
  ('강우석', 'art_char_model', FALSE),
  ('김소영', 'art_char_model', FALSE),
  ('안수지', 'art_char_model', FALSE),
  ('이소연', 'art_char_model', FALSE),
  ('이지훈', 'art_char_model', FALSE),
  ('이희영', 'art_char_model', FALSE),
  ('조원식', 'art_char_model', FALSE),
  ('최재영', 'art_char_model', FALSE)
ON CONFLICT DO NOTHING;

-- Animation (애니) - 5, lead: 나경종
INSERT INTO workers (name, part_id, is_part_lead) VALUES
  ('나경종', 'art_anim', TRUE),
  ('고은해', 'art_anim', FALSE),
  ('오재민', 'art_anim', FALSE),
  ('윤성철', 'art_anim', FALSE),
  ('이주연', 'art_anim', FALSE)
ON CONFLICT DO NOTHING;

-- VFX (이팩트) - 3, lead: 윤정환
INSERT INTO workers (name, part_id, is_part_lead) VALUES
  ('윤정환', 'art_fx', TRUE),
  ('권준호', 'art_fx', FALSE),
  ('인다겸', 'art_fx', FALSE)
ON CONFLICT DO NOTHING;

-- Art 2 Team Lead
INSERT INTO workers (name, part_id, is_part_lead, is_team_lead) VALUES
  ('이필우', 'art_team_2', FALSE, TRUE)
ON CONFLICT DO NOTHING;

-- BG Concept (배원) - 3, lead: 이대인
INSERT INTO workers (name, part_id, is_part_lead) VALUES
  ('이대인', 'art_bg_concept', TRUE),
  ('이지수', 'art_bg_concept', FALSE),
  ('한호연', 'art_bg_concept', FALSE)
ON CONFLICT DO NOTHING;

-- BG Modeling (배모) - 11
INSERT INTO workers (name, part_id, is_part_lead) VALUES
  ('권혁',   'art_bg_model', FALSE),
  ('김나영', 'art_bg_model', FALSE),
  ('김우근', 'art_bg_model', FALSE),
  ('박소현', 'art_bg_model', FALSE),
  ('변지연', 'art_bg_model', FALSE),
  ('엄연재', 'art_bg_model', FALSE),
  ('우현균', 'art_bg_model', FALSE),
  ('이창곤', 'art_bg_model', FALSE),
  ('정지윤', 'art_bg_model', FALSE),
  ('지은혜', 'art_bg_model', FALSE),
  ('황은솔', 'art_bg_model', FALSE)
ON CONFLICT DO NOTHING;

-- TA - 3, lead: 김광준
INSERT INTO workers (name, part_id, is_part_lead) VALUES
  ('김광준', 'art_ta', TRUE),
  ('고영만', 'art_ta', FALSE),
  ('장규봉', 'art_ta', FALSE)
ON CONFLICT DO NOTHING;

-- Cutscene (연출) - 4
INSERT INTO workers (name, part_id, is_part_lead) VALUES
  ('김상연', 'cutscene', FALSE),
  ('박민주', 'cutscene', FALSE),
  ('노보람', 'cutscene', FALSE),
  ('노태호', 'cutscene', FALSE)
ON CONFLICT DO NOTHING;
