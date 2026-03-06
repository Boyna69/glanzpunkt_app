#!/usr/bin/env bash
set -euo pipefail

PRIVACY_URL="${LEGAL_PRIVACY_URL:-https://www.glanzpunkt-wahlstedt.de/datenschutz}"
IMPRINT_URL="${LEGAL_IMPRINT_URL:-https://www.glanzpunkt-wahlstedt.de/impressum}"
SUPPORT_EMAIL_VALUE="${SUPPORT_EMAIL:-support@glanzpunkt-wahlstedt.de}"

FAILED=0

check_http_200() {
  local label="$1"
  local url="$2"
  local response
  local code
  local final_url

  response="$(curl -sS -L -o /dev/null -w '%{http_code} %{url_effective}' "$url" || true)"
  code="$(printf '%s' "$response" | awk '{print $1}')"
  final_url="$(printf '%s' "$response" | awk '{$1=""; sub(/^ /,""); print}')"

  if [ -z "$code" ] || [ "$code" = "000" ]; then
    echo "FAIL ${label}: request failed for ${url}"
    FAILED=1
    return
  fi

  echo "${label}: ${url} -> ${code} (${final_url})"
  if [ "$code" != "200" ]; then
    echo "FAIL ${label}: expected HTTP 200 but got ${code}"
    FAILED=1
  fi
}

echo "== Legal and support live check =="
check_http_200 "Datenschutz" "$PRIVACY_URL"
check_http_200 "Impressum" "$IMPRINT_URL"

if printf '%s' "$SUPPORT_EMAIL_VALUE" | grep -Eq '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'; then
  echo "Support email format: OK (${SUPPORT_EMAIL_VALUE})"
else
  echo "FAIL Support email format: invalid (${SUPPORT_EMAIL_VALUE})"
  FAILED=1
fi

if [ "$FAILED" -ne 0 ]; then
  echo "LEGAL SUPPORT CHECK FAILED"
  exit 1
fi

echo "LEGAL SUPPORT CHECK PASSED"
