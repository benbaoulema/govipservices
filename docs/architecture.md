# Architecture

Ce projet est une application Flutter organisee par features metier.

## Arborescence principale

- `lib/app`
  - shell applicatif
  - routes
  - page d'accueil
- `lib/features`
  - `travel`
  - `parcels`
  - `user`
  - `notifications`
- `lib/shared`
  - composants et utilitaires transverses
- `functions`
  - Cloud Functions Firebase
- `docs`
  - documentation projet

## Principe d'organisation

Chaque feature suit autant que possible une separation simple :

- `data`
  - acces Firestore, services, repositories
- `domain`
  - modeles et contrats
- `presentation`
  - pages, widgets, navigation locale

## Backend principal

Stockage principal :

- Firestore
- Firebase Authentication
- Firebase Cloud Messaging
- Firebase Storage
- Cloud Functions

## Collections Firestore importantes

- `users`
- `voyageTrips`
- `voyageBookings`
- `services`
- `demands`
- `notifications`
- `pushInstallations`
- `typeVehicules`

## Regles techniques retenues

- eviter les listeners temps reel inutiles
- preferer les chargements ponctuels quand le produit ne demande pas du live
- conserver un contrat Firestore simple et coherent entre mobile et web
- documenter les champs metier transverses dans `users`

## Champs transverses importants dans `users/{uid}`

- `role`
- `phone`
- `service`
- `isServiceProvider`
- `capabilities.travelProvider`
- `capabilities.parcelsProvider`
- `availability`

## Cloud Functions

Le dossier `functions/` contient la logique serveur liee aux notifications push.

Point principal actuel :

- `sendPushOnNotificationCreated`

Voir :

- [Notifications et FCM](./notifications.md)
