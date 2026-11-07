# SELF BUILD v3 — Checklist de tests sur iPhone

Coche au fur et à mesure. Si un test échoue : note ce que tu as fait, ce que tu attendais et ce qui s'est passé, puis envoie-le à Claude.

## A. Installation et premier lancement
- [ ] L'app s'installe via SideStore et s'ouvre (pas d'écran noir).
- [ ] Onboarding : « Tester la clé » affiche ✅ avec une vraie clé, un message clair avec une clé fausse.
- [ ] Ville « Le Kef » → « Vérifier » affiche 📍 Le Kef, Tunisie. La météo du Hub affiche la bonne ville.
- [ ] Calories / protéines calculées à l'étape 4, modifiables.
- [ ] Après « C'est parti », le Hub affiche un planning qui commence à ton heure de réveil.
- [ ] Tes anciennes données v2 (dépenses, séries, devoirs…) sont toujours là.

## B. Hub (la pièce maîtresse)
- [ ] Carte « À VENIR · dans X min » + « Commencer maintenant » : la tâche passe à l'heure actuelle, les suivantes glissent sans chevauchement ; cours et sommeil ne bougent pas.
- [ ] Carte « EN COURS » : « Démarrer / Mode Focus » lance la Live Activity ; « Terminé » coche la tâche.
- [ ] « ENSUITE » affiche toujours l'heure ACTUALISÉE après un changement.
- [ ] Un cours dont l'heure de fin est passée disparaît tout seul.
- [ ] « Je fais autre chose » (Famille, 30 min) : la suite est décalée de 30 min ; le Journal l'indique.
- [ ] Tuiles : kcal/prot., solde, devoirs, hygiène X/6, séance, prochain cours, prochain contrôle, prochain cours particulier — un tap ouvre l'écran.
- [ ] « Demander à Nexus quoi faire » n'apparaît que quand tout le planning est fait, et ouvre Nexus avec la question déjà envoyée.

## C. Nexus + Journal (critère d'acceptation)
Après chaque phrase, vérifie SANS relancer l'app : le Journal, les tuiles et le planning du Hub.
- [ ] « j'ai dépensé 3 dinars en snack » → ligne dans Finances + « ✅ Dépense −3,00 TND (Snacks) » + bouton Annuler (qui la retire vraiment).
- [ ] « j'ai mangé du riz et du poulet » → aliments dans Nutrition + carte créée si nouvelle + tâche repas cochée + tuile kcal à jour.
- [ ] « je me suis brossé les dents » (le soir) → Hygiène « Dents (soir) » ✓ ET tâche du Hub cochée.
- [ ] « j'ai fini mes devoirs » → tâche cochée, « ensuite ‹…› à HH:mm » avec l'heure réelle.
- [ ] « réorganise ma journée » → bandeau « Nexus a dit » avec bouton « Appliquer ce planning » ; après le tap, le Hub correspond aux heures proposées.
- [ ] « rappelle-moi tous les lundis à 18 h de ranger mon sac » → visible dans Rappels « chaque lundi à 18:00 » + notification reçue lundi.
- [ ] Phrase sans montant (« j'ai acheté un truc ») → Nexus pose une question, rien n'est inventé.
- [ ] Même phrase envoyée deux fois de suite → la 2ᵉ est « Doublon ignoré ».
- [ ] Mode avion → message d'erreur clair (pas de bulle vide qui tourne à l'infini).
- [ ] Réponse lue à voix haute (🔊) : voix naturelle ou voix française de l'iPhone.
- [ ] Dictée 🎤 et photo 📷 fonctionnent dans le chat.

## D. Modules
- [ ] **Finances** : dépense en 2 taps (catégorie puis montant), argent reçu, scan de ticket, suppression (annulable dans le Journal).
- [ ] **Cours particuliers** : ajout d'un prof → séance dans le planning du bon jour ; « Séance faite ✅ » ; « Khallast 💸 » crée la dépense « Études » ; rappel 1 h avant ; rappel de paiement le dernier jour du mois à 18 h.
- [ ] **Études** : devoirs cochés/décochés ; contrôle dans ≤ 3 jours → tâche « Réviser… » ajoutée.
- [ ] **Lockdown** : plein écran + compte à rebours + bruit ; photo des devoirs validée par l'IA déverrouille ; maintenir le cadenas 5 s = sortie de secours ; quitter l'app → notification « Lockdown actif ».
- [ ] **Cours en photos** : photo → résumé automatique ; la tâche « Photos des cours » se coche ; partage vers Drive.
- [ ] **Muscu** : série validée → repos 90 s + notification + compte à rebours dans la Dynamic Island ; « Nexus adapte » propose charge/reps (+2,5 kg max) ; vidéo YouTube ; « Séance terminée » → confettis + bilan + photo (derrière Face ID dans Bilans).
- [ ] **Nutrition** : tap sur une carte = portion ajoutée ; appui long = autre portion ; « Autre » + estimation IA ; photo du repas.
- [ ] **Hygiène** : cocher/décocher met à jour le Hub ; série de jours.
- [ ] **Santé** : +250 ml, symptômes, PDF « rapport médecin » partageable.
- [ ] **Safe Space** : Face ID ; se reverrouille dès que tu quittes l'app ; analyse d'humeur seulement après confirmation.
- [ ] **Garde-robe** : photo de plusieurs habits → tous ajoutés ; propre/sale ; tenue suggérée selon la météo de ta ville.
- [ ] **Cuisine** : recette selon le stock ; photo du plat → note /10 et profil de goûts mis à jour.
- [ ] **Running** : GPS + tracé + allure ; coach vocal toutes les 3 min et à chaque km ; la musique baisse quand il parle ; Live Activity pendant la course.
- [ ] **Musique** : import, lecture, AirPlay (LocalDevVPN coupé), bruits blancs.
- [ ] **Projets / Défis / Capsule / Bilans** : roadmap IA cochable ; défis + XP + série ; capsule verrouillée + notification ; anneaux, analyse, Story 1080×1920 partageable.

## E. Dynamic Island / Live Activity
- [ ] Réglages → Dynamic Island : « ✅ autorisées » et « ✅ Extension présente ».
- [ ] « Tester la Dynamic Island » puis écran d'accueil : Nexus à gauche, titre, compte à rebours ; la pose change toutes les ~8 s tant que l'app tourne.
- [ ] Fin d'une séance / d'un Lockdown réussi : « Terminé ✅ » avec Nexus content, puis disparition après quelques secondes.

## F. Notifications
- [ ] Rappel de tâche avec vignette Nexus, boutons « ✅ Fait » et « ⏰ +10 min ».
- [ ] « ✅ Fait » coche la tâche dans le Hub (et l'action apparaît dans le Journal, source « Notification »).
- [ ] « ⏰ +10 min » renvoie la notification 10 min plus tard.
