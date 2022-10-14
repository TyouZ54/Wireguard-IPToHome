# Wireguard-IPToHome <img src="https://play-lh.googleusercontent.com/tixGgVipnsaKeGQzykJfgSEhUc_YYMSsr3gwBuPTpXb2F1BKPVzv5OxfCrpS8OAXXh8" alt="WireGuard" width="50"/>
#Développement en cours

Prérequis:
 - Un serveur VPS ou dédié qui possède une IP publique principale et une IP en ALIAS (Celle-ci ne doit pas être configurée sur le serveur)
 - Un serveur chez soit (Fonctionne aussi sous Windows)

Permet la mise en place d'un serveur Wireguard afin de transporter son IP public depuis un VPS vers un serveur à la maison ou autre part

Comment l'installer ? 
 - Côté serveur (Reçevant les IPs de l'ISP) : ```curl https://raw.githubusercontent.com/TyouZ54/Wireguard-IPToHome/main/wireguard-server.sh | sudo bash```
 - Côté client (Serveur chez soit) : ```curl https://raw.githubusercontent.com/TyouZ54/Wireguard-IPToHome/main/wireguard-client.sh | sudo bash```
