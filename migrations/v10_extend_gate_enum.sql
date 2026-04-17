-- v10: Gate enum 확장 (G4~G7 추가)
-- 기존: G0, G1, G1a, G1b, G2, G3, DONE
-- 추가: G4 (아트 요청), G5 (구현/제작), G6 (재미검증), G7 (QA/폴리싱)

ALTER TYPE gate_stage ADD VALUE IF NOT EXISTS 'G4' BEFORE 'DONE';
ALTER TYPE gate_stage ADD VALUE IF NOT EXISTS 'G5' BEFORE 'DONE';
ALTER TYPE gate_stage ADD VALUE IF NOT EXISTS 'G6' BEFORE 'DONE';
ALTER TYPE gate_stage ADD VALUE IF NOT EXISTS 'G7' BEFORE 'DONE';
