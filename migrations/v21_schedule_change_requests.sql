-- v21: 일정 조정 요청 + 승인 워크플로 (Phase 3 FUTURE-2)
-- 작성일: 2026-05-08
-- 사유:
--   작업자(non-admin)가 본인 task 의 일정 조정 시 승인 게이트 + 영향 범위 노출.
--   3일 이내 = 1차 파트장만 / 1주일 이상 = 1차 파트장 + 2차 팀장(신주나) 양쪽 승인.
-- 영향:
--   - schedule_change_requests 테이블 신규 (기존 데이터 0)
--   - workers.is_part_lead / is_team_lead 권한 활용 (이미 존재)
--   - cascade 알고리즘 v2 (5/8 Phase 2.5 도입) 와 연계: 영향 범위 자동 계산 → affected_tasks JSONB
-- 클라이언트 변경 (별도 commit):
--   - TaskDetail 에 "일정 조정 요청" 버튼 (본인 task 만, non-admin)
--   - AdminPanel 6번째 탭 "일정 조정 요청" (파트장/팀장 권한별 row 분리)
--   - NoticeBar 본인 승인 대기 N건

-- ============================================================================
-- § 1. 테이블 + 인덱스
-- ============================================================================

CREATE TABLE IF NOT EXISTS schedule_change_requests (
  id BIGSERIAL PRIMARY KEY,
  task_id INTEGER NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  requester_id INTEGER NOT NULL REFERENCES workers(id) ON DELETE SET NULL,

  -- 현재 일정 (요청 시점 스냅샷)
  current_start DATE,
  current_end DATE,

  -- 희망 일정
  desired_start DATE NOT NULL,
  desired_end DATE NOT NULL,

  -- 분석 결과
  delay_days INTEGER NOT NULL,                  -- 영업일 기준 (음수 = 당김)
  reason TEXT NOT NULL,
  affected_tasks JSONB DEFAULT '[]'::jsonb,     -- [{task_id, current_end, proposed_end, worker_name}]

  -- 워크플로 상태
  status TEXT NOT NULL DEFAULT 'pending',
    -- pending / lvl1_approved / approved / rejected / cancelled / applied

  -- 1차 승인 (파트장)
  lvl1_approver_id INTEGER REFERENCES workers(id) ON DELETE SET NULL,
  lvl1_at TIMESTAMPTZ,
  lvl1_adjustments JSONB,                       -- 파트장이 영향받는 task 추가 조정한 결과
  lvl1_comment TEXT,

  -- 2차 승인 (팀장, 1주일 이상 변경 시만 필요)
  lvl2_required BOOLEAN NOT NULL DEFAULT false,
  lvl2_approver_id INTEGER REFERENCES workers(id) ON DELETE SET NULL,
  lvl2_at TIMESTAMPTZ,
  lvl2_adjustments JSONB,
  lvl2_comment TEXT,

  -- 적용
  applied_at TIMESTAMPTZ,
  rejected_reason TEXT,

  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE schedule_change_requests IS
  '일정 조정 요청 + 1차(파트장)/2차(팀장) 승인 워크플로. 3일 이내 = 1차만 / 1주일 이상 = 1차 + 2차. v21 (2026-05-08).';
COMMENT ON COLUMN schedule_change_requests.delay_days IS '영업일 기준 지연 일수 (한국 공휴일 + 주말 제외, 클라이언트 계산 후 저장).';
COMMENT ON COLUMN schedule_change_requests.affected_tasks IS 'cascade v2 알고리즘 (동일 워커 + old 기간 겹침) 결과. 1차/2차 승인자가 추가 조정 가능.';
COMMENT ON COLUMN schedule_change_requests.lvl2_required IS '7 영업일 이상 지연 시 true. 클라이언트가 delay_days >= 7 자동 설정.';
COMMENT ON COLUMN schedule_change_requests.status IS
  'pending(요청) / lvl1_approved(1차 승인, 2차 대기) / approved(최종 승인) / rejected(거절) / cancelled(요청자 취소) / applied(트래커 적용 완료)';

CREATE INDEX IF NOT EXISTS idx_scr_task          ON schedule_change_requests(task_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scr_requester     ON schedule_change_requests(requester_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scr_status        ON schedule_change_requests(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_scr_lvl1_approver ON schedule_change_requests(lvl1_approver_id, status);
CREATE INDEX IF NOT EXISTS idx_scr_lvl2_approver ON schedule_change_requests(lvl2_approver_id, status);
CREATE INDEX IF NOT EXISTS idx_scr_recent        ON schedule_change_requests(created_at DESC);

-- updated_at 자동 갱신 트리거 (v19 표준 패턴)
CREATE OR REPLACE FUNCTION schedule_change_requests_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_scr_updated_at ON schedule_change_requests;
CREATE TRIGGER trg_scr_updated_at
  BEFORE UPDATE ON schedule_change_requests
  FOR EACH ROW EXECUTE FUNCTION schedule_change_requests_set_updated_at();

-- ============================================================================
-- § 2. RLS
-- ============================================================================
-- 정책 행렬 (v19 표준 + 워크플로 권한):
--   SELECT: 인증된 활성 워커 전원 (광범위 표시 - NoticeBar / AdminPanel 탭)
--   INSERT: requester_id = current_worker_id() (본인만 요청)
--   UPDATE: 1차 승인자 / 2차 승인자 / admin (각자 단계만 수정)
--   DELETE: 요청자 본인 (pending 상태에서만 취소) 또는 admin

ALTER TABLE schedule_change_requests ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS scr_select   ON schedule_change_requests;
DROP POLICY IF EXISTS scr_insert   ON schedule_change_requests;
DROP POLICY IF EXISTS scr_update   ON schedule_change_requests;
DROP POLICY IF EXISTS scr_delete   ON schedule_change_requests;

CREATE POLICY scr_select ON schedule_change_requests FOR SELECT
  USING (current_worker_id() IS NOT NULL);

CREATE POLICY scr_insert ON schedule_change_requests FOR INSERT
  WITH CHECK (requester_id = current_worker_id());

CREATE POLICY scr_update ON schedule_change_requests FOR UPDATE
  USING (
    is_admin()
    OR lvl1_approver_id = current_worker_id()
    OR lvl2_approver_id = current_worker_id()
    OR (status = 'pending' AND requester_id = current_worker_id())
  )
  WITH CHECK (
    is_admin()
    OR lvl1_approver_id = current_worker_id()
    OR lvl2_approver_id = current_worker_id()
    OR (status IN ('pending','cancelled') AND requester_id = current_worker_id())
  );

CREATE POLICY scr_delete ON schedule_change_requests FOR DELETE
  USING (
    is_admin()
    OR (status = 'pending' AND requester_id = current_worker_id())
  );

-- ============================================================================
-- § 3. 검증 쿼리 (수동 실행)
-- ============================================================================
-- 1. 테이블 + 컬럼 확인
--    SELECT column_name, data_type, is_nullable
--    FROM information_schema.columns
--    WHERE table_name = 'schedule_change_requests'
--    ORDER BY ordinal_position;
--
-- 2. RLS 정책 4개 활성 확인
--    SELECT polname, polcmd FROM pg_policy
--    WHERE polrelid = 'schedule_change_requests'::regclass;
--
-- 3. 인덱스 6개 확인
--    SELECT indexname FROM pg_indexes
--    WHERE tablename = 'schedule_change_requests';
--
-- 4. 빈 테이블 확인
--    SELECT COUNT(*) FROM schedule_change_requests; -- 기대값: 0
