# SELF BUILD v3 sans Mac : GitHub compile, iloader / SideStore installe

Principe : le code est sur GitHub → un Mac dans le cloud (GitHub Actions, runner `macos-26`) compile l'app sans signature et publie un `.ipa` dans **Releases** → tu le télécharges → SideStore le signe avec ton Apple ID gratuit et l'installe.

Un ordinateur (Windows suffit) n'est nécessaire qu'une seule fois : pour installer SideStore avec **iloader**.

---------------------------------------------------------------
## 1. Ce qu'il te faut
- Un compte **GitHub** (le dépôt `build-self` existe déjà sur ton compte `mouka3112`).
- Un **Apple ID** (de préférence secondaire) pour SideStore.
- Une **clé Gemini gratuite** : https://aistudio.google.com/apikey → *Create API key* (l'app te guide aussi au premier lancement).
- Un iPhone sous **iOS 17 ou plus récent**.

## 2. Compiler l'app sur GitHub
1. Le build démarre **tout seul** à chaque push sur les branches `main` et `v3`.
2. Pour le relancer à la main : dépôt → onglet **Actions** → **Build IPA** → **Run workflow** → choisis la branche (`v3` tant qu'elle n'est pas fusionnée dans `main`) → **Run workflow**.
3. Attends 8 à 20 minutes. Pastille verte ✅ = réussi.
4. Le workflow **échoue exprès** si l'extension Dynamic Island (`SelfBuildWidget.appex`) manque dans l'app : sans elle, pas de Live Activity.

### Si c'est rouge ❌
1. Clique sur le run → étape **Résumé des erreurs** : copie les lignes `error:`.
2. Envoie-les à Claude : il corrige le fichier concerné.
3. Le journal complet est dans **Artifacts → build-log** en bas de la page du run.

## 3. Récupérer le `.ipa`
Dépôt → colonne de droite **Releases** → la plus récente (**Build N · branche · commit**) → télécharge `SelfBuild.ipa`.
- Les builds de la branche `v3` sont marqués **Pre-release** ; ceux de `main` sont des versions normales.
- Fais-le depuis Safari sur l'iPhone : le fichier arrive dans **Fichiers → Téléchargements**.

## 4. Installer SideStore avec iloader (une seule fois, sur ordinateur)
Les outils évoluent : en cas de doute, suis https://docs.sidestore.io (section Installation).

**Sur l'iPhone**
1. Réglages → Confidentialité et sécurité → **Mode développeur** → ON → redémarrage → confirme.
2. App Store → installe **LocalDevVPN** → ouvre-le → **Connect** → autorise le VPN.

**Sur l'ordinateur**
1. Windows : installe iTunes (version du site d'Apple, pas Microsoft Store) pour les pilotes USB.
2. Télécharge **iloader** : https://github.com/nab138/iloader/releases/latest (`.msi` sous Windows).
3. Branche l'iPhone en USB, déverrouillé, « Faire confiance ». Ordinateur et iPhone sur le même Wi-Fi.
4. Ouvre iloader → connecte-toi avec ton Apple ID → vérifie que l'iPhone est détecté → **Install SideStore (Stable)**.
5. Sur l'iPhone : Réglages → Général → **VPN et gestion de l'appareil** → ton Apple ID → **Faire confiance**.
6. Ouvre SideStore, connecte-toi avec ton Apple ID si demandé. Tu peux débrancher le câble.

## 5. Installer (ou mettre à jour) SELF BUILD
1. LocalDevVPN → **Connect** (toujours avant d'installer ou de rafraîchir).
2. SideStore → onglet **My Apps** → **+** → choisis `SelfBuild.ipa` dans Fichiers.
3. Si SideStore demande quoi faire des **extensions** (« Keep App Extensions » / « Remove ») : choisis **Keep / Garder**. Sinon la Dynamic Island ne marchera pas (Réglages de l'app → Dynamic Island affichera « ❌ Extension absente »).
4. Une mise à jour remplace l'ancienne version **en gardant tes données** (la v3 reprend automatiquement les données de la v2).

## 6. Premier lancement (v3)
L'app te demande dans l'ordre :
1. **La clé Gemini** : bouton « Ouvrir Google AI Studio », puis **Coller** et **Tester la clé**.
2. **Ton profil** : prénom, âge, taille, poids, ville (« Vérifier » : la météo suit ta ville), monnaie, et si tu es élève : niveau, établissement, matières.
3. **Tes objectifs** (prise de muscle, études, argent…).
4. **Ton rythme** : réveil, coucher ; calories et protéines sont calculées puis modifiables.
Accepte ensuite : notifications, micro, reconnaissance vocale, appareil photo, localisation (Running), Activités en direct.

## 7. Chaque semaine (signature gratuite = 7 jours)
LocalDevVPN → Connect → SideStore → My Apps → **Refresh All**. Si l'app expire, la rafraîchir suffit : tes données restent.

---------------------------------------------------------------
## Limites du compte Apple gratuit (à connaître)
- **3 apps actives** max (SideStore en compte une) et **10 identifiants d'app (App IDs) par semaine**. SELF BUILD + son extension en utilisent **2** : ne réinstalle pas en boucle.
- **Pas d'entitlements payants** : 
  - notifications « urgentes » (`timeSensitive`) : iOS peut les afficher comme des notifications normales ;
  - **Lockdown** = verrouillage **dans SELF BUILD uniquement** (bloquer les autres apps exige FamilyControls, réservé aux comptes payants).
- **Dynamic Island** : iPhone 14 Pro et plus récents. Sur les autres, la Live Activity s'affiche sur l'écran verrouillé. Elle n'est **visible que hors de l'app** (écran d'accueil ou verrouillé). iOS interdit les animations continues : Nexus change de pose toutes les ~8 s tant que l'app tourne.

## Dépannage rapide
- **AirPlay ne trouve pas tes enceintes** : coupe **LocalDevVPN** pendant l'écoute (un VPN actif bloque la découverte AirPlay sur le Wi-Fi). Rallume-le seulement pour installer/rafraîchir.
- **« Cannot start DebugServer » / échec SideStore** : Wi-Fi + LocalDevVPN connectés, redémarre les deux apps ; sinon régénère le fichier de pairing avec iloader.
- **Nexus répond « Gemini est surchargé (503) »** : l'app a déjà essayé plusieurs modèles ; réessaie dans une minute ou choisis un autre modèle dans Réglages.
- **Mise à jour d'iOS** : le fichier de pairing peut devenir invalide → refais l'étape 4 sur un ordinateur.

---------------------------------------------------------------
## Annexe — Google Drive automatique (optionnel, non activé)
Aujourd'hui, les photos de cours vont dans Drive via **Partager → Drive** (aucune configuration).
Une synchro **automatique** exigerait :
1. un projet sur https://console.cloud.google.com avec l'API **Google Drive** activée ;
2. un **ID client OAuth** de type iOS (avec l'identifiant `com.melik.selfbuild`) et un écran de consentement (mode « Test », ton compte ajouté comme testeur) ;
3. dans l'app : la connexion Google (par ex. `ASWebAuthenticationSession`), la conservation sécurisée du jeton, puis l'envoi des fichiers via l'API REST Drive.
C'est faisable gratuitement mais plus complexe ; le partage manuel reste la solution recommandée.

## Annexe — Passer la v3 sur `main`
Tant que tu testes, la v3 vit sur la branche `v3` (builds « Pre-release »). Quand tout va bien, fusionne-la dans `main` (GitHub → Pull requests → New → `v3` → `main` → Merge) : le build de `main` repart seul.
