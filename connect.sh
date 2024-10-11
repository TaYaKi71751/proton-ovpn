#!/bin/bash

__APP_VERSION__="web-account@5.0.153.3"
__UID__=""
__LOCALE__="en_US"
__USER_AGENT__="Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:132.0) Gecko/20100101 Firefox/132.0"

__COOKIE_PATHS__="$(find $HOME -name 'cookies.sqlite' -type f)"
__COOKIE_PATHS__="${__COOKIE_PATHS__}
$(find $HOME -name 'Cookies' -type f)"
__COOKIE_STRING_RESULT__=""
__COOKIE_STRING_TEMP__=""
while IFS= read -r __COOKIE_PATH__
do
	if ( echo $__COOKIE_PATH__ | grep 'cookies.sqlite' );then
	 __COOKIE_STRING_TEMP__="$(sqlite3 << EOF
.open "${__COOKIE_PATH__}"
SELECT name,value FROM moz_cookies WHERE host = 'account.proton.me';
EOF
)"
  while IFS= read -r __COOKIE_STRING__
		do
			if ( echo $__COOKIE_STRING__ | grep 'AUTH-' > /dev/null );then
				__UID__="$(echo $__COOKIE_STRING__ | cut -f1 -d '|' | rev | cut -f1 -d '-' | rev )"
			fi
			__COOKIE_STRING_RESULT__="${__COOKIE_STRING_RESULT__}$(echo $__COOKIE_STRING__ | sed 's/|/=/g');"
		done < <(printf '%s\n' "${__COOKIE_STRING_TEMP__}")
	fi
done < <(printf '%s\n' "${__COOKIE_PATHS__}")

# https://github.com/Kr0wZ/NeutrOSINT/blob/master/neutrosint.py
# https://gist.github.com/fusetim/1a1ee1bdf821a45361f346e9c7f41e5a?permalink_comment_id=5089762
__SESSION_RESPONSE__="$(curl -LsSf 'https://account.proton.me/' -H "x-pm-appversion: ${__APP_VERSION__}" -H "x-pm-locale: ${__LOCALE__}" --user-agent "${__USER_AGENT__}" --cookie "$__COOKIE_STRING_RESULT__" -v 2>&1)"
__SET_COOKIES__=""
while IFS= read -r __RESPONSE_LINE__
do
	if ( echo $__RESPONSE_LINE__ | grep 'set-cookie' > /dev/null );then
		__SET_COOKIES__="${__SET_COOKIES__}
$__RESPONSE_LINE__"
	fi
done < <(printf '%s\n' "${__SESSION_RESPONSE__}")
while IFS= read -r __SET_COOKIE__
do
	if ( echo $__SET_COOKIE__ | grep '=' > /dev/null);then 
		__COOKIE_STRING_RESULT__="${__COOKIE_STRING_RESULT__}$(echo $__SET_COOKIE__ | cut -f1 -d ';' | rev | cut -f1 -d ':' | tr -d ' ' | rev);"
	fi
