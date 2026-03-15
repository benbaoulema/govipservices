# Disponibilite et Presence

Ce document decrit le mecanisme mobile de mise en ligne depuis l'accueil.

## Objectif

Permettre a un utilisateur connecte de se declarer disponible pour :

- `travel`
- `parcels`
- `all`

avec une position geographique initiale, puis des mises a jour ponctuelles.

## UI mobile

Point d'entree :

- haut de l'accueil
- panneau dedie sous l'app bar

Comportement :

- etat `Hors ligne` / `En ligne`
- choix de portee : `Voyage`, `Colis`, `Les deux`
- si utilisateur non connecte :
  - ouverture du login au moment d'activer
- si l'utilisateur n'a pas l'aptitude metier correspondante :
  - le scope reste indisponible
  - un message invite a publier un trajet ou proposer un service
- si utilisateur active `En ligne` :
  - permission localisation
  - recuperation position
  - ecriture Firestore

## Stockage Firestore

Document cible :

- `users/{uid}`

Champ utilise :

```json
{
  "availability": {
    "isOnline": true,
    "scope": "travel",
    "updatedAt": "...",
    "lastSeenAt": "...",
    "source": "mobile",
    "location": {
      "lat": 5.348,
      "lng": -4.027,
      "accuracy": 18.0,
      "geohash": "s06g7h0k4"
    }
  },
  "capabilities": {
    "travelProvider": true,
    "parcelsProvider": false
  }
}
```

Champs retenus :

- `availability.isOnline`
- `availability.scope`
- `availability.updatedAt`
- `availability.lastSeenAt`
- `availability.source`
- `availability.location.lat`
- `availability.location.lng`
- `availability.location.accuracy`
- `availability.location.geohash`
- `capabilities.travelProvider`
- `capabilities.parcelsProvider`

## Service Flutter

Fichier :

- `lib/features/user/data/user_availability_service.dart`

Responsabilites :

- lire l'etat courant
- passer en ligne
- passer hors ligne
- rafraichir ponctuellement la position si l'utilisateur est deja en ligne
- calculer un `geohash` local sans dependance supplementaire
- exposer les aptitudes metier pour filtrer les scopes autorises

API actuelle :

- `fetchCurrent()`
- `goOnline(scope: ...)`
- `goOffline()`
- `refreshIfOnline(...)`

## Politique de mise a jour

Choix actuel :

- pas de listener Firestore
- pas de tracking continu permanent
- refresh ponctuel au retour foreground de l'application
- propagation ponctuelle de la disponibilite vers les `services` actifs du proprietaire

But :

- limiter cout Firebase
- limiter consommation batterie
- garder une semantics "presence recente" plutot qu'un tracking temps reel lourd
- permettre au matching colis de requeter directement `services`

## Propagation vers `services`

Quand l'utilisateur passe en ligne ou hors ligne, le service Flutter met a jour tous les documents :

- `services` avec `ownerUid == uid`
- `status == active`

Champs mis a jour :

- `ownerAvailability.isOnline`
- `ownerAvailability.scope`
- `ownerAvailability.lat`
- `ownerAvailability.lng`
- `ownerAvailability.geohash`
- `ownerAvailability.updatedAt`
- `search.isSearchable`
- `search.serviceStatus`
- `search.ownerOnline`
- `search.ownerScope`
- `search.ownerLat`
- `search.ownerLng`
- `search.ownerGeohash`
- `search.ownerAvailabilityUpdatedAt`

Regle actuelle :

- `search.isSearchable = true` seulement si :
  - l'utilisateur est en ligne
  - et le scope vaut `parcels` ou `all`

## Limitations actuelles

- pas de throttling par distance ou par tranche de temps
- les scopes sont filtres par aptitudes simples, pas encore par etat fin des annonces/trajets

## Extensions recommandees

- ajouter un throttling :
  - mise a jour si distance > seuil
  - ou si delai > seuil
- reutiliser le `geohash` pour des requetes geo si la recherche geographique devient necessaire
- propager ensuite l'etat vers les vues metier utiles

## Backfill des utilisateurs existants

Un script Node admin est disponible pour completer les documents `users` deja presents :

- fichier : `functions/scripts/backfill_user_capabilities.js`
- commande dry-run :
  - `cd functions`
  - `npm run backfill:user-capabilities`
- commande ecriture :
  - `cd functions`
  - `npm run backfill:user-capabilities -- --write`

Ce script :

- pose `capabilities.travelProvider` si l'utilisateur possede deja au moins un document dans `voyageTrips`
- pose `capabilities.parcelsProvider` si l'utilisateur a `isServiceProvider == true` ou au moins un document dans `services`
- recalcule `availability.location.geohash` si `lat/lng` sont deja presents

Le script est idempotent :

- sans `--write`, il affiche seulement les patches
- avec `--write`, il met a jour uniquement les documents necessaires
