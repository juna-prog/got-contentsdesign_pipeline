-- ============================================================================
-- v19: Supabase Auth (Magic Link) + RLS 전면 재설계 + audit_log 통합
-- ============================================================================
-- 사유: 콘텐츠기획팀 공용 웹앱 진화. URL 만 알면 누구나 접근하던 익명 PostgREST
--       구조를 폐기하고 회사 메일 기반 invite-only 인증 도입.
-- 결정 (2026-05-04 사용자 확정):
--   - 인증 = Magic Link (signInWithOtp + shouldCreateUser:false)
--   - 가입 = invite-only (workers 사전 등록 + 본인 첫 로그인 시 auth_user_id 매핑)
--   - 도메인 = @nm-neo.com 전용 (Auth Hook before-user-created)
--   - workers.email = NOT NULL (28명 사전 수집)
--   - 비활성 워커 = 인증/데이터 모두 차단
--   - 관리자 = workers.is_team_lead 재사용
-- 적용 절차:
--   1) 28명 이메일 수집 후 § 6 의 backfill UPDATE 절을 채워 넣고 v19 실행
--      (TODO 가 남아 있으면 § 7 의 NOT NULL 적용 단계에서 명시 ERROR)
--   2) Supabase 대시보드 > Auth > Hooks > "Before User Created"
--      에 함수 `before_user_created_check_domain` 등록
--   3) 본인 (juna@nm-neo.com) UI SignInScreen 에서 매직링크 자가 발송 → 첫 로그인
-- 롤백:
--   - 비상 시 v19_rollback.sql 사용. RLS 정책을 v8 의 USING(true) 로 되돌리고
--     workers.email 등 추가 컬럼은 유지 (데이터 손실 회피).
-- ============================================================================

BEGIN;

-- ============================================================================
-- § 1. workers 확장
-- ============================================================================

ALTER TABLE workers
  ADD COLUMN IF NOT EXISTS email          TEXT,
  ADD COLUMN IF NOT EXISTS auth_user_id   UUID,
  ADD COLUMN IF NOT EXISTS last_login_at  TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS invited_at     TIMESTAMPTZ DEFAULT NOW();

-- email UNIQUE (NOT NULL 적용은 백필 후)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workers_email_unique'
  ) THEN
    ALTER TABLE workers ADD CONSTRAINT workers_email_unique UNIQUE (email);
  END IF;
END $$;

-- auth_user_id FK (auth.users 가 ON DELETE 시 NULL 로)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workers_auth_user_id_fkey'
  ) THEN
    ALTER TABLE workers
      ADD CONSTRAINT workers_auth_user_id_fkey
      FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workers_auth_user_id_unique'
  ) THEN
    ALTER TABLE workers
      ADD CONSTRAINT workers_auth_user_id_unique UNIQUE (auth_user_id);
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_workers_email          ON workers(email);
CREATE INDEX IF NOT EXISTS idx_workers_auth_user_id   ON workers(auth_user_id);
CREATE INDEX IF NOT EXISTS idx_workers_active_email   ON workers(is_active, email);

COMMENT ON COLUMN workers.email          IS '회사 메일 (@nm-neo.com). Magic Link 발송 키. UNIQUE NOT NULL.';
COMMENT ON COLUMN workers.auth_user_id   IS 'auth.users.id 매핑. 첫 로그인 시 백필.';
COMMENT ON COLUMN workers.last_login_at  IS '마지막 매직링크 인증 시각.';
COMMENT ON COLUMN workers.invited_at     IS '워커 행 생성 시각 (= 초대 시각).';

-- ============================================================================
-- § 2. allowed_email_domains 화이트리스트 + Auth Hook
-- ============================================================================

