# 파이프라인 트래커 인증 + 관리자 운영 가이드 (Phase 7)

> 콘텐츠기획팀 공용 웹앱. 회사 메일 매직링크 인증 + invite-only 화이트리스트 + 관리자 페이지.

## 1. 한눈에 보기

```
[일반 워커]                          [관리자 (is_team_lead)]
회사 메일 입력                          관리자 페이지 ⚙️
  ↓                                       ↓
매직링크 수신                            ┌─────────────────────┐
  ↓                                      │ 사용자 / 워커 / 활동 │
링크 클릭 → 자동 로그인                   │ 로그 / Quick Actions│
  ↓                                      └─────────────────────┘
파이프라인 / 빌드 스펙 / 간트 / ...
```

## 2. 인증 흐름

1. SignInScreen 에서 회사 메일 입력 → `signInWithOtp({email, shouldCreateUser:false})`
2. Supabase 가 메일 발송 (미등록자 = 메일 미발송)
3. 사용자가 메일에서 링크 클릭 → `?token_hash=...` 콜백 처리 → SIGNED_IN
4. App 이 `workers.email = auth.email()` 매핑 조회
5. 미존재 / `is_active=false` → `signOut()` + 안내
6. 첫 로그인이면 `workers.auth_user_id` 백필 + `last_login_at` 갱신
7. 정상 → `user state` 세팅 → 평소 화면 진입
8. 모든 PostgREST 호출이 `Authorization: Bearer <session.access_token>` 로 동작 → RLS 가 권한 적용

## 3. 게이트 4단

| 단 | 게이트 | 통과 조건 |
|---|---|---|
| 1 | `shouldCreateUser:false` | 클라이언트 설정. 기존 가입자만 OTP 메일 발송 |
| 2 | Auth Hook 도메인 | `@nm-neo.com` 만 허용 (allowed_email_domains 테이블) |
| 3 | workers.is_active | `false` 면 로그인 후 즉시 signOut + 안내 |
| 4 | RLS `is_admin()` | 관리자 페이지 / audit_log SELECT / 마스터 테이블 변경 |

## 4. 부트스트랩 (최초 1회)

### 4-A. 우회 모드 (2026-05-04 채택) - 본인 1명만 활성

본인 (juna) 만 채운 채로 v19 적용 + UI 빌드 + 점진적으로 다른 워커 풀어주기.

#### Step 1. v19 적용
- `migrations/v19_auth_audit.sql` 의 § 5 가 이미 우회 모드로 작성되어 있음
  - 본인 email 만 채워 둠
  - 다른 활성 워커는 `is_active=FALSE` 로 임시 전환
- Supabase 대시보드 > SQL Editor 에서 `v19_auth_audit.sql` 전체 실행

#### Step 2. Auth Hook 등록
- 대시보드 > Auth > Hooks > "Before User Created" → `before_user_created_check_domain`

#### Step 3. UI 배포
- index.html 변경분 commit + push → Vercel 자동 배포

#### Step 4. 본인 첫 로그인
- SignInScreen 에서 `juna@nm-neo.com` 입력 → 매직링크 클릭 → 관리자 페이지 노출

#### Step 5. 점진 풀이 (워커별)
관리자 페이지 > 사용자 탭 에서 워커 1명씩:
1. **email 입력** (회사 메일 회신 받은 후)
2. **활성 토글 ON** (`is_active=TRUE` 로 복구)
3. 본인에게 사이트 주소 + 회사 메일 입력 안내
4. 본인 첫 로그인 시 `auth_user_id` 자동 백필

> 풀어주기 전에는 해당 워커가 SignInScreen 진입해도 `is_active=false` 라 즉시 signOut.

### 4-B. 정상 모드 - 28명 일괄

이메일 28명 모두 수집된 시점에 1회 실행.

#### Step 1. 28명 이메일 수집 (사용자 수동)
- NAVER WORKS or 사내 메일로 본인 메일 회신 받기
- jira_account_id (예: `juna`) 와 prefix 가 다를 수 있어 본인 확인 필수

#### Step 2. v19_email_template.sql 채우기
- `migrations/v19_email_template.sql` 의 `TODO@nm-neo.com` 28건을 실제 메일로 치환

#### Step 3. 일괄 실행 (Supabase SQL Editor)
```sql
-- 1) 28건 UPDATE 실행
\i v19_email_template.sql
-- 2) 임시 비활성 풀이
UPDATE workers SET is_active = TRUE WHERE email NOT LIKE 'inactive_%@nm-neo.local';
-- 3) 검증
SELECT COUNT(*) FROM workers WHERE is_active = TRUE AND email IS NOT NULL; -- 28
```

### Step 4. Auth Hook 등록
- Supabase 대시보드 > Auth > Hooks > "Before User Created" 토글 ON
- 함수 선택: `before_user_created_check_domain`

### Step 5. (선택) Magic Link 메일 본문 한글화
- Supabase 대시보드 > Auth > Email Templates > Magic Link
- 한국어 안내 + 회사 로고 등 (선택)

### Step 6. 본인 첫 로그인
- 배포된 페이지 (Vercel) 진입 → SignInScreen 이 자동 노출
- `juna@nm-neo.com` 입력 → 회사 메일 수신 → 링크 클릭
- 자동으로 `workers.auth_user_id` 백필 + 관리자 페이지 노출 (`⚙️ 관리자` 버튼)

