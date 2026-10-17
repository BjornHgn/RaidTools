# RaidTools 1.9

Addon de gestion de raid PU pour World of Warcraft Retail (Midnight, 12.1), dans l'esprit de Northern Sky Raid Tools et Method Raid Tools, en plus simple.

## Installation

1. Copie le dossier `RaidTools` (celui qui contient `RaidTools.toc`) dans
   `World of Warcraft\_retail_\Interface\AddOns\`
2. Le chemin final doit être `...\Interface\AddOns\RaidTools\RaidTools.toc`.
3. Relance le jeu (ou `/reload`), active **RaidTools** dans la liste des addons.
4. Clique sur l'icône RaidTools autour de la minimap, ou tape `/rt`.

## Ce que voit un joueur SANS l'addon

Tout ce qui compte passe par les canaux du jeu, visibles par tout le raid. Tout ce qui part au raid est **en anglais**, pour être compris par tous les joueurs PU ; la fenêtre de l'addon reste en français.

| Quoi | Ce qu'il voit |
|---|---|
| Pull | Le compte à rebours officiel de Blizzard + « Pull in 10 s » en alerte raid |
| Pause | « BREAK TIME », « Break: 1 min left », « Break over, let's go! » en alerte raid |
| Calls (barre de calls, raccourcis, macros) | Le call en alerte raid, même en plein boss : « SOAK - Throw Junk », « RAID DEFENSIVES »… |
| Calls de marqueurs | « {crâne} GO TO SKULL {crâne} », « KILL CROSS », « STACK ON STAR »… en alerte raid, avec l'icône |
| Changement de phase | « >> PHASE 2 << » ou « >> INTERMISSION << » en alerte raid quand tu appuies sur Phase suivante |
| Mécaniques clés (lignes `!rw`) | Le message en alerte raid quand tu appuies sur ta touche **Annonce** |
| Assignations (lignes `rc`) | Postées dans le chat raid au ready check |
| Vérif raid | « No food: … », « No flask: … », « Missing Arcane Intellect: … » dans le chat raid |
| Équilibrage des groupes | « Groups balanced: LEFT = G1-G2, RIGHT = G3-G4 » dans le chat raid |
| Marqueurs | Les marqueurs de cible et au sol, visibles par tout le monde |
| Joueurs qui ont MRT | Ta note du boss dans leur fenêtre de note MRT, avec les temps |
| Joueurs qui ont DBM ou BigWigs | Une barre de pull et une barre de pause |

Les joueurs qui ont l'addon ont en plus l'affichage en grand, le son, la voix et leurs rappels perso (rôle, classe, groupe).

**La touche Annonce** : pendant un boss, le jeu interdit aux addons d'envoyer un message tout seul. RaidTools prépare donc hors combat la liste des lignes `!rw` du boss sélectionné. Quand une de ces mécaniques arrive, ton écran affiche « Annonce : Soak… appuie sur F1 ». Un appui l'envoie en alerte raid à tout le monde. Choisis la touche dans Raccourcis > AddOns > RaidTools > « Annoncer le prochain rappel !rw ». Les presets marquent déjà en `!rw` les soaks, les adds et les changements de phase. Pense à sélectionner le bon boss (onglet Raid ou Rappels) avant le premier pull : au ready check, l'addon te dit pour quel boss les annonces sont prêtes. Une fois un boss engagé, il devient le boss sélectionné pour les pulls suivants.

## La barre de calls (l'outil du lead en combat)

Une petite barre déplaçable, affichée automatiquement quand tu es chef ou assistant en raid (`/rt calls` ou le bouton « Barre de calls » pour l'afficher ou la masquer). Tous ses boutons envoient leur `/rw` comme si tu le tapais, donc ils marchent en plein boss.

```
PHASE 2                       [Phase suivante  F4]
[Annonce 3/12 : Soak : Throw Junk           F1]
[SOAK - Throw Junk   F5]  [ADDS - Mushroom   F6]
[SPREAD              F7]  [RAID DEFENSIVES   F8]
[STACK                 ]  [BLOODLUST           ]
...
(crâne) (croix) (carré) (lune) (triangle) (losange) (cercle) (étoile)
```

- **Calls par phase** : les 8 boutons suivent le boss sélectionné et sa phase. Avec un preset, les calls principaux de chaque phase sont déduits des mécaniques (soaks, adds, spreads, frontaux, knockbacks, défensifs), puis complétés par tes calls génériques (onglet Options).
- **Modifier un call** : clic droit (ou Alt + clic) sur un bouton de call, hors combat. Le texte (en anglais) est gardé pour ce boss et cette phase. Vide ou « Par défaut » remet le call d'origine.
- **Phase suivante** (bouton ou touche) : annonce « >> PHASE 2 << » (ou « >> INTERMISSION << ») en alerte raid, recale tes rappels et passe les 8 boutons sur les calls de la nouvelle phase, même en combat. Sur Entombed Sentinels et The Lost Explorers, quand l'addon détecte la phase tout seul en combat, il te demande d'appuyer sur ta touche Phase pour que l'alerte raid et les boutons suivent.
- **Choisir tes calls** : dans la note du boss, une ligne `call TEXTE` impose un call en phase 1, `call p2 TEXTE` en phase 2 (`call p1.5 TEXTE` pour une intermission). Ils passent avant les calls déduits. Exemple :

```
call STACK ON BOSS
call p2 {rt8} GO TO SKULL {rt8}
call p2 BLOODLUST
```

- **Calls de marqueurs** : une ligne de 8 marqueurs sous les calls. Clic : `GO TO`, clic droit : `KILL`, Maj + clic : `STACK ON`, Maj + clic droit : `SOAK`. Exemple : clic droit sur la croix envoie « {croix} KILL CROSS {croix} » en alerte raid, l'icône s'affiche chez tout le monde.
- **Raccourcis** : Options du jeu > Raccourcis > AddOns > RaidTools : « Phase suivante », « Annoncer le prochain rappel !rw », « Call 1 » à « Call 8 » (ils suivent la phase), « Call marqueur : GO TO crâne »… Le raccourci s'affiche sur le bouton.
- La barre ne peut être affichée, masquée ou déplacée qu'hors combat (règle du jeu pour les boutons sécurisés).

## L'icône minimap

- **Clic gauche** : ouvre / ferme la fenêtre.
- **Clic droit** : menu rapide du lead, sans ouvrir la fenêtre : Pull 5 / 10 / 15 s, Pause 5 / 10 / 15 min (et leurs annulations), Ready check, Vérification des rôles, Qui a l'addon ?, Vérif raid, Équilibrer les groupes, Barre de calls, Barre de marqueurs, Calls (ceux de la phase en cours).
- **Glisser** : déplace l'icône autour de la minimap.
- Le menu propose aussi « Masquer cette icône ». `/rt minimap` la réaffiche.

Tout ce que lance le menu part en alerte raid comme depuis la fenêtre. Seule exception : en plein boss, le jeu bloque les calls lancés depuis un menu. Pendant le combat, utilise la barre de calls ou ses raccourcis clavier.

## La fenêtre

Elle se redimensionne avec la poignée en bas à droite (clic droit sur la poignée : taille d'origine), et garde sa taille et sa place. Le contenu s'adapte : les rangées de boutons passent sur deux lignes quand la fenêtre est étroite, les textes reviennent à la ligne, l'éditeur de rappels prend toute la hauteur libre, et chaque onglet défile si besoin. Elle s'ouvre et se ferme (Échap) aussi en combat.

## Onglet Raid

- **Boss** : le boss préparé pour la barre de calls, les annonces `!rw` et le partage des rappels.
- **Pull 5 / 10 / 15 s** : compte à rebours officiel de Blizzard (visible par tout le raid, même sans addon), annoncé en alerte raid.
- **Pause 5 / 10 / 15 min** : annonce « BREAK TIME », rappel à 1 min, annonce de fin. La pause survit à un `/reload` et un joueur qui rejoint le groupe récupère la barre automatiquement.
- **Ready check**, **Rôles**, **Qui a l'addon ?**, **Vérif raid**.
- **Calls en combat** : boutons pour afficher la barre de calls et la barre de marqueurs, et l'aperçu des calls que la barre proposera pour chaque phase du boss sélectionné.
- **Call libre** : tape un call (en anglais) puis Entrée. Il fonctionne hors rencontre ; en plein boss, utilise la barre de calls.
- **Macros** : Options > « Créer les macros de call » crée une macro de personnage `/rw TEXTE` par call générique, à glisser sur tes barres d'action.
- **Alertes raid en grand** : chaque alerte raid du chef (bouton, macro `/rw` ou tapée à la main) s'affiche en gros avec son et voix chez ceux qui ont l'addon, même en plein boss.

## Onglet Rappels (les « customs » par boss)

Choisis le boss, puis écris une ligne par rappel :

```
0:15 BLOODLUST !rw
0:45 Personal defensive @tank
1:30 Soak left @Bjorn,Lyra
2:05 Dispel @heal !rw
```

Écris en anglais les lignes `!rw`, `rc` et `call` : elles partent telles quelles au raid. Les autres lignes ne s'affichent que chez ceux qui ont l'addon, tu peux les écrire comme tu veux.

- Temps depuis le pull (m:ss ou secondes).
- `@cible` : pseudo, `tank`, `heal`, `dps`, `melee`, `ranged`, une classe (`mage`, `prêtre`, `druide`…), un groupe du raid (`g1` à `g8`) ou `all`. Sans cible, c'est pour tout le monde. Exemple d'assignation PU : `0:42 Soak left @g1,g2` et `0:42 Soak right @g3,g4` (avec « Équilibrer les groupes » dans Outils pour des moitiés justes).
- `!rw` : si tu es chef de raid, l'addon l'annonce aussi en alerte raid (hors blocage du jeu en rencontre).
- `#` : commentaire.

