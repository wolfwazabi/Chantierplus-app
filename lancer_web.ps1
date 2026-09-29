# Lance Chantier+ pour le web en gardant la connexion d'un lancement à l'autre.
#
# « flutter run -d chrome » ouvre Chrome avec un profil neuf et un port au
# hasard : la session Firebase est alors perdue à chaque lancement. Ici, l'app
# est servie sur un port fixe et s'ouvre dans votre Chrome habituel, qui garde
# la session comme pour n'importe quel site.
#
# Utilisation (depuis le dossier du projet) :  .\lancer_web.ps1
# Puis, dans ce terminal : r = rechargement, R = redémarrage, q = quitter.

$url = 'http://localhost:5500'

# Ouvre le navigateur dès que le serveur répond (sans bloquer flutter run).
Start-Job -ArgumentList $url -ScriptBlock {
    param($url)
    for ($i = 0; $i -lt 180; $i++) {
        try {
            Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 2 | Out-Null
            Start-Process $url
            return
        } catch { Start-Sleep -Seconds 1 }
    }
} | Out-Null

flutter run -d web-server --web-port=5500
