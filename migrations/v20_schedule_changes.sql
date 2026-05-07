-- v20: schedule_changes 테이블 복원
-- 작성일: 2026-05-07
-- 사유:
--   v5_phase_abc 가 미적용 또는 롤백되어 schedule_changes 테이블 부재.
--   v19_auth_audit (line 254~256, 342) 에서 명시적으로 RLS 생성 skip.
--   결과: index.html 의 NoticeBar 무력화 + 콘텐츠 일정 변경 사유 기록 불가.
--   본 마이그레이션이 v5_phase_abc 의 A.3 섹션을 v19 표준 RLS 로 재정의하여 분리 적용.
-- 영향:
--   - schedule_changes 테이블 신규 (기존 데이터 0)
--   - actor_worker_id 컬럼 추가 (v9 표준 - workers FK 기반 감사 강화)
--   - RLS 정책 4종 (select/insert/admin update/admin delete)
-- 클라이언트 변경:
--   - index.html addChange 호출 시 actor_worker_id: user.id 자동 포함 (별도 commit)

-- ============================================================================
-- § 1. 테이블 + 인덱스
-- ============================================================================

CREATE TABLE IF NOT EXISTS schedule_changes (
  id BIGSERIAL PRIMARY KEY,
  content_id INTEGER REFERENCES contents(id) ON DELETE CASCADE,
  task_id INTEGER REFERENCES tasks(id) ON DELETE CASCADE,
  field TEXT NOT NULL,
  old_value TEXT,
  new_value TEXT,
  reason TEXT NOT NULL,
  changed_by TEXT NOT NULL,
  actor_worker_id INTEGER REFERENCES workers(id) ON DELETE SET NULL,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

COMMENT ON TABLE schedule_changes IS '콘텐츠/태스크 일정/상태 변경 이력 + 사유. NoticeBar 데이터 소스. v20 복원 (2026-05-07).';
COMMENT ON COLUMN schedule_changes.changed_by IS '워커 이름 (legacy v5 호환, 표시용).';
COMMENT ON COLUMN schedule_changes.actor_worker_id IS '워커 FK (v9 표준, 감사용). 워커 삭제 시 SET NULL.';
COMMENT ON COLUMN schedule_changes.field IS '변경 필드명 (start_date / end_date / version_id / gate / locked / status 등).';

CREATE INDEX IF NOT EXISTS idx_schedule_changes_content
  ON schedule_changes(content_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_schedule_changes_task
  ON schedule_changes(task_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_schedule_changes_recent
  ON schedule_changes(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_schedule_changes_actor
  ON schedule_changes(actor_worker_id, created_at DESC);

-- ============================================================================
-- § 2. RLS (v19 표준)
-- ============================================================================
-- 정책 행렬:
--   SELECT: 인증된 활성 워커 전원 (current_worker_id() IS NOT NULL)
--   INSERT: 인증된 활성 워커 전원 (본인 변경 기록)
--   UPDATE: admin 만 (이력 보존성)
--   DELETE: admin 만 (이력 보존성)

ALTER TABLE schedule_changes ENABLE ROW LEVEL SECURITY;

-- legacy 정책 정리 (v5_phase_abc 가 적용된 적 있다면)
DROP POLICY IF EXISTS schedule_changes_all          ON schedule_changes;
DROP POLICY IF EXISTS schedule_changes_anon_all     ON schedule_changes;

-- 신규 정책
DROP POLICY IF EXISTS schedule_changes_select       ON schedule_changes;
DROP POLICY IF EXISTS schedule_changes_insert       ON schedule_changes;
DROP POLICY IF EXISTS schedule_changes_admin_u      ON schedule_changes;
DROP POLICY IF EXISTS schedule_changes_admin_d      ON schedule_changes;

CREATE POLICY schedule_changes_select  ON schedule_changes FOR SELECT
  USING (current_worker_id() IS NOT NULL);

CREATE POLICY schedule_changes_insert  ON schedule_changes FOR INSERT
  WITH CHECK (current_worker_id() IS NOT NULL);

CREATE POLICY schedule_changes_admin_u ON schedule_changes FOR UPDATE
  USING (is_admin()) WITH CHECK (is_admin());

CREATE POLICY schedule_changes_admin_d ON schedule_changes FOR DELETE
  USING (is_admin());

-- ============================================================================
-- § 3. 검증 쿼리 (수동 실행)
-- ============================================================================
-- 적용 후 아래 쿼리로 확인:
--
-- 1. 테이블 + 컬럼 확인
--    SELECT column_name, data_type, is_nullable
--    FROM information_schema.columns
--    WHERE table_name = 'schedule_changes'
--    ORDER BY ordinal_position;
--
-- 2. RLS 정책 4개 활성 확인
--    SELECT polname, polcmd
--    FROM pg_policy
--    WHERE polrelid = 'schedule_changes'::regclass;
--    -- 기대값: schedule_changes_select / _insert / _admin_u / _admin_d
--
-- 3. 인덱스 4개 확인
--    SELECT indexname FROM pg_indexes WHERE tablename = 'schedule_changes';
--    -- 기대값: schedule_changes_pkey / idx_schedule_changes_content /
--    --        idx_schedule_changes_task / idx_schedule_changes_recent /
--    --        idx_schedule_changes_actor
--
-- 4. 빈 테이블 확인 (신규 생성)
--    SELECT COUNT(*) FROM schedule_changes;
--    -- 기대값: 0
