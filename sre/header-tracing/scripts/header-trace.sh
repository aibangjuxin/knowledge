#!/usr/bin/env zsh
#
# header-trace.sh — Hop-by-hop header trace helper for a multi-hop proxy chain.
#
# WHAT IT DOES
#   1. --probe  : Sends the same probe request to every hop in the chain and
#                 reports the value of the watched header at each hop.
#                 Requires each hop to expose an endpoint that echoes the
#                 headers it received (httpbin-style JSON).
#   2. --generate: Emits ready-to-paste nginx / Kong probe configuration with
#                 per-hop unique header names so evidence is not overwritten.
#
# USAGE
#   ./header-trace.sh --probe   --url "L7=https://l7.example.com" \
#                                  --url "KONG=https://kong.example.com" \
#                                  --watch x-caep-src-useragent
#
#   ./header-trace.sh --probe --url "L7=https://l7.example.com/headers" \
#                                  --watch x-caep-src-useragent \
#                                  --send "user-agent=UA_DIRECT_A" \
#                                  --send "x-caep-src-useragent=SRC_B"
#
#   ./header-trace.sh --generate --hops 3
#
# EXIT CODES
#   0 success
#   1 usage / parameter error
#   2 network or HTTP error
#   3 parse error (unexpected response shape)
#
# DEPENDENCIES
#   curl, jq, zsh

set -u
set -o pipefail

readonly PROG="${0:t}"

# ---------- colors ----------
readonly C_RESET=$'\033[0m'
readonly C_BOLD=$'\033[1m'
readonly C_DIM=$'\033[2m'
readonly C_RED=$'\033[31m'
readonly C_GREEN=$'\033[32m'
readonly C_YELLOW=$'\033[33m'
readonly C_BLUE=$'\033[34m'
readonly C_CYAN=$'\033[36m'

# ---------- defaults ----------
typeset -a URLS=()
typeset -a SENDS=()
typeset -a WATCHES=()
typeset MODE="probe"
typeset TMPDIR_TRACE=""
typeset TIMEOUT="10"
typeset INSECURE=0
typeset HOP_COUNT=3
typeset SHOW_HEADER=1

usage() {
  cat <<EOF
${C_BOLD}${PROG}${C_RESET} - hop-by-hop header trace helper

${C_BOLD}MODES${C_RESET}
  --probe        Send the same request to each hop directly and compare the
                 watched header. Isolates each hop: a value that differs from
                 what was sent was changed BY that hop.
  --stamps       Send the request to ONE endpoint (the runtime) and read back
                 the X-Dbg-Hn-* stamp headers. Reconstructs the whole chain
                 from a single request. Requires the probes to be installed.
  --generate     Print nginx / Kong probe config with per-hop unique names

${C_BOLD}OPTIONS${C_RESET}
  --url "LABEL=URL"   Hop endpoint to probe (repeatable, order matters).
                      For --stamps give exactly one: the runtime endpoint.
  --send "K=V"        Extra header to send (repeatable)
  --watch "NAME"      Header name to watch (repeatable, default all X-Dbg-* and
                       the watched list)
  --timeout SEC       curl timeout per hop (default ${TIMEOUT})
  --insecure          Skip TLS verification
  --hops N            Number of hops for --generate (default ${HOP_COUNT})
  --no-header         Omit the header block in --generate output
  -h, --help          Show this help

${C_BOLD}EXIT CODES${C_RESET}
  0 success   1 usage error   2 network/HTTP error   3 parse error
EOF
}

die() {
  local code="$1"; shift
  print -u2 -- "${C_RED}${C_BOLD}[${PROG}] ERROR${C_RESET} $*"
  exit "$code"
}

