#!/bin/sh
# コンテナ内で root として起動され、ケースに応じた条件を組み立ててから
# 本番と同じ形（パイプ経由の sudo sh）でインストーラを実行する。
#
#   $1: ケース名
#
# 実行後、生成された state.json から API キーを取り出して STORED_API_KEY[...] を
# 出力する。expect 側はこの行を見て、入力値が正しく保存されたかを判定する。
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
    interactive-normal | interactive-trim)
        : ;;
    interactive-no-icrnl)
        # 顧客環境で観測された状態: 端末が CR を NL に変換しない。
        # 打鍵は端末のエコーで画面に出るが read には改行が届かない。
        stty -icrnl < /dev/tty ;;
    input-timeout)
        # 入力が全く届かない状況。無言で待ち続けないことを確認するため、
        # 待ち時間を短くして実行する。
        SUDO_ENV="AGENTICSEC_INPUT_TIMEOUT_SEC=5" ;;
    non-interactive)
        SUDO_ENV="AGENTICSEC_API_KEY=$TEST_API_KEY AGENTICSEC_BASEURL=$TEST_BASEURL" ;;
    no-tty)
        # 制御端末なしで起動される（docker run に -t を付けない）。
        # 環境変数も渡さないので、インストーラは対話入力に頼れない。
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