done < <(printf '%s\n' "${__SET_COOKIES__}")
__AUTH_INFO__="$(node << EOF
 const result = JSON.parse(\`$(curl -X PUT 'https://account.proton.me/api/vpn/settings/reset' --compressed --user-agent "${__USER_AGENT__}" -H "x-pm-appversion: ${__APP_VERSION__}" -H "x-pm-locale: ${__LOCALE__}" -H "x-pm-uid: ${__UID__}" --cookie "${__COOKIE_STRING_RESULT__}")\`);
	console.log(\`\${result.VPNSettings.Name}\\n\${result.VPNSettings.Password}\`)
EOF
)"
rm /tmp/askpass.txt
while IFS= read -r __LINE__
do
	echo "$__LINE__" >> /tmp/askpass.txt
done < <(printf '%s\n' "${__AUTH_INFO__}")

#!/bin/bash
# exec 2>&1
# exec > >(tee file.log)

SHELL_RUN_COMMANDS=`find ${ORIG_HOME} -maxdepth 1 -name '.*shrc'`
for shrc in ${SHELL_RUN_COMMANDS[@]};do
	echo "source ${shrc}"
	source ${shrc}
done

function auto_path() {
	TARGET_PATHS="$(find / -name "$1" -type f)"
	echo $TARGET_PATHS
	while IFS= read -r line
	do
		export PATH=${PATH}:$(dirname ${line})
	done < <(printf '%s\n' "$TARGET_PATHS")
}
auto_path openvpn
auto_path node
auto_path kdialog
auto_path zenity

ORIG_HOME=${HOME}

function check_openvpn(){
	export OPENVPN_USABLE=`find / -name 'openvpn' -type f -exec {} --help \;`
	if ( which openvpn );then
		export OPENVPN_USABLE="true"
	else
		unset OPENVPN_USABLE
	fi
}
check_openvpn

# https://github.com/ValveSoftware/SteamOS/issues/1039
function check_kdialog(){
	if ( which kdialog );then
		export KDIALOG_USABLE="true"
	else
		unset KDIALOG_USABLE
	fi
}

function check_zenity(){
	if ( which zenity );then
		export ZENITY_USABLE="true"
	else
		unset ZENITY_USABLE="true"
	fi
	env | grep STEAM_DECK\= && unset $ZENITY_USABLE
}
check_kdialog
check_zenity

if [ -z "${OPENVPN_USABLE}" ];then
	if [ -n "${KDIALOG_USABLE}" ];then
		kdialog --error 'openvpn binary not found. please install openvpn.'
	elif [ -n "${ZENITY_USABLE}" ];then
		zenity --error --text='openvpn binary not found. please install openvpn.'
	fi
fi

if [ -z "${OPENVPN_CONFIG_PATH}" ];then
	if [ -n "${KDIALOG_USABLE}" ];then
		kdialog --error 'openvpn config not found. please select openvpn config.'
	elif [ -n "${ZENITY_USABLE}" ];then
		zenity --error --text='openvpn config not found. please select openvpn config.'
	fi
fi

function get_password(){
	if [ -n "${KDIALOG_USABLE}" ];then
		kdialog --password 'Enter Password'
	elif [ -n "${ZENITY_USABLE}" ];then
		zenity --password
	fi
}


function check_sudo() {
	if ( `sudo -nv` );then
		return "0"
	fi
	export SUDO_PASSWORD=$(get_password)
	# https://github.com/SteamDeckHomebrew/decky-installer/releases/latest/download/user_install_script.sh…
	if ( echo ${SUDO_PASSWORD} | sudo -S echo A | grep A );then
		export SUDO_PASSWORD=${SUDO_PASSWORD}
	else
		check_sudo
	fi
}
check_sudo

# https://superuser.com/questions/553932/how-to-check-if-i-have-sudo-access
function sudo_executor(){
	if ( `sudo -nv` );then
		sudo $@
	else
		echo ${SUDO_PASSWORD} | sudo -S $@
	fi
}


TARGET_CIPHER="$(cat "${OPENVPN_CONFIG_PATH}" | grep "^cipher" | rev | cut -d ' ' -f1 | rev | tr -d ' ' | tr -d '\r' | tr -d '\n')"
function run_openvpn(){
		sudo openvpn \
			--data-ciphers ${TARGET_CIPHER} \
			--data-ciphers-fallback ${TARGET_CIPHER} \
			--config "$OPENVPN_CONFIG_PATH" \
			--ask-pass-path /tmp/askpass.txt
EOF
}
echo $TARGET_CIPHER
sudo_executor sysctl -w net.ipv6.conf.all.disable_ipv6=1

# https://www.reddit.com/r/PrivateInternetAccess/comments/j1iyl7/openvpn_client_no_longer_connects_cipher_not/?rdt=54856
run_openvpn
