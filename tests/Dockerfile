ARG BASE=ubuntu:22.04
FROM ${BASE}

# インストーラを実際に走らせるための最小環境。
# Docker と systemd はスタブに差し替えるため、本物は入れない。
RUN apt-get update -qq \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
         sudo curl ca-certificates tar jq socat > /dev/null \
    && rm -rf /var/lib/apt/lists/* \
    && useradd -m -s /bin/bash tester \
    && printf 'tester ALL=(ALL) NOPASSWD:ALL\n' > /etc/sudoers.d/tester \
    && chmod 440 /etc/sudoers.d/tester

# 本番は curl | sudo sh で実行されるため、sudo は Ubuntu/Debian の既定に近づけて
# pty を割り当てる設定にしておく（この条件でも対話入力が通ることを確かめる）。
RUN printf 'Defaults use_pty\n' > /etc/sudoers.d/zz-use-pty \
    && chmod 440 /etc/sudoers.d/zz-use-pty

COPY docker-stub.sh /usr/local/bin/docker
COPY systemctl-stub.sh /usr/local/bin/systemctl
RUN chmod 755 /usr/local/bin/docker /usr/local/bin/systemctl
