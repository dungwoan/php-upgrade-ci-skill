#!/usr/bin/env bash
# sweep-patterns.sh - grep a PHP project for PHP 8.x hazard patterns and print counts.
#
# Usage:
#   sweep-patterns.sh [options] [project-dir]        (default project-dir: .)
#
# Options:
#   --samples N            sample hits printed per pattern (default 3)
#   --full                 print every hit, not samples
#   --include-system       also scan system/ (a framework tree can hide app files)
#   --include-third-party  also scan third_party/ (often real app code, e.g. CLI workers)
#   --include-vendor       also scan vendor/ (rarely useful)
#   -h, --help             show this help
#
# Groups:
#   F  fatal on PHP 8.0+ (or a removed function). Target: 0 hits.
#   D  deprecated, behaviour change, or lint-invisible deprecation (8.1-8.5). Fix them.
#   R  review: needs a human to read the code (extensions, guards, heuristics).
#
# Counts are raw grep hits after the exclude regex. They are NOT confirmed bugs.
# Read each sample before counting it as a fix (guards, JS template literals and
# dead code all produce hits). See references/php84-85-patterns.md.
#
# Exit codes: 0 no F-group hits, 1 F-group hits found, 2 usage error.

set -u

SAMPLES=3
FULL=0
INCLUDE_SYSTEM=0
INCLUDE_THIRD_PARTY=0
INCLUDE_VENDOR=0
ROOT="."

# Pattern table: parallel arrays, one entry per pattern.
NAMES=()
PAT_GROUPS=()
REGEXES=()
EXCLUDES=()
NOTES=()

add() {
  # add <name> <group> <ERE> <exclude-ERE-or-empty> <note>
  NAMES+=("$1")
  PAT_GROUPS+=("$2")
  REGEXES+=("$3")
  EXCLUDES+=("$4")
  NOTES+=("$5")
}

