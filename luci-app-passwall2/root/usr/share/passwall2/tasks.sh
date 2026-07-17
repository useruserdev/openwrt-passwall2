#!/bin/sh
## Loop update script

. /usr/share/passwall2/utils.sh
LOCK_FILE=${LOCK_PATH}/${CONFIG}_tasks.lock

CFG_UPDATE_INT=0

exec 99>"$LOCK_FILE"
flock -n 99
if [ "$?" != 0 ]; then
	exit 0
fi

while true
do

	if [ "$CFG_UPDATE_INT" -ne 0 ]; then

		restart_week_mode=$(config_t_get global_delay restart_week_mode)
		restart_interval_mode=$(config_t_get global_delay restart_interval_mode)
		restart_interval_mode=$(expr "$restart_interval_mode" \* 60)
		if [ -n "$restart_week_mode" ]; then
			[ "$restart_week_mode" = "8" ] && {
				[ "$(expr "$CFG_UPDATE_INT" % "$restart_interval_mode")" -eq 0 ] && { /etc/init.d/$CONFIG restart > /dev/null 2>&1 & }
			}
		fi

		rules_update_week_mode=$(config_t_get global_rules update_week_mode)
		rules_update_interval_mode=$(config_t_get global_rules update_interval_mode)
		rules_update_interval_mode=$(expr "$rules_update_interval_mode" \* 60)
		if [ -n "$rules_update_week_mode" ]; then
			[ "$rules_update_week_mode" = "8" ] && {
				[ "$(expr "$CFG_UPDATE_INT" % "$rules_update_interval_mode")" -eq 0 ] && { lua $APP_PATH/rule_update.lua log all cron > /dev/null 2>&1 & }
			}
		fi

		# Loop-mode subscriptions are scheduled by the persistent last_update timestamp
		# (written by subscribe.lua) instead of an in-memory counter, so the interval
		# survives service restarts and reboots.
		now=$(date +%s)
		cfgids=""
		for item in $(uci show ${CONFIG} | grep "=subscribe_list" | cut -d '.' -sf 2 | cut -d '=' -sf 1); do
			sub_update_week_mode=$(config_n_get $item update_week_mode)
			[ "$sub_update_week_mode" = "8" ] || continue
			sub_update_interval_mode=$(config_n_get $item update_interval_mode 2)
			sub_last_update=$(config_n_get $item last_update 0)
			if [ $(( now - sub_last_update )) -ge $(( sub_update_interval_mode * 3600 )) ]; then
				cfgid=$(uci show ${CONFIG}.$item | head -n 1 | cut -d '.' -sf 2 | cut -d '=' -sf 1)
				cfgids="${cfgids:+$cfgids,}$cfgid"
			fi
		done
		[ -n "$cfgids" ] && { lua $APP_PATH/subscribe.lua start $cfgids cron > /dev/null 2>&1 & }

	fi

	CFG_UPDATE_INT=$(expr "$CFG_UPDATE_INT" + 10)

	sleep 600

done 2>/dev/null
