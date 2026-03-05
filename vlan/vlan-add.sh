#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Script : vlan-add.sh
# Objectif : ajouter un VLAN dans /etc/network/interfaces
# Usage : vlan-add.sh <parent> <vid> <ip> <mask>
# Exemple : vlan-add.sh eth1 10 192.168.10.1 255.255.255.0
# ------------------------------------------------------------

# Arguments
PARENT="$1"   # Interface parent (ex: eth1)
VID="$2"      # VLAN ID (ex: 10)
IP="$3"       # Adresse IP du VLAN
MASK="$4"     # Masque réseau

# Fichier de configuration réseau
CONF="/etc/network/interfaces"

# ------------------------------------------------------------
# Construction du bloc VLAN à ajouter
# ------------------------------------------------------------
# Le bloc suit la syntaxe Debian classique :
#
# auto eth1.10
# iface eth1.10 inet static
#     address 192.168.10.1
#     netmask 255.255.255.0
#     vlan-raw-device eth1
#
# On utilise un heredoc pour générer le bloc proprement.
# ------------------------------------------------------------

BLOCK=$(cat <<EOF

auto ${PARENT}.${VID}
iface ${PARENT}.${VID} inet static
    address ${IP}
    netmask ${MASK}
    vlan-raw-device ${PARENT}
EOF
)

# ------------------------------------------------------------
# Ajout du bloc à la fin du fichier interfaces
# ------------------------------------------------------------
# On utilise >> pour ajouter sans écraser.
# Le bloc commence par une ligne vide pour séparer proprement.
# ------------------------------------------------------------
echo "$BLOCK" >> "$CONF"

# ------------------------------------------------------------
# Redémarrage du service réseau
# ------------------------------------------------------------
# Certaines distributions renvoient un code d'erreur même si
# le redémarrage est correct → on ignore l'erreur.
# ------------------------------------------------------------
systemctl restart networking || true

# Message final
echo "VLAN ${VID} ajouté sur ${PARENT}.${VID} (${IP}/${MASK})."
