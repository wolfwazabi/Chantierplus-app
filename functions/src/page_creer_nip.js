// Page web de création du NIP (lien reçu par courriel). Autonome : aucun
// script ni style externe. Le jeton est lu dans le fragment « # » de
// l'adresse puis envoyé en POST ; il n'apparaît jamais dans l'URL demandée.
module.exports = `<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>Chantier+ — Créer mon NIP</title>
<style>
  body{margin:0;font-family:system-ui,-apple-system,"Segoe UI",Roboto,sans-serif;background:#EAE2D0;color:#1E1E1A}
  header{background:#2F4A34;color:#EAE2D0;padding:16px 20px;font-size:20px;font-weight:600}
  main{max-width:420px;margin:24px auto;padding:0 16px}
  .carte{background:#fff;border-radius:12px;padding:20px;border:1px solid #D8CEB5}
  label{display:block;font-size:14px;margin:14px 0 6px}
  input{width:100%;box-sizing:border-box;font-size:22px;letter-spacing:6px;padding:10px 12px;border:1px solid #B8AC90;border-radius:8px}
  button{margin-top:18px;width:100%;padding:14px;font-size:16px;font-weight:600;border:0;border-radius:8px;background:#2F4A34;color:#EAE2D0;cursor:pointer}
  button:disabled{opacity:.6;cursor:default}
  .erreur{color:#A32D2D;font-size:14px;margin-top:12px}
  .ok{font-size:15px;line-height:1.6}
  .aide{font-size:13px;color:#5F5E5A;margin-top:4px}
</style>
</head>
<body>
<header>Chantier+</header>
<main>
  <div class="carte" id="carte">
    <h1 style="font-size:20px;margin:0 0 6px">Créer mon NIP</h1>
    <p class="aide">Choisissez un NIP de 6 à 8 chiffres. Il vous servira à vous connecter à l'application avec votre numéro de compagnie et votre courriel.</p>
    <form id="formulaire" novalidate>
      <label for="nip">Nouveau NIP</label>
      <input id="nip" type="password" inputmode="numeric" autocomplete="new-password" maxlength="8" required>
      <label for="confirmation">Confirmer le NIP</label>
      <input id="confirmation" type="password" inputmode="numeric" autocomplete="new-password" maxlength="8" required>
      <div class="erreur" id="erreur" role="alert"></div>
      <button type="submit" id="bouton">Créer mon NIP</button>
    </form>
  </div>
</main>
<script>
(function () {
  var params = new URLSearchParams(location.hash.slice(1));
  var employeeId = params.get("e") || "";
  var jeton = params.get("t") || "";
  var carte = document.getElementById("carte");
  var erreur = document.getElementById("erreur");
  var bouton = document.getElementById("bouton");

  function afficherErreur(m) { erreur.textContent = m; }
  function message(html) { carte.innerHTML = html; }

  if (!employeeId || !jeton) {
    message('<h1 style="font-size:20px;margin:0 0 6px">Lien incomplet</h1><p class="ok">Ouvrez le lien directement depuis le courriel reçu, ou demandez un nouveau lien à votre employeur.</p>');
    return;
  }

  document.getElementById("formulaire").addEventListener("submit", function (ev) {
    ev.preventDefault();
    var nip = document.getElementById("nip").value.trim();
    var conf = document.getElementById("confirmation").value.trim();
    if (!/^[0-9]{6,8}$/.test(nip)) { afficherErreur("Le NIP doit contenir de 6 à 8 chiffres."); return; }
    if (nip !== conf) { afficherErreur("La confirmation ne correspond pas."); return; }
    afficherErreur("");
    bouton.disabled = true;
    fetch(location.href.split("#")[0], {
      method: "POST",
      headers: {"Content-Type": "application/json"},
      body: JSON.stringify({employeeId: employeeId, jeton: jeton, nip: nip})
    }).then(function (r) {
      return r.json().then(function (d) { return {ok: r.ok, d: d}; });
    }).then(function (x) {
      if (!x.ok) { afficherErreur(x.d.erreur || "Une erreur est survenue."); bouton.disabled = false; return; }
      history.replaceState(null, "", location.pathname);
      var p = document.createElement("div");
      p.innerHTML = '<h1 style="font-size:20px;margin:0 0 6px">NIP créé</h1><p class="ok">Vous pouvez maintenant vous connecter dans l\\'application Chantier+ avec :</p>';
      var ul = document.createElement("ul");
      ul.className = "ok";
      [["Numéro de compagnie", x.d.numero], ["Courriel", x.d.courriel], ["NIP", "celui que vous venez de choisir"]].forEach(function (l) {
        var li = document.createElement("li");
        li.textContent = l[0] + " : " + l[1];
        ul.appendChild(li);
      });
      p.appendChild(ul);
      carte.innerHTML = "";
      carte.appendChild(p);
    }).catch(function () {
      afficherErreur("Connexion impossible. Vérifiez votre réseau et réessayez.");
      bouton.disabled = false;
    });
  });
})();
</script>
</body>
</html>`;
