#!/bin/sh
# install.sh 相当のブートストラップ。
#
# 本番では `curl -fsSL .../install.sh | sudo sh` で実行されるため、install.sh の
# 標準入力はパイプであり、そこから呼ばれる setup.sh も EOF 済みのパイプを
# 標準入力として受け取る。対話入力の不具合はこの構造と密接に関係するので、
# テストでも同じ形（パイプ経由で sudo sh に流し込む）を保つ。
#
# GitHub からアーカイブを取得する部分だけを、作業ツリーの内容に差し替えている。
set -e
cd /tmp/inst
sh setup.sh "$@"
