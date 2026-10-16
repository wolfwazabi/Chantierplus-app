# Devis : copie sans montants pour les contremaîtres

Demande de l'entrepreneur (16 oct. 2026) : un fichier déposé dans les documents d'un chantier
dont le **nom** contient « devis » (majuscules et accents ignorés : « Devis cuisine.pdf »,
« DEVIS_2026-112.pdf ») montre aux contremaîtres une copie **sans les montants**. Seuls les
admins voient l'original.

## Ce que voit chacun

| | Admin | Contremaître |
|---|---|---|
| Devis PDF avec du texte | l'original ; « Voir la copie des contremaîtres » | la copie « … (sans montants).pdf » |
| Devis pas en PDF (Excel, Word, photo) | l'original | rien (caché) |
| Devis PDF numérisé (sans texte) ou de plus de 30 pages | l'original | rien (caché) |
| Pendant la préparation (quelques secondes) | l'original | « en préparation », grisé |

Sous le nom d'un devis, l'admin voit l'état de la copie (« 4 montants masqués », « caché :
PDF numérisé »…) ; si elle a échoué, le bouton ↻ la refait.

## Montants masqués

Un nombre avec **$** avant ou après (« 450 $ », « $1,234.56 », « 1 234,56 $ ») ou à
**exactement 2 décimales** (« 1 234,56 », « 450.00 »). Restent lisibles : quantités (« 6 »),
dimensions (« 30" », « 2x4 »), dates, téléphones, numéros de devis, taux (« 9,975 % »).

**Limites** : un prix sans $ ni décimales (« 1234 » seul dans une colonne) reste visible, et
un montant dessiné dans une image du PDF n'est pas vu. L'admin vérifie avec « Voir la copie des
contremaîtres ».

## Comment c'est fait

- `functions/src/devis.js` : le serveur lit le texte du PDF avec ses positions (pdf.js), trouve
  les montants, rend chaque page en image (144 ppp), y dessine les carrés noirs et refait un PDF
  d'images : le texte n'existe plus dans la copie (rien à copier sous les carrés).
- Déclencheur `copieDevis` (fiche créée) ; `preparerCopieDevis` (admin) pour un devis déposé
  avant cette fonction ou une copie ratée — l'app de l'admin le demande toute seule pour un
  ancien devis ; `effacerFichiersDocument` (fiche supprimée) efface le fichier et sa copie.
- Fiche `chantier_documents` : `devis: true`, `copieContremaitre` = {etat (en_cours, prete,
  cachee, erreur), chemin, taille, pages, montants, raison}. **Pas de `url`** pour un devis : ce
  lien à jeton contournerait les règles. Une ancienne version de l'app en envoie un : le serveur
  le retire et **révoque le jeton** du fichier.
- Storage : original `chantiers/{c}/{ch}/documents/…devis…` lisible par les admins seulement
  (le nom du fichier contient toujours « devis » : l'app l'ajoute, le serveur renomme au besoin) ;
  copie `chantiers/{c}/{ch}/devis_sans_montants/{documentId}.pdf`, lue par admins et
  contremaîtres, écrite par le serveur seul.

## Tests

- `tests/rules/devis.unit.test.mjs` : montants trouvés ou non, carrés noirs au bon endroit
  (mesurés sur l'image), quantités lisibles, copie sans texte, numérisé et trop long cachés.
- `tests/rules/functions.test.mjs` (« Devis… ») : déclencheur, lien révoqué, Excel caché,
  copie refaite par l'admin seulement, fichiers effacés avec la fiche.
- Règles : `storage.test.mjs`, `firestore.test.mjs` ; app : `test/documents_chantier_test.dart`.

# Supprimer définitivement un chantier archivé

Admin > Chantiers > Archivés > menu du chantier (ou menu de la page du chantier) >
**Supprimer définitivement**. Seulement un chantier **archivé**, par un **admin**, en tapant son
nom (espaces, majuscules et accents ignorés). « Exporter d'abord » (page du chantier) lance
l'export ZIP.

Fonction `supprimerChantier` (`functions/src/suppression_chantier.js`) : fichiers du chantier
(photos, documents, copies, extras…), exports ZIP de ce chantier, fiches (photos, travaux,
matériel, extras, commandes, documents), regroupement des notifications, puis la fiche du
chantier en dernier (une suppression interrompue se reprend). Les **heures restent** : chaque
journée des feuilles de temps garde le nom du chantier. Journal `journal_chantiers_supprimes`
(serveur seulement) : nom, adresse, date, auteur, décompte.
