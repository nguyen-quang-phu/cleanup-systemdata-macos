#!/usr/bin/env bash

set -E
trap cleanup SIGINT SIGTERM ERR EXIT

cleanup() {
	trap - SIGINT SIGTERM ERR EXIT
}

# Default arguments
update=false

usage() {
	cat <<EOF
Usage: $(basename "${BASH_SOURCE[0]}") [-h] [-v] [-u]

A Mac Cleaning up Utility by fwartner
https://github.com/fwartner/mac-cleanup

Available options:

-h, --help       Print this help and exit
-v, --verbose    Print script debug info
-u, --update     Run brew update
EOF
	exit
}

# shellcheck disable=SC2034  # Unused variables left for readability
setup_colors() {
	if [[ -t 2 ]] && [[ -z "${NO_COLOR-}" ]] && [[ "${TERM-}" != "dumb" ]]; then
		NOFORMAT='\033[0m' RED='\033[0;31m' GREEN='\033[0;32m' ORANGE='\033[0;33m' BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' YELLOW='\033[1;33m'
	else
		NOFORMAT='' RED='' GREEN='' ORANGE='' BLUE='' PURPLE='' CYAN='' YELLOW=''
	fi
}

msg() {
	echo >&2 -e "${1-}"
}

die() {
	local msg=$1
	local code=${2-1} # default exit status 1
	msg "$msg"
	exit "$code"
}

parse_params() {
	# default values of variables set from params
	update=false

	while :; do
		case "${1-}" in
		-h | --help) usage ;;
		-v | --verbose) set -x ;;
		--no-color) NO_COLOR=1 ;;
		-u | --update) update=true ;; # update flag
		-n) true ;;                   # This is a legacy option, now default behaviour
		-?*) die "Unknown option: $1" ;;
		*) break ;;
		esac
		shift
	done

	return 0
}

parse_params "$@"
setup_colors

deleteCaches() {
	local cacheName=$1
	shift
	local paths=("$@")
	echo "Initiating cleanup ${cacheName} cache..."
	for folderPath in "${paths[@]}"; do
		if [[ -d ${folderPath} ]]; then
			dirSize=$(du -hs "${folderPath}" | awk '{print $1}')
			echo "Deleting ${folderPath} to free up ${dirSize}..."
			rm -rfv "${folderPath}"
		fi
	done
}

bytesToHuman() {
	b=${1:-0}
	d=''
	s=1
	S=(Bytes {K,M,G,T,E,P,Y,Z}iB)
	while ((b > 1024)); do
		d="$(printf ".%02d" $((b % 1024 * 100 / 1024)))"
		b=$((b / 1024))
		((s++))
	done
	msg "$b$d ${S[$s]} of space was cleaned up"
}

# Ask for the administrator password upfront
sudo -v

HOST=$(whoami)

# Keep-alive sudo until `mac-cleanup.sh` has finished
while true; do
	sudo -n true
	sleep 60
	kill -0 "$$" || exit
done 2>/dev/null &

oldAvailable=$(df / | tail -1 | awk '{print $4}')

msg 'Emptying the Trash 🗑 on all mounted volumes and the main HDD...'
sudo rm -rfv /Volumes/*/.Trashes/* &>/dev/null
sudo rm -rfv ~/.Trash/* &>/dev/null

msg 'Clearing System Cache Files...'
sudo rm -rfv /Library/Caches/* &>/dev/null
sudo rm -rfv /System/Library/Caches/* &>/dev/null
sudo rm -rfv ~/Library/Caches/* &>/dev/null
sudo rm -rfv /private/var/folders/bh/*/*/*/* &>/dev/null

msg 'Clearing System Log Files...'
sudo rm -rfv /private/var/log/asl/*.asl &>/dev/null
sudo rm -rfv /Library/Logs/DiagnosticReports/* &>/dev/null
sudo rm -rfv /Library/Logs/CreativeCloud/* &>/dev/null
sudo rm -rfv /Library/Logs/Adobe/* &>/dev/null
sudo rm -fv /Library/Logs/adobegc.log &>/dev/null
rm -rfv ~/Library/Containers/com.apple.mail/Data/Library/Logs/Mail/* &>/dev/null
rm -rfv ~/Library/Logs/CoreSimulator/* &>/dev/null

if [ -d ~/Library/Logs/JetBrains/ ]; then
  msg 'Clearing all application log files from JetBrains...'
  rm -rfc ~/Library/Logs/JetBrains/*/ &>/dev/null
