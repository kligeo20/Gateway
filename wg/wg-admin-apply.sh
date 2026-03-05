#!/usr/bin/env bash
set -euo pipefail
# -e  : stoppe le script si une commande échoue
# -u  : erreur si une variable non définie est utilisée
# -o pipefail : une erreur dans un pipe fait échouer tout le pipe

WG_IF="wg0"
CONF="/etc/wireguard/$WG_IF.conf"
# Variables de base : nom de l’interface et chemin du fichier wg0.conf

# ---------------------------------------------------------
# Lecture de la nouvelle configuration envoyée par Cockpit
# ---------------------------------------------------------
# Cockpit envoie le contenu du textarea via stdin.
# NEWCONF contient donc l'intégralité du fichier wg0.conf modifié.
NEWCONF=$(cat)

# ---------------------------------------------------------
# Écriture de la nouvelle configuration dans wg0.conf
# ---------------------------------------------------------
# On remplace complètement le fichier par le contenu fourni.
echo "$NEWCONF" > "$CONF"

# ---------------------------------------------------------
# Rechargement de WireGuard (compatible DEBIX)
# ---------------------------------------------------------
# La DEBIX ne supporte pas wg syncconf ni process substitution.
# On utilise donc wg-quick down/up, qui fonctionne partout.
wg-quick down wg0 2>/dev/null || true   # On ignore les erreurs si wg0 est déjà down
wg-quick up wg0                         # Redémarre l'interface avec la nouvelle config

# ---------------------------------------------------------
# Message final pour Cockpit
# ---------------------------------------------------------
echo "Configuration appliquée avec succès."
