#!/usr/bin/env bash
# Funnel publish for the legal site (path B of UPC-3986 decision package) —
# works WITHOUT any GitHub PAT: exposes the local nginx mirror through
# Tailscale Funnel so App Store Connect / Play can reach privacy/support.
#
# Prereqs (checked by this script):
#   1. nginx :8443 serving /opt/openwrt-site (mirror of openwrt-manager www/)
#   2. tailscale CLI present (tested with 1.98.8)
#   3. ONE human click to enable Serve on the tailnet (script prints the link)
#
# Usage: bash /opt/openwrt-site/publish-funnel.sh
# Idempotent: safe to re-run after the enable click; leave it registered.
set -uo pipefail

LOCAL_BASE="http://127.0.0.1:8443/"
PAGES=("/" "privacy.html" "support.html" "terms.html")

fail() { echo "FAIL: $*" >&2; exit 1; }

# 0) tailscale present?
command -v tailscale >/dev/null || fail "tailscale CLI not found"

# 1) Local mirror must be healthy first — funnel would only expose 404s otherwise
for p in "${PAGES[@]}"; do
  code=$(curl -sS -m 10 -o /dev/null -w '%{http_code}' "$LOCAL_BASE$p" || echo 000)
  [ "$code" = "200" ] || fail "local mirror $LOCAL_BASE$p -> $code (nginx :8443 down or content missing) — fix hosting first"
done
echo "local mirror OK: ${PAGES[*]}"

# 2) tailscale serve registered? If not, apply; if tailnet lacks the Serve flag, print the human link
if ! tailscale serve status 2>/dev/null | grep -q "https://"; then
  echo "tailscale serve not registered — applying: tailscale serve --bg --https=443 $LOCAL_BASE"
  # CLI prints the enable link and BLOCKS until the tailnet admin enables Serve — cap it.
  out=$(timeout 25 tailscale serve --bg --https=443 "$LOCAL_BASE" 2>&1); rc=$?
  echo "$out"
  if [ "$rc" -ne 0 ]; then
    link=$(echo "$out" | grep -oE 'https://login\.tailscale\.com/f/serve[^[:space:]]*' | head -1)
    if [ -n "$link" ]; then
      fail "HUMAN STEP (once, ~10s): open $link — then re-run this script"
    fi
    fail "tailscale serve apply failed (rc=$rc — see output above)"
  fi
fi
tailscale serve status || true

# 3) Resolve the public funnel URL from serve status
URL=$(tailscale serve status 2>/dev/null | grep -oE 'https://[^ |]+' | grep 'ts\.net' | head -1)
[ -n "$URL" ] || fail "cannot resolve funnel URL from 'tailscale serve status' — is tailscale logged in?"
echo "funnel URL: $URL"

# 4) Verify public pages (Funnel ACL/propagation retries)
for i in $(seq 1 10); do
  ok=1
  for p in "${PAGES[@]}"; do
    code=$(curl -sS -m 20 -o /dev/null -w '%{http_code}' "$URL$p" || echo 000)
    [ "$code" = "200" ] || { ok=0; echo "wait: $URL$p -> $code"; }
  done
  [ "$ok" = "1" ] && break
  [ "$i" = "10" ] && fail "funnel URLs not reachable — check Serve/Funnel enable + tailnet ACLs"
  sleep 20
done

echo "ALL funnel URLs 200 — temporary public base for ASO metadata (doc/ASO.md sync):"
for p in "${PAGES[@]}"; do
  echo "  $URL$p"
done
echo "NOTE: after the GitHub PAT fix (UPC-3986/3982) migrate URLs back to https://sytler.github.io/openwrt-site and run: tailscale funnel --bg off 2>/dev/null || tailscale serve --bg off"