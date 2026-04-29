"""JIRA REST API 직접 operator (Phase 6 P2).

MCP 한계 3종 (reporter / Epic Name / Epic Link customfield) 우회 목적.

Auth: Basic Auth — env 우선, 없으면 .jira_creds.json fallback
  env: JIRA_USER, JIRA_PASS (또는 PAT 를 JIRA_PASS 로 사용)
  file: <operator_dir>/.jira_creds.json  {"user":"...","pass":"..."}

JIRA Custom Field 매핑 (env 로 override 가능):
  JIRA_EPIC_NAME_FIELD = customfield_13102   (Epic 생성 시 Epic Name)
  JIRA_EPIC_LINK_FIELD = customfield_10008   (Sub-Task 의 Epic Link)

지원 operation_type:
  - create_epic           → POST issue (Epic) + Epic Name 자동 주입 + reporter 후처리 + contents 백필
  - create_subtask        → POST issue (Sub-Task / Task) + 모드별 분기
                            * parent_task 모드: payload.fields.parent.key 그대로
                            * epic_link 모드: 생성 후 PUT customfield_10008 = target_epic_key

CLI:
  python jira_rest_operator.py                      # pending 전체 처리
  python jira_rest_operator.py --dry-run            # 실제 호출 없이 plan 출력
  python jira_rest_operator.py --log-id 5           # 특정 로그만 처리
  python jira_rest_operator.py --limit 1            # 1건만 처리
"""
import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

# ============================================================================
# 설정
# ============================================================================

SUPABASE_URL = "https://huegoxqcoqealhhlrkww.supabase.co"
SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Imh1ZWdveHFjb3FlYWxoaGxya3d3Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUxMDMwOTUsImV4cCI6MjA5MDY3OTA5NX0.1UbszKIibvon_6zRUe1-M4ukCxpu7iytC3dGWhi-EjQ"

JIRA_BASE = "https://jira.nmn.io"
JIRA_EPIC_NAME_FIELD = os.environ.get("JIRA_EPIC_NAME_FIELD", "customfield_13102")
JIRA_EPIC_LINK_FIELD = os.environ.get("JIRA_EPIC_LINK_FIELD", "customfield_13101")

OPERATOR_DIR = Path(__file__).resolve().parent
CREDS_FILE = OPERATOR_DIR / ".jira_creds.json"

sys.stdout.reconfigure(encoding="utf-8")


# ============================================================================
# 자격 증명 로드 (env > file)
# ============================================================================

def load_jira_creds(allow_missing=False):
    user = os.environ.get("JIRA_USER")
    password = os.environ.get("JIRA_PASS")
    if user and password:
        return {"user": user, "pass": password, "source": "env"}
    if CREDS_FILE.exists():
        d = json.loads(CREDS_FILE.read_text(encoding="utf-8"))
        if d.get("user") and d.get("pass"):
            return {"user": d["user"], "pass": d["pass"], "source": str(CREDS_FILE)}
    if allow_missing:
        return {"user": "(unset)", "pass": "(unset)", "source": "missing"}
    raise SystemExit(
        "JIRA 자격 증명 미설정. 다음 중 하나로 제공:\n"
        "  1) env: JIRA_USER=... JIRA_PASS=...\n"
        f"  2) file: {CREDS_FILE} (JSON: {{\"user\":..., \"pass\":...}})\n"
    )


# ============================================================================
# HTTP 헬퍼
# ============================================================================

def supabase_request(method, path, body=None):
    headers = {"apikey": SUPABASE_ANON_KEY, "Authorization": f"Bearer {SUPABASE_ANON_KEY}"}
    if body is not None:
        headers["Content-Type"] = "application/json"
        headers["Prefer"] = "return=representation"
    req = urllib.request.Request(
        SUPABASE_URL + "/rest/v1/" + path,
        headers=headers,
        method=method,
        data=json.dumps(body).encode("utf-8") if body is not None else None,
    )
    with urllib.request.urlopen(req) as r:
        txt = r.read().decode("utf-8")
        return json.loads(txt) if txt else None