define_patterns() {
  # ---- F: fatal on PHP 8.0+ or a removed function -------------------------
  add implode_reversed_literal F \
    'implode[[:space:]]*\([[:space:]]*\$[A-Za-z_][A-Za-z0-9_]*(->[A-Za-z_][A-Za-z0-9_]*)*[[:space:]]*,[[:space:]]*['\''"]' \
    '' \
    'implode(array, glue) order removed in 8.0: TypeError. Swap to implode(glue, array).'
  add removed_functions F \
    '(^|[^A-Za-z0-9_.>:$\\])(mysql_[a-z_]+|eregi?|ereg_replace|eregi_replace|split|spliti|each|create_function|money_format|get_magic_quotes_gpc|get_magic_quotes_runtime|mcrypt_[a-z_]+)[[:space:]]*\(' \
    'function[[:space:]]' \
    'Removed in 7.0-8.0. Undefined-function fatal at runtime, lint does not see it. Check guards (function_exists) before fixing vendored code.'
  add string_offset_braces F \
    '\$[A-Za-z_][A-Za-z0-9_]*\{[0-9$'\''"]' \
    '' \
    '$str{0} syntax removed in 8.0: parse error. Use $str[0].'
  add cast_real F \
    '\((real)\)' \
    '' \
    '(real) cast removed in 8.0: parse error. Use (float).'
  add http_raw_post_data F \
    '\$HTTP_RAW_POST_DATA' \
    '' \
    'Removed in 7.0. Use file_get_contents("php://input").'
  add assert_string_arg F \
    '\bassert[[:space:]]*\([[:space:]]*['\''"]' \
    '' \
    'assert() with a string argument removed in 8.0. Pass an expression.'
  add legacy_mongo_classes F \
    '\bMongo(Client|Id|Date|Regex|Code|Collection|Cursor)\b' \
    '' \
    'Legacy mongo ext/adapter classes. Fatal once the adapter is gone. Port to MongoDB\Driver\Manager and BSON types.'

  # ---- D: deprecated or behaviour change (8.0-8.5) ------------------------
  add json_decode_input_null D \
    'json_decode[[:space:]]*\([[:space:]]*\$this->input->(post|get|get_post|post_get|cookie)\(' \
    '\?\?' \
    'input->post() returns NULL when the key is missing. NULL into json_decode is deprecated (8.1). Use ?? "" (not (string): post() can return an array).'
  add input_null_to_internal D \
    '(strtoupper|strtolower|trim|urldecode|rawurldecode|base64_decode|htmlspecialchars|strlen)[[:space:]]*\([[:space:]]*\$this->input->(post|get)\(' \
    '\?\?|\(string\)' \
    'NULL into a string internal function (8.1 deprecation). Add ?? "".'
  add dollar_brace_interp R \
    '\$\{[A-Za-z_][A-Za-z0-9_]*\}' \
    '`' \
    '"${var}" inside a PHP string is deprecated in 8.2. Hits in HTML/JS outside <?php ... ?> are not PHP; check each line.'
  add utf8_encode_decode D \
    '\butf8_(en|de)code[[:space:]]*\(' \
    '' \
    'utf8_encode/utf8_decode deprecated in 8.2. Use mb_convert_encoding($s, "UTF-8", "ISO-8859-1").'
  add strftime_family D \
    '(^|[^A-Za-z0-9_.>:$])(strftime|gmstrftime|date_sunrise|date_sunset)[[:space:]]*\(' \
    '' \
    'Deprecated in 8.1. Use date()/IntlDateFormatter and date_sun_info().'
  add filter_sanitize_string D \
    'FILTER_SANITIZE_STRING' \
    '' \
    'Deprecated in 8.1. Use htmlspecialchars() at output, or validate with filter_var().'
  add short_open_tag D \
    '<\?' \
    '<\?(php|=)|['\''"]<\?' \
    'Short open tag. Lint cannot see it. Output changes with short_open_tag=Off. Use <?php. <?xml is a parse error when on.'
  add implicit_nullable_param D \
    '([(,][[:space:]]*)[A-Za-z_][A-Za-z0-9_\\]*[[:space:]]+&?\$[A-Za-z_][A-Za-z0-9_]*[[:space:]]*=[[:space:]]*null\b' \
    'mixed' \
    'Implicit nullable "Type $x = null" deprecated in 8.4. Write ?Type $x = null.'
  add required_after_optional D \
    'function[[:space:]]+[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\([^)]*=[^,)]*,[[:space:]]*&?\$[A-Za-z_][A-Za-z0-9_]*[[:space:]]*[,)]' \
    '' \
    'Heuristic, single-line signatures only. Required parameter after an optional one: deprecated since 8.0. Lint reports it too.'
  add e_strict_ref D \
    '\bE_STRICT\b' \
    '' \
    'E_STRICT deprecated in 8.4 when referenced. Remove from error_reporting() masks.'
  add curl_close_call D \
    '\bcurl_close[[:space:]]*\(' \
    '' \
    'curl_close() deprecated in 8.5 (no effect since 8.0). Lint does not report it. Delete the call.'
  add deprecated_casts D \
    '\((double|boolean|integer|binary)\)' \
    '' \
    '(double)/(boolean)/(integer)/(binary) deprecated in 8.5. Use (float)/(bool)/(int)/(string).'
  add http_response_header_var D \
    '\$http_response_header' \
    '' \
    'Direct $http_response_header deprecated in 8.5. Read it via get_defined_vars() or http_get_last_response_headers().'

  # ---- R: review, not a fixed count --------------------------------------
  add count_sizeof R \
    '(^|[^A-Za-z0-9_.>:$])(count|sizeof)[[:space:]]*\(' \
    '' \
    'count(NULL) is a TypeError on 8.0+. Only guard values that can really be NULL; do not mass-edit.'
  add is_resource_call R \
    '\bis_resource[[:space:]]*\(' \
    '' \
    'imap_open returns IMAP\Connection and curl_init returns CurlHandle since 8.1: is_resource() is false. Check the argument type.'
  add is_callable_array_this R \
    'is_callable[[:space:]]*\([[:space:]]*\[[[:space:]]*\$this' \
    '' \
    'is_callable() on a non-static method array can return false on 8.x. Use method_exists() or ReflectionMethod.'
  add scandir_call R \
    '\bscandir[[:space:]]*\(' \
    '\?:' \
    'scandir() returns false when the directory is missing. array_diff() then throws. Guard with ?: [].'
  add unserialize_call R \
    '\bunserialize[[:space:]]*\(' \
    'allowed_classes' \
    'Unrestricted unserialize() of untrusted input. Pass allowed_classes => false in the options where the input is not trusted.'
  add fputcsv_call R \
    '\bfputcsv[[:space:]]*\(' \
    '' \
    'Deprecated in 8.4 when $escape is omitted. Pass the separator, enclosure and escape explicitly.'
  add delete_cookie_call R \
    '\bdelete_cookie[[:space:]]*\(' \
    '' \
    'CI helper: empty cookie name throws ValueError on 8.x. Guard against empty names in the helper.'
  add error_visibility R \
    'error_reporting[[:space:]]*\(|display_errors|E_DEPRECATED' \
    '' \
    'Every place that hides or shows errors. All must agree: image ini, index.php, .htaccess, env bootstrap.'
  add ext_imap_calls R \
    '\bimap_[a-z_]+[[:space:]]*\(' \
    '' \
    'imap left core in 8.4 (PECL). Check the image has it, and grep callers before installing.'
  add ext_ftp_calls R \
    '\bftp_[a-z_]+[[:space:]]*\(' \
    '' \
    'ftp is not in the official php:*-cli image. Check the image has it.'
  add ext_soap_classes R \
    '\bnew[[:space:]]+Soap(Client|Server)\b' \
    '' \
    'SOAP needs ext-soap in the image.'
  add ci_removed_encrypt_sha1 R \
    'load->library\([[:space:]]*['\''"](encrypt|sha1)['\''"]|->encrypt->' \
    '' \
    'CI fork removed the Encrypt and Sha1 libraries. Move to Encryption or hash().'
}

