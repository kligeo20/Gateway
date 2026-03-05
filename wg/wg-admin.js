// ---------------------------------------------------------
//  wg-admin.js — Interface Cockpit pour gérer WireGuard
// ---------------------------------------------------------

// Récupération des éléments HTML du tableau et des zones d'affichage
const peersTable = document.querySelector("#peers tbody");
const peerConf = document.getElementById("peerconf");
const qrDiv = document.getElementById("qrcode");
const downloadBtn = document.getElementById("download");
const textarea = document.getElementById("wgconf");
const statusDiv = document.getElementById("status");

// Affiche un message d'état (utilisé après apply)
function setStatus(msg) { statusDiv.textContent = msg; }

// ---------------------------------------------------------
//  Chargement du tableau principal (dashboard WireGuard)
// ---------------------------------------------------------
function loadDashboard() {
  // Appelle le script Bash qui renvoie l'état complet de wg0
  cockpit.spawn(["/usr/local/sbin/wg-admin-dashboard.sh"], { superuser: "try" })
    .done(data => {

      // Découpe la sortie en lignes
      const lines = data.trim().split("\n");

      // Lecture de l'état de l'interface (UP/DOWN)
      const stateLine = lines.find(l => l.startsWith("STATE="));
      if (!stateLine) return;
      const state = stateLine.split("=")[1];
      document.getElementById("ifstate").textContent = state;

      // Si wg0 est DOWN → on vide le tableau et on arrête
      if (state === "DOWN") {
        document.getElementById("serverinfo").textContent = "Interface inactive";
        peersTable.innerHTML = "";
        return;
      }

      // Lecture des infos serveur (clé publique, port, RX/TX)
      const pub = lines.find(l => l.startsWith("PUB=")).split("=")[1];
      const port = lines.find(l => l.startsWith("PORT=")).split("=")[1];
      const rx = lines.find(l => l.startsWith("RX=")).split("=")[1];
      const tx = lines.find(l => l.startsWith("TX=")).split("=")[1];

      // Affichage des infos serveur dans la zone dédiée
      document.getElementById("serverinfo").textContent =
        `Clé publique : ${pub}\nPort : ${port}\nRX : ${rx} bytes\nTX : ${tx} bytes`;

      // Détection des sections PEERS_BEGIN / PEERS_END
      const peersStart = lines.indexOf("PEERS_BEGIN") + 1;
      const peersEnd = lines.indexOf("PEERS_END");

      // On vide le tableau avant de le reconstruire
      peersTable.innerHTML = "";

      // Parcours de chaque peer renvoyé par le script Bash
      lines.slice(peersStart, peersEnd).forEach(line => {
        if (!line.trim()) return;

        // Chaque ligne est au format : pub|allowed|endpoint|latest|rx|tx
        const [pub, allowed, endpoint, latest, rx, tx] = line.split("|");

        // Construction d'une ligne HTML du tableau
        const tr = document.createElement("tr");
        tr.innerHTML = `
          <td>${allowed}</td>
          <td>${pub}</td>
          <td>${endpoint}</td>
          <td>${latest}</td>
          <td>${rx}</td>
          <td>${tx}</td>
          <!-- Le bouton Supprimer transporte la clé publique ET l'IP -->
          <td><button class="del" data-pub="${pub}" data-ip="${allowed}">Supprimer</button></td>
        `;
        peersTable.appendChild(tr);
      });
    });
}

// Bouton "Rafraîchir"
document.getElementById("refresh").onclick = loadDashboard;

// ---------------------------------------------------------
//  Ajout d'un peer (génération clé + config + QR code)
// ---------------------------------------------------------
document.getElementById("add").onclick = () => {

  // Appelle le script Bash qui génère un nouveau peer
  cockpit.spawn(["/usr/local/sbin/wg-admin-generate.sh"], { superuser: "require" })
    .done(data => {

      // Découpe la sortie en lignes
      const lines = data.trim().split("\n");

      // Extraction de la config client entre CONF_BEGIN / CONF_END
      const confStart = lines.indexOf("CONF_BEGIN") + 1;
      const confEnd = lines.indexOf("CONF_END");
      const pngStart = lines.indexOf("PNG_BEGIN") + 1;
      const pngEnd = lines.indexOf("PNG_END");

      const conf = lines.slice(confStart, confEnd).join("\n");
      const pngB64 = lines.slice(pngStart, pngEnd).join("");

      // Affiche la configuration client dans la zone dédiée
      peerConf.textContent = conf;

      // Active le bouton de téléchargement
      downloadBtn.style.display = "inline-block";
      downloadBtn.onclick = () => {
        const blob = new Blob([conf], { type: "text/plain" });
        const url = URL.createObjectURL(blob);
        const a = document.createElement("a");
        a.href = url;
        a.download = "wg-client.conf";
        a.click();
      };

      // Affiche le QR code généré par le script Bash
      qrDiv.innerHTML = "";
      const img = document.createElement("img");
      img.src = "data:image/png;base64," + pngB64;
      qrDiv.appendChild(img);

      // Recharge le tableau des peers
      loadDashboard();
    });
};

// ---------------------------------------------------------
//  Suppression d'un peer (avec confirmation)
// ---------------------------------------------------------
peersTable.onclick = e => {
  if (e.target.classList.contains("del")) {

    // Récupération des attributs du bouton
    const pub = e.target.dataset.pub;
    const ip = e.target.dataset.ip;

    // Message de confirmation avant suppression
    if (!confirm(`Supprimer ce peer ?\n\nIP : ${ip}\nClé publique : ${pub}`)) {
      return;
    }

    // Appelle le script Bash de suppression
    cockpit.spawn(["/usr/local/sbin/wg-admin-delete.sh", pub], { superuser: "require" })
      .done(() => loadDashboard());
  }
};

// ---------------------------------------------------------
//  Application manuelle d'une configuration wg0.conf
// ---------------------------------------------------------
document.getElementById("apply").onclick = () => {
  const proc = cockpit.spawn(["/usr/local/sbin/wg-admin-apply.sh"], { superuser: "require", pty: true });
  proc.input(textarea.value);
  proc.close();
  proc.done(data => setStatus(data));
};

// Charge le contenu actuel de wg0.conf dans la zone d'édition
cockpit.spawn(["cat", "/etc/wireguard/wg0.conf"], { superuser: "try" })
  .done(data => textarea.value = data);

// Chargement initial du dashboard
loadDashboard();