def jira_request(creds, method, path, body=None):
    auth_str = f"{creds['user']}:{creds['pass']}"
    auth_b64 = base64.b64encode(auth_str.encode("utf-8")).decode("ascii")
    headers = {"Authorization": "Basic " + auth_b64, "Content-Type": "application/json", "Accept": "application/json"}
    req = urllib.request.Request(
        JIRA_BASE + path,
        headers=headers,
        method=method,
        data=json.dumps(body).encode("utf-8") if body is not None else None,
    )
    try:
        with urllib.request.urlopen(req) as r:
            txt = r.read().decode("utf-8")
            return json.loads(txt) if txt else None
    except urllib.error.HTTPError as e:
        body_txt = e.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"JIRA {method} {path} → HTTP {e.code}: {body_txt}")


# ============================================================================
# Operation 핸들러
# ============================================================================

def handle_create_epic(creds, log, dry_run):
    """payload.fields 에 Epic Name 자동 주입 후 POST."""
    payload = log["payload"]
    fields = dict(payload["fields"])
    summary = fields["summary"]

    fields[JIRA_EPIC_NAME_FIELD] = summary  # Epic Name = summary 기본
    fields["issuetype"] = {"name": "Epic"}

    # Epic assignee 미설정 시 juna 기본값 (JIRA 자동 배정 회피)
    if not (fields.get("assignee") or {}).get("name"):
        fields["assignee"] = {"name": "juna"}

    desired_reporter = (fields.get("reporter") or {}).get("name")
    fields.pop("reporter", None)  # 인증 사용자로 일단 생성, 후처리 PUT

    create_body = {"fields": fields}
    if dry_run:
        print(f"  [DRY] POST /rest/api/2/issue (Epic) summary={summary!r}")
        print(f"        {JIRA_EPIC_NAME_FIELD}={summary!r}")
        print(f"        assignee={fields['assignee']['name']}")
        return {"key": "DRY-EPIC-0", "url": "https://jira.nmn.io/browse/DRY-EPIC-0"}

    res = jira_request(creds, "POST", "/rest/api/2/issue", create_body)
    key = res["key"]
    url = f"{JIRA_BASE}/browse/{key}"
    print(f"  Epic 생성: {key}")

    if desired_reporter and desired_reporter != creds["user"]:
        try:
            jira_request(creds, "PUT", f"/rest/api/2/issue/{key}", {"fields": {"reporter": {"name": desired_reporter}}})
            print(f"  reporter 변경: → {desired_reporter}")
        except RuntimeError as e:
            print(f"  reporter 변경 실패 (권한 부족 가능): {e}")

    return {"key": key, "url": url}


def handle_create_subtask(creds, log, dry_run):
    """parent_task / epic_link 두 모드 처리."""
    payload = log["payload"]
    mode = payload.get("_subtask_mode", "parent_task")
    target_epic = log.get("target_epic_key")
    fields = dict(payload["fields"])

    desired_reporter = (fields.get("reporter") or {}).get("name")
    fields.pop("reporter", None)

    create_body = {"fields": fields}
    if dry_run:
        print(f"  [DRY] POST /rest/api/2/issue mode={mode} type={fields['issuetype']['name']}")
        if mode == "parent_task":
            print(f"        parent.key={fields.get('parent', {}).get('key')}")
        elif mode == "epic_link":
            print(f"        + 후처리 PUT {JIRA_EPIC_LINK_FIELD}={target_epic}")
        return {"key": "DRY-TASK-0", "url": "https://jira.nmn.io/browse/DRY-TASK-0"}

    res = jira_request(creds, "POST", "/rest/api/2/issue", create_body)
    key = res["key"]
    url = f"{JIRA_BASE}/browse/{key}"
    print(f"  생성: {key} ({mode})")

    if mode == "epic_link":
        if not target_epic:
            raise RuntimeError("epic_link 모드인데 target_epic_key 없음")
        jira_request(creds, "PUT", f"/rest/api/2/issue/{key}", {"fields": {JIRA_EPIC_LINK_FIELD: target_epic}})
        print(f"  Epic Link: {target_epic} ({JIRA_EPIC_LINK_FIELD})")

    if desired_reporter and desired_reporter != creds["user"]:
        try:
            jira_request(creds, "PUT", f"/rest/api/2/issue/{key}", {"fields": {"reporter": {"name": desired_reporter}}})
            print(f"  reporter 변경: → {desired_reporter}")
        except RuntimeError as e:
            print(f"  reporter 변경 실패 (권한 부족 가능): {e}")

    return {"key": key, "url": url}


