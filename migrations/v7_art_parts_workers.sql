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
-- ============================================================================

-- Art 1 Team Lead
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('서민석', 'art_team_1', TRUE, FALSE)
ON CONFLICT DO NOTHING;

-- Character Concept (캐원) - 3
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('우승훈', 'art_char_concept', FALSE, FALSE),
  ('김선우', 'art_char_concept', FALSE, FALSE),
  ('최세린', 'art_char_concept', FALSE, FALSE)
ON CONFLICT DO NOTHING;

-- Character Modeling (캐모) - 9, lead: 원근식
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('원근식', 'art_char_model', TRUE, TRUE),
  ('강우석', 'art_char_model', FALSE, FALSE),
  ('김소영', 'art_char_model', FALSE, FALSE),
  ('안수지', 'art_char_model', FALSE, FALSE),
  ('이소연', 'art_char_model', FALSE, FALSE),
  ('이지훈', 'art_char_model', FALSE, FALSE),
  ('이희영', 'art_char_model', FALSE, FALSE),
  ('조원식', 'art_char_model', FALSE, FALSE),
  ('최재영', 'art_char_model', FALSE, FALSE)
ON CONFLICT DO NOTHING;

-- Animation (애니) - 5, lead: 나경종
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('나경종', 'art_anim', TRUE, TRUE),
  ('고은해', 'art_anim', FALSE, FALSE),
  ('오재민', 'art_anim', FALSE, FALSE),
  ('윤성철', 'art_anim', FALSE, FALSE),
  ('이주연', 'art_anim', FALSE, FALSE)
ON CONFLICT DO NOTHING;

-- VFX (이팩트) - 3, lead: 윤정환
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('윤정환', 'art_fx', TRUE, TRUE),
  ('권준호', 'art_fx', FALSE, FALSE),
  ('인다겸', 'art_fx', FALSE, FALSE)
ON CONFLICT DO NOTHING;

-- Art 2 Team Lead
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('이필우', 'art_team_2', TRUE, FALSE)
ON CONFLICT DO NOTHING;

-- BG Concept (배원) - 3, lead: 이대인
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('이대인', 'art_bg_concept', TRUE, TRUE),
  ('이지수', 'art_bg_concept', FALSE, FALSE),
  ('한호연', 'art_bg_concept', FALSE, FALSE)
ON CONFLICT DO NOTHING;

-- BG Modeling (배모) - 11
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('권혁',   'art_bg_model', FALSE, FALSE),
  ('김나영', 'art_bg_model', FALSE, FALSE),
  ('김우근', 'art_bg_model', FALSE, FALSE),
  ('박소현', 'art_bg_model', FALSE, FALSE),
  ('변지연', 'art_bg_model', FALSE, FALSE),
  ('엄연재', 'art_bg_model', FALSE, FALSE),
  ('우현균', 'art_bg_model', FALSE, FALSE),
  ('이창곤', 'art_bg_model', FALSE, FALSE),
  ('정지윤', 'art_bg_model', FALSE, FALSE),
  ('지은혜', 'art_bg_model', FALSE, FALSE),
  ('황은솔', 'art_bg_model', FALSE, FALSE)
ON CONFLICT DO NOTHING;

-- TA - 3, lead: 김광준
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('김광준', 'art_ta', TRUE, TRUE),
  ('고영만', 'art_ta', FALSE, FALSE),
  ('장규봉', 'art_ta', FALSE, FALSE)
ON CONFLICT DO NOTHING;

-- Cutscene (연출) - 4
INSERT INTO workers (name, part_id, is_lead, is_part_lead) VALUES
  ('김상연', 'cutscene', FALSE, FALSE),
  ('박민주', 'cutscene', FALSE, FALSE),
  ('노보람', 'cutscene', FALSE, FALSE),
  ('노태호', 'cutscene', FALSE, FALSE)
ON CONFLICT DO NOTHING;
