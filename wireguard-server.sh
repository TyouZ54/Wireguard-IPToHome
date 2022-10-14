#!/bin/bash

ROUGE='\033[0;31m'
ORANGE='\033[0;33m'
VERT='\033[0;32m'
NC='\033[0m'

function isRoot() {
	if [ "${EUID}" -ne 0 ]; then
		echo "${ROUGE}[ERREUR]${NC} Vous devez executer ce script en tant que root."
		exit 1
	else
		echo "${VERT}[OK]${NC} Execution du script en tant que root..."
	fi
}

function checkVirt() {
	if [ "$(systemd-detect-virt)" == "openvz" ]; then
		echo "${ROUGE}[ERREUR]${NC} OpenVZ n'est pas supporté."
		exit 1
	fi

	if [ "$(systemd-detect-virt)" == "lxc" ]; then
		echo "${ROUGE}[ERREUR]${NC} LXC n'est pas supporté."
		exit 1
	fi
}

function checkOS() {
	# Check OS version
	if [[ -e /etc/debian_version ]]; then
		source /etc/os-release
		OS="${ID}" # debian or ubuntu
		if [[ ${ID} == "debian" || ${ID} == "raspbian" ]]; then
			if [[ ${VERSION_ID} -lt 10 ]]; then
				echo "Votre version de debian (${VERSION_ID}) n'est pas supporte. Merci d'utiliser Debian 10 au minimum"
				exit 1
			fi
			OS=debian # overwrite if raspbian
		fi
	elif [[ -e /etc/fedora-release ]]; then
		source /etc/os-release
		OS="${ID}"
	elif [[ -e /etc/centos-release ]]; then
		source /etc/os-release
		OS=centos
	elif [[ -e /etc/oracle-release ]]; then
		source /etc/os-release
		OS=oracle
	elif [[ -e /etc/arch-release ]]; then
		OS=arch
	else
		echo "Vous devez utiliser une machine sous Debian, Ubuntu, Fedora, CentOS, Oracle ou Arch Linux"
		exit 1
	fi
}

function initialCheck() {
	isRoot
	checkVirt
	checkOS
}