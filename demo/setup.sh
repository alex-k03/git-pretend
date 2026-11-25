#!/bin/sh
# Creates a small, realistic fixture repository in /tmp/api
# and a matching Starship config for recording demo/demo.gif with VHS.
set -eu

demo_dir=/tmp/api
starship_cfg=/tmp/git-pretend-starship.toml

rm -rf "$demo_dir"
mkdir -p "$demo_dir/src" "$demo_dir/tests"
cd "$demo_dir"

export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="Alex"
export GIT_AUTHOR_EMAIL="alex@example.com"
export GIT_COMMITTER_NAME="Alex"
export GIT_COMMITTER_EMAIL="alex@example.com"

git init -q -b main

: >tests/__init__.py

cat <<'EOF' >src/server.py
# TODO: add rate limiting

def handle_request(user_id: str, path: str) -> dict:
    return {"status": 200, "path": path}
EOF

cat <<'EOF' >tests/test_server.py
import unittest
from src.server import handle_request


class TestServer(unittest.TestCase):
    def test_handle_request(self):
        res = handle_request("u1", "/items")
        self.assertEqual(res["status"], 200)
EOF

git add -A
git commit -q -m "Initial request handler"

git switch -q -c feat/rate-limit

cat <<'EOF' >src/limiter.py
class TokenBucket:
    def __init__(self, capacity: int):
        self.capacity = capacity
        self.counts: dict[str, int] = {}

    def allow(self, key: str) -> bool:
        used = self.counts.get(key, 0)
        if used >= self.capacity:
            return False
        self.counts[key] = used + 1
        return True
EOF

git add -A
git commit -q -m "Add per-user token bucket"

cat <<'EOF' >src/server.py
from src.limiter import TokenBucket

limiter = TokenBucket(capacity=60)


def handle_request(user_id: str, path: str) -> dict:
    if not limiter.allow(user_id):
        return {"status": 429, "error": "rate limited"}
    return {"status": 200, "user": user_id}
EOF

git add -A
git commit -q -m "Enforce rate limit in request handler"

cat <<'EOF' >tests/test_server.py
import unittest
from src.limiter import TokenBucket
from src.server import handle_request


class TestServer(unittest.TestCase):
    def test_handle_request(self):
        res = handle_request("u1", "/items")
        self.assertEqual(res["status"], 200)

    def test_rate_limit_blocks_excess(self):
        bucket = TokenBucket(capacity=1)
        self.assertTrue(bucket.allow("u1"))
        self.assertFalse(bucket.allow("u1"))
EOF

git add -A
git commit -q -m "Add rate limiter unit tests"

cat <<'EOF' >"$starship_cfg"
add_newline = false
format = "$directory$git_branch${custom.pretend}${custom.git_commit}$git_status$character"

[directory]
truncation_length = 1
truncate_to_repo = true
style = "bold blue"

[git_branch]
only_attached = true
format = "[$branch]($style) "
style = "green"

[git_status]
format = "([$all_status$ahead_behind]($style) )"
style = "red"

[custom.pretend]
require_repo = true
when = '[ -f "$(git rev-parse --absolute-git-dir 2>/dev/null)/pretend/state" ]'
command = "git pretend status --short"
shell = ["sh"]
format = "[$output](green) [pretend](bold purple) "

[custom.git_commit]
require_repo = true
when = '! git symbolic-ref -q HEAD >/dev/null && [ ! -f "$(git rev-parse --absolute-git-dir)/pretend/state" ]'
command = "git rev-parse --short=7 HEAD"
shell = ["sh"]
format = "[$output](green) "

[character]
success_symbol = "[❯](bold green)"
error_symbol = "[❯](bold red)"
EOF
