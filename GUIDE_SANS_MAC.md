# SELF BUILD sans Mac : GitHub compile, SideStore installe

Principe : tu envoies le code sur GitHub → un Mac dans le cloud (gratuit) compile l'app et fabrique un fichier `.ipa` → tu le télécharges sur ton iPhone → SideStore le signe avec ton Apple ID et l'installe. Aucun Mac, aucun TeamViewer.

⚠️ Une seule chose exige un ordinateur : l'installation INITIALE de SideStore (10 minutes, USB). Un PC Windows, Linux ou Mac, même emprunté, suffit. Après, plus jamais besoin.
Alternative si tu n'as vraiment aucun ordinateur : il n'existe pas de méthode propre et gratuite. Demande à un ami/au lycée/à un cyber de te prêter un PC 10 minutes.

---------------------------------------------------------------
## ÉTAPE 1 – Les comptes (5 min, depuis ton téléphone)
1. **GitHub** : va sur github.com → Sign up (gratuit). Note ton nom d'utilisateur.
2. **Apple ID** : utilise de préférence un Apple ID secondaire créé juste pour ça (SideStore s'y connecte). Active si besoin la double authentification.
3. **Clé Gemini** : aistudio.google.com/apikey → Create API key → copie-la (tu la colleras dans l'app).

## ÉTAPE 2 – Créer le dépôt GitHub
1. GitHub → bouton **+** (en haut à droite) → **New repository**.
2. Nom : `selfbuild`. Choisis **Public** (builds macOS illimités et gratuits ; le code ne contient aucun secret car la clé Gemini se saisit dans l'app). En **Private**, les minutes macOS sont comptées beaucoup plus cher sur le plan gratuit (vérifie le quota dans Settings → Billing).
3. Coche **Add a README file** → Create repository.

## ÉTAPE 3 – Envoyer les fichiers (sur ordinateur, ou le Mac TeamViewer)
Dézippe `SelfBuild-GitHub.zip`. Tu obtiens : `SelfBuild/` (18 fichiers .swift), `SelfBuildWidget/`, `project.yml`, `.gitignore`, `.github/`.

1. Dans ton dépôt : **Add file → Upload files**.
2. Glisse **les dossiers `SelfBuild` et `SelfBuildWidget`** + les fichiers `project.yml` et `.gitignore`. Attends la fin du chargement.
3. En bas : **Commit changes** (branche main).
4. Le dossier caché `.github` est souvent ignoré par le glisser-déposer. Crée-le à la main :
   - **Add file → Create new file**
   - Dans le champ du nom, tape exactement : `.github/workflows/build.yml` (les `/` créent les dossiers)
   - Ouvre `build.yml` du zip, copie-colle tout son contenu
   - **Commit changes**.

Vérifie à la fin que tu vois à la racine du dépôt : `.github`, `SelfBuild`, `SelfBuildWidget`, `project.yml`.

## ÉTAPE 4 – Lancer la compilation
1. Onglet **Actions** du dépôt. (Si GitHub demande d'activer les workflows : « I understand… enable ».)
2. À gauche **Build IPA** → **Run workflow** → Run workflow. (Ça démarre aussi tout seul à chaque commit sur main.)
3. Attends 5 à 12 minutes. Pastille verte ✅ = réussi.

### Si c'est rouge ❌ (probable au premier essai : je n'ai pas pu compiler le code moi-même)
1. Clique sur le run rouge → étape **Résumé des erreurs** : tu vois les lignes `error:`.
2. Copie ces lignes et envoie-les-moi ici : je corrige le fichier concerné et tu le remplaces sur GitHub (ouvre le fichier → icône crayon → colle → Commit).
3. Le journal complet est aussi dans « Artifacts → build-log » en bas de la page du run.

## ÉTAPE 5 – Récupérer l'IPA
Dépôt → colonne de droite **Releases** → **Build N** → télécharge `SelfBuild.ipa`. Fais-le directement depuis Safari sur l'iPhone (connecté à GitHub) → il atterrit dans Fichiers → Téléchargements.

## ÉTAPE 6 – Installer SideStore (une seule fois, ordinateur requis)
Les outils bougent : en cas de doute, suis https://docs.sidestore.io (section Installation).

**Sur l'iPhone**
1. iPhone iOS 17 minimum. Réglages → Confidentialité et sécurité → **Mode développeur** → ON → l'iPhone redémarre → confirme.
2. App Store → installe **LocalDevVPN** → ouvre-le → Skip → **Connect** → Allow + code. (Laisse-le connecté pendant l'étape.)

**Sur l'ordinateur (Windows/Linux/Mac)**
1. Windows : installe iTunes (version du site Apple, pas Microsoft Store) pour les pilotes. Linux : installe `usbmuxd`.
2. Télécharge **iloader** (github.com/nab138/iloader/releases/latest) : `iloader-windows-x64.msi` sous Windows, `.dmg` sous Mac.
3. Branche l'iPhone en USB, déverrouillé, « Faire confiance ». Ordinateur et iPhone sur le même Wi-Fi.
4. Ouvre iloader → connecte-toi avec ton Apple ID → vérifie que l'iPhone est détecté → **Install SideStore (Stable)**.
5. Sur l'iPhone : ouvre SideStore. Si un message de confiance apparaît : Réglages → Général → VPN et gestion de l'appareil → ton Apple ID → Faire confiance.
6. Connecte-toi dans SideStore avec ton Apple ID si demandé. Tu peux débrancher.

## ÉTAPE 7 – Installer SELF BUILD
1. LocalDevVPN : **Connect** (toujours le faire avant d'installer/rafraîchir).
2. Ouvre SideStore → onglet **My Apps** → **+** (en haut à gauche) → choisis `SelfBuild.ipa` dans Fichiers.
3. Attends la fin de la signature/installation. Si ça bloque : relance le bouton, ou redémarre SideStore puis LocalDevVPN.
4. Ouvre SELF BUILD. Accepte notifications, micro, reconnaissance vocale, appareil photo.
5. **Plus → Réglages** : colle ta clé Gemini.

## ÉTAPE 8 – Chaque semaine (7 jours de validité)
1. LocalDevVPN → Connect.
2. SideStore → My Apps → **Refresh All**.
Le rafraîchissement automatique en arrière-plan marche tant que LocalDevVPN reste connecté et que l'actualisation en arrière-plan est active (Réglages → Général). Si l'app expire, la rafraîchir suffit : tes données restent.

## ÉTAPE 9 – Mettre à jour l'app (après une modification du code)
1. Modifie le fichier sur GitHub (crayon → Commit) → le build repart seul.
2. Télécharge le nouvel IPA dans Releases.
3. SideStore → My Apps → **+** → le nouvel IPA : il remplace l'ancienne version et garde tes données.

---------------------------------------------------------------
## Dépannage rapide
- **« Cannot start DebugServer » / échec de connexion** : vérifie Wi-Fi + LocalDevVPN connectés, redémarre les deux apps ; sinon régénère le fichier de pairing avec iloader (doc SideStore → Advanced → Pairing File).
- **Limite Apple gratuite** : 3 apps actives (SideStore compte pour une) et 10 identifiants d'app par semaine. SELF BUILD + son extension Dynamic Island en utilisent 2. Ne réinstalle pas en boucle.
- **Pas de Dynamic Island** : elle n'existe que sur iPhone 14 Pro et plus récents ; ailleurs, la Live Activity s'affiche sur l'écran verrouillé.
- **Mise à jour d'iOS / réinitialisation** : le fichier de pairing peut devenir invalide → ré-ouvre iloader sur un ordinateur.
- **Run GitHub rouge** : voir étape 4, envoie-moi les lignes `error:`.

---------------------------------------------------------------
## MISE À JOUR v2 (logo, modules, correction Gemini)
Les fichiers ont changé : remplace tout le contenu de ton dépôt par le nouveau zip.
Dans le dossier du projet sur le Mac :
```bash
git add .
git commit -m "v2"
git push
```
Le build repart seul. Récupère le nouvel IPA dans Releases puis SideStore → My Apps → + (il remplace l'ancienne version, tes données restent).
Si GitHub refuse le push parce que le dépôt a des changements distants : `git push --force`.