**Presets des raids de Midnight** : pour les 10 boss de la saison 1 et les 9 boss de la saison 2 (Nymrissa Wavecaller, Nekzali, Entombed Sentinels, Vashnik, The Lost Explorers, Sszorak, The Twin Fangs, The Coiled Altar, Ula'tek), les boutons **Héroïque** et **Mythique** remplissent l'éditeur avec les mécaniques importantes : tankbusters pour les tanks, AoE, soaks, adds, spreads, frontaux, knockbacks, changements de phase. Les noms de sorts sont en anglais, comme ce qui part au raid. Si tu as chargé un preset avec une version précédente, recharge-le pour avoir les noms anglais et les calls par phase. Supprime ou réécris les lignes à ta sauce, c'est un point de départ. En Normal, prends le preset Héroïque, les timings sont proches.

**Assignations du ready check** : une ligne `rc Soak left @g1,g2` s'affiche au ready check chez les joueurs concernés qui ont l'addon. En tant que chef, l'addon poste aussi toutes les lignes `rc` dans le chat raid, pour que ceux sans l'addon les voient. `{rt1}` à `{rt8}` (ou `{star}`, `{skull}`…) deviennent les icônes de marqueur.

**Importer une note MRT ou NSRT** : colle la note dans l'éditeur, puis clique sur **Importer**.
- Note MRT (lignes `{time:1:30} …`) : sélectionne d'abord le boss. Les temps `{time:0:30,p2}` deviennent des lignes de phase, `{spell:ID}` devient le nom du sort, et les blocs `{H}`, `{T}`, `{D}`, `{p:Nom}`, `{g1}`, `{c:Classe}` deviennent des cibles `@`. Les lignes sans temps sont gardées en commentaire.
- Note NSRT (lignes `time:…;tag:…;text:…`) : elle est rangée toute seule sous le bon boss.

Les débuts de phase sont repris des presets. Ajoute ensuite `!rw` aux lignes que tout le raid doit voir.

**Phases** : les boss à plusieurs phases utilisent deux lignes spéciales :

```
phase 2 2:47        # début estimé de la phase 2 depuis le pull
p2 0:30 Soak        # 30 s après le début réel de la phase 2
```

Comme le jeu ne laisse plus les addons détecter les phases, le début est estimé. Quand la phase change vraiment, appuie sur **Phase suivante** (barre de calls ou raccourci) : alerte raid, rappels recalés et calls de la phase. Les phases à virgule (`phase 1.5`, `p2.5`) sont des intermissions, annoncées « INTERMISSION ».

Pour Entombed Sentinels et The Lost Explorers, le preset ajoute une ligne `autophase` : l'addon repère le changement de phase tout seul, quand la timeline de boss de Blizzard ajoute d'un coup les barres de la nouvelle phase. Surveille-le sur les premiers essais. Le bouton Phase suivante reste là en secours.

**Lisibilité des phases** : dans l'éditeur, chaque phase d'un preset est séparée par un titre du type `# ===== PHASE 2 · début estimé 2:47 =====`. Au changement de phase, une grosse alerte « PHASE 2 » ou « INTERMISSION » s'affiche avec son et voix.

**Panneau de suivi** : pendant le boss, un petit panneau au-dessus des alertes affiche la phase en cours et son chrono, tes 3 prochaines mécaniques avec le temps restant (en rouge sous 5 s), l'heure estimée de la phase suivante et, en haut à droite, les charges de rez de combat du raid avec la recharge en cours. Sur un boss sans rappel, il garde le chrono du combat et les rez. Chaque mécanique a une couleur selon son type : rouge tankbuster, orange AoE, violet soak, vert adds, bleu spread, jaune frontal ou knockback, rose debuff. Il se place avec les alertes (`/rt unlock`) et se désactive dans Options.

Quand le chef t'envoie ses rappels, l'onglet affiche « Reçu de … à HH:MM » pour ce boss.

**Partage** : en tant que chef, les rappels du boss sélectionné (et ceux de « Tous les boss ») sont envoyés automatiquement au raid au ready check et au pull, avant que le combat ne bloque les échanges. Une note identique n'est pas renvoyée dans les 5 minutes, sauf si de nouveaux joueurs ont rejoint. Le bouton **Envoyer au raid** le fait à la main. La note part aussi en note MRT (voir l'onglet Outils).

