#!/bin/sh
# 该脚本为immortalwrt首次启动时 运行的脚本 即 /etc/uci-defaults/99-custom.sh
# 设置默认防火墙规则，方便虚拟机首次访问 WebUI
uci set firewall.@zone[1].input='ACCEPT'

# 设置主机名映射，解决安卓原生 TV 无法联网的问题
uci add dhcp domain
uci set "dhcp.@domain[-1].name=time.android.com"
uci set "dhcp.@domain[-1].ip=203.107.6.88"

# 检查配置文件是否存在
SETTINGS_FILE="/etc/config/pppoe-settings"
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "PPPoE settings file not found. Skipping." >> $LOGFILE
else
   # 读取pppoe信息(由build.sh写入)
   . "$SETTINGS_FILE"
fi
# 无需判断网卡数量 因为glinet是多网口
uci set network.lan.ipaddr='192.168.6.1'
echo "set 192.168.6.1 at $(date)" >> $LOGFILE
# 判断是否启用 PPPoE
echo "print enable_pppoe value=== $enable_pppoe" >> $LOGFILE
if [ "$enable_pppoe" = "yes" ]; then
    echo "PPPoE is enabled at $(date)" >> $LOGFILE
    # 设置拨号信息
    uci set network.wan.proto='pppoe'                
    uci set network.wan.username=$pppoe_account     
    uci set network.wan.password=$pppoe_password     
    uci set network.wan.peerdns='1'                  
    uci set network.wan.auto='1' 
    echo "PPPoE configuration completed successfully." >> $LOGFILE
else
    echo "PPPoE is not enabled. Skipping configuration." >> $LOGFILE
fi

# 设置所有网口可访问网页终端
uci delete ttyd.@ttyd[0].interface

# 设置所有网口可连接 SSH
uci set dropbear.@dropbear[0].Interface=''
uci commit



# 设置编译作者信息
FILE_PATH="/etc/openwrt_release"
NEW_DESCRIPTION="Compiled by vx:Mr___zjz"
sed -i "s/DISTRIB_DESCRIPTION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"
sed -i "s/DISTRIB_REVISION='[^']*'/DISTRIB_DESCRIPTION='$NEW_DESCRIPTION'/" "$FILE_PATH"

do_istore() {
	echo "do_istore method==================>"
	# 换源
	ISTORE_REPO=https://istore.istoreos.com/repo/all/store
	FCURL="curl --fail --show-error"

	curl -V >/dev/null 2>&1 || {
		echo "prereq: install curl"
		opkg info curl | grep -Fqm1 curl || opkg update
		opkg install curl
	}

	IPK=$($FCURL "$ISTORE_REPO/Packages.gz" | zcat | grep -m1 '^Filename: luci-app-store.*\.ipk$' | sed -n -e 's/^Filename: \(.\+\)$/\1/p')

	[ -n "$IPK" ] || exit 1

	$FCURL "$ISTORE_REPO/$IPK" | tar -xzO ./data.tar.gz | tar -xzO ./bin/is-opkg >/tmp/is-opkg

	[ -s "/tmp/is-opkg" ] || exit 1

	chmod 755 /tmp/is-opkg
	/tmp/is-opkg update
	# /tmp/is-opkg install taskd
	/tmp/is-opkg opkg install --force-reinstall luci-lib-taskd luci-lib-xterm
	/tmp/is-opkg opkg install --force-reinstall luci-app-store || exit $?
	[ -s "/etc/init.d/tasks" ] || /tmp/is-opkg opkg install --force-reinstall taskd
	[ -s "/usr/lib/lua/luci/cbi.lua" ] || /tmp/is-opkg opkg install luci-compat >/dev/null 2>&1
	# 换源
	sed -i 's/istore.linkease.com/istore.istoreos.com/g' /bin/is-opkg
	sed -i 's/istore.linkease.com/istore.istoreos.com/g' /etc/opkg/compatfeeds.conf
	sed -i 's/istore.linkease.com/istore.istoreos.com/g' /www/luci-static/istore/index.js
}

do_istore

exit 0
