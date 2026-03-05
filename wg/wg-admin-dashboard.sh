#!/usr/bin/env bash
set -euo pipefail
# -e  : stoppe le script si une commande échoue
# -u  : erreur si une variable non définie est utilisée
# -o pipefail : une erreur dans un pipe fait échouer tout le pipe

WG_IF="wg0"
# Nom de l’interface WireGuard à inspecter

# ---------------------------------------------------------
# Vérification : l’interface wg0 existe et est active
# ---------------------------------------------------------
if ! wg show "$WG_IF" &>/dev/null; then
    # Si wg show échoue → l’interface n’est pas montée
    echo "STATE=DOWN"
    exit 0
fi

# Si on arrive ici → wg0 est active
echo "STATE=UP"

# ---------------------------------------------------------
# Informations générales du serveur WireGuard
# ---------------------------------------------------------
SERVER_PUB=$(wg show "$WG_IF" public-key)   # Clé publique du serveur
PORT=$(wg show "$WG_IF" listen-port)        # Port d’écoute
# Lecture du trafic total RX/TX de l’interface
read -r _ RX _ TX <<< "$(wg show "$WG_IF" transfer)"

# Ces lignes seront lues par Cockpit pour afficher les infos serveur
echo "PUB=$SERVER_PUB"
echo "PORT=$PORT"
echo "RX=$RX"
echo "TX=$TX"

# ---------------------------------------------------------
# Début de la section des peers
# Cockpit lit tout ce qui est entre PEERS_BEGIN et PEERS_END
# ---------------------------------------------------------
echo "PEERS_BEGIN"

# wg show wg0 dump renvoie tous les peers au format tabulé
# On ignore la première ligne (en-têtes) avec tail -n +2
wg show "$WG_IF" dump | tail -n +2 | while IFS=$'\t' read -r pub psk endpoint allowed latest rx tx rest; do

    # Si aucun endpoint n’est défini → afficher (none)
    [[ -z "$endpoint" ]] && endpoint="(none)"

    # -----------------------------------------------------
    # Nettoyage : certaines implémentations (BusyBox/DEBIX)
    # ajoutent "off" ou du texte parasite dans rx/tx.
    # On ne garde que le premier champ numérique.
    # -----------------------------------------------------
    rx=$(echo "$rx" | awk '{print $1}')
    tx=$(echo "$tx" | awk '{print $1}')

    # -----------------------------------------------------
    # Format final d’une ligne peer :
    # pub|allowed|endpoint|latest|rx|tx
    #
    # Ce format est exactement celui attendu par wg-admin.js
    # -----------------------------------------------------
    echo "$pub|$allowed|$endpoint|$latest|$rx|$tx"

done

# Fin de la section des peers
echo "PEERS_END"