## Onglet Outils

**Vérif raid** : une seule fenêtre réunit le ready check et la vérif des buffs, avec une ligne par joueur : statut du ready check (prêt, pas prêt, en attente), nourriture, flacon, rune et buffs de raid (coche verte ou croix rouge, nom au survol des icônes). Elle s'ouvre toute seule chez le chef au ready check, ou avec **Vérif raid**, `/rt verif` et le menu de la minimap. Ses boutons : **Ready check**, **Poster au raid** et **Actualiser**. Les buffs de raid (Arcane Intellect, Fortitude, Battle Shout, Mark of the Wild, Skyfury, Blessing of the Bronze) ne sont vérifiés que si la classe qui les donne est là. Rien n'est posté dans le chat automatiquement : seul le bouton **Poster au raid** envoie les manques dans le chat raid :

```
RaidTools · Raid check: food 18/20, flask 15/20, rune 6/20
No food: Lyra, Tankou
No flask: ...
```

La liste des joueurs sans rune et ceux trop loin pour être vérifiés restent dans ton chat à toi. Impossible en combat : le jeu masque les buffs.

**Barre de marqueurs** : une petite barre déplaçable. Ligne « Cible » : marqueur sur ta cible. Ligne « Sol » : marqueur au sol (clique puis vise le sol). Clic gauche pose, clic droit retire, la croix rouge retire tout. Elle marche en combat, mais ne peut être affichée ou masquée qu'hors combat. Il faut être chef ou assistant en raid.

