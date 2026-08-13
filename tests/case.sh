#!/bin/sh
# コンテナ内で root として起動され、ケースに応じた条件を組み立ててから
# 本番と同じ形（パイプ経由の sudo sh）でインストーラを実行する。
#
#   $1: ケース名
#
# 実行後、生成された state.json から設定値を取り出して STORED_* を出力する。
# 呼び出し側はこの行を見て、設定が正しく保存されたかを判定する。
set -u

CASE_NAME="$1"
TEST_API_KEY="testkey123"
TEST_BASEURL="https://api.agenticsec.tech/api/edge/supervisor"
STATE_FILE="/etc/agenticsec/supervisor/state.json"

# 作業ツリーは read-only でマウントされるため、実行用にコピーする
rm -rf /tmp/inst
mkdir -p /tmp/inst
cp /src/setup.sh /tmp/inst/
cp /src/tests/bootstrap.sh /tmp/inst/
cp -r /src/templates /tmp/inst/

# setup.sh の docker socket 検出（[ -S ... ]）を通すためのダミー socket
socat UNIX-LISTEN:/var/run/docker.sock,fork,unlink-early /dev/null &
i=0
while [ ! -S /var/run/docker.sock ] && [ "$i" -lt 500 ]; do i=$((i + 1)); done

SUDO_ENV=""
case "$CASE_NAME" in
    with-env | with-env-no-tty)
        # 正常系。Web UI が配布するインストーラと同じく、設定を環境変数で渡す。
        SUDO_ENV="AGENTICSEC_API_KEY=$TEST_API_KEY AGENTICSEC_BASEURL=$TEST_BASEURL" ;;
    missing-api-key | no-tty)
        # 設定が無い場合。案内を出して直ちに終了することを期待する。
        : ;;
    *)
        echo "unknown case: $CASE_NAME" >&2
        exit 2 ;;
esac

echo "--- $(sudo -V | head -1)"
echo "--- $(. /etc/os-release && echo "$PRETTY_NAME") / case=$CASE_NAME"

# su / runuser は新しいセッションを作って制御端末を落としてしまうため、
# 実端末を保ったまま降格できる setpriv を使う。
setpriv --reuid=tester --regid=tester --init-groups \
    sh -c "cat /tmp/inst/bootstrap.sh | sudo $SUDO_ENV sh"
INSTALLER_RC=$?

echo "--- installer exited with $INSTALLER_RC"

# 生成物の検査。systemctl スタブが手順8で止めるため state.json は残っている。
if [ -f "$STATE_FILE" ]; then
    printf 'STORED_API_KEY[%s]\n' "$(jq -r '.agenticsec_cloud_api_key' "$STATE_FILE")"
    printf 'STORED_BASEURL[%s]\n' "$(jq -r '.agenticsec_cloud_baseurl' "$STATE_FILE")"
else
    echo "STATE_FILE_MISSING"
fi

exit "$INSTALLER_RC"
