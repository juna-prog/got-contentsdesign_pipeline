-- ============================================================================
-- v19_email_template: 28명 이메일 매핑 템플릿
-- ============================================================================
-- 사용법:
--   1. 아래 28건 의 'TODO@nm-neo.com' 자리를 실제 회사 메일로 치환
--   2. 채워진 UPDATE 절을 v19_auth_audit.sql 의 § 5 에 붙여넣고 실행
--   3. 이메일 미수집 인원이 있으면 § 6 검증에서 ERROR 로 트랜잭션 중단
-- 정책:
--   - jira_account_id (예: juna) 와 회사 메일 prefix 가 동일한 경우가 대부분
--     → 1차 추정: jira_account_id || '@nm-neo.com'
--     → 단 . _ 등 prefix 가 다른 케이스 있어 본인 확인 필수
--   - 도메인 = @nm-neo.com (allowed_email_domains 화이트리스트)
-- ============================================================================

-- 본인 (관리자) 부터 - juna 가 jira_account_id, 메일 prefix 도 juna 추정
UPDATE workers SET email = 'juna@nm-neo.com'           WHERE name = '신주나';

-- 콘텐츠기획팀 (4파트 + 팀 리드)
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '조현용';        -- jira: hycho
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '권재만';        -- jira: jaemann
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '박상철';        -- jira: sangcheol.park
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '홍준';          -- jira: jun_hong
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '남경훈';        -- jira: kyeonghun
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '박찬현';        -- jira: chanhyun
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '김진수';        -- jira: jinsu_kim
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '전정욱';        -- jira: jeongook
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '신가현';        -- jira: gahyeon_s
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '임주원';        -- jira: imjuwon
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '정성민';        -- jira: sungmin.jung
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '권지은';        -- jira: jieun.kwon
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '손석완';        -- jira: seokwan
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '이진용';        -- jira: jinyong_lee
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '정하진';        -- jira: hajin
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '곽명준';        -- jira: myungjun
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '윤경열';        -- jira: kyoungyeol
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '안태경';        -- jira: taegyeong
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '최중훈';        -- jira: joonghoon
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '김지호';        -- jira: hyeri
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '김지예';        -- jira: jiyea
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '김한나';        -- jira: hannah
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '김윤석';        -- jira: yunsuk
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '유예담';        -- jira: youyedam
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '김도완';        -- jira: dowan
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '김덕규';        -- jira: deokgyu
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '한승희';        -- jira: seunghee  (balance 파트장)
UPDATE workers SET email = 'TODO@nm-neo.com'           WHERE name = '최진이';        -- jira: choijn    (uiux 파트장)

-- 김현재 (퇴사자, v16b 에서 제외) - 활성 워커가 아니라 패스. 단 v18 적용 후
-- workers 에 행이 있다면 § 7 의 inactive 처리에서 'inactive_<id>@nm-neo.local' 로 자동 채움.

-- ============================================================================
-- 검증 SELECT: TODO 가 남은 행 확인
-- ============================================================================
-- SELECT name, jira_account_id, email
--   FROM workers
--   WHERE email LIKE 'TODO@%' AND is_active = TRUE
--   ORDER BY part_id, name;
