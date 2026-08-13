#!/bin/sh
# シェルスクリプトの構文チェックと静的解析。
#
#   ./tests/lint.sh
#
# shellcheck が入っていない場合は構文チェックのみを行う。
set -eu

TESTS_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$TESTS_DIR/.." && pwd)
cd "$REPO_ROOT"

SCRIPTS="install.sh setup.sh uninstall.sh
templates/agenticsec-log-cleanup.sh
templates/agenticsec-supervisor-check-upgrade.sh
tests/bootstrap.sh
tests/case.sh
tests/docker-stub.sh
tests/systemctl-stub.sh
tests/lint.sh
tests/run.sh"

status=0

echo "== syntax check (sh -n)"
for f in $SCRIPTS; do
    if sh -n "$f"; then
        echo "  ok  $f"
    else
        echo "  NG  $f"
        status=1
    fi
done

# 本番の実行シェルは Ubuntu/Debian の /bin/sh (dash) なので、そちらでも確認する
if command -v dash > /dev/null 2>&1; then
    echo "== syntax check (dash -n)"
    for f in $SCRIPTS; do
        if dash -n "$f"; then
            echo "  ok  $f"
        else
            echo "  NG  $f"
            status=1
        fi
    done
else
    echo "== dash not installed; skipping dash syntax check"
fi

if command -v shellcheck > /dev/null 2>&1; then
    # まずは明確な誤りだけを止める水準から始める。
    # 指摘を潰しながら段階的に引き上げていく想定。
    echo "== shellcheck (severity: error)"
    # shellcheck disable=SC2086
    if shellcheck -s sh -S error $SCRIPTS; then
        echo "  ok"
    else
        status=1
    fi

    echo "== shellcheck (severity: warning, 参考表示のみ)"
    # shellcheck disable=SC2086
    shellcheck -s sh -S warning $SCRIPTS || true
else
    echo "== shellcheck not installed; skipping"
fi

exit "$status"
