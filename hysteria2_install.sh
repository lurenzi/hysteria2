#!/bin/bash
export LANG=en_US.UTF-8

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
PLAIN="\033[0m"
yellow(){
    echo -e "\033[33m\033[01m$1\033[0m"
}
green(){
    echo -e "\033[32m\033[01m$1\033[0m"
}
red(){
    echo -e "\033[31m\033[01m$1\033[0m"
}
# 判断系统是否为debain系列
DEBAIN=("debian" "ubuntu")
CHANGE=("debian" "Ubuntu")
[[ $EUID -ne 0 ]] && red "注意: 请在root用户下运行脚本" && exit 1
COMMAND="$(hostnamectl 2>/dev/null | grep -i system | cut -d : -f2)"
for i in "${COMMAND[@]}"; do
    SYS="$i" && [[ -n $SYS ]] && break
done
for ((int = 0; int < ${#DEBAIN[@]}; int++)); do
    [[ $(echo "$SYS" | tr '[:upper:]' '[:lower:]') =~ ${DEBAIN[int]} ]] && SYSTEM="${CHANGE[int]}" && [[ -n $SYSTEM ]] && break
done
if [ "$SYSTEM" == "${CHANGE[0]}" ] || [ "$SYSTEM" == "${CHANGE[1]}" ]; then
    green "VPS系统是'$COMMAND'，该脚本适用！"
else
    red "VPS系统是'$COMMAND'，该脚本不适用！"
    exit 1
fi
#证书申请
#获取IP
ip=$(curl -s4m8 ip.sb -k)
#获取域名
read -p "请输入需要申请证书的域名：" domainName
[[ -z $domainName ]] && red "未输入域名！" && exit 1
green "已输入的域名：$domainName" && sleep 1

domainIP=$(curl -sm8 ipget.net/?ip="${domainName}")

if [[ $domainIP == $ip ]]; then
    #安装基础软件
    apt update -y && apt install -y curl socat
    #域名证书申请
    #下载acme脚本
    curl https://get.acme.sh | sh -s email=$(date +%s%N | md5sum | cut -c 1-16)@gmail.com
    source ~/.bashrc
    #升级
    bash ~/.acme.sh/acme.sh --upgrade --auto-upgrade
    #申请证书的网站改为letsencrypt
    bash ~/.acme.sh/acme.sh --set-default-ca --server letsencrypt
    #证书申请
    bash ~/.acme.sh/acme.sh --issue -d ${domainName} --standalone -k ec-256 --insecure
    #域名证书路径
    mkdir /root/ssl/
    bash ~/.acme.sh/acme.sh --install-cert -d ${domainName} --key-file /root/ssl/private.key --fullchain-file /root/ssl/cert.crt --ecc
    #定时执行脚本
    echo -n '#!/bin/bash
             /etc/init.d/nginx stop
             "/root/.acme.sh"/acme.sh --cron --home "/root/.acme.sh" &> /root/renew_ssl.log
             /etc/init.d/nginx start
            ' > /usr/local/bin/ssl_renew.sh
    chmod +x /usr/local/bin/ssl_renew.sh
    (crontab -l;echo "0 0 15 * * /usr/local/bin/ssl_renew.sh") | crontab
    echo "域名：$domainName" >> /root/infomation.log
    echo "公钥：/root/ssl/cert.crt" >> /root/infomation.log
    echo "私钥：/root/ssl/private.key" >> /root/infomation.log
    echo "证书信息存储：/root/infomation.log"
else
    red "域名当前VPS使用的真实IP不匹配"
    yellow "1. 请检查CloudFlare小云朵是否为关闭状态(仅限DNS)"
    yellow "2. 请检查DNS解析域名的IP是否为VPS的真实IP"
    exit 1
fi
cert_path="/root/ssl/cert.crt"
key_path="/root/ssl/private.key"
#随机端口
Serverport=$(shuf -i 40000-60000 -n 1)
#随机密码
auth_pwd=$(date +%s%N | md5sum | cut -c 1-8)
#伪装网站
proxysite="maimai.sega.jp"
yellow "伪装网站为世嘉maimai日本网站：$proxysite"
#安装hysteria2
bash <(curl -fsSL https://get.hy2.sh/)
systemctl enable hysteria-server.service
#hysteria2配置文件
cat << EOF > /etc/hysteria/config.yaml
listen: :$Serverport

tls:
  cert: $cert_path
  key: $key_path

quic:
  initStreamReceiveWindow: 16777216
  maxStreamReceiveWindow: 16777216
  initConnReceiveWindow: 33554432
  maxConnReceiveWindow: 33554432

auth:
  type: password
  password: $auth_pwd

masquerade:
  type: proxy
  proxy:
    url: https://$proxysite
    rewriteHost: true
EOF
#hysteria2客户端配置文件
Clientport=$(shuf -i 10000-30000 -n 1)
cat << EOF > /root/hysteria2-client.json
{
  "server": "$ip:$Serverport",
  "auth": "$auth_pwd",
  "tls": {
    "sni": "$domainName",
    "insecure": true
  },
  "quic": {
    "initStreamReceiveWindow": 16777216,
    "maxStreamReceiveWindow": 16777216,
    "initConnReceiveWindow": 33554432,
    "maxConnReceiveWindow": 33554432
  },
  "fastOpen": true,
  "socks5": {
    "listen": "127.0.0.1:$Clientport"
  },
  "transport": {
    "udp": {
      "hopInterval": "30s"
    }
  }
}
EOF
#启动
chmod 777 /root/ssl/cert.crt
chmod 777 /root/ssl/private.key

systemctl daemon-reload
systemctl start hysteria-server
if [[ -n $(systemctl status hysteria-server 2>/dev/null | grep -w active) && -f '/etc/hysteria/config.yaml' ]]; then
    green "Hysteria 2 服务启动成功"
else
    red "Hysteria 2 服务启动失败，请运行 systemctl status hysteria-server 查看服务状态并反馈，脚本退出" && exit 1
fi
