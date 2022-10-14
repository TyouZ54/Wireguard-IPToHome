#!/bin/bash

NameOfProgram="WG-IPToHome"

function isRoot() {

	if [ "${EUID}" -ne 0 ]; then

		echo "ERREUR: Vous devez executer ce script en tant que root."
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
				echo "ERREUR: Votre version de debian (${VERSION_ID}) n'est pas supporte. Merci d'utiliser Debian 10 au minimum"
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
		echo "ERREUR: Vous devez utiliser une machine sous Debian, Ubuntu, Fedora, CentOS, Oracle ou Arch Linux"
		exit 1
	fi
}

function installQuestions() {

    read -rp "Adresse IPv4 publique du serveur distant: " -e REMOTEIP
    read -rp "Nom d'utilisateur du serveur distant: " -e REMOTEUSER

}

function installClient(){

	# Demande les questions
	installQuestions
    
	# Installation de WireGuard, ses outils et modules
	if [[ ${OS} == 'ubuntu' ]] || [[ ${OS} == 'debian' && ${VERSION_ID} -gt 10 ]]; then
		apt-get update
		apt-get install -y wireguard wireguard-tools resolvconf
	elif [[ ${OS} == 'debian' ]]; then
		apt update
		apt-get install -y wireguard wireguard-tools resolvconf
	elif [[ ${OS} == 'fedora' ]]; then
		dnf install -y wireguard wireguard-tools resolvconf
	elif [[ ${OS} == 'centos' ]]; then
		yum -y install wireguard wireguard-tools resolvconf
	elif [[ ${OS} == 'oracle' ]]; then
		dnf install -y wireguard wireguard-tools resolvconf
	elif [[ ${OS} == 'arch' ]]; then
		pacman -S --needed --noconfirm wireguard wireguard-tools resolvconf
	fi

    REMOTEFILE='/home/WGIPToHome/wg0-client-WGIPToHome.conf'
    LOCALFILE='/etc/wireguard/wg0.conf'

    scp $REMOTEUSER@$REMOTEIP:$REMOTEFILE $LOCALFILE
    ExitCode=$?

    systemctl enable wg-quick@wg0 --now

    sleep 3

    NowIP=$(curl ifconfig.me)
    echo "Votre IP Publique est maintenant : $NowIP"

}