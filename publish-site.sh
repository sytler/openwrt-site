#!/usr/bin/env bash
# Publish www/ (from openwrt-manager) to the PUBLIC openwrt-site repo + enable GitHub Pages.
# One-shot: sync -> push -> enable Pages API -> verify public URLs.
# Usage: bash /opt/openwrt-site/publish-site.sh
set -uo pipefail

MAIN_REPO="${MAIN_REPO:-/opt/openwrt-manager}"
SITE_REPO="${SITE_REPO:-/opt/openwrt-site}"
SITE_URL_BASE="https://sytler.github.io/openwrt-site"

fail() { echo "FAIL: $*" >&2; exit 1; }

[ -d "$SITE_REPO/.git" ] || fail "site repo missing: $SITE_REPO"
[ -d "$MAIN_REPO/www" ] || fail "main repo www/ missing: $MAIN_REPO/www — refusing to wipe site repo"
[ -f "$MAIN_REPO/www/index.html" ] || fail "www/index.html missing — refusing sync"
cd "$SITE_REPO"

# 1) Mirror current main-repo www/ -> site repo root (same as sync-site-to-ghpages.sh)
read -r MAIN_HEAD _ < <(git -C "$MAIN_REPO" rev-parse HEAD) \
  || fail "cannot resolve MAIN_REPO HEAD — refusing sync"
find . -mindepth 1 -maxdepth 1 ! -name .git ! -name publish-site.sh -exec rm -rf {} +
cp -a "$MAIN_REPO/www/." . || fail "cp www/ failed after wipe — restoring: git -C \"$SITE_REPO\" checkout ."
for f in index.html privacy.html support.html terms.html; do
  [ -f "$f" ] || fail "sync incomplete: $f missing after cp — restore with: git -C $SITE_REPO checkout ."
done
touch .nojekyll
# sanity: doc-relative links only
if grep -rnE '(src|href)="/' ./*.html >/dev/null 2>&1; then
  fail "site HTML contains site-absolute links (must be doc-relative)"
fi
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git -c user.name="DevOps Engineer" -c user.email="devops@upc0dee.local" \
    commit -m "Sync site from openwrt www/ @ ${MAIN_HEAD:0:7}"
fi

# 2) Push (retry loop handles token-grant flapping)
for i in $(seq 1 12); do
  if out=$(git push origin +HEAD:refs/heads/main 2>&1); then
    echo "PUSH OK (attempt $i): $(echo "$out" | tail -1)"
    break
  fi
  echo "push attempt $i failed: $(echo "$out" | tail -1)"
  [ "$i" -eq 12 ] && fail "push still 403 after 12 attempts — token lacks Contents RW (see UPC-3986)"
  sleep 45
done

# 3) Enable GitHub Pages (source: main /). 409/422 'already exists' treated as OK.
pages_err=$(mktemp)
if ! gh api --method POST repos/sytler/openwrt-site/pages \
      -f 'source[branch]=main' -f 'source[path]=/' 2>"$pages_err"; then
  msg=$(cat "$pages_err")
  case "$msg" in
    *409*|*"already exists"*) echo "Pages already enabled" ;;
    *) fail "Pages enable failed: $msg — ak je to 403 'not accessible', PAT potrebuje aj Administration: RW na openwrt-site" ;;
  esac
fi

# 4) Verify public URLs (build propagates with retries)
for i in $(seq 1 20); do
  ok=1
  for p in "/" "privacy.html" "support.html" "terms.html"; do
    code=$(curl -sS -m 15 -o /dev/null -w '%{http_code}' "$SITE_URL_BASE/$p" || echo 000)
    [ "$code" = "200" ] || { ok=0; echo "wait: $SITE_URL_BASE/$p -> $code"; }
  done
  [ "$ok" = 1 ] && break
  [ "$i" -eq 20 ] && fail "URLs not reachable after propagation window (Pages build?)"
  sleep 30
done

echo "ALL URLs 200:"
for p in "/" "privacy.html" "support.html" "terms.html"; do
  echo "  $SITE_URL_BASE/$p"
done