**Groupes** : **Équilibrer les groupes** répartit tanks, soigneurs, mêlées et distances à parts égales entre la moitié gauche et la moitié droite du raid (G1-G2 / G3-G4 en mythique, G1-G3 / G4-G6 en normal et héroïque à 30), un joueur à la fois, puis l'annonce dans le chat raid. Il faut être chef de raid, hors combat. Aussi dans le menu de la minimap et avec `/rt groupes`.

**Assist automatique** : écris les pseudos de tes assistants habituels (séparés par des virgules). Ils passent assistant dès qu'ils sont dans le raid, si tu es chef.

**Invitations** : coche « Inviter qui me chuchote le mot » et choisis le mot (`inv` par défaut). Le groupe passe en raid tout seul. Les chuchotements ne sont écoutés que si l'option est cochée.

**Journal de combat** : coché, le journal de combat (pour Warcraft Logs) démarre tout seul en entrant dans un raid et s'arrête quand tu en sors. L'addon n'affiche pas les logs : le fichier est dans `World of Warcraft\_retail_\Logs\WoWCombatLog-*.txt`, à envoyer sur warcraftlogs.com avec l'appli Warcraft Logs (Uploader).

## Pulls et lecteur de logs

Le jeu interdit aux addons de lire le fichier de log, et depuis Midnight ils ne voient plus le journal de combat en direct. Deux outils le remplacent :

