#!/bin/sh
# テスト用の systemctl スタブ。
#
# `systemctl start agenticsec-supervisor` だけを失敗させて、そこでインストーラを
# 終わらせる。狙いは 2 つ。
#
#   - コンテナには systemd が無いため、サービス起動から先は検証できない
#   - setup.sh の失敗時クリーンアップ (cleanup_on_error) は /etc/agenticsec を
#     丸ごと消す。手順8の `systemctl start` は cleanup_on_error で囲まれておらず
#     set -e でそのまま終了するため、ここで止めれば生成された state.json が残り、
#     API キーが正しく保存されたかを検査できる
#
if [ "$1" = "start" ] && [ "$2" = "agenticsec-supervisor" ]; then
    echo "stub: refusing to start agenticsec-supervisor (no systemd in test container)" >&2
    exit 1
fi
exit 0
