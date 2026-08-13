#!/bin/sh
# Edge Installer の E2E テスト。
#
#   ./tests/run.sh                        全ケースを既定のベースイメージで実行
#   ./tests/run.sh --base debian:12       ベースイメージを指定
#   ./tests/run.sh with-env               ケースを指定（複数可）
#
# 必要なもの: docker, expect, ネットワーク（インストーラが GitHub Release を引くため）
set -eu

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$TESTS_DIR/.." && pwd)

BASE_IMAGE="${BASE_IMAGE:-ubuntu:22.04}"
IMAGE_TAG="agenticsec-edge-installer-tests"

ALL_CASES="with-env with-env-no-tty missing-api-key no-tty"

# 既知の失敗。ここに載ったケースは、落ちても全体を赤にせず XFAIL として報告する。
# 不具合を修正する PR では、このリストから該当ケースを外して PASS を示すこと。
XFAIL_CASES=""

# --- 引数 -------------------------------------------------------------------

CASES=""
while [ $# -gt 0 ]; do
    case "$1" in
        --base) BASE_IMAGE="$2"; shift 2 ;;
        --base=*) BASE_IMAGE="${1#--base=}"; shift ;;
        -h | --help) sed -n '2,9p' "$0"; exit 0 ;;
        -*) echo "unknown option: $1" >&2; exit 2 ;;
        *) CASES="$CASES $1"; shift ;;
    esac
done
[ -n "$CASES" ] || CASES="$ALL_CASES"

# --- 準備 -------------------------------------------------------------------

for cmd in docker expect; do
    command -v "$cmd" > /dev/null 2>&1 || { echo "$cmd is required" >&2; exit 2; }
done

echo "== building test image ($BASE_IMAGE)"
docker build -q --build-arg "BASE=$BASE_IMAGE" -t "$IMAGE_TAG" "$TESTS_DIR" > /dev/null

# --- 端末を必要としないケース -----------------------------------------------

# 制御端末が無くても、設定が渡っていればインストールが進むこと
# （構成管理ツールから実行される状況）
run_with_env_no_tty() {
    _out=$(docker run --rm -i -v "$REPO_ROOT:/src:ro" "$IMAGE_TAG" \
               sh /src/tests/case.sh with-env-no-tty 2>&1) || true
    printf '%s\n' "$_out"

    if ! printf '%s' "$_out" | grep -qF 'STORED_API_KEY[testkey123]'; then
        printf '\n>>> FAIL: API キーが保存されていない\n'; return 1
    fi
    printf '\n>>> PASS: 端末が無くても設定が渡っていれば進む\n'
}

# 制御端末も設定も無い場合に、黙って失敗せず取得方法を案内すること
run_no_tty() {
    # -t を付けない = 制御端末を持たないプロセスとして実行する
    _out=$(docker run --rm -i -v "$REPO_ROOT:/src:ro" "$IMAGE_TAG" \
               sh /src/tests/case.sh no-tty 2>&1) || true
    printf '%s\n' "$_out"

    if printf '%s' "$_out" | grep -q 'installer exited with 0'; then
        printf '\n>>> FAIL: 設定が無いのに成功扱いになった\n'; return 1
    fi
    if ! printf '%s' "$_out" | grep -q 'AGENTICSEC_API_KEY is not set'; then
        printf '\n>>> FAIL: 設定不足である旨が案内されていない\n'; return 1
    fi
    if ! printf '%s' "$_out" | grep -q 'Pentest Edge'; then
        printf '\n>>> FAIL: Web UI からの取得方法が案内されていない\n'; return 1
    fi
    printf '\n>>> PASS: 明示的なエラーと取得方法の案内が出た\n'
}

run_case() {
    case "$1" in
        with-env | missing-api-key)
            expect "$TESTS_DIR/drive.exp" "$1" "$IMAGE_TAG" "$REPO_ROOT" ;;
        with-env-no-tty) run_with_env_no_tty ;;
        no-tty)          run_no_tty ;;
        *) echo "unknown case: $1" >&2; return 2 ;;
    esac
}

is_xfail() {
    for _x in $XFAIL_CASES; do
        [ "$_x" = "$1" ] && return 0
    done
    return 1
}

# --- 実行 -------------------------------------------------------------------

n_pass=0
n_fail=0
n_xfail=0
n_xpass=0
summary=""

for case_name in $CASES; do
    echo
    echo "======================================================================"
    echo "== $case_name  ($BASE_IMAGE)"
    echo "======================================================================"

    if run_case "$case_name"; then
        _rc=0
    else
        _rc=$?
    fi

    if is_xfail "$case_name"; then
        if [ "$_rc" -eq 0 ]; then
            n_xpass=$((n_xpass + 1))
            summary="$summary\nXPASS  $case_name  (既知の失敗が解消。XFAIL_CASES から外すこと)"
        else
            n_xfail=$((n_xfail + 1))
            summary="$summary\nXFAIL  $case_name  (既知の失敗)"
        fi
    else
        if [ "$_rc" -eq 0 ]; then
            n_pass=$((n_pass + 1))
            summary="$summary\nPASS   $case_name"
        else
            n_fail=$((n_fail + 1))
            summary="$summary\nFAIL   $case_name"
        fi
    fi
done

echo
echo "======================================================================"
echo "== 結果 ($BASE_IMAGE)"
echo "======================================================================"
printf '%b\n' "$summary"
echo
echo "PASS=$n_pass FAIL=$n_fail XFAIL=$n_xfail XPASS=$n_xpass"

[ "$n_fail" -eq 0 ] || exit 1
