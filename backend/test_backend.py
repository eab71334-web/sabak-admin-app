#!/usr/bin/env python3
"""End-to-end test: starts the server on a temp DB and walks through every feature. python3 test_backend.py"""
import hashlib, hmac, json, os, subprocess, sys, tempfile, time, urllib.request, urllib.error

PORT = 18081
KEY = "testkey123"
tmp = tempfile.mkdtemp()
env = dict(os.environ, PORT=str(PORT), ADMIN_KEY=KEY, DB_PATH=os.path.join(tmp, "t.db"), PAY_PROVIDER="test", PUBLIC_URL="http://127.0.0.1:%d" % PORT,
           STRIPE_WEBHOOK_SECRET="whsec_test", SABAK_QUIET="1", SABAK_CONFIG=os.path.join(tmp, "c.json"))
proc = subprocess.Popen([sys.executable, os.path.join(os.path.dirname(os.path.abspath(__file__)), "server.py")], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
time.sleep(1.2)
BASE = "http://127.0.0.1:%d" % PORT
fails = 0


def call(method, path, body=None, admin=False, raw=False, headers=None):
    h = {"Content-Type": "application/json"}
    if admin:
        h["X-Admin-Key"] = KEY
    if headers:
        h.update(headers)
    data = body if raw else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(BASE + path, data=data, method=method, headers=h)
    try:
        with urllib.request.urlopen(req, timeout=10) as r:
            t = r.read().decode()
            return r.status, (json.loads(t) if t.startswith("{") else t)
    except urllib.error.HTTPError as e:
        t = e.read().decode()
        return e.code, (json.loads(t) if t.startswith("{") else t)


def check(name, cond, info=""):
    global fails
    print(("PASS " if cond else "FAIL ") + name + (("  " + str(info)) if not cond else ""))
    if not cond:
        fails += 1


try:
    s, r = call("GET", "/api/config?game=hairpin")
    check("config", s == 200 and r["payments"] and len(r["packs"]) == 10, r)
    s, r = call("GET", "/admin/api/summary")
    check("admin without key rejected", s == 401)
    s, r = call("POST", "/admin/api/codes", {"coins": 5000, "gems": 20, "max_uses": 2, "count": 1, "code": "WELCOME1", "game": "hairpin"}, admin=True)
    check("create custom code", r.get("ok"), r)
    s, r = call("POST", "/admin/api/codes", {"coins": 100, "gems": 1, "max_uses": 1, "count": 3, "game": "hairpin"}, admin=True)
    gen = r.get("codes", [])
    check("create 3 generated codes", len(gen) == 3 and len(gen[0]) == 14, r)
    s, r = call("POST", "/api/redeem", {"player_id": "p1", "code": "welcome1", "game": "hairpin"})
    check("redeem (case-insensitive)", r.get("ok") and r["coins"] == 5000 and r["gems"] == 20, r)
    s, r = call("POST", "/api/redeem", {"player_id": "p1", "code": "WELCOME1", "game": "hairpin"})
    check("same player cannot reuse", r.get("error") == "used", r)
    s, r = call("POST", "/api/redeem", {"player_id": "p2", "code": "WELCOME1", "game": "hairpin"})
    check("second player ok", r.get("ok"), r)
    s, r = call("POST", "/api/redeem", {"player_id": "p3", "code": "WELCOME1", "game": "hairpin"})
    check("max uses enforced", r.get("error") == "limit", r)
    s, r = call("POST", "/api/redeem", {"player_id": "p3", "code": "NOPE-NOPE-NOPE", "game": "hairpin"})
    check("invalid code", r.get("error") == "invalid", r)
    s, r = call("POST", "/api/redeem", {"player_id": "p3", "code": gen[0], "game": "other_game"})
    check("code is bound to its game", r.get("error") == "invalid", r)
    call("POST", "/admin/api/code/toggle", {"code": gen[1], "active": False}, admin=True)
    s, r = call("POST", "/api/redeem", {"player_id": "p3", "code": gen[1], "game": "hairpin"})
    check("disabled code rejected", r.get("error") == "invalid", r)
    # brute force limit
    codes = [call("POST", "/api/redeem", {"player_id": "bf%d" % i, "code": "AAAA-BBBB-C%03d" % i, "game": "hairpin"})[0] for i in range(15)]
    check("redeem brute-force rate limit", 429 in codes, codes)

    s, r = call("POST", "/admin/api/events", {"game": "hairpin", "title": "Weekend boost", "title_ar": "تعزيز نهاية الأسبوع", "body": "Free gift", "reward_coins": 2000, "reward_gems": 5, "days": 3}, admin=True)
    check("create event", r.get("ok"), r)
    s, r = call("GET", "/api/events?game=hairpin&player_id=p1")
    ev = r["events"][0]
    check("event visible, not claimed", len(r["events"]) == 1 and not ev["claimed"], r)
    s, r = call("POST", "/api/event/claim", {"player_id": "p1", "event_id": ev["id"]})
    check("event claim", r.get("ok") and r["coins"] == 2000, r)
    s, r = call("POST", "/api/event/claim", {"player_id": "p1", "event_id": ev["id"]})
    check("event claim only once", r.get("error") == "used", r)

    # payments (test provider)
    s, r = call("POST", "/api/pay/create", {"player_id": "p1", "pack_id": "g450", "game": "hairpin"})
    oid = r.get("order_id")
    check("create order", r.get("ok") and "/pay/test/" in r["checkout_url"], r)
    s, r = call("POST", "/api/pay/claim", {"player_id": "p1", "order_id": oid})
    check("claim before payment refused", r.get("error") == "pending", r)
    s, r = call("POST", "/api/pay/claim", {"player_id": "pX", "order_id": oid})
    check("other player cannot claim my order", r.get("error") == "unknown", r)
    s, r = call("POST", "/api/pay/create", {"player_id": "p1", "pack_id": "free_money"})
    check("unknown pack refused (price is server side)", not r.get("ok"), r)
    s, t = call("POST", "/pay/test/" + oid, b"", raw=True)
    s, r = call("GET", "/api/pay/status?order_id=%s&player_id=p1" % oid)
    check("status paid", r.get("status") == "paid", r)
    s, r = call("POST", "/api/pay/claim", {"player_id": "p1", "order_id": oid})
    check("claim grants 450 gems", r.get("ok") and r["kind"] == "gems" and r["amount"] == 450, r)
    s, r = call("POST", "/api/pay/claim", {"player_id": "p1", "order_id": oid})
    check("cannot claim twice", not r.get("ok") and r.get("error") == "granted", r)
    # stripe webhook signature
    payload = json.dumps({"type": "checkout.session.completed", "data": {"object": {"payment_status": "paid", "client_reference_id": "ord_none"}}}).encode()
    s, r = call("POST", "/api/pay/webhook/stripe", payload, raw=True, headers={"Stripe-Signature": "t=1,v1=bad"})
    check("stripe webhook bad signature rejected", s == 400, r)
    t = str(int(time.time()))
    sig = hmac.new(b"whsec_test", (t + ".").encode() + payload, hashlib.sha256).hexdigest()
    s, r = call("POST", "/api/pay/webhook/stripe", payload, raw=True, headers={"Stripe-Signature": "t=%s,v1=%s" % (t, sig)})
    check("stripe webhook valid signature accepted", s == 200, r)

    # reports
    for i in range(3):
        call("POST", "/api/report", {"game": "hairpin", "version": "1.0", "player_id": "p%d" % i, "kind": "error", "message": "Null instance in car.gd:88", "stack": "car.gd:88", "platform": "Android"})
    call("POST", "/api/report", {"game": "hairpin", "kind": "crash", "message": "Unclean exit", "player_id": "p1"})
    s, r = call("GET", "/admin/api/reports?game=hairpin", admin=True)
    check("reports grouped", r["top"][0]["n"] == 3 and len(r["reports"]) == 4, r)
    s, r = call("GET", "/admin/api/summary?game=hairpin", admin=True)
    check("summary", r["players"] >= 3 and r["errors_24h"] == 4 and r["test_orders"] == 1 and r["codes_active"] >= 2, r)
    s, r = call("GET", "/admin/api/payments", admin=True)
    check("payments list", len(r["payments"]) == 1 and r["payments"][0]["status"] == "granted", r)
    s, r = call("GET", "/admin/api/codes?game=hairpin", admin=True)
    check("codes list with usage", any(c["code"] == "WELCOME1" and c["used"] == 2 for c in r["codes"]), r)
    s, r = call("GET", "/admin/api/spenders", admin=True)
    check("spenders ignore test payments", r["spenders"] == [], r)
finally:
    proc.terminate()
print("\nFAILED: %d" % fails if fails else "\nALL PASSED")
sys.exit(1 if fails else 0)