usage() {
  sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
}

# grep_scan <regex> <grep-dir-args...>: prints "path:line:content" hits under ROOT.
# Runs inside ROOT so paths come out relative (./x.php).
grep_scan() {
  local regex="$1"
  shift
  (cd "$ROOT" && grep -rnE --include='*.php' "$@" -- "$regex" . 2>/dev/null)
}

# drop_excluded <exclude-ERE>: reads grep output, drops lines whose CONTENT matches.
# Comment-only lines (//, *, #, /*, and CI's |-style docblocks) are always dropped.
# The exclude regex is passed through ENVIRON so awk does not process escapes.
drop_excluded() {
  RE="$1" awk 'BEGIN { re = ENVIRON["RE"] }
    {
      line = $0
      sub(/^[^:]*:[0-9]+:/, "", line)
      if (line ~ /^[[:space:]]*(\/\/|\*|#|\/\*|\|)/) next
      if (re != "" && line ~ re) next
      print
    }'
}

# tidy_line <hit>: strip the leading ./ and cap the display width.
tidy_line() {
  printf '%s\n' "$1" | sed -e 's#^\./##' | cut -c1-200
}

scan_pattern() {
  # scan_pattern <index> -> prints hits (one per line) on stdout
  local idx="$1"
  local dir_args=()
  [ "$INCLUDE_SYSTEM" -eq 0 ] && dir_args+=(--exclude-dir=system)
  [ "$INCLUDE_THIRD_PARTY" -eq 0 ] && dir_args+=(--exclude-dir=third_party)
  [ "$INCLUDE_VENDOR" -eq 0 ] && dir_args+=(--exclude-dir=vendor)
  dir_args+=(--exclude-dir=node_modules --exclude-dir=.git)
  grep_scan "${REGEXES[$idx]}" "${dir_args[@]}" | drop_excluded "${EXCLUDES[$idx]}"
}

main() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --samples)
        [ "$#" -ge 2 ] || { echo "sweep-patterns: --samples needs a number" >&2; return 2; }
        case "$2" in
          ''|*[!0-9]*) echo "sweep-patterns: --samples must be a number" >&2; return 2 ;;
        esac
        SAMPLES="$2"
        shift 2
        ;;
      --full) FULL=1; shift ;;
      --include-system) INCLUDE_SYSTEM=1; shift ;;
      --include-third-party) INCLUDE_THIRD_PARTY=1; shift ;;
      --include-vendor) INCLUDE_VENDOR=1; shift ;;
      -h|--help) usage; return 0 ;;
      -*) echo "sweep-patterns: unknown option '$1'" >&2; usage >&2; return 2 ;;
      *) ROOT="$1"; shift ;;
    esac
  done

  [ -d "$ROOT" ] || { echo "sweep-patterns: not a directory: $ROOT" >&2; return 2; }
  ROOT="$(cd "$ROOT" && pwd)"

  define_patterns

  local excluded="vendor node_modules .git"
  [ "$INCLUDE_SYSTEM" -eq 0 ] && excluded="$excluded system"
  [ "$INCLUDE_THIRD_PARTY" -eq 0 ] && excluded="$excluded third_party"
  echo "PHP 8.x hazard sweep: $ROOT"
  echo "Excluded directories: $excluded"
  echo "Counts are raw hits after exclude regexes. Confirm samples before counting them as fixes."
  echo

  local f_total=0 d_total=0 r_total=0 f_pat=0 d_pat=0 r_pat=0
  local i hits count group label
  for i in "${!NAMES[@]}"; do
    hits="$(scan_pattern "$i")"
    count=0
    [ -n "$hits" ] && count="$(printf '%s\n' "$hits" | grep -c .)"
    group="${PAT_GROUPS[$i]}"
    case "$group" in
      F) label="fatal on 8.0+"; f_total=$((f_total + count)); [ "$count" -gt 0 ] && f_pat=$((f_pat + 1)) ;;
      D) label="deprecated/behaviour"; d_total=$((d_total + count)); [ "$count" -gt 0 ] && d_pat=$((d_pat + 1)) ;;
      R) label="review"; r_total=$((r_total + count)); [ "$count" -gt 0 ] && r_pat=$((r_pat + 1)) ;;
    esac

    printf '[%s] %-28s %6s hit(s)  (%s)\n' "$group" "${NAMES[$i]}" "$count" "$label"
    if [ "$count" -gt 0 ]; then
      echo "      note: ${NOTES[$i]}"
      local shown=0 line
      while IFS= read -r line; do
        [ "$FULL" -eq 0 ] && [ "$shown" -ge "$SAMPLES" ] && break
        printf '      %s\n' "$(tidy_line "$line")"
        shown=$((shown + 1))
      done <<< "$hits"
      if [ "$FULL" -eq 0 ] && [ "$count" -gt "$SAMPLES" ]; then
        echo "      ... $((count - SAMPLES)) more (use --full)"
      fi
    fi
    echo
  done

  echo "SUMMARY"
  echo "  F fatal on 8.0+        : $f_total hit(s) in $f_pat pattern(s). Target 0."
  echo "  D deprecated/behaviour : $d_total hit(s) in $d_pat pattern(s)."
  echo "  R review               : $r_total hit(s) in $r_pat pattern(s)."
  echo "Lint (php -l) does not replace this sweep, and this sweep does not replace a staging run."

  [ "$f_total" -gt 0 ] && return 1
  return 0
}

main "$@"
