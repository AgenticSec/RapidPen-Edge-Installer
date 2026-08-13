#!/bin/sh
# テスト用の docker スタブ。
#
# テストの主眼は「インストーラが対話入力と設定生成を正しく行うか」なので、
# 実際のイメージ取得は行わない。20GB 近い Operator イメージを CI で引くのは
# 現実的でなく、取得成否はインストーラのロジックとは独立しているため。
case "$1" in
    --version) echo "Docker version 24.0.7, build stubbed" ;;
    info)      exit 0 ;;
    pull)      echo "stub: pretending to pull $2" ;;
    image)     exit 1 ;;   # image inspect -> 未取得扱い
    volume)    exit 1 ;;   # volume inspect -> 存在しない扱い
    ps)        exit 0 ;;
    *)         exit 0 ;;
esac