### Step 7. 팀원 1명 시범
- 관리자 페이지 > 사용자 탭 > 신규 초대 (또는 기존 워커의 email 확인)
- 해당 팀원에게 "사이트 주소 + 회사 메일 입력" 안내
- 본인 첫 로그인 검증 후 점진 안내

## 5. 관리자 페이지 (`⚙️ 관리자`)

### 5.1 사용자 탭
- 워커 목록 (이름 / 이메일 / 파트 / 권한 / 활성 / 마지막 접속 / `auth_user_id` 매핑 여부)
- 신규 초대: 이름 / 파트 / 이메일 → INSERT workers (auth_user_id NULL) → 본인이 SignInScreen 에서 OTP 발송하면 자동 매핑
- 잠금 / 잠금 해제: `is_active` 토글 (audit_log 기록)
- 이메일 변경: `auth_user_id` NULL 로 리셋 → 다음 로그인 시 재매핑

### 5.2 워커 상세 탭 (Track 3 모달 흡수)
- jira_account_id / 권한 (is_part_lead / is_team_lead) / 파트 변경
- 비밀번호 개념 없음 (매직링크라 비번 무관)

### 5.3 활동 로그 탭
- audit_log 시간 역순
- 필터: actor / action_type / 날짜 범위 / target_table
- payload JSON 펼쳐 보기

### 5.4 Quick Actions 탭
- CSV 다운로드 (= 기존 exportCSV)
- 시트 import (= 기존 ImportModal)
- JIRA 동기화 (= 기존 JiraSyncModal)
- 일정 일괄 수정 (TaskSheet 점프)

### 5.5 확장 슬롯 (Phase 2~4 placeholder)
- 공지 / 채널 / 게시판 / 권한 그룹 / 파일 업로드

## 6. 운영 시나리오

### 신규 입사자 추가
1. 관리자 페이지 > 사용자 탭 > **신규 초대**
2. 이름 / 파트 / 회사 메일 입력
3. 본인에게 사이트 주소 + 안내 (`회사 메일 입력만 하면 매직링크 발송됩니다`)
4. 본인이 첫 로그인하면 `auth_user_id` 자동 백필

### 퇴사자 처리
1. 관리자 페이지 > 사용자 탭 > 해당 워커 > **활성 토글 OFF**
2. `is_active = false` → 즉시 인증 거부 + 데이터 접근 차단
3. workers 행은 보존 (task_assignees CASCADE 회피)

### 권한 부여 / 회수
1. 관리자 페이지 > 워커 상세 > `is_part_lead` / `is_team_lead` 토글
2. audit_log 에 자동 기록

### 도메인 추가 (관계사 등)
- Supabase SQL Editor:
  ```sql
  INSERT INTO allowed_email_domains(domain, note) VALUES ('netmarble.com', '관계사');
  ```
- 또는 관리자 페이지에서 추후 UI 노출 (Phase 2)

## 7. 보안 노트

- **anon key 노출**: index.html 에 그대로 노출되지만 v19 적용 후 anon 으로는 어떤 테이블도 SELECT 불가 (`current_worker_id() IS NOT NULL` 게이트). anon key 는 "로그인 폼만 동작시키는 키" 가 됨
- **세션 토큰**: localStorage 에 `sb-...-auth-token` 저장. XSS 시 도난 가능 - 일반 SPA 와 동일한 위험 수준
- **매직링크 토큰**: Supabase 기본 1시간 유효 (대시보드에서 조정 가능)
- **audit_log 불변성**: UPDATE / DELETE 정책 미부여 → 사실상 INSERT-only
- **부트스트랩 데드락 회피**: workers.auth_user_id 가 nullable 이라 v19 직후 본인이 첫 로그인하면 정상 매핑

## 8. 트러블슈팅

| 증상 | 원인 후보 | 조치 |
|---|---|---|
| 매직링크 메일 미수신 | shouldCreateUser:false + 미등록 / 도메인 불일치 / 스팸함 | workers.email 확인 / allowed_email_domains 확인 / 스팸함 확인 |
| 링크 클릭해도 로그인 실패 | 토큰 만료 (1시간 초과) / 다른 브라우저에서 클릭 | SignInScreen 에서 재발송 |
| 로그인 후 즉시 로그아웃 | workers 미존재 or is_active=false | 관리자 페이지에서 워커/활성 확인 |
| PostgREST 401 (데이터 안 보임) | 세션 만료 | 페이지 새로고침 → 자동 refresh |
| 관리자 버튼 미노출 | is_team_lead=false | 관리자에게 권한 요청 |

## 9. 운영자 (operator) 처리

JIRA 자동 처리 등 백엔드 운영자는 본인 user 세션 없이 service_role 키 사용 권장:
- `operator/jira_rest_operator.py` 는 PostgREST 가 아닌 JIRA REST 만 호출 → 영향 없음
- Supabase 데이터를 직접 PATCH 하는 운영자 스크립트가 추가될 경우 service_role 사용 (RLS 우회). 단 키 노출 금지 - 환경변수만.

## 10. 향후 확장 (Phase 2~)

- **Phase 2**: 공지 / 게시판 (notices 테이블, 한 페이지)
- **Phase 3**: 채널 / 메시지 (Realtime), 멘션, 알림
- **Phase 4**: 파일 첨부 (Storage), PWA, 푸시
- **장기**: 회사 SSO, 부서별 가시성 그룹

각 Phase 는 별도 plan + migration + UI commit 단위로 진입.
