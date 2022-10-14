#!/bin/bash


NameOfProgram="WG-IPToHome"

function isRoot() {
	if [ "${EUID}" -ne 0 ]; then
		echo "ERREUR: Vous devez executer ce script en tant que root."
		exit 1
	fi
}

function checkVirt() {
	if [ "$(systemd-detect-virt)" == "openvz" ]; then
		echo "ERREUR: OpenVZ n'est pas supporté."
		exit 1
	fi

	if [ "$(systemd-detect-virt)" == "lxc" ]; then
		echo "ERREUR: LXC n'est pas supporté."
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

function initialCheck() {
	isRoot
	checkVirt
	checkOS
}

function installQuestions() {
	echo ""
	echo "Bienvenue dans le programme d'installation de $NameOfProgram (Serveur)."
	echo ""
	echo "Je dois vous poser quelques questions avant de commencer la configuration."
	echo ""

	#Détection automatique de l'IP publique
	SERVER_PUB_IP=$(ip -4 addr | sed -ne 's|^.* inet \([^/]*\)/.* scope global.*$|\1|p' | awk '{print $1}' | head -1)
	read -rp "Adresse IPv4 publique principale : " -e -i "${SERVER_PUB_IP}" SERVER_PUB_IP
	
	#Détection automatique de l'interface réseau
	SERVER_NIC="$(ip -4 route ls | grep default | grep -Po '(?<=dev )(\S+)' | head -1)"
	until [[ ${SERVER_PUB_NIC} =~ ^[a-zA-Z0-9_]+$ ]]; do
		read -rp "Interface publique: " -e -i "${SERVER_NIC}" SERVER_PUB_NIC
	done

	# Configuration automatique
	RANDOM_PORT=$(shuf -i49152-65535 -n1)
	SERVER_WG_NIC='wg0'
	SERVER_WG_IPV4='172.30.254.1'
	SERVER_WG_IPV6='fd42:42:42::1'
	SERVER_PORT="${RANDOM_PORT}"
	CLIENT_DNS_1="208.67.222.222" #OPENDNS
	CLIENT_DNS_2="208.67.220.220" #OPENDNS
	
	echo ""
	echo "Super, c'était tout ce dont j'avais besoin. Nous sommes prêts à configurer votre serveur $NameOfProgram."
	echo "Récapitulatif : "
	echo " - IPv4 principale : $SERVER_PUB_IP"
	echo " - Interface publique : $SERVER_NIC"
	echo " - Port de WG : $SERVER_PORT"
	echo " - Interface de WG : $SERVER_WG_NIC"
	echo " - Sous réseau WG : $SERVER_WG_IPV4"
	echo " - DNS WG : $CLIENT_DNS_1 et $CLIENT_DNS_2"
	read -n1 -r -p "Appuyez sur n'importe quelle touche pour continuer..."

}

function installWireGuard() {
	# Demande les questions
	installQuestions
	
	# Installation de WireGuard, ses outils et modules
	if [[ ${OS} == 'ubuntu' ]] || [[ ${OS} == 'debian' && ${VERSION_ID} -gt 10 ]]; then
		apt-get update
		apt-get install -y wireguard iptables resolvconf qrencode
	elif [[ ${OS} == 'debian' ]]; then
		if ! grep -rqs "^deb .* buster-backports" /etc/apt/; then
			echo "deb http://deb.debian.org/debian buster-backports main" >/etc/apt/sources.list.d/backports.list
			apt-get update
		fi
		apt update
		apt-get install -y iptables resolvconf qrencode
		apt-get install -y -t buster-backports wireguard
	elif [[ ${OS} == 'fedora' ]]; then
		if [[ ${VERSION_ID} -lt 32 ]]; then
			dnf install -y dnf-plugins-core
			dnf copr enable -y jdoss/wireguard
			dnf install -y wireguard-dkms
		fi
		dnf install -y wireguard-tools iptables qrencode
	elif [[ ${OS} == 'centos' ]]; then
		yum -y install epel-release elrepo-release
		if [[ ${VERSION_ID} -eq 7 ]]; then
			yum -y install yum-plugin-elrepo
		fi
		yum -y install kmod-wireguard wireguard-tools iptables qrencode
	elif [[ ${OS} == 'oracle' ]]; then
		dnf install -y oraclelinux-developer-release-el8
		dnf config-manager --disable -y ol8_developer
		dnf config-manager --enable -y ol8_developer_UEKR6
		dnf config-manager --save -y --setopt=ol8_developer_UEKR6.includepkgs='wireguard-tools*'
		dnf install -y wireguard-tools qrencode iptables
	elif [[ ${OS} == 'arch' ]]; then
		pacman -S --needed --noconfirm wireguard-tools qrencode
	fi

	# Vérification que le répertoire existe (cela ne semble pas être le cas sur fedora)
	mkdir /etc/wireguard >/dev/null 2>&1
	chmod 600 -R /etc/wireguard/

	SERVER_PRIV_KEY=$(wg genkey)
	SERVER_PUB_KEY=$(echo "${SERVER_PRIV_KEY}" | wg pubkey)

	# Enregistrement des paramètres WireGuard
	echo "SERVER_PUB_IP=${SERVER_PUB_IP}
SERVER_PUB_NIC=${SERVER_PUB_NIC}
SERVER_WG_NIC=${SERVER_WG_NIC}
SERVER_WG_IPV4=${SERVER_WG_IPV4}
SERVER_WG_IPV6=${SERVER_WG_IPV6}
SERVER_PORT=${SERVER_PORT}
SERVER_PRIV_KEY=${SERVER_PRIV_KEY}
SERVER_PUB_KEY=${SERVER_PUB_KEY}
CLIENT_DNS_1=${CLIENT_DNS_1}
CLIENT_DNS_2=${CLIENT_DNS_2}" >/etc/wireguard/params

	# Ajout et configuration de l'interface au serveur
	echo "[Interface]
Address = ${SERVER_WG_IPV4}/24
ListenPort = ${SERVER_PORT}
PrivateKey = ${SERVER_PRIV_KEY}" >"/etc/wireguard/${SERVER_WG_NIC}.conf"
	
	# Activation du routage sur le serveur
	echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
net.ipv4.conf.all.proxy_arp=1
net.ipv6.conf.all.forwarding=1" >/etc/sysctl.d/wg.conf
	sysctl --system
	
	#Activation de l'interface
	systemctl start "wg-quick@${SERVER_WG_NIC}"
	systemctl enable "wg-quick@${SERVER_WG_NIC}"

	#Création du premier client
	newClient

	# Vérification si WireGuard est en cours d'exécution
	systemctl is-active --quiet "wg-quick@${SERVER_WG_NIC}"
	WG_RUNNING=$?
	# WireGuard pourrait ne pas fonctionner si nous mettions à jour le noyau. Dites à l'utilisateur de redémarrer
	if [[ ${WG_RUNNING} -ne 0 ]]; then
		echo -e "\nATTENTION: WireGuard ne semble pas fonctionner."
		echo -e "Vous pouvez vérifier si WireGuard fonctionne avec: systemctl status wg-quick@${SERVER_WG_NIC}"
		echo -e "Si vous obtenez quelque chose comme \"Cannot find device ${SERVER_WG_NIC}\", s'il vous plaît redémarrez!"
	fi

}

function clientIP(){

	read -rp "Adresse IPv4 publique pour le client (FORMAT: 1.2.3.4): " -e CLIENT_IP4

}

function newClient() {

	if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then

	ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"

	HOME_DIR='/home/WGIPToHome'
	mkdir $HOME_DIR

	CLIENT_NAME="WGIPToHome"

	# Generate key pair for the client
	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
	CLIENT_PRE_SHARED_KEY=$(wg genpsk)
	

	# Configuration Serveur
	echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_IP4}/32" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"

	# Configuration Client
	echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_IP4}/32
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}
[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0,::/0" >>"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")
	echo "La configuration client est disponible à cet emplacement : ${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"

	else
	echo "ERREUR: Mauvaise IP"
	clientIP
	fi

}

# Vérification initiale
initialCheck
# Vérification de si Wireguard est déjà installé
if [[ -e /etc/wireguard/params ]]; then
	source /etc/wireguard/params
	echo "WireGuard déjà installé."
else
	installWireGuard
fi