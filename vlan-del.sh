#!/usr/bin/env bash
set -euo pipefail

# ------------------------------------------------------------
# Script : vlan-del.sh
# Objectif : supprimer un VLAN dans /etc/network/interfaces
# Usage : vlan-del.sh <interface>
# Exemple : vlan-del.sh eth1.10
# ------------------------------------------------------------

# Interface VLAN à supprimer (ex: eth1.10)
IFACE="$1"

# Fichier de configuration réseau
CONF="/etc/network/interfaces"

# Fichier temporaire pour écrire la nouvelle config
TMP=$(mktemp)

# ------------------------------------------------------------
# Suppression du bloc correspondant à l'interface VLAN
# ------------------------------------------------------------
# Le fichier interfaces est structuré en blocs :
#
# auto eth1.10
# iface eth1.10 inet static
#     address 192.168.10.1
#     netmask 255.255.255.0
#
# On doit supprimer *tout le bloc*, pas seulement une ligne.
#
# La logique :
# - Quand on rencontre "auto <iface>" → on active skip=1
# - Tant que skip=1 → on ignore les lignes
# - Dès qu'on rencontre un autre "auto X" → skip repasse à 0
# ------------------------------------------------------------

awk -v iface="$IFACE" '
  BEGIN { skip=0 }

  # Début d'un bloc "auto <interface>"
  /^auto / {
    if ($2 == iface) {
      skip=1      # On commence à ignorer ce bloc
    } else {
      skip=0      # On imprime les autres blocs normalement
    }
  }

  # Si skip=0 → on imprime la ligne
  skip == 0 { print }

' "$CONF" > "$TMP"

# Remplace l'ancien fichier par le nouveau
mv "$TMP" "$CONF"

# ------------------------------------------------------------
# Redémarrage du service réseau
# ------------------------------------------------------------
# Sur certaines distributions, "systemctl restart networking"
# peut échouer sans conséquence → on ignore l'erreur.
# ------------------------------------------------------------
systemctl restart networking || true

# Message final
echo "VLAN ${IFACE} supprimé."