- **Onglet Pulls** (dans l'addon) : les 30 derniers pulls avec boss, difficulté, kill ou wipe, durée, puis le détail minute par minute des morts et rez dans l'ordre, des phases et de tes calls. « Poster au raid » envoie le résumé en anglais (durée, morts, premiers morts), seulement quand tu cliques.
- **LecteurLogs.html** (dans le dossier de l'addon) : ouvre-le dans ton navigateur et dépose ton fichier `WoWCombatLog-*.txt`. Pour chaque pull : qui est mort, quand et de quoi (les derniers coups reçus), les sorts qui ont fait le plus mal au raid, les dégâts, soins, interruptions, dispels, pierres de soins et potions de chaque joueur. Le fichier est lu dans le navigateur, rien n'est envoyé. Le pourcentage du boss demande la journalisation avancée du combat (déjà requise par Warcraft Logs).

**Joueurs avec MRT, DBM ou BigWigs** :
- **Note MRT** : beaucoup de joueurs PU ont Method Raid Tools. Tes rappels leur arrivent dans leur note MRT, en anglais, avec les temps au format MRT. La note reprend tes assignations `rc`, les lignes `!rw` et toutes les lignes que tu as écrites toi-même. Les lignes génériques des presets sans `!rw` (AoE, tankbusters…) n'y sont pas, DBM et BigWigs les affichent déjà. Elle part avec tes rappels (ready check, pull, Envoyer au raid) ou avec le bouton **Envoyer la note MRT**. MRT n'accepte la note que du chef ou d'un assistant, et elle remplace leur note actuelle.
- **DBM / BigWigs** : tes pulls et tes pauses leur affichent une barre, comme si tu les avais lancés avec leur addon.

## Fenêtres, voix et démarrage

Options > « Fenêtres et voix » : un interrupteur pour la voix (synthèse vocale, sons perso et décomptes), la fenêtre de suivi (chrono du combat, phase, prochaines mécaniques), les barres de temps, les alertes au centre de l'écran, la barre de calls, la barre de marqueurs et l'icône de la minimap.

Par défaut, **rien ne démarre tout seul au pull** : pas de rappels, pas de chrono, pas de suivi. Tu fais tes calls toi-même avec la barre de calls ou la fenêtre. Coche « Lancer rappels, chrono et suivi tout seuls au pull » pour retrouver le mode automatique. Le bouton **Tester** de l'onglet Rappels marche toujours.

## Couper des alertes

- **Par type** : Options > « Alertes à afficher » : tankbusters, AoE, soaks, adds, spreads, frontaux, knockbacks, absorbs, debuffs, changements de phase, rappels perso, pauses. Décoché = ni alerte, ni son, ni barre, ni ligne dans le suivi.
- **Par boss** : Rappels > « Mes alertes pour ce boss ».
- **Une par une** : Options > « Alertes une par une » : choisis le boss, chaque alerte a sa case (avec le nombre de fois où elle tombe), plus « Tout activer » / « Tout couper ».

Tes annonces `!rw` pour le raid partent toujours : seules tes alertes à toi sont coupées.

## Mode édition

`/rt unlock` (ou Options > Aperçu / déplacer) : glisse les fenêtres à la souris. Chacune affiche une petite **roue** : taille (50 à 200 %), opacité, afficher ou masquer, réinitialiser. La **poignée** en bas à droite agrandit ou réduit en glissant. Fenêtres concernées : alertes, barres de temps, suivi de phase, barre de calls, barre de marqueurs (ces deux-là hors combat seulement). `/rt lock` pour finir.

## Tes propres sons

Dépose des fichiers `.ogg` ou `.mp3` dans `RaidTools\Sounds\` pour remplacer la voix de synthèse. Le nom du fichier reprend le texte du call ou du rappel, en minuscules, sans accents ni icônes et avec `_` à la place des espaces : `soak.ogg`, `spread.ogg`, `raid_defensives.ogg`, `break_over.ogg`, `go_to_skull.ogg`. Pour « Soak : Toxic Droplets » ou « SOAK - Toxic Droplets », l'addon essaie `soak_toxic_droplets.ogg` puis `soak.ogg`. Les calls étant passés en anglais, renomme tes anciens fichiers (`defensifs_raid.ogg` devient `raid_defensives.ogg`, `fin_de_pause.ogg` devient `break_over.ogg`). Relance complètement le jeu après avoir ajouté un fichier. Les sons LibSharedMedia d'autres addons marchent aussi s'ils portent le même nom.

## Décomptes vocaux

La fin de pause est annoncée par un décompte « 5, 4, 3, 2, 1 ». Pour les rappels, active le décompte dans Options (de 1 à 5 secondes). Avec des fichiers `1.ogg` à `5.ogg` dans `Sounds\`, ce sont tes sons qui sont joués.

## Ready check

Au ready check, l'addon te dit dans quel groupe tu es et t'alerte s'il te manque le buff de nourriture ou si ton équipement est sous 30 % de durabilité.

## Commandes

| Commande | Effet |
|---|---|
| `/rt` | ouvre / ferme la fenêtre |
| `/rt pull 10` · `/rt pull stop` | pull / annulation |
| `/rt break 10` · `/rt break stop` | pause de 10 min / annulation |
| `/rt call SOAK` | call (hors rencontre) |
| `/rt phase` · `/rt phase 3` | recale les rappels sur la phase suivante / la phase 3 (sans alerte raid : en combat, utilise la touche Phase) |
| `/rt check` | liste qui a l'addon dans le groupe (bouton « Qui a l'addon ? ») |
| `/rt test` · `/rt stop` | tester / arrêter les rappels du boss sélectionné |
| `/rt unlock` · `/rt lock` | aperçu des alertes, des barres et du panneau de suivi pour les placer / valider |
| `/rt verif` | ouvre la fenêtre de vérif raid (ready check, nourriture, flacon, rune, buffs) |
| `/rt calls` | affiche / masque la barre de calls |
| `/rt marqueurs` | affiche / masque la barre de marqueurs |
| `/rt groupes` | équilibre les groupes (moitié gauche / droite) |
| `/rt mrt` | envoie la note du boss sélectionné aux joueurs MRT |
| `/rt minimap` | réaffiche l'icône minimap |

## Limites liées à Midnight

- Les addons ne lisent plus le journal de combat : les rappels sont calés sur le chrono, et les phases se recalent à la main.
- Pendant une rencontre, le jeu bloque les messages envoyés par les addons (alertes raid automatiques `!rw`, messages entre addons). Les boutons de la barre de calls ne sont pas concernés car c'est toi qui envoies le `/rw`.
- En combat, l'addon ne peut pas changer seul les boutons de la barre : c'est ta touche Phase qui les fait passer à la phase suivante.

## Légèreté

L'addon ne tourne presque pas quand rien ne se passe : la fenêtre n'est créée qu'à la première ouverture et seul l'onglet affiché se recalcule, les barres de temps et le panneau de suivi s'arrêtent quand ils sont vides ou masqués, les mises à jour du raid sont regroupées (une par demi-seconde quand le raid se remplit), les chuchotements ne sont écoutés que si l'invitation auto est cochée, et les rappels de chaque joueur sont calculés une fois par pull au lieu de plusieurs fois par seconde.
- Il faut être chef ou assistant pour qu'une alerte raid s'affiche en raid.

## Crédits

Les timings des presets sont des relevés de combat (IDs de rencontre, IDs de sort, temps de cast) publiés avec Northern Sky Raid Tools. Plusieurs outils (vérif raid, barre de marqueurs, note MRT, assist et journal de combat automatiques, équilibrage des groupes) s'inspirent de Method Raid Tools. Le code de RaidTools est écrit séparément, sans bibliothèque externe (l'icône minimap compris) : seuls les formats de message publics de MRT, DBM et BigWigs sont utilisés pour leur parler. Garde ces presets pour ton usage et celui de ton raid, ne les republie pas.
