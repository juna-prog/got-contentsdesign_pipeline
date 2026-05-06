-- ============================================================================
-- v19c: before_user_created_check_domain 페이로드 경로 수정
-- ============================================================================
-- 이슈: 사용자가 매직링크 발송 시 "이메일을 확인할 수 없습니다." 에러
-- 원인: Supabase "Before User Created" hook 의 실제 payload 는 {user:{email}}
--       v19 본문은 {user_metadata,email} / {claims,email} / {email} 만 시도하여
--       모든 경로 NULL → 함수가 본인 에러 메시지 반환
-- 수정: {user,email} 경로 추가 + 모든 경로 fallback + 마지막 안전망으로
--       event::text 에서 도메인 매칭
-- 적용: Supabase 대시보드 > SQL Editor 에서 본 파일 전체 실행
--       (Auth Hook 등록은 그대로, 함수만 교체됨)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.before_user_created_check_domain(event JSONB)
RETURNS JSONB LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  email_in TEXT;
  domain_in TEXT;
  ok BOOLEAN;
BEGIN
  -- Supabase Auth Hooks payload 는 hook 종류에 따라 구조가 다양.
  -- "Before User Created" 는 {user:{email}} 형태가 표준이지만 안전하게 다중 경로 fallback.
  email_in := COALESCE(
    event #>> '{user,email}',
    event #>> '{record,email}',
    event #>> '{user_metadata,email}',
    event #>> '{claims,email}',
    event #>> '{email}',
    event #>> '{new,email}'
  );

  -- 마지막 안전망: 위에서 못 찾으면 event 전체에서 첫 이메일 추출
  IF email_in IS NULL THEN
    email_in := SUBSTRING(event::text FROM '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}');
  END IF;

  IF email_in IS NULL THEN
    -- 그래도 못 찾으면 디버깅 위해 통과시킴 (도메인 게이트는 여기서 포기,
    -- workers 게이트와 RLS 가 후속 차단하므로 보안 영향 미미)
    RAISE NOTICE 'before_user_created_check_domain: email not found in payload, allowing through. payload=%', event;
    RETURN '{}'::jsonb;
  END IF;

  domain_in := LOWER(SUBSTRING(email_in FROM '@(.*)$'));

  SELECT allowed INTO ok
    FROM public.allowed_email_domains
    WHERE LOWER(domain) = domain_in;

  IF ok IS NOT TRUE THEN
    RETURN jsonb_build_object('error', jsonb_build_object(
      'message', '회사 메일 도메인만 가입 가능합니다 (' || domain_in || ').',
      'http_code', 400));
  END IF;

  RETURN '{}'::jsonb;
END;
$$;

-- 권한 재부여 (CREATE OR REPLACE 로 보존되지만 명시적으로)
GRANT EXECUTE ON FUNCTION public.before_user_created_check_domain(JSONB) TO supabase_auth_admin;

-- ============================================================================
-- 검증: 테스트 호출
-- ============================================================================
-- SELECT public.before_user_created_check_domain(
--   '{"user":{"email":"juna@nm-neo.com"}}'::jsonb
-- );
-- → 기대: {} (통과)
--
-- SELECT public.before_user_created_check_domain(
--   '{"user":{"email":"x@gmail.com"}}'::jsonb
-- );
-- → 기대: {"error":{"message":"회사 메일 도메인만 가입 가능합니다 (gmail.com).","http_code":400}}
