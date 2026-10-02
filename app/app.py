"""
Staff Portal: a deliberately small Flask web application used as a log source.

Security-relevant events (logins, logouts, access denials, admin access) are
written as one JSON object per line to AUDIT_LOG_PATH. The Azure Monitor Agent
ships that file to the WebAppAudit_CL table in Microsoft Sentinel.
Operational logs go to stdout, which Docker forwards to syslog (container logs).

Secrets (session key, user passwords) come from environment variables that are
generated on the host by the setup script. Nothing secret lives in this code.
"""
import json
import logging
import os
import secrets
import sys
from datetime import datetime, timezone
from functools import wraps

from flask import Flask, abort, redirect, render_template_string, request, session, url_for
from werkzeug.security import check_password_hash, generate_password_hash

AUDIT_LOG_PATH = os.environ.get("AUDIT_LOG_PATH", "/var/log/webapp/audit.log")


def required_env(name):
    value = os.environ.get(name)
    if not value:
        sys.exit(f"Missing required environment variable: {name}")
    return value


app = Flask(__name__)
app.config.update(
    SECRET_KEY=required_env("FLASK_SECRET_KEY"),
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE="Lax",
    MAX_CONTENT_LENGTH=16 * 1024,
)

# Passwords are hashed in memory at start-up; plaintext is never stored or logged.
USERS = {
    "admin": {"hash": generate_password_hash(required_env("APP_ADMIN_PASSWORD")), "role": "admin"},
    "staff": {"hash": generate_password_hash(required_env("APP_STAFF_PASSWORD")), "role": "staff"},
}
# Used for unknown usernames so response time does not reveal which users exist.
DUMMY_HASH = generate_password_hash(secrets.token_urlsafe(16))

# Operational log -> stdout -> Docker syslog driver -> Syslog table (facility local0)
logging.basicConfig(stream=sys.stdout, level=logging.INFO,
                    format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("staff-portal")

# Security audit log -> JSON lines file -> WebAppAudit_CL table
audit_logger = logging.getLogger("audit")
audit_handler = logging.FileHandler(AUDIT_LOG_PATH)
audit_handler.setFormatter(logging.Formatter("%(message)s"))
audit_logger.addHandler(audit_handler)
audit_logger.setLevel(logging.INFO)
audit_logger.propagate = False


def client_ip():
    # Nginx sets X-Real-IP. The app only listens on 127.0.0.1, so the header
    # can only come from the local reverse proxy.
    return request.headers.get("X-Real-IP", request.remote_addr)


def clip(value, limit=64):
    return (value or "")[:limit]


def audit(event, outcome, user=None):
    record = {
        "timestamp": datetime.now(timezone.utc).isoformat(timespec="milliseconds").replace("+00:00", "Z"),
        "app": "staff-portal",
        "event": event,
        "outcome": outcome,
        "user": clip(user),
        "src_ip": client_ip(),
        "method": request.method,
        "path": clip(request.path, 256),
        "user_agent": clip(request.headers.get("User-Agent"), 256),
    }
    # json.dumps escapes control characters, which prevents log injection.
    audit_logger.info(json.dumps(record))


def login_required(view):
    @wraps(view)
    def wrapper(*args, **kwargs):
        if "user" not in session:
            audit("access_denied", "failure")
            return redirect(url_for("login"))
        return view(*args, **kwargs)
    return wrapper


PAGE = """<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Staff Portal</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
 body{font-family:Segoe UI,Arial,sans-serif;background:#f3f5f9;color:#1f2937;margin:0}
 header{background:#0f2a4a;color:#fff;padding:14px 24px}
 main{max-width:480px;margin:40px auto;background:#fff;padding:28px;border-radius:10px;box-shadow:0 2px 8px #0001}
 input{width:100%;padding:9px;margin:6px 0 14px;border:1px solid #c9d2de;border-radius:6px;box-sizing:border-box}
 button{background:#0b5cad;color:#fff;border:0;padding:10px 18px;border-radius:6px;cursor:pointer}
 .error{color:#b91c1c} a{color:#0b5cad}
</style></head>
<body><header><strong>Staff Portal</strong></header><main>{{ body|safe }}</main></body></html>"""


def page(body_template, **context):
    # Inner templates are rendered with autoescaping, then placed in the layout.
    return render_template_string(PAGE, body=render_template_string(body_template, **context))


@app.get("/")
def index():
    return page("<h2>Welcome</h2><p>Internal staff portal.</p><p><a href='{{ url_for('login') }}'>Sign in</a></p>")


@app.route("/login", methods=["GET", "POST"])
def login():
    error = None
    if request.method == "POST":
        username = clip(request.form.get("username", ""))
        password = request.form.get("password", "")
        user = USERS.get(username)
        if user and check_password_hash(user["hash"], password):
            session.clear()
            session["user"] = username
            session["role"] = user["role"]
            audit("login_success", "success", username)
            log.info("Login succeeded for user=%s", username)
            return redirect(url_for("dashboard"))
        if not user:
            check_password_hash(DUMMY_HASH, password)
        audit("login_failed", "failure", username)
        log.warning("Login failed for user=%s from %s", username, client_ip())
        error = "Invalid username or password."
    body = """<h2>Sign in</h2>
    {% if error %}<p class="error">{{ error }}</p>{% endif %}
    <form method="post">
      <label>Username</label><input name="username" autocomplete="username" required>
      <label>Password</label><input name="password" type="password" autocomplete="current-password" required>
      <button type="submit">Sign in</button>
    </form>"""
    return page(body, error=error), (401 if error else 200)


@app.get("/dashboard")
@login_required
def dashboard():
    return page("<h2>Dashboard</h2><p>Signed in as <strong>{{ user }}</strong> ({{ role }}).</p>"
                "<p><a href='{{ url_for('admin') }}'>Admin area</a> | <a href='{{ url_for('logout') }}'>Sign out</a></p>",
                user=session["user"], role=session["role"])


@app.get("/admin")
@login_required
def admin():
    if session.get("role") != "admin":
        audit("access_denied", "failure", session.get("user"))
        abort(403)
    audit("admin_page_access", "success", session.get("user"))
    return page("<h2>Admin area</h2><p>Restricted administrative functions.</p>"
                "<p><a href='{{ url_for('dashboard') }}'>Back</a></p>")


@app.get("/logout")
def logout():
    user = session.get("user")
    session.clear()
    if user:
        audit("logout", "success", user)
    return redirect(url_for("index"))


@app.get("/health")
def health():
    return "ok"
