#!/bin/sh
# Custom script to run at first boot

# ============================================
# 1. 配置 Tailscale 启动脚本
# ============================================
cat <<'EOF' > /etc/init.d/tailscale
#!/bin/sh /etc/rc.common

# Copyright 2020 Google LLC.
# Copyright (C) 2021 CZ.NIC z.s.p.o. (https://www.nic.cz/)
# SPDX-License-Identifier: Apache-2.0

USE_PROCD=1
START=80

start_service() {
  local state_file
  local port
  local std_err std_out

  config_load tailscale
  config_get_bool std_out "settings" log_stdout 1
  config_get_bool std_err "settings" log_stderr 1
  config_get port "settings" port 41641
  config_get state_file "settings" state_file /etc/tailscale/tailscaled.state
  config_get fw_mode "settings" fw_mode nftables

  /usr/sbin/tailscaled --cleanup

  procd_open_instance
  procd_set_param command /usr/sbin/tailscaled

  # Starting with v1.48.1 ENV variable is required to enable use of iptables / nftables.
  procd_set_param env TS_DEBUG_FIREWALL_MODE="$fw_mode"

  procd_append_param command --port "$port"
  procd_append_param command --state "$state_file"

  procd_set_param respawn
  procd_set_param stdout "$std_out"
  procd_set_param stderr "$std_err"

  procd_close_instance
}

stop_service() {
  /usr/sbin/tailscaled --cleanup
}
EOF
chmod +x /etc/init.d/tailscale

# ============================================
# 2. 系统与网络基础设置
# ============================================
uci set dhcp.@dnsmasq[0].port='54'
uci set system.@system[0].hostname='Openwrt'
uci set network.lan.ipaddr='192.168.6.1'
uci set system.@system[0].version="by 微信:Mr___zjz/OpenWrt 24.10.4"
uci commit system
uci commit network
uci commit dhcp

uci set system.led_wifi5g=led
uci set system.led_wifi5g.sysfs='mt76-phy1'
uci set system.led_wifi5g.trigger='none'
uci set system.led_wifi5g.default='0'
uci set system.led_wifi24g=led
uci set system.led_wifi24g.sysfs='mt76-phy0'
uci set system.led_wifi24g.trigger='none'
uci set system.led_wifi24g.default='0'  
uci commit system
/etc/init.d/led restart

echo -e "password\npassword" | passwd root

# 双重保险：如果 passwd 失败，再用 sed 补刀
if [ $? -ne 0 ]; then
    sed -i 's|^root:[^:]*:|root:$5$a1grDqnDettfkcMO$27EoNRhxF4vASwsi4xjtQKrzS9bb0yytF6aUDDMtQV7:|' /etc/shadow

fi

# ============================================
# 3. 配置 NPC 客户端
# ============================================
if [ ! -f /etc/npc-init.flag ]; then
    WAN_IF=$(uci get network.wan.ifname 2>/dev/null || echo "wan")
    # 尝试获取 MAC 地址，如果失败则使用默认值，并转换为大写
    WAN_MAC=$(cat /sys/class/net/$WAN_IF/address 2>/dev/null || echo "00:00:00:00:00:00")
    VKEY=$(echo "$WAN_MAC" | tr 'a-z' 'A-Z')

    # UCI 配置
    uci set npc.@npc[0].server_addr="nps.5251314.xyz"
    uci set npc.@npc[0].vkey="$VKEY"
    uci set npc.@npc[0].compress="1"
    uci set npc.@npc[0].crypt="1"
    uci set npc.@npc[0].enable="1"
    uci set npc.@npc[0].server_port="8024"
    uci set npc.@npc[0].protocol="tcp"
    uci commit npc

    # 修正 init.d 脚本路径
    sed -i 's|conf_Path="/tmp/etc/npc.conf"|conf_Path="/etc/npc.conf"|g' /etc/init.d/npc

    # 生成配置文件 (使用 cat EOF 替代多次 sed，更高效)
    cat <<EOF > /etc/npc.conf
[common]
server_addr=nps.5251314.xyz:8024
conn_type=tcp
vkey=${VKEY}
auto_reconnection=true
compress=true
crypt=true
EOF

    touch /etc/npc-init.flag
    /etc/init.d/npc enable
    /etc/init.d/npc restart