CREATE TABLE IF NOT EXISTS allowed_email_domains (
  domain     TEXT PRIMARY KEY,
  allowed    BOOLEAN DEFAULT TRUE,
  note       TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO allowed_email_domains(domain, note)
VALUES ('nm-neo.com', '넷마블네오 사내 메일')
ON CONFLICT (domain) DO NOTHING;

-- Auth Hook 함수: 가입 시 도메인 검증
-- 등록 위치: Supabase 대시보드 > Auth > Hooks > "Before User Created"
CREATE OR REPLACE FUNCTION public.before_user_created_check_domain(event JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  email_in TEXT;
  domain_in TEXT;
  ok BOOLEAN;
BEGIN
  email_in := COALESCE(
    event #>> '{user_metadata,email}',
    event #>> '{claims,email}',
    event #>> '{email}'
  );
  IF email_in IS NULL THEN
    RETURN jsonb_build_object('error', jsonb_build_object(
      'message', '이메일을 확인할 수 없습니다.',
      'http_code', 400));
  END IF;

  domain_in := LOWER(SUBSTRING(email_in FROM '@(.*)$'));

  SELECT allowed INTO ok
    FROM public.allowed_email_domains
    WHERE LOWER(domain) = domain_in;

  IF ok IS NOT TRUE THEN
    RETURN jsonb_build_object('error', jsonb_build_object(
      'message', '회사 메일 도메인만 가입 가능합니다.',
      'http_code', 400));
  END IF;

  RETURN '{}'::jsonb;
END;
$$;

GRANT EXECUTE ON FUNCTION public.before_user_created_check_domain(JSONB) TO supabase_auth_admin;

COMMENT ON FUNCTION public.before_user_created_check_domain IS
  'Supabase Auth Before-User-Created hook. allowed_email_domains 미등록 도메인 가입 차단.';

-- ============================================================================
-- § 3. SQL helper 함수
-- ============================================================================

CREATE OR REPLACE FUNCTION public.current_worker_id()
RETURNS INTEGER LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT id FROM workers
  WHERE auth_user_id = auth.uid() AND is_active = TRUE
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT COALESCE(
    (SELECT is_team_lead FROM workers
     WHERE auth_user_id = auth.uid() AND is_active = TRUE
     LIMIT 1),
    FALSE);
$$;

GRANT EXECUTE ON FUNCTION public.current_worker_id() TO authenticated, anon;
GRANT EXECUTE ON FUNCTION public.is_admin() TO authenticated, anon;

COMMENT ON FUNCTION public.current_worker_id IS
  '현재 인증 사용자의 활성 worker.id 반환. 미인증/비활성 시 NULL.';
COMMENT ON FUNCTION public.is_admin IS
  '현재 인증 사용자가 활성 + is_team_lead=TRUE 인지.';

-- ============================================================================
-- § 4. audit_log 통합 테이블
-- ============================================================================

CREATE TABLE IF NOT EXISTS audit_log (
  id              BIGSERIAL PRIMARY KEY,
  actor_worker_id INTEGER REFERENCES workers(id) ON DELETE SET NULL,
  actor_email     TEXT,
  action_type     TEXT NOT NULL,
  target_table    TEXT,
  target_id       TEXT,
  payload         JSONB,
  ip_address      TEXT,
  user_agent      TEXT,
  created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_audit_actor   ON audit_log(actor_worker_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_target  ON audit_log(target_table, target_id);
CREATE INDEX IF NOT EXISTS idx_audit_created ON audit_log(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_audit_action  ON audit_log(action_type, created_at DESC);

ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;

COMMENT ON TABLE audit_log IS
  '인증 이벤트 + admin 액션 통합 감사 로그. action_type 예: worker.create / worker.update / '
  'worker.activate / worker.deactivate / auth.login / auth.logout / admin.invite. '
  '콘텐츠/태스크 수정 이력은 schedule_changes 가 정본.';

-- ============================================================================
-- § 5. 이메일 백필 (우회 부트스트랩 모드)
-- ============================================================================
-- 사용자 결정 (2026-05-04): 본인 (juna) 1명만 활성 + 나머지 활성 워커는 임시
-- 비활성화 (is_active=FALSE) 로 전환. 향후 관리자 페이지에서 워커별 email 입력
-- + 활성 토글로 점진적으로 풀어줌.
-- 효과:
--   - § 6 검증은 활성 워커 1명만 검사 → PASS
--   - § 7 NOT NULL: 임시 비활성 워커들은 placeholder 'inactive_<id>@nm-neo.local'
--     로 자동 채움 → NOT NULL 통과
--   - 점진 풀이: admin UI 에서 (a) email 입력 (b) is_active=true 토글
-- 향후 정상 모드 전환 (28명 일괄 활성화) 시:
--   - migrations/v19_email_template.sql 의 28건 UPDATE 실행 +
--     UPDATE workers SET is_active=TRUE WHERE email NOT LIKE 'inactive_%';
-- ============================================================================

-- 본인 활성 + 메일 매핑
UPDATE workers SET email = 'juna@nm-neo.com' WHERE name = '신주나';

-- 다른 활성 워커 임시 비활성 (email 미수집 인원만 대상)
UPDATE workers
   SET is_active = FALSE
 WHERE name <> '신주나'
   AND is_active = TRUE
   AND email IS NULL;

-- ============================================================================
-- § 6. 백필 검증 (1건이라도 미수집이면 ERROR 로 트랜잭션 중단)
-- ============================================================================

DO $$
DECLARE
  missing_count INTEGER;
  missing_names TEXT;
BEGIN
  SELECT COUNT(*), STRING_AGG(name, ', ')
    INTO missing_count, missing_names
  FROM workers
  WHERE email IS NULL AND is_active = TRUE;

  IF missing_count > 0 THEN
    RAISE EXCEPTION
      '활성 워커 % 명의 이메일이 누락되었습니다 (% ). § 5 의 UPDATE 절을 채운 뒤 다시 실행하세요.',
      missing_count, missing_names;
  END IF;
END $$;

-- ============================================================================
-- § 7. workers.email NOT NULL 적용
-- ============================================================================
-- 비활성 워커도 email 이 채워져야 NOT NULL 통과. 비활성 + email NULL 행이 있으면
-- placeholder 로 채우거나 (deactivated_<id>@nm-neo.local) 행을 정리.

UPDATE workers
   SET email = 'inactive_' || id || '@nm-neo.local'
 WHERE email IS NULL AND is_active = FALSE;

ALTER TABLE workers ALTER COLUMN email SET NOT NULL;

-- ============================================================================
-- § 8. RLS 재설계 - 기존 *_all 정책 일괄 제거
-- ============================================================================
-- v8 / v9 / v12 / v17 등에서 만든 USING(true) WITH CHECK(true) 정책 폐기.
-- 정책 이름 컨벤션: <table>_all → 새 컨벤션 <table>_select_authed / <table>_write_admin / <table>_write_self.

-- 주의: schedule_changes 테이블은 현재 DB 에 미생성 상태 (v5_phase_abc 미적용
-- 또는 롤백). 관련 정책 처리 자체를 제외. 향후 schedule_changes 를 만들어
-- 사용하게 되면 별도 마이그레이션에서 RLS 정책도 같이 추가.
DROP POLICY IF EXISTS contents_all          ON contents;
DROP POLICY IF EXISTS tasks_all             ON tasks;
DROP POLICY IF EXISTS workers_all           ON workers;
DROP POLICY IF EXISTS parts_all             ON parts;
DROP POLICY IF EXISTS versions_all          ON versions;
DROP POLICY IF EXISTS milestones_all        ON milestones;
DROP POLICY IF EXISTS gate_transitions_all  ON gate_transitions;
DROP POLICY IF EXISTS task_assignees_all    ON task_assignees;
DROP POLICY IF EXISTS task_action_verbs_all ON task_action_verbs;
DROP POLICY IF EXISTS regions_all           ON regions;
DROP POLICY IF EXISTS part_categories_all   ON part_categories;
DROP POLICY IF EXISTS task_dependencies_all ON task_dependencies;
DROP POLICY IF EXISTS task_templates_all    ON task_templates;
DROP POLICY IF EXISTS sprint_config_all     ON sprint_config;
DROP POLICY IF EXISTS work_types_all        ON work_types;
DROP POLICY IF EXISTS jira_templates_all    ON jira_templates;
DROP POLICY IF EXISTS jira_creation_log_all ON jira_creation_log;
DROP POLICY IF EXISTS import_runs_all       ON import_runs;

-- ============================================================================
-- § 9. RLS 신규 정책
-- ============================================================================
-- 정책 행렬 요약:
--   [A] 읽기 전원 / 쓰기 admin
--       parts, versions, milestones, work_types, sprint_config, jira_templates,
--       regions, part_categories, task_action_verbs, task_templates,
--       allowed_email_domains
--   [B] 읽기 전원 / 쓰기 본인 또는 admin
--       contents, tasks, task_assignees, task_dependencies, schedule_changes,
--       gate_transitions, jira_creation_log, import_runs
--   [W] workers - 특수 (마지막 § 9.W)
--   [L] audit_log - 특수 (마지막 § 9.L)

-- ─── [A] 읽기 전원 / 쓰기 admin ───────────────────────────────────────────

CREATE POLICY parts_select          ON parts          FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY parts_write           ON parts          FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY versions_select       ON versions       FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY versions_write        ON versions       FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY milestones_select     ON milestones     FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY milestones_write      ON milestones     FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY work_types_select     ON work_types     FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY work_types_write      ON work_types     FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY sprint_config_select  ON sprint_config  FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY sprint_config_write   ON sprint_config  FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY jira_templates_select ON jira_templates FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY jira_templates_write  ON jira_templates FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY regions_select        ON regions        FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY regions_write         ON regions        FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY part_categories_select ON part_categories FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY part_categories_write  ON part_categories FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY task_action_verbs_select ON task_action_verbs FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY task_action_verbs_write  ON task_action_verbs FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY task_templates_select ON task_templates FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY task_templates_write  ON task_templates FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

ALTER TABLE allowed_email_domains ENABLE ROW LEVEL SECURITY;
CREATE POLICY allowed_email_domains_select ON allowed_email_domains FOR SELECT USING (is_admin());
CREATE POLICY allowed_email_domains_write  ON allowed_email_domains FOR ALL    USING (is_admin()) WITH CHECK (is_admin());

-- ─── [B] 읽기 전원 / 쓰기 본인 또는 admin ─────────────────────────────────
-- 본인 = current_worker_id() IS NOT NULL (= 인증된 활성 워커)
-- 운영 정책상 모든 활성 워커가 콘텐츠/태스크 입력 가능 (현재 클라이언트와 동일).

CREATE POLICY contents_select  ON contents  FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY contents_write   ON contents  FOR ALL    USING (current_worker_id() IS NOT NULL) WITH CHECK (current_worker_id() IS NOT NULL);

CREATE POLICY tasks_select     ON tasks     FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY tasks_write      ON tasks     FOR ALL    USING (current_worker_id() IS NOT NULL) WITH CHECK (current_worker_id() IS NOT NULL);

CREATE POLICY task_assignees_select ON task_assignees FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY task_assignees_write  ON task_assignees FOR ALL    USING (current_worker_id() IS NOT NULL) WITH CHECK (current_worker_id() IS NOT NULL);

CREATE POLICY task_dependencies_select ON task_dependencies FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY task_dependencies_write  ON task_dependencies FOR ALL    USING (current_worker_id() IS NOT NULL) WITH CHECK (current_worker_id() IS NOT NULL);

-- schedule_changes: 테이블 미존재로 정책 생성 생략 (위 § 8 주석 참조)

CREATE POLICY gate_transitions_select ON gate_transitions FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY gate_transitions_insert ON gate_transitions FOR INSERT WITH CHECK (current_worker_id() IS NOT NULL);
CREATE POLICY gate_transitions_admin  ON gate_transitions FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY gate_transitions_admin_d ON gate_transitions FOR DELETE USING (is_admin());

CREATE POLICY jira_creation_log_select ON jira_creation_log FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY jira_creation_log_insert ON jira_creation_log FOR INSERT WITH CHECK (current_worker_id() IS NOT NULL);
CREATE POLICY jira_creation_log_update ON jira_creation_log FOR UPDATE USING (current_worker_id() IS NOT NULL) WITH CHECK (current_worker_id() IS NOT NULL);
CREATE POLICY jira_creation_log_admin_d ON jira_creation_log FOR DELETE USING (is_admin());

CREATE POLICY import_runs_select ON import_runs FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY import_runs_insert ON import_runs FOR INSERT WITH CHECK (current_worker_id() IS NOT NULL);
CREATE POLICY import_runs_admin  ON import_runs FOR UPDATE USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY import_runs_admin_d ON import_runs FOR DELETE USING (is_admin());

-- ─── [W] workers ──────────────────────────────────────────────────────────
-- SELECT: 인증된 활성 워커 전원
-- INSERT/UPDATE/DELETE: admin 만
-- 예외: 본인 행의 last_login_at, auth_user_id 갱신은 본인 허용 (첫 로그인 백필용)

CREATE POLICY workers_select         ON workers FOR SELECT USING (current_worker_id() IS NOT NULL);
CREATE POLICY workers_admin_write    ON workers FOR ALL    USING (is_admin()) WITH CHECK (is_admin());
CREATE POLICY workers_self_login_upd ON workers FOR UPDATE
  USING ( email = (auth.jwt() ->> 'email') )
  WITH CHECK ( email = (auth.jwt() ->> 'email') );
-- 주의: 위 self UPDATE 정책은 모든 컬럼 수정을 허용하므로,
-- 클라이언트에서 본인 행에는 last_login_at / auth_user_id 만 PATCH 하도록 강제
-- (UI 가드 + 본인 행 외에는 admin 정책만 적용). 향후 column-level RLS 가
-- Supabase 에 정식 도입되면 그때 컬럼별 분리.

-- ─── [L] audit_log ────────────────────────────────────────────────────────
-- INSERT: 인증된 활성 워커 (단 actor_worker_id = current_worker_id() 강제)
-- SELECT: admin 만
-- UPDATE/DELETE: 금지 (감사 로그 불변성)

CREATE POLICY audit_log_insert ON audit_log FOR INSERT
  WITH CHECK ( actor_worker_id = current_worker_id() );
CREATE POLICY audit_log_select ON audit_log FOR SELECT
  USING ( is_admin() );
-- UPDATE / DELETE 정책 없음 → 자동으로 거부됨

-- ============================================================================
-- § 10. 검증 SELECT (트랜잭션 커밋 전 점검)
-- ============================================================================

DO $$
DECLARE
  workers_email_count INTEGER;
  workers_total INTEGER;
  policies_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO workers_total FROM workers;
  SELECT COUNT(*) INTO workers_email_count FROM workers WHERE email IS NOT NULL;

  IF workers_total <> workers_email_count THEN
    RAISE EXCEPTION 'workers.email 누락 행 발견: % / %', workers_email_count, workers_total;
  END IF;

  SELECT COUNT(*) INTO policies_count
    FROM pg_policies WHERE schemaname = 'public';
  RAISE NOTICE 'v19 적용 완료. workers % 명, RLS 정책 % 개', workers_total, policies_count;
END $$;

COMMIT;

-- ============================================================================
-- 후속 (대시보드 수동 작업)
-- ============================================================================
-- 1. Auth > Hooks > "Before User Created" → before_user_created_check_domain 등록
-- 2. (선택) Auth > Email Templates > Magic Link 본문 한글화
-- 3. UI 배포 후 본인 (juna@nm-neo.com) 첫 로그인 검증
-- 4. 다른 팀원 1명 시범 → 본인 SignInScreen 첫 로그인 검증 → 점진 안내
