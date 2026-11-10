#!/bin/bash
usermod -l "${username}" ubuntu  
usermod -d "/home/${username}" -m ${username}
sed -i "s/ubuntu/${username}/" /etc/sudoers.d/90-cloud-init-users

# [Learner Lab] 学内ネットワーク等で外向き 22 番が遮断されている環境向けに、443 番でも SSH を待ち受ける
mkdir -p /etc/ssh/sshd_config.d
printf 'Port 22\nPort 443\n' > /etc/ssh/sshd_config.d/10-goad-ports.conf
if systemctl is-active --quiet ssh.socket; then
  mkdir -p /etc/systemd/system/ssh.socket.d
  printf '[Socket]\nListenStream=\nListenStream=22\nListenStream=443\n' > /etc/systemd/system/ssh.socket.d/10-goad-ports.conf
  systemctl daemon-reload
  systemctl restart ssh.socket
else
  systemctl restart ssh
fi