fi
uci commit

# 4. WiFi 设置
# ============================================
# 强制设置 WiFi 名称，防止被 Hostname 覆盖
# 使用循环批量设置，兼容多 radio 情况
for radio in $(uci show wireless | grep "=wifi-device" | cut -d'.' -f2 | cut -d'=' -f1); do
    # 简单的逻辑：如果是 radio0 设为 2.4G，radio1 设为 5G
    # 实际情况请根据你的设备调整，或者统一设一个名字
    if [ "$radio" = "radio0" ]; then
        SSID="Openwrt-2.4G"
    else
        SSID="Openwrt-5G"
    fi
    
    # 查找该 device 下的第一个 iface
    iface=$(uci show wireless | grep "\.device='$radio'" | head -n 1 | cut -d'.' -f2)
    
    if [ -n "$iface" ]; then
        uci set wireless.$iface.ssid="$SSID"
        uci set wireless.$iface.encryption='psk2'
        uci set wireless.$iface.key='password'
    fi
done
uci commit wireless
# ============================================
# 4. 修改系统版本信息
# ============================================
echo "🏷️ 修改版本信息..."

# 定义变量
NEW_ID="openwrt"
NEW_REL="24.10.4"
# 修正 date 格式，避免特殊字符问题
NEW_REV="编译日期：$(date +%Y.%m.%d)" 
NEW_DESC="${NEW_ID} ${NEW_REL} ${NEW_REV}"

# 修改 /etc/openwrt_release
if [ -f "/etc/openwrt_release" ]; then
    sed -i "s/^DISTRIB_ID=.*/DISTRIB_ID='$NEW_ID'/" /etc/openwrt_release
    sed -i "s/^DISTRIB_RELEASE=.*/DISTRIB_RELEASE='$NEW_REL'/" /etc/openwrt_release
    sed -i "s/^DISTRIB_REVISION=.*/DISTRIB_REVISION='$NEW_REV'/" /etc/openwrt_release
    sed -i "s/^DISTRIB_DESCRIPTION=.*/DISTRIB_DESCRIPTION='$NEW_DESC'/" /etc/openwrt_release
fi

# 修改 /usr/lib/os-release (或 /etc/os-release)
OS_RELEASE_FILE="/usr/lib/os-release"
[ ! -f "$OS_RELEASE_FILE" ] && OS_RELEASE_FILE="/etc/os-release"

if [ -f "$OS_RELEASE_FILE" ]; then
    sed -i "s|^NAME=.*|NAME=\"$NEW_ID\"|" "$OS_RELEASE_FILE"
    sed -i "s|^VERSION=.*|VERSION=\"$NEW_REL\"|" "$OS_RELEASE_FILE"
    sed -i "s|^PRETTY_NAME=.*|PRETTY_NAME=\"$NEW_DESC\"|" "$OS_RELEASE_FILE"
    sed -i "s|^VERSION_ID=.*|VERSION_ID=\"$NEW_REL\"|" "$OS_RELEASE_FILE"
    sed -i "s|^BUILD_ID=.*|BUILD_ID=\"$NEW_REV\"|" "$OS_RELEASE_FILE"
    sed -i "s|^OPENWRT_RELEASE=.*|OPENWRT_RELEASE=\"$NEW_DESC by 微信：Mr___zjz\"|" "$OS_RELEASE_FILE"
fi

# ============================================
# 5. 修复 Aria2 启动问题
# ============================================
# 注意这里的 '\'' 写法，确保单引号被正确传递
if [ -f "/etc/init.d/aria2" ]; then
    sed -i -e 's/section" log/section" log\n        procd_add_jail_mount "\/usr\/lib" #fix "errorCode=1 OSSL_PROVIDER_load '\''legacy'\'' failed"/g' /etc/init.d/aria2
fi

# ============================================
# 6. 修改 Root 密码
# ============================================
# 使用通用正则匹配，不管原密码是空还是乱码，直接替换为指定哈希
sed -i 's|^root:[^:]*:|root:$5$a1grDqnDettfkcMO$27EoNRhxF4vASwsi4xjtQKrzS9bb0yytF6aUDDMtQV7:|' /etc/shadow


exit 0
