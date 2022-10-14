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
	if pgrep firewalld; then
		FIREWALLD_IPV4_ADDRESS=$(echo "${SERVER_WG_IPV4}" | cut -d"." -f1-3)".0"
		FIREWALLD_IPV6_ADDRESS=$(echo "${SERVER_WG_IPV6}" | sed 's/:[^:]*$/:0/')
		echo "PostUp = firewall-cmd --add-port ${SERVER_PORT}/udp && firewall-cmd --add-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS}/24 masquerade' && firewall-cmd --add-rich-rule='rule family=ipv6 source address=${FIREWALLD_IPV6_ADDRESS}/24 masquerade'
PostDown = firewall-cmd --remove-port ${SERVER_PORT}/udp && firewall-cmd --remove-rich-rule='rule family=ipv4 source address=${FIREWALLD_IPV4_ADDRESS}/24 masquerade' && firewall-cmd --remove-rich-rule='rule family=ipv6 source address=${FIREWALLD_IPV6_ADDRESS}/24 masquerade'" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
	else
		echo "PostUp = iptables -A FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT; iptables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE; ip6tables -A FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; ip6tables -t nat -A POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${SERVER_PUB_NIC} -o ${SERVER_WG_NIC} -j ACCEPT; iptables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE; ip6tables -D FORWARD -i ${SERVER_WG_NIC} -j ACCEPT; ip6tables -t nat -D POSTROUTING -o ${SERVER_PUB_NIC} -j MASQUERADE" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
	fi
	
	# Activation du routage sur le serveur
	echo "net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1" >/etc/sysctl.d/wg.conf
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

function newClient() {
	ENDPOINT="${SERVER_PUB_IP}:${SERVER_PORT}"
	echo ""
	echo "Tell me a name for the client."
	echo "The name must consist of alphanumeric character. It may also include an underscore or a dash and can't exceed 15 chars."
	until [[ ${CLIENT_NAME} =~ ^[a-zA-Z0-9_-]+$ && ${CLIENT_EXISTS} == '0' && ${#CLIENT_NAME} -lt 16 ]]; do
		read -rp "Client name: " -e CLIENT_NAME
		CLIENT_EXISTS=$(grep -c -E "^### Client ${CLIENT_NAME}\$" "/etc/wireguard/${SERVER_WG_NIC}.conf")
		if [[ ${CLIENT_EXISTS} == '1' ]]; then
			echo ""
			echo "A client with the specified name was already created, please choose another name."
			echo ""
		fi
	done
	for DOT_IP in {2..254}; do
		DOT_EXISTS=$(grep -c "${SERVER_WG_IPV4::-1}${DOT_IP}" "/etc/wireguard/${SERVER_WG_NIC}.conf")
		if [[ ${DOT_EXISTS} == '0' ]]; then
			break
		fi
	done
	if [[ ${DOT_EXISTS} == '1' ]]; then
		echo ""
		echo "The subnet configured supports only 253 clients."
		exit 1
	fi
	BASE_IP=$(echo "$SERVER_WG_IPV4" | awk -F '.' '{ print $1"."$2"."$3 }')
	until [[ ${IPV4_EXISTS} == '0' ]]; do
		read -rp "Client's WireGuard IPv4: ${BASE_IP}." -e -i "${DOT_IP}" DOT_IP
		CLIENT_WG_IPV4="${BASE_IP}.${DOT_IP}"
		IPV4_EXISTS=$(grep -c "$CLIENT_WG_IPV4/24" "/etc/wireguard/${SERVER_WG_NIC}.conf")
		if [[ ${IPV4_EXISTS} == '1' ]]; then
			echo ""
			echo "A client with the specified IPv4 was already created, please choose another IPv4."
			echo ""
		fi
	done
	BASE_IP=$(echo "$SERVER_WG_IPV6" | awk -F '::' '{ print $1 }')
	until [[ ${IPV6_EXISTS} == '0' ]]; do
		read -rp "Client's WireGuard IPv6: ${BASE_IP}::" -e -i "${DOT_IP}" DOT_IP
		CLIENT_WG_IPV6="${BASE_IP}::${DOT_IP}"
		IPV6_EXISTS=$(grep -c "${CLIENT_WG_IPV6}/64" "/etc/wireguard/${SERVER_WG_NIC}.conf")
		if [[ ${IPV6_EXISTS} == '1' ]]; then
			echo ""
			echo "A client with the specified IPv6 was already created, please choose another IPv6."
			echo ""
		fi
	done
	# Generate key pair for the client
	CLIENT_PRIV_KEY=$(wg genkey)
	CLIENT_PUB_KEY=$(echo "${CLIENT_PRIV_KEY}" | wg pubkey)
	CLIENT_PRE_SHARED_KEY=$(wg genpsk)
	# Home directory of the user, where the client configuration will be written
	if [ -e "/home/${CLIENT_NAME}" ]; then
		# if $1 is a user name
		HOME_DIR="/home/${CLIENT_NAME}"
	elif [ "${SUDO_USER}" ]; then
		# if not, use SUDO_USER
		if [ "${SUDO_USER}" == "root" ]; then
			# If running sudo as root
			HOME_DIR="/root"
		else
			HOME_DIR="/home/${SUDO_USER}"
		fi
	else
		# if not SUDO_USER, use /root
		HOME_DIR="/root"
	fi
	# Create client file and add the server as a peer
	echo "[Interface]
PrivateKey = ${CLIENT_PRIV_KEY}
Address = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128
DNS = ${CLIENT_DNS_1},${CLIENT_DNS_2}
[Peer]
PublicKey = ${SERVER_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
Endpoint = ${ENDPOINT}
AllowedIPs = 0.0.0.0/0,::/0" >>"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
	# Add the client as a peer to the server
	echo -e "\n### Client ${CLIENT_NAME}
[Peer]
PublicKey = ${CLIENT_PUB_KEY}
PresharedKey = ${CLIENT_PRE_SHARED_KEY}
AllowedIPs = ${CLIENT_WG_IPV4}/32,${CLIENT_WG_IPV6}/128" >>"/etc/wireguard/${SERVER_WG_NIC}.conf"
	wg syncconf "${SERVER_WG_NIC}" <(wg-quick strip "${SERVER_WG_NIC}")
	echo -e "\nHere is your client config file as a QR Code:"
	qrencode -t ansiutf8 -l L <"${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
	echo "It is also available in ${HOME_DIR}/${SERVER_WG_NIC}-client-${CLIENT_NAME}.conf"
}

# Vérification initiale
initialCheck
# Vérification de si Wireguard est déjà installé
if [[ -e /etc/wireguard/params ]]; then
	source /etc/wireguard/params
	echo "already installed"
else
	installWireGuard
fi