# ---------- arg parsing ----------
while (( $# > 0 )); do
  case "$1" in
    --probe)     MODE="probe"; shift ;;
    --stamps)    MODE="stamps"; shift ;;
    --generate)  MODE="generate"; shift ;;
    --url)       [[ $# -ge 2 ]] || die 1 "--url requires an argument"
                 URLS+=("$2"); shift 2 ;;
    --send)      [[ $# -ge 2 ]] || die 1 "--send requires an argument"
                 SENDS+=("$2"); shift 2 ;;
    --watch)     [[ $# -ge 2 ]] || die 1 "--watch requires an argument"
                 WATCHES+=("$2"); shift 2 ;;
    --timeout)   [[ $# -ge 2 ]] || die 1 "--timeout requires an argument"
                 TIMEOUT="$2"; shift 2 ;;
    --insecure)  INSECURE=1; shift ;;
    --hops)      [[ $# -ge 2 ]] || die 1 "--hops requires an argument"
                 HOP_COUNT="$2"; shift 2 ;;
    --no-header) SHOW_HEADER=0; shift ;;
    -h|--help)   usage; exit 0 ;;
    *)           usage >&2; die 1 "unknown argument: $1" ;;
  esac
done

(( ${#WATCHES[@]} == 0 )) && WATCHES=("x-caep-src-useragent" "user-agent")

# ---------- helpers ----------
hr() {
  local line=""
  local i
  for (( i = 0; i < 78; i++ )); do line+="─"; done
  printf '%s%s%s\n' "$C_DIM" "$line" "$C_RESET"
}

section() {
  print -- "\n${C_BOLD}${C_BLUE}==>${C_RESET} ${C_BOLD}$1${C_RESET}"
}

# Extract a header value from an httpbin-style JSON echo response.
# Supports {"headers":{...}} and flat {...} shapes.
extract_header() {
  local json="$1" name="$2"
  printf '%s' "$json" | jq -r --arg n "$name" '
    (if type == "object" and has("headers") then .headers else . end)
    | to_entries
    | map(select(.key | ascii_downcase == ($n | ascii_downcase)))
    | if length == 0 then "<absent>"
      else (.[0].value | if type == "array" then join(", ") else tostring end)
      end
  ' 2>/dev/null
}

# ---------- generate mode ----------
emit_generate() {
  local n="$HOP_COUNT" i

  if (( SHOW_HEADER )); then
    print -- "${C_BOLD}# nginx L7 probe configuration (stamps H1)${C_RESET}"
    print -- "# A hop stamps what it RECEIVED, so the stamp records the state BEFORE"
    print -- "# this hop rewrites anything. Compare stamps in hop order: the hop where"
    print -- "# the value first differs is the hop AFTER the one that rewrote it."
    print -- "#"
    print -- "# ${C_YELLOW}Drop these lines when the investigation is done.${C_RESET}"
    print -- ""
    print -- "http {"
    print -- "    # Only enable for the investigator source IP."
    print -- "    map \"\$remote_addr\" \$debug_trace_on {"
    print -- "        default       0;"
    print -- "        \"10.20.30.40\" 1;   # ${C_YELLOW}TODO: your IP${C_RESET}"
    print -- "    }"
    print -- ""
    print -- "    # An empty value means the header is not sent at all, so the probe"
    print -- "    # stays completely silent for everyone except the investigator."
    print -- "    map \$debug_trace_on \$dbg_h1_useragent {"
    print -- "        0  \"\";"
    print -- "        1  \$http_user_agent;"
    print -- "    }"
    print -- "    map \$debug_trace_on \$dbg_h1_caepsrcuseragent {"
    print -- "        0  \"\";"
    print -- "        1  \$http_x_caep_src_useragent;"
    print -- "    }"
    print -- ""
    print -- "    server {"
    print -- "        location / {"
    print -- "            # ${C_YELLOW}KEEP the business proxy_set_header lines in this same block${C_RESET}"
    print -- "            # ${C_YELLOW}Adding one proxy_set_header in a location DISCARDS all inherited ones.${C_RESET}"
    print -- ""
    print -- "            # ${C_DIM}-- probe: request direction --${C_RESET}"
    print -- "            proxy_set_header X-Dbg-H1-UserAgent       \$dbg_h1_useragent;"
    print -- "            proxy_set_header X-Dbg-H1-CaepSrcUserAgent \$dbg_h1_caepsrcuseragent;"
    print -- ""
    print -- "            # ${C_DIM}-- probe: response direction (always is required) --${C_RESET}"
    print -- "            add_header X-Dbg-R1-UpstreamUserAgent \$upstream_http_user_agent always;"
    print -- "            add_header X-Dbg-R1-SentUserAgent     \$sent_http_user_agent always;"
    print -- ""
    print -- "            # ${C_DIM}-- your existing business headers go below, unchanged --${C_RESET}"
    print -- "            # proxy_set_header Host              \$host;"
    print -- "            # proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;"
    print -- ""
    print -- "            proxy_pass http://backend_upstream;"
    print -- "        }"
    print -- "    }"
    print -- "}"
    print -- ""
  fi

  print -- "${C_BOLD}# Kong request-transformer probe (stamps H2${C_RESET}${n:+, and later hops})"
  print -- "#"
  print -- "# 'add' only sets a header when it is ABSENT, so it never overwrites"
  print -- "# anything. That makes it the safe choice for a probe."
  print -- "# The template reads the header as Kong RECEIVED it, before any"
  print -- "# replace in the same plugin runs."
  print -- ""
  print -- "apiVersion: configuration.konghq.com/v1"
  print -- "kind: KongPlugin"
  print -- "metadata:"
  print -- "  name: debug-header-probe"
  print -- "  annotations:"
  print -- "    konghq.com/plugin: request-transformer"
  print -- "plugin: request-transformer"
  print -- "config:"
  print -- "  add:"
  print -- "    headers:"
  for (( i = 2; i <= n; i++ )); do
    print -- "      - \"X-Dbg-H${i}-CaepSrcUserAgent:\$(headers['x-caep-src-useragent'])\""
    print -- "      - \"X-Dbg-H${i}-UserAgent:\$(headers['user-agent'])\""
  done
  print -- ""
  print -- "${C_DIM}# Bind the plugin to a route or service:"
  print -- "#   kubectl patch kongroute <route> -n <ns> --type=merge \\"
  print -- "#     -p '{\"pluginRefs\": [\"debug-header-probe\"]}'${C_RESET}"
  print -- ""
  print -- "${C_YELLOW}NOTE:${C_RESET} request-transformer cannot rewrite X-Forwarded-* headers."
  print -- "      Use the post-function plugin if you need to observe those."
}

# ---------- probe mode ----------
run_probe() {
  local http_status rc
  TMPDIR_TRACE="$(mktemp -d)" || die 2 "cannot create temp dir"
  trap 'rm -rf "$TMPDIR_TRACE"' EXIT INT TERM
  local tmpdir="$TMPDIR_TRACE"

  local -a labels=() endpoints=()
  local entry label url
  for entry in "${URLS[@]}"; do
    label="${entry%%=*}"
    url="${entry#*=}"
    [[ "$url" == "$entry" ]] && die 1 "--url must be LABEL=URL, got: $entry"
    labels+=("$label")
    endpoints+=("$url")
  done

  (( ${#endpoints[@]} == 0 )) && die 1 "--probe requires at least one --url"

  section "Chain (${#endpoints[@]} hops)"
  local i
  for (( i = 1; i <= ${#endpoints[@]}; i++ )); do
    printf '  %s%-4s%s %s%s%s\n' "$C_CYAN" "H$i" "$C_RESET" "$C_DIM" "${labels[$i]}" "$C_RESET"
    printf '       %s%s%s\n' "$C_DIM" "${endpoints[$i]}" "$C_RESET"
  done

  section "Sending probe request"
  local -a curl_args=()
  curl_args+=(--silent --show-error --max-time "$TIMEOUT")
  (( INSECURE )) && curl_args+=(--insecure)
  for entry in "${SENDS[@]}"; do
    # curl only accepts "Name: value". A "Name=value" argument is silently
    # dropped by curl, so translate it here instead of failing quietly.
    local h_name="${entry%%=*}"
    local h_value="${entry#*=}"
    [[ "$h_name" == "$entry" ]] && die 1 "--send must be K=V, got: $entry"
    [[ -z "$h_value" ]] && die 1 "--send has an empty value: $entry"
    curl_args+=(--header "${h_name}: ${h_value}")
    printf '  %s+%s %s%s%s\n' "$C_GREEN" "$C_RESET" "$C_BOLD" "${h_name}: ${h_value}" "$C_RESET"
  done
  (( ${#SENDS[@]} == 0 )) && print -- "  ${C_DIM}(no --send headers)${C_RESET}"

  local -a results=()
  local failures=0
  for (( i = 1; i <= ${#endpoints[@]}; i++ )); do
    local body_file="${tmpdir}/hop${i}.json"
    http_status="$(curl "${curl_args[@]}" --output "$body_file" --write-out '%{http_code}' \
      "${endpoints[$i]}" 2>"${tmpdir}/hop${i}.err")"
    rc=$?
    if (( rc != 0 )); then
      print -- "  ${C_RED}H${i} ${labels[$i]}: request failed${C_RESET} $(<"${tmpdir}/hop${i}.err")"
      results+=("")
      (( failures++ ))
      continue
    fi
    if [[ "$http_status" != "200" ]]; then
      print -- "  ${C_YELLOW}H${i} ${labels[$i]}: HTTP ${http_status}${C_RESET}"
      results+=("")
      (( failures++ ))
      continue
    fi
    print -- "  ${C_GREEN}H${i} ${labels[$i]}: HTTP 200${C_RESET}"
    results+=("$(<"$body_file")")
  done

  section "Observed header values per hop"
  local watch prev_value
  for watch in "${WATCHES[@]}"; do
    print -- "\n  ${C_BOLD}${watch}${C_RESET}"
    prev_value=""
    for (( i = 1; i <= ${#endpoints[@]}; i++ )); do
      local body="${results[$i]}"
      local value="<no-response>"
      if [[ -n "$body" ]]; then
        value="$(extract_header "$body" "$watch")"
        [[ -z "$value" ]] && value="<parse-error>"
      fi

      # A hop that did not answer breaks the comparison chain.
      if [[ "$value" == "<no-response>" || "$value" == "<parse-error>" ]]; then
        printf '  ! %-2s %-14s %s%s%s\n' \
          "$i" "${labels[$i]}" "$C_DIM" "$value" "$C_RESET"
        prev_value=""
        continue
      fi

      # Compare against the previous hop that answered. "<absent>" is a real
      # observation: a header that appears or disappears is also a change.
      if [[ -n "$prev_value" && "$value" != "$prev_value" ]]; then
        printf '  * %-2s %-14s %s%s%s  %s<-- CHANGED HERE%s\n' \
          "$i" "${labels[$i]}" "$C_BOLD" "$value" "$C_RESET" "$C_YELLOW" "$C_RESET"
      elif [[ "$value" == "<absent>" ]]; then
        printf '  ! %-2s %-14s %s%s%s\n' \
          "$i" "${labels[$i]}" "$C_DIM" "$value" "$C_RESET"
      else
        printf '    %-2s %-14s %s%s%s\n' \
          "$i" "${labels[$i]}" "$C_BOLD" "$value" "$C_RESET"
      fi
      prev_value="$value"
    done
  done

  print -- ""
  hr
  print -- "${C_BOLD}Reading the result${C_RESET}"
  print -- "  ${C_GREEN}*${C_RESET} marks the hop where the value first differs from the previous hop."
  print -- "  The changing hop is where the header was rewritten."
  print -- "  Remember: the probe records what a hop RECEIVED, so a rewrite done by"
  print -- "  hop N shows up at hop N+1. The last hop in the chain is the runtime."

  (( failures > 0 )) && die 2 "${failures} of ${#endpoints[@]} hops did not return HTTP 200"
  return 0
}

# ---------- stamps mode ----------
# The chain is reconstructed from the per-hop stamp headers installed by
# --generate. Hop N stamps what it RECEIVED, so a rewrite done by hop N shows
# up as a difference between stamp N and stamp N+1.
run_stamps() {
  local tmpdir http_status rc
  TMPDIR_TRACE="$(mktemp -d)" || die 2 "cannot create temp dir"
  trap 'rm -rf "$TMPDIR_TRACE"' EXIT INT TERM
  tmpdir="$TMPDIR_TRACE"

  (( ${#URLS[@]} == 1 )) || die 1 "--stamps requires exactly one --url (the runtime endpoint)"

  local entry h_name h_value
  local -a curl_args=(--silent --show-error --max-time "$TIMEOUT")
  (( INSECURE )) && curl_args+=(--insecure)
  for entry in "${SENDS[@]}"; do
    h_name="${entry%%=*}"; h_value="${entry#*=}"
    [[ "$h_name" == "$entry" ]] && die 1 "--send must be K=V, got: $entry"
    curl_args+=(--header "${h_name}: ${h_value}")
  done

  section "Request"
  print -- "  ${C_DIM}${URLS[1]#*=}${C_RESET}"
  for entry in "${SENDS[@]}"; do
    print -- "  ${C_GREEN}+${C_RESET} ${C_BOLD}${entry%%=*}: ${entry#*=}${C_RESET}"
  done

  local body_file="${tmpdir}/stamps.json"
  http_status="$(curl "${curl_args[@]}" --output "$body_file" --write-out '%{http_code}' \
    "${URLS[1]#*=}" 2>"${tmpdir}/err")"
  rc=$?
  (( rc != 0 )) && die 2 "request failed: $(<"${tmpdir}/err")"
  [[ "$http_status" != "200" ]] && die 2 "unexpected HTTP status: $http_status"

  section "Chain reconstruction from stamp headers"
  local stamps
  stamps="$(jq -r '
    (if type == "object" and has("headers") then .headers else . end)
    | to_entries
    | map(select(.key | ascii_downcase | test("^x-dbg-h[0-9]+-")))
    | map({ hop: (.key | capture("^x-dbg-h(?<n>[0-9]+)-") | .n | tonumber),
            name: .key, value: (if (.value|type) == "array" then (.value|join(", ")) else (.value|tostring) end) })
    | sort_by(.hop, .name)
  ' "$body_file" 2>/dev/null)" || die 3 "cannot parse response as JSON"

  [[ -z "$stamps" ]] && die 3 "no X-Dbg-Hn-* stamp headers found in the response"

  printf '%s' "$stamps" | jq -r '
    .[] | "H\(.hop)\t\(.name)\t\(.value)"
  ' | while IFS=$'\t' read -r hop name value; do
    printf '  %s%-4s%s %-32s %s%s%s\n' "$C_CYAN" "$hop" "$C_RESET" "$name" "$C_BOLD" "$value" "$C_RESET"
  done

  print -- ""
  hr
  print -- "${C_BOLD}Reading the result${C_RESET}"
  print -- "  Each hop stamps what it RECEIVED. Compare stamps in hop order:"
  print -- "  the hop where the value first differs is the hop AFTER the one"
  print -- "  that rewrote it."
  print -- "  A value present at H1 but changed at H2 means H1 rewrote it."
}

# ---------- main ----------
case "$MODE" in
  generate) emit_generate ;;
  probe)    run_probe ;;
  stamps)   run_stamps ;;
  *)        die 1 "unknown mode: $MODE" ;;
esac

exit 0
