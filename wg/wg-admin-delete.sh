#!/usr/bin/env bash
set -euo pipefail
# -e  : stoppe le script si une commande échoue
# -u  : erreur si une variable non définie est utilisée
# -o pipefail : une erreur dans un pipe fait échouer tout le pipe

PUB="$1"                                # Clé publique du peer à supprimer
CONF="/etc/wireguard/wg0.conf"          # Fichier de configuration WireGuard
TMP="$(mktemp)"                         # Fichier temporaire pour reconstruire wg0.conf

in_block=0                               # Indique si on est actuellement dans un bloc [Peer]
delete_block=0                           # Indique si le bloc courant doit être supprimé

# ---------------------------------------------------------
# Lecture du fichier wg0.conf ligne par ligne
# ---------------------------------------------------------
while IFS= read -r line; do

    # -----------------------------------------------------
    # Détection du début d'un bloc [Peer]
    # -----------------------------------------------------
    if [[ "$line" == "[Peer]" ]]; then

        # Si on était en train de supprimer un bloc, on termine la suppression
        if [[ $delete_block -eq 1 ]]; then
            delete_block=0
        fi

        in_block=1                       # On entre dans un bloc Peer
        buffer="$line"                   # On commence à stocker le bloc
        continue
    fi

    # -----------------------------------------------------
    # Si on est dans un bloc Peer, on accumule les lignes
    # -----------------------------------------------------
    if [[ $in_block -eq 1 ]]; then
        buffer="$buffer"$'\n'"$line"     # Ajout de la ligne au bloc

        # Si la ligne contient la clé publique → ce bloc doit être supprimé
        if [[ "$line" == "PublicKey = $PUB" ]]; then
            delete_block=1
        fi

        # Sécurité : si une ligne "[Peer]" apparaît ici (rare), on ignore
        if [[ "$line" == "[Peer]" ]]; then
            :
        fi

        # -------------------------------------------------
        # Fin du bloc Peer :
        # - ligne vide
        # - ou fin du fichier (géré plus bas)
        # -------------------------------------------------
        if [[ -z "$line" ]]; then

            # Si le bloc n'est PAS à supprimer → on l'écrit dans le fichier temporaire
            if [[ $delete_block -eq 0 ]]; then
                echo "$buffer" >> "$TMP"
            fi

            in_block=0                   # On sort du bloc Peer
        fi

        continue
    fi

    # -----------------------------------------------------
    # Lignes hors bloc Peer → recopier telles quelles
    # -----------------------------------------------------
    echo "$line" >> "$TMP"

done < "$CONF"

# ---------------------------------------------------------
# Cas particulier : dernier bloc sans ligne vide finale
# ---------------------------------------------------------
if [[ $in_block -eq 1 && $delete_block -eq 0 ]]; then
    echo "$buffer" >> "$TMP"
fi

# ---------------------------------------------------------
# Remplacement du fichier wg0.conf par la version nettoyée
# ---------------------------------------------------------
mv "$TMP" "$CONF"

# ---------------------------------------------------------
# Rechargement WireGuard (compatible DEBIX)
# ---------------------------------------------------------
wg-quick down wg0 2>/dev/null || true     # On ignore les erreurs si wg0 est déjà down
wg-quick up wg0                           # Redémarre l'interface proprement

echo "Peer supprimé : $PUB"
