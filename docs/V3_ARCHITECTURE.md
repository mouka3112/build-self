# SELF BUILD v3 — Architecture (Lot 1)

## 1. Schéma

```
                ┌──────────── UI (projections, aucune copie locale) ─────────────┐
                │ HubView · NexusView · Journal · Onboarding · modules (Lot 2)   │
                └───────┬───────────────────────────────▲────────────────────────┘
       taps (AppAction) │                               │ @Published (lecture directe)
                        ▼                               │
 Notification ──► ActionEngine.apply(_:) ──mutations──► AppStore (@MainActor, SOURCE UNIQUE)
 « ✅ Fait »        │ validate → run → ActionResult        │ tasks · foods · txns · hygieneLog · … · journal · profile
                   │ (status, summary, destination, undo)  │ persistance JSON protégée (+ migration v2)
                   └──► JournalEntry (persisté, « Annuler »)│
                        ▲                                   │
 NexusSession ──────────┘ perform([PlannedAction])          │ AIContext.build (relu à CHAQUE tour)
   │  ▲                                                     ▼
   │  └── NexusTools.plan(ToolCall) ← validation stricte ← GeminiClient.chatTurn (SSE + function calling)
   └── Router.aiTarget (navigate_to) → barre « prochaine action »
 Planner (fonctions pures) : generate · reflow · replan · match  ← utilisé par Engine, Hub ET aperçu des propositions
```

- `AppStore` : unique source de vérité. Les vues ne gardent aucune copie.
- `ActionEngine` : seul chemin de modification métier (UI, Nexus, notifications). Actions typées, validées, idempotentes, annulables (`UndoOp` persistés).
- `Planner` : calculs purs → l'aperçu « Appliquer ce planning » est calculé exactement comme l'exécution.
- `NexusSession` : conversation partagée ; le texte arrive en streaming, les actions arrivent en appels de fonctions (plus aucune balise `[[ACT:…]]`).

## 2. Fonctions Gemini (function calling)