fi

if [ -d ~/Library/Application\ Support/Adobe/ ]; then
  msg 'Clearing Adobe Cache Files...'
  sudo rm -rfv ~/Library/Application\ Support/Adobe/Common/Media\ Cache\ Files/* &>/dev/null
fi

if [ -d ~/Library/Application\ Support/Google/Chrome/ ]; then
  msg 'Clearing Google Chrome Cache Files...'
  sudo rm -rfv ~/Library/Application\ Support/Google/Chrome/Default/Application\ Cache/* &>/dev/null
fi

msg 'Cleaning up iOS Applications...'
rm -rfv ~/Music/iTunes/iTunes\ Media/Mobile\ Applications/* &>/dev/null

msg 'Removing iOS Device Backups...'
rm -rfv ~/Library/Application\ Support/MobileSync/Backup/* &>/dev/null

msg 'Cleaning up XCode Derived Data and Archives...'
rm -rfv ~/Library/Developer/Xcode/DerivedData/* &>/dev/null
rm -rfv ~/Library/Developer/Xcode/Archives/* &>/dev/null
rm -rfv ~/Library/Developer/Xcode/iOS Device Logs/* &>/dev/null

if type "xcrun" &>/dev/null; then
	msg 'Cleaning up iOS Simulators...'
	osascript -e 'tell application "com.apple.CoreSimulator.CoreSimulatorService" to quit' &>/dev/null
	osascript -e 'tell application "iOS Simulator" to quit' &>/dev/null
	osascript -e 'tell application "Simulator" to quit' &>/dev/null
	xcrun simctl shutdown all &>/dev/null
	xcrun simctl erase all &>/dev/null
fi

# support deleting gradle caches
if [ -d "/Users/${HOST}/.gradle/caches" ]; then
	msg 'Cleaning up Gradle cache...'
	rm -rfv ~/.gradle/caches/ &>/dev/null
fi

# support deleting Dropbox Cache if they exist
if [ -d "/Users/${HOST}/Dropbox" ]; then
	msg 'Clearing Dropbox 📦 Cache Files...'
	sudo rm -rfv ~/Dropbox/.dropbox.cache/* &>/dev/null
fi

if [ -d ~/Library/Application\ Support/Google/DriveFS/ ]; then
  msg 'Clearing Google Drive File Stream Cache Files...'
  killall "Google Drive File Stream"
  rm -rfv ~/Library/Application\ Support/Google/DriveFS/[0-9a-zA-Z]*/content_cache &>/dev/null
fi

if type "composer" &>/dev/null; then
	msg 'Cleaning up composer...'
	composer clearcache &>/dev/null
fi

# Deletes Steam caches, logs, and temp files
# -Astro
if [ -d ~/Library/Application\ Support/Steam/ ]; then
	msg 'Clearing Steam Cache, Log, and Temp Files...'
	rm -rfv ~/Library/Application\ Support/Steam/appcache &>/dev/null
	rm -rfv ~/Library/Application\ Support/Steam/depotcache &>/dev/null
	rm -rfv ~/Library/Application\ Support/Steam/logs &>/dev/null
	rm -rfv ~/Library/Application\ Support/Steam/steamapps/shadercache &>/dev/null
	rm -rfv ~/Library/Application\ Support/Steam/steamapps/temp &>/dev/null
	rm -rfv ~/Library/Application\ Support/Steam/steamapps/download &>/dev/null
fi

