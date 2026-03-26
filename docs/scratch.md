# Scratch Cards et Rewards

Cette doc decrit le fonctionnement du systeme de cartes a gratter et des recompenses associees.

## Vue d'ensemble

- Les campagnes sont stockees dans `scratch_campaigns/{campaignId}`.
- Une campagne peut etre declenchee par `app_launch`, `payment_completed` ou `wallet_topup`.
- Quand une campagne est eligibile, une carte est creee dans `user_scratch_cards/{uid}/cards/{cardId}`.
- Quand l'utilisateur revele la carte, le backend tire une recompense et cree un document dans `user_rewards/{uid}/rewards/{rewardId}`.

## Structure d'une reward dans une campagne

Chaque entree de `scratch_campaigns.{campaignId}.rewards[]` suit cette logique:

- `id`
  - identifiant technique de la recompense dans la campagne
- `type`
  - `discount`, `free_trip`, `cash` ou `nothing`
- `label`
  - texte affiche a l'utilisateur
- `value`
  - valeur monetaire ou pourcentage selon le type
- `weight`
  - poids relatif utilise pendant le tirage aleatoire
- `totalAvailable`
  - stock total configure, avec `-1` pour illimite
- `remainingCount`
  - stock restant decremente a chaque gain

## Detail du poids `weight`

Le champ `weight` ne represente pas un pourcentage fixe. C'est un poids relatif entre les recompenses eligibles.

Regles actuelles:

- une reward avec `weight <= 0` est exclue du tirage
- une reward avec `remainingCount == 0` est exclue du tirage
- la probabilite finale depend du poids de chaque reward par rapport a la somme des poids eligibles

Exemple:

- reward A: `weight = 10`
- reward B: `weight = 5`
- reward C: `weight = 1`

Total = `16`

- A a `10/16` de chance
- B a `5/16` de chance
- C a `1/16` de chance

Autrement dit, une reward avec `weight = 10` est 10 fois plus probable qu'une reward a `weight = 1`, tant que les deux sont encore eligibles.

## Expiration en jours

Il faut distinguer la carte et la recompense utilisateur:

### Carte a gratter

- la carte creee dans `user_scratch_cards` expire actuellement au bout de `30 jours`
- cette duree est definie en dur dans `functions/src/scratch/engine.ts`
- la date est stockee dans `expiresAt`

### Reward utilisateur

- le modele `UserReward` supporte un champ optionnel `expiresAt`
- en revanche, dans le code actuel de `revealScratchCard`, aucune expiration par defaut n'est renseignee sur la reward creee
- donc aujourd'hui, la reward n'a pas de duree d'expiration en jours automatiquement appliquee par le backend
- si un `expiresAt` est ajoute plus tard, `redeemReward` refusera bien l'utilisation apres expiration

## Points d'attention

- Si on veut une expiration metier des rewards, il faudra definir clairement une duree en jours, puis renseigner `expiresAt` lors de la creation du document `user_rewards`.
- La doc doit rester alignee avec le comportement backend reel, surtout sur `weight`, `remainingCount` et `expiresAt`.
