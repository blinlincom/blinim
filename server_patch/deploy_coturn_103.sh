#!/usr/bin/env bash
export DEBIAN_FRONTEND=noninteractive
apt-get update -y
apt-get install -y coturn
systemctl stop coturn 2>/dev/null || true
if [ -f /etc/turnserver.conf ]; then
  cp -a /etc/turnserver.conf /etc/turnserver.conf.bak_$(date +%Y%m%d%H%M%S)
fi
cat > /etc/turnserver.conf <<'EOF'
listening-port=3478
tls-listening-port=5349
listening-ip=0.0.0.0
relay-ip=103.39.221.135
external-ip=103.39.221.135
fingerprint
lt-cred-mech
realm=103.39.221.135
server-name=imblinlin-turn
user=imblinlin:946898zhouyu@turn
min-port=49152
max-port=65535
no-multicast-peers
no-cli
no-tlsv1
no-tlsv1_1
log-file=/var/log/turnserver/turnserver.log
simple-log
EOF
cat > /etc/default/coturn <<'EOF'
TURNSERVER_ENABLED=1
EOF
mkdir -p /var/log/turnserver
chown turnserver:turnserver /var/log/turnserver 2>/dev/null || true
if command -v ufw >/dev/null 2>&1; then
  ufw allow 3478/tcp || true
  ufw allow 3478/udp || true
  ufw allow 5349/tcp || true
  ufw allow 49152:65535/udp || true
fi
systemctl enable coturn
systemctl restart coturn
sleep 2
systemctl --no-pager --full status coturn | head -n 50
ss -lntup | grep -E ':3478|:5349' || true