# Deletes Minecraft logs
# -Astro
if [ -d ~/Library/Application\ Support/minecraft ]; then
	msg 'Clearing Minecraft Cache and Log Files...'
	rm -rfv ~/Library/Application\ Support/minecraft/logs &>/dev/null
	rm -rfv ~/Library/Application\ Support/minecraft/crash-reports &>/dev/null
	rm -rfv ~/Library/Application\ Support/minecraft/webcache &>/dev/null
	rm -rfv ~/Library/Application\ Support/minecraft/webcache2 &>/dev/null
	rm -rfv ~/Library/Application\ Support/minecraft/crash-reports &>/dev/null
	rm -rfv ~/Library/Application\ Support/minecraft/*.log &>/dev/null
	rm -rfv ~/Library/Application\ Support/minecraft/launcher_cef_log.txt &>/dev/null

	if [ -d ~/Library/Application\ Support/minecraft/.mixin.out ]; then
		rm -rfv ~/Library/Application\ Support/minecraft/.mixin.out &>/dev/null
	fi
fi

# Deletes Lunar Client logs (Minecraft alternate client)
# -Astro
if [ -d ~/.lunarclient ]; then
	msg 'Deleting Lunar Client logs and caches...'
	rm -rfv ~/.lunarclient/game-cache &>/dev/null
	rm -rfv ~/.lunarclient/launcher-cache &>/dev/null
	rm -rfv ~/.lunarclient/logs &>/dev/null
	rm -rfv ~/.lunarclient/offline/*/logs &>/dev/null
	rm -rfv ~/.lunarclient/offline/files/*/logs &>/dev/null
fi

# Deletes Wget logs
# -Astro
if [ -d ~/wget-log ]; then
	msg 'Deleting Wget log and hosts file...'
	rm -fv ~/wget-log &>/dev/null
	rm -fv ~/.wget-hsts &>/dev/null
fi

# Deletes Bash/ZSH logs
# -Astro
msg 'Clearing Bash/ZSH history...'
rm -fv ~/.bash_history &>/dev/null
rm -fv ~/.zhistory &>/dev/null

# Deletes Cacher logs
# I dunno either
# -Astro
if [ -d ~/.cacher ]; then
	msg 'Deleting Cacher logs...'
	rm -rfv ~/.cacher/logs
fi

# Deletes Android (studio?) cache
# -Astro
if [ -d ~/.android ]; then
	msg 'Deleting Android cache...'
	rm -rfv ~/.android/cache
fi

# Clears Gradle caches
# -Astro
if [ -d ~/.gradle ]; then
	msg 'Clearing Gradle caches...'
	rm -rfv ~/.gradle/caches
fi

# Deletes Kite Autocomplete logs
# -Astro
if [ -d ~/.kite ]; then
	msg 'Deleting Kite logs...'
	rm -rfv ~/.kite/logs
fi

if type "brew" &>/dev/null; then
	if [ "$update" = true ]; then
		msg 'Updating Homebrew Recipes...'
		brew update &>/dev/null
		msg 'Upgrading and removing outdated formulae...'
		brew upgrade &>/dev/null
	fi
	msg 'Cleaning up Homebrew Cache...'
	brew cleanup -s &>/dev/null
	rm -rfv "$(brew --cache)"
	brew tap --repair &>/dev/null
fi

if type "gem" &>/dev/null; then
	msg 'Cleaning up any old versions of gems'
	gem cleanup &>/dev/null
fi

if type "docker" &>/dev/null; then
	if ! docker ps >/dev/null 2>&1; then
		open --background -a Docker
	fi
	msg 'Cleaning up Docker'
	docker system prune -af &>/dev/null
fi

if [ "$PYENV_VIRTUALENV_CACHE_PATH" ]; then
	msg 'Removing Pyenv-VirtualEnv Cache...'
	rm -rfv "$PYENV_VIRTUALENV_CACHE_PATH" &>/dev/null
fi

if type "npm" &>/dev/null; then
	msg 'Cleaning up npm cache...'
	npm cache clean --force &>/dev/null
fi

if type "yarn" &>/dev/null; then
	msg 'Cleaning up Yarn Cache...'
	yarn cache clean --force &>/dev/null
fi

if type "pod" &>/dev/null; then
	msg 'Cleaning up Pod Cache...'
	pod cache clean --all &>/dev/null
fi

# Deletes all Microsoft Teams Caches and resets it to default - can fix also some performance issues
# -Astro
if [ -d ~/Library/Application\ Support/Microsoft/Teams ]; then
	# msg 'Deleting Microsoft Teams logs and caches...'
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/IndexedDB &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/Cache &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/Application\ Cache &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/Code\ Cache &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/blob_storage &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/databases &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/gpucache &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/Local\ Storage &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/tmp &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/*logs*.txt &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/watchdog &>/dev/null
	rm -rfv ~/Library/Application\ Support/Microsoft/Teams/*watchdog*.json &>/dev/null
fi

msg 'Cleaning up DNS cache...'
sudo dscacheutil -flushcache &>/dev/null
sudo killall -HUP mDNSResponder &>/dev/null

msg 'Purging inactive memory...'
sudo purge &>/dev/null

msg "${GREEN}Success!${NOFORMAT}"

newAvailable=$(df / | tail -1 | awk '{print $4}')
count=$((newAvailable - oldAvailable))
bytesToHuman $count

cleanup
