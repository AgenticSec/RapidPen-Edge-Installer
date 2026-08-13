#!/bin/sh
# シェルスクリプトの構文チェックと静的解析。
#
#   ./tests/lint.sh
#
# なお shellcheck が入っていない場合は構文チェックのみを行う。
# (行頭を "# shellcheck" で始めると shellcheck のディレクティブとして解釈される)
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
    # 既存コードは warning まで指摘ゼロなので、その水準を維持する。
    echo "== shellcheck (severity: warning)"
    # shellcheck disable=SC2086
    if shellcheck -s sh -S warning $SCRIPTS; then
        echo "  ok"
    else
        status=1
    fi

    # info / style は件数が多くなりがちなので、止めずに参考表示に留める。
    echo "== shellcheck (severity: info, 参考表示のみ)"
    # shellcheck disable=SC2086
    shellcheck -s sh -S info $SCRIPTS || true
else
    echo "== shellcheck not installed; skipping"
fi

exit "$status"