# ============================================================================
# 백필
# ============================================================================

def backfill_success(log, jira_key, jira_url, dry_run):
    if dry_run:
        print(f"  [DRY] log #{log['id']} → done / result_key={jira_key}")
        return
    now = datetime.now(timezone.utc).isoformat()
    supabase_request("PATCH", f"jira_creation_log?id=eq.{log['id']}", {
        "status": "done",
        "result_key": jira_key,
        "result_url": jira_url,
        "executed_at": now,
        "executed_by": "rest_operator",
    })
    op = log["operation_type"]
    if op == "create_epic":
        supabase_request("PATCH", f"contents?id=eq.{log['content_id']}", {
            "jira_epic_key": jira_key,
            "jira_epic_url": jira_url,
        })
        print(f"  contents #{log['content_id']} jira_epic_key 백필")
    elif op == "create_subtask":
        if log.get("task_id"):
            supabase_request("PATCH", f"tasks?id=eq.{log['task_id']}", {"jira_url": jira_url})
            print(f"  tasks #{log['task_id']} jira_url 백필")


def backfill_failure(log, error_msg, dry_run):
    if dry_run:
        print(f"  [DRY] log #{log['id']} → failed / error={error_msg!r}")
        return
    now = datetime.now(timezone.utc).isoformat()
    supabase_request("PATCH", f"jira_creation_log?id=eq.{log['id']}", {
        "status": "failed",
        "error_message": error_msg[:2000],
        "executed_at": now,
        "executed_by": "rest_operator",
    })


# ============================================================================
# 메인 루프
# ============================================================================

def fetch_pending(log_id=None, limit=None):
    if log_id is not None:
        return supabase_request("GET", f"jira_creation_log?id=eq.{log_id}&status=eq.pending&select=id,operation_type,content_id,task_id,target_epic_key,payload,template_key")
    q = "jira_creation_log?status=eq.pending&select=id,operation_type,content_id,task_id,target_epic_key,payload,template_key&order=created_at.asc"
    if limit:
        q += f"&limit={limit}"
    return supabase_request("GET", q)


def process_log(creds, log, dry_run):
    print(f"\nlog #{log['id']} op={log['operation_type']} content={log.get('content_id')} task={log.get('task_id')}")
    op = log["operation_type"]
    try:
        if op == "create_epic":
            r = handle_create_epic(creds, log, dry_run)
        elif op == "create_subtask":
            r = handle_create_subtask(creds, log, dry_run)
        else:
            raise RuntimeError(f"미지원 operation_type: {op}")
        backfill_success(log, r["key"], r["url"], dry_run)
        return True
    except (RuntimeError, urllib.error.URLError) as e:
        msg = str(e)
        print(f"  [FAIL] {msg}")
        backfill_failure(log, msg, dry_run)
        return False


def main():
    p = argparse.ArgumentParser(description="JIRA REST direct operator")
    p.add_argument("--dry-run", action="store_true", help="실제 호출 없이 plan 출력")
    p.add_argument("--log-id", type=int, help="특정 log id 만 처리")
    p.add_argument("--limit", type=int, help="최대 처리 건수")
    args = p.parse_args()

    creds = load_jira_creds(allow_missing=args.dry_run)
    print(f"JIRA 자격 증명: user={creds['user']} (source={creds['source']})")
    print(f"Custom fields: epic_name={JIRA_EPIC_NAME_FIELD}, epic_link={JIRA_EPIC_LINK_FIELD}")
    if args.dry_run:
        print("** DRY RUN — 실제 변경 없음 **")

    pending = fetch_pending(log_id=args.log_id, limit=args.limit)
    if not pending:
        print("\npending 큐 비어있음.")
        return

    print(f"\npending {len(pending)} 건 처리 시작")
    ok = 0
    fail = 0
    for log in pending:
        if process_log(creds, log, args.dry_run):
            ok += 1
        else:
            fail += 1

    print(f"\n=== 완료: 성공 {ok} / 실패 {fail} ===")


if __name__ == "__main__":
    main()
