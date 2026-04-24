-- v16: workers.jira_account_id 재활용 (JIRA Server username 저장)
-- Phase 6 JIRA 양방향 sync 2단계
--
-- 배경:
--   - 기존 스키마에 workers.jira_account_id 컬럼이 존재하나 74명 전원 NULL 상태
--   - JIRA Cloud 는 accountId 를 쓰지만, 사내는 JIRA Server (jira.nmn.io) 를 쓰므로
--     실질적으로 저장 값은 username (예: juna, hycho)
--   - 컬럼을 추가 신설하지 않고 기존 컬럼을 재활용하여 DDL 없이 진행
--   - COMMENT 로 실제 저장 값 명시
--
-- 소스: [DEV][왕좌의게임] 콘텐츠 기획팀 작업 관리 시트.xlsx > JIra_Users 시트 (29명)
-- 적용 위치:
--   - index.html buildTaskPayload: assignee_id -> workers.jira_account_id -> fields.assignee.name
--   - operator: content.owner -> workers.jira_account_id -> fields.reporter.name (기본 juna)

-- ============================================================================
-- 1. 컬럼 주석 명시 (DDL 필요 시 Supabase SQL editor 에서만 실행)
-- ============================================================================

COMMENT ON COLUMN workers.jira_account_id IS
  'JIRA Server(jira.nmn.io) 로그인 username. 예: juna, hycho, jaemann. '
  'payload.fields.assignee.name / reporter.name 에 사용. '
  'Cloud accountId 가 아닌 점 주의 (사내는 Server 배포).';

CREATE INDEX IF NOT EXISTS idx_workers_jira_account_id ON workers(jira_account_id);

-- ============================================================================
-- 2. 29명 매핑 (JIra_Users 시트 기준, PostgREST 로도 실행 가능)
-- ============================================================================

UPDATE workers SET jira_account_id = 'juna'           WHERE name = '신주나';
UPDATE workers SET jira_account_id = 'hycho'          WHERE name = '조현용';
UPDATE workers SET jira_account_id = 'jaemann'        WHERE name = '권재만';
UPDATE workers SET jira_account_id = 'sangcheol.park' WHERE name = '박상철';
-- UPDATE workers SET jira_account_id = 'hyunjae' WHERE name = '김현재'; -- 퇴사자 (사용자 확인 2026-04-24)
UPDATE workers SET jira_account_id = 'jun_hong'       WHERE name = '홍준';
UPDATE workers SET jira_account_id = 'kyeonghun'      WHERE name = '남경훈';
UPDATE workers SET jira_account_id = 'chanhyun'       WHERE name = '박찬현';
UPDATE workers SET jira_account_id = 'jinsu_kim'      WHERE name = '김진수';
UPDATE workers SET jira_account_id = 'jeongook'       WHERE name = '전정욱';
UPDATE workers SET jira_account_id = 'gahyeon_s'      WHERE name = '신가현';
UPDATE workers SET jira_account_id = 'imjuwon'        WHERE name = '임주원';
UPDATE workers SET jira_account_id = 'sungmin.jung'   WHERE name = '정성민';
UPDATE workers SET jira_account_id = 'jieun.kwon'     WHERE name = '권지은';
UPDATE workers SET jira_account_id = 'seokwan'        WHERE name = '손석완';
UPDATE workers SET jira_account_id = 'jinyong_lee'    WHERE name = '이진용';
UPDATE workers SET jira_account_id = 'hajin'          WHERE name = '정하진';
UPDATE workers SET jira_account_id = 'myungjun'       WHERE name = '곽명준';
UPDATE workers SET jira_account_id = 'kyoungyeol'     WHERE name = '윤경열';
UPDATE workers SET jira_account_id = 'taegyeong'      WHERE name = '안태경';
UPDATE workers SET jira_account_id = 'joonghoon'      WHERE name = '최중훈';
UPDATE workers SET jira_account_id = 'hyeri'          WHERE name = '김지호';
UPDATE workers SET jira_account_id = 'jiyea'          WHERE name = '김지예';
UPDATE workers SET jira_account_id = 'hannah'         WHERE name = '김한나';
UPDATE workers SET jira_account_id = 'yunsuk'         WHERE name = '김윤석';
UPDATE workers SET jira_account_id = 'youyedam'       WHERE name = '유예담';
UPDATE workers SET jira_account_id = 'dowan'          WHERE name = '김도완';
UPDATE workers SET jira_account_id = 'deokgyu'        WHERE name = '김덕규';
UPDATE workers SET jira_account_id = 'seunghee'       WHERE name = '한승희';
UPDATE workers SET jira_account_id = 'choijn'         WHERE name = '최진이';

-- ============================================================================
-- 3. 검증 뷰: 매핑 누락 확인용
-- ============================================================================

CREATE OR REPLACE VIEW v_workers_jira_mapping AS
SELECT
  w.id, w.name, w.part_id, w.jira_account_id AS jira_username,
  CASE WHEN w.jira_account_id IS NULL THEN '미매핑'
       ELSE '완료' END AS mapping_status,
  w.is_part_lead, w.is_team_lead
FROM workers w
ORDER BY w.jira_account_id NULLS LAST, w.part_id, w.name;

COMMENT ON VIEW v_workers_jira_mapping IS
  'workers 테이블의 jira_account_id(=JIRA username) 매핑 상태 점검용. 미매핑 건을 상단에 노출.';
