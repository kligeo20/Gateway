#!/usr/bin/env bash
set -euo pipefail
# -e : stoppe le script si une commande échoue
# -u : erreur si une variable non définie est utilisée
# -o pipefail : une erreur dans un pipe fait échouer tout le pipe

WG_DIR="/etc/wireguard"
WG_IF="wg0"
WG_CONF="$WG_DIR/$WG_IF.conf"
# Variables de base : emplacement du fichier wg0.conf

# ---------------------------------------------------------
# 1) Génération des clés du peer
# ---------------------------------------------------------
priv=$(wg genkey)              # Clé privée du peer
pub=$(echo "$priv" | wg pubkey) # Clé publique du peer
psk=$(wg genpsk)               # PresharedKey optionnelle (sécurité supplémentaire)

# ---------------------------------------------------------
# 2) Trouver la prochaine IP disponible dans le réseau WG
# ---------------------------------------------------------
# On récupère toutes les IP déjà utilisées dans AllowedIPs
used_ips=$(grep AllowedIPs "$WG_CONF" | awk '{print $3}' | sed 's/\/32//')

# On cherche la première IP libre dans 10.77.0.X
for i in $(seq 2 254); do
    candidate="10.77.0.$i"
    # Si l'IP n'est pas déjà utilisée → on la prend
    if ! echo "$used_ips" | grep -q "$candidate"; then
        peer_ip="$candidate"
        break
    fi
done

# ---------------------------------------------------------
# 3) Récupération des informations du serveur WireGuard
# ---------------------------------------------------------
server_pub=$(wg show "$WG_IF" public-key)   # Clé publique du serveur
server_ip=$(hostname -I | awk '{print $1}') # IP publique/locale du serveur
server_port=$(grep ListenPort "$WG_CONF" | awk '{print $3}') # Port WG

# ---------------------------------------------------------
# 4) Génération de la configuration client (wg-client.conf)
# ---------------------------------------------------------
client_conf=$(cat <<EOF
[Interface]
PrivateKey = $priv
Address = $peer_ip/32
DNS = 1.1.1.1

[Peer]
PublicKey = $server_pub
PresharedKey = $psk
Endpoint = $server_ip:$server_port
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF
)
# Cette config est affichée dans Cockpit + téléchargeable

# ---------------------------------------------------------
# 5) Génération du QR code en Base64
# ---------------------------------------------------------
# qrencode génère un PNG → base64 pour affichage dans Cockpit
qr_png=$(echo "$client_conf" | qrencode -o - -t PNG | base64 -w0)

# ---------------------------------------------------------
# 6) Ajout du peer dans wg0.conf
# ---------------------------------------------------------
# On ajoute un bloc complet [Peer] à la fin du fichier
{
    echo ""
    echo "[Peer]"
    echo "PublicKey = $pub"
    echo "PresharedKey = $psk"
    echo "AllowedIPs = $peer_ip/32"
} >> "$WG_CONF"

# ---------------------------------------------------------
# 7) Rechargement de WireGuard
# ---------------------------------------------------------
# syncconf applique la configuration sans couper l'interface
wg syncconf "$WG_IF" <(wg-quick strip "$WG_IF")

# ---------------------------------------------------------
# 8) Sortie structurée pour Cockpit
# ---------------------------------------------------------
# Cockpit lit ces marqueurs pour extraire la config et le QR code
echo "CONF_BEGIN"
echo "$client_conf"
echo "CONF_END"

echo "PNG_BEGIN"
echo "$qr_png"
echo "PNG_END"