| Fonction | Paramètres (requis en gras) | Action | Proposition ? |
|---|---|---|---|
| log_expense | **amount**, **category** (enum), note | `.expense` | non |
| log_income | **amount**, note | `.income` | non |
| log_meal | **items[]** {**name, grams, kcal, protein**} | `.meal` | non |
| log_water | **ml** | `.water` | non |
| log_hygiene | **habits[]** (teethAM, faceAM, teethPM, facePM, shower, hair) | `.hygiene` | non |
| complete_task | **task** (#XXXX ou titre) | `.completeTask` | non |
| start_task | **task** | `.startTask` | non |
| add_task | **title, start** HH:mm, **duration**, kind, confirm | `.addTask` | si confirm |
| remove_task | **task**, confirm | `.removeTask` | si confirm |
| replan_day | **slots[]** {**task, start**, duration}, reason | `.replanDay` | **toujours** |
| switch_activity | **activity, minutes**, confirm | `.switchActivity` | si confirm |
| log_workout_set | **exercise, weight, reps**, effort 1-3 | `.workoutSet` | non |
| log_health | **kind** (enum), **text** | `.health` | non |
| add_note | **text** | `.note` | non |
| create_reminder | **title, datetime** yyyy-MM-dd HH:mm, repeat (none/daily/weekly/monthly), urgent, confirm | `.reminder` | si confirm |
| add_exam | **subject, date**, topic, confirm | `.exam` | si confirm |
| add_homework | **subject, title, due**, confirm | `.homework` | si confirm |
| complete_homework | **homework** | `.completeHomework` | non |
| log_tutor_session | **tutor** | `.tutorSession` | non |
| pay_tutor | **tutor** | `.tutorPaid` | non |
| complete_challenge | **challenge** | `.completeChallenge` | non |
| undo_last | — | `.undoLast` | non |
| navigate_to | **screen** (enum des écrans) | `.navigate` | non |

Le schéma exact envoyé à l'API est généré par `NexusTools.declarations()` (types `object/string/number/integer/boolean/array`, `enum` pour les valeurs fermées). Chaque appel est revalidé côté app (`NexusTools.plan` puis `ActionEngine.validate`) : un appel invalide apparaît « ⚠️ Refusé » dans le Journal, jamais un faux succès.

## 3. Action → modules mis à jour (en un seul `apply`)

| Action | Modules touchés |
|---|---|
| expense | Finances (+ si « Études » : séances du prof marquées payées) |
| income | Finances |
| meal | Nutrition (aliments) + cartes d'ingrédients manquantes + tâche « repas » la plus proche cochée + tuiles kcal/prot. |
| water | Santé |
| hygiene | Hygiène (log) + tâche(s) d'hygiène du Hub cochée(s) |
| completeTask | Hub (fait + réorganisation si fin en retard) + hygiène liée + curseur muscu (séance suivante) + séance de cours particulier |
| startTask / addTask / removeTask / replanDay / switchActivity | Hub (planning vivant, sans chevauchement ; cours, cours particuliers et sommeil fixes) |
| workoutSet | Musculation |
| health / note | Santé / Notes |
| reminder | Rappels + notification programmée |
| exam | Contrôles + tâche de révision si le contrôle est dans ≤ 3 jours |
| homework / completeHomework | Études (devoirs) |
| tutorSession | Cours particuliers + tâche du Hub cochée |
| tutorPaid | Finances (dépense « Études ») + séances payées |
| completeChallenge | Micro-défis (XP) |
| undoLast | Inverse exacte de la dernière action applicable |
| navigate | Barre « prochaine action » |

## 4. Checklist d'acceptation (exécutée à la lecture du code)

| Phrase | Chemin | Résultat attendu |
|---|---|---|
| « j'ai dépensé 3 dinars en snack » | log_expense → `.expense` → `Txn` | ligne dans Finances, entrée Journal « Dépense −3,00 TND (Snacks) → Finances », bouton Annuler |
| « j'ai mangé du riz et du poulet » | log_meal → `.meal` | aliments + cartes + tâche repas proche cochée + tuiles à jour |
| « je me suis brossé les dents » | log_hygiene(teethPM) → `.hygiene` | habitude + tâche « Dents (soir) » cochées |
| « j'ai fini mes devoirs » | complete_task(#id) → `.completeTask` | tâche cochée, suite réorganisée, « ensuite ‹…› à HH:mm » réel |
| « réorganise ma journée » | replan_day → proposition | bouton « Appliquer ce planning » ; après tap, Hub = aperçu (même `Planner.replan`) |
| « rappelle-moi tous les lundis à 18 h » | create_reminder(weekly) → `.reminder` | visible dans Rappels + notification `rem-<id>` hebdo |
| Erreur 503 | `GeminiClient` → modèle suivant, 2 passes, pause 2 s | message clair listant les modèles essayés si tout échoue, jamais de bulle vide |

## 5. Lot 2 — modules branchés sur le moteur

Toutes les écritures des écrans passent par `ActionEngine` :

| Écran | Actions utilisées |
|---|---|
| Finances | `.expense`, `.income`, scan ticket → `.expense`, suppression → `.delete(.txn)` |
| Études / Lockdown | `.homework`, `.completeHomework` / `.reopenHomework`, `.setLockdown`, validation photo → `.completeHomework` |
| Emploi du temps / contrôles | `.add(.timetable)`, `.exam`, `.delete(…)` |
| Cours particuliers | `.add(.tutor)` (rappels + tâche du jour), `.tutorSession`, `.tutorPaid` (Khallast), `.delete(.tutor)` |
| Cours en photos | `.add(.lesson)` (+ coche la tâche « Photos des cours »), résumé IA → `.update(.lesson)` |
| Rappels | `.reminder`, `.delete(.reminder)` (notification annulée) |
| Muscu | `.workoutSet`, `.finishWorkout`, `.delete(.workoutSet)`, bilan → `.add(.review)` |
| Nutrition | cartes / Autre / photo → `.meal`, suppression → `.delete(.food)` / `.delete(.customFood)` |
| Hygiène / Santé | `.hygiene`, `.water`, `.health`, `.delete(.health)` |
| Garde-robe, Cuisine, Running | `.add` / `.update` / `.delete` (`clothing`, `dish`, `runRecord`) |
| Projets, Défis, Capsule | `.add(.project)`, `.update(.project)`, `.add(.challenge)`, `.completeChallenge` / `.reopenChallenge`, `.add(.capsule)` (notification) |

Actions génériques : `.add(Record)`, `.update(Record)`, `.delete(RecordRef)` — chacune annulable (`UndoOp.remove` / `.upsert`).
Les petites modifications (cocher un habit, une étape de projet, résumé d'un cours, Lockdown) sont « discrètes » : elles passent par le moteur mais ne remplissent pas le Journal.

Restent liés directement à `AppStore` (réglages, pas des données métier) : objectifs kcal/protéines, stock de cuisine, profil de goûts.
Les invites IA n'utilisent plus de prénom/âge/monnaie en dur : tout vient du profil (`store.aiPersona`, `store.currency`).

## 6. Lot 3 — Live Activity, build, installation

- `SelfBuildAttributes` (partagé app + extension) : `ContentState.pose` (idle, wave, lookL, lookR, blink, happy) + `finished` (optionnel, écran « Terminé ✅ »).
- `LiveActivityManager` : pose « coucou » au départ puis cycle toutes les ~8 s, minuteur de repos de muscu affiché dans la Dynamic Island puis retour à la séance, fin avec Nexus content (8 s), diagnostic (autorisations, `.appex`, erreur de `Activity.request`).
- `build.yml` : builds sur `main` et `v3`, un build à la fois par branche, échec si `SelfBuildWidget.appex` manque, Release taguée sur le commit compilé (`--target`), « Pre-release » hors `main`.
- `project.yml` : version 3.0, permissions détaillées, `ITSAppUsesNonExemptEncryption = false`.
- Guide : `GUIDE_SANS_MAC.md`. Tests sur iPhone : `docs/CHECKLIST_TESTS.md`.
