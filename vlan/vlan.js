/* ---------------------------------------------------------
   Attendre que Cockpit soit prêt AVANT d'exécuter le JS
   ---------------------------------------------------------
   - cockpit.transport.wait() garantit que :
       • l’iframe Cockpit est initialisée
       • cockpit.js est chargé
       • le DOM du module est disponible
   - Sans cela, ton script s’exécuterait trop tôt :
       → cockpit = undefined
       → document.getElementById() = null
       → boutons inactifs
--------------------------------------------------------- */
cockpit.transport.wait(function () {

    console.log("VLAN JS chargé et DOM prêt !");
    initVLAN();   // Appel de la fonction principale du module


    /* ---------------------------------------------------------
       Fonction principale : tout le code du module est ici
       ---------------------------------------------------------
       - On encapsule TOUT le code dans initVLAN()
       - Cela garantit que :
           • le DOM est prêt
           • les éléments HTML existent
           • les handlers peuvent être attachés
           • cockpit.spawn() fonctionne
    --------------------------------------------------------- */
    function initVLAN() {

        console.log("initVLAN() exécuté !");

        // Récupération des éléments HTML du module
        const tableBody = document.getElementById("vlan-table-body");
        const textarea = document.getElementById("interfaces-content");
        const statusDiv = document.getElementById("status");

        /* ---------------------------------------------------------
           Fonction utilitaire : afficher un message d'état
           ---------------------------------------------------------
           - Permet d'afficher un retour utilisateur
           - Utilisé après chaque action (ajout, suppression, erreur)
        --------------------------------------------------------- */
        function setStatus(msg) {
            statusDiv.textContent = msg;
        }

        /* ---------------------------------------------------------
           Charger le fichier /etc/network/interfaces
           ---------------------------------------------------------
           - cockpit.spawn() exécute une commande système
           - superuser:"try" → demande sudo si nécessaire
           - On récupère le fichier brut et on le parse
        --------------------------------------------------------- */
        function loadInterfaces() {
            cockpit.spawn(["cat", "/etc/network/interfaces"], { superuser: "try" })
                .done(data => {
                    textarea.value = data;   // Affiche le fichier brut dans le textarea
                    parseVLANs(data);        // Analyse et remplit le tableau des VLANs
                })
                .fail(err => {
                    console.error("Erreur loadInterfaces:", err);
                    setStatus("Erreur lors du chargement des interfaces.");
                });
        }

        /* ---------------------------------------------------------
           Analyse du fichier interfaces pour détecter les VLANs
           ---------------------------------------------------------
           - On utilise une regex pour trouver les blocs VLAN :
               iface eth1.10 inet static
               address X.X.X.X
               netmask X.X.X.X
           - Chaque VLAN détecté génère une ligne dans le tableau
        --------------------------------------------------------- */
        function parseVLANs(content) {
            tableBody.innerHTML = ""; // On vide le tableau avant de le remplir

            const regex = /iface\s+(\w+)\.(\d+)\s+inet\s+static[\s\S]*?address\s+([\d.]+)[\s\S]*?netmask\s+([\d.]+)/g;
            let match;

            while ((match = regex.exec(content)) !== null) {

                const iface = match[1] + "." + match[2];   // ex: eth1.10
                const parent = match[1];                   // ex: eth1
                const vlanId = match[2];                   // ex: 10
                const ip = match[3] + "/" + match[4];      // ex: 192.168.10.1/255.255.255.0

                // Création d'une ligne HTML pour le tableau
                const row = document.createElement("tr");
                row.innerHTML = `
                    <td>${vlanId}</td>
                    <td>${iface}</td>
                    <td>${ip}</td>
                    <td>${parent}</td>
                    <td>
                        <button class="btn btn-secondary btn-delete" data-iface="${iface}">
                            Supprimer
                        </button>
                    </td>
                `;
                tableBody.appendChild(row);
            }
        }

        /* ---------------------------------------------------------
           Ajouter un VLAN via vlan-add.sh
           ---------------------------------------------------------
           - Récupère les champs du formulaire
           - Vérifie qu'ils sont remplis
           - Appelle le script backend via cockpit.spawn()
           - Recharge la liste après ajout
        --------------------------------------------------------- */
        function addVLAN() {
            const id = document.getElementById("new-vlan-id").value;
            const parent = document.getElementById("new-vlan-parent").value;
            const ip = document.getElementById("new-vlan-ip").value;
            const mask = document.getElementById("new-vlan-mask").value;

            if (!id || !parent || !ip || !mask) {
                setStatus("Champs manquants.");
                return;
            }

            const proc = cockpit.spawn(
                ["/usr/local/sbin/vlan-add.sh", parent, id, ip, mask],
                { superuser: "require", pty: true }
            );

            proc.done(data => {
                setStatus(data);
                loadInterfaces();  // Mise à jour du tableau
            });

            proc.fail(err => {
                console.error("Erreur addVLAN:", err);
                setStatus("Erreur lors de l'ajout du VLAN.");
            });
        }

        /* ---------------------------------------------------------
           Supprimer un VLAN via vlan-del.sh
           ---------------------------------------------------------
           - Appelé lorsqu'on clique sur un bouton "Supprimer"
           - Supprime le bloc correspondant dans /etc/network/interfaces
           - Recharge la liste
        --------------------------------------------------------- */
        function deleteVLAN(iface) {

            const proc = cockpit.spawn(
                ["/usr/local/sbin/vlan-del.sh", iface],
                { superuser: "require", pty: true }
            );

            proc.done(data => {
                setStatus(data);
                loadInterfaces();
            });

            proc.fail(err => {
                console.error("Erreur deleteVLAN:", err);
                setStatus("Erreur lors de la suppression du VLAN.");
            });
        }

        /* ---------------------------------------------------------
           Appliquer la configuration brute via vlan-apply.sh
           ---------------------------------------------------------
           - Envoie le contenu du textarea au script backend
           - Permet une édition manuelle avancée
        --------------------------------------------------------- */
        function applyConfig() {

            const proc = cockpit.spawn(
                ["/usr/local/sbin/vlan-apply.sh"],
                { superuser: "require", pty: true }
            );

            proc.input(textarea.value);  // Envoie le contenu du textarea
            proc.close();

            proc.done(data => {
                setStatus(data);
                loadInterfaces();
            });

            proc.fail(err => {
                console.error("Erreur applyConfig:", err);
                setStatus("Erreur lors de l'application de la configuration.");
            });
        }

        /* ---------------------------------------------------------
           Gestion du clic sur les boutons "Supprimer"
           ---------------------------------------------------------
           - On utilise un event listener sur le <tbody>
           - Cela permet de gérer des lignes ajoutées dynamiquement
        --------------------------------------------------------- */
        tableBody.addEventListener("click", (e) => {
            if (e.target.classList.contains("btn-delete")) {
                const iface = e.target.getAttribute("data-iface");
                deleteVLAN(iface);
            }
        });

        /* ---------------------------------------------------------
           Attachement des handlers des boutons principaux
        --------------------------------------------------------- */
        document.getElementById("refresh").onclick = loadInterfaces;
        document.getElementById("add-vlan").onclick = addVLAN;
        document.getElementById("apply-config").onclick = applyConfig;

        /* ---------------------------------------------------------
           Chargement initial du tableau VLAN
        --------------------------------------------------------- */
        loadInterfaces();
    }
});
