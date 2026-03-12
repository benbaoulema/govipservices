# Notifications et FCM

Ce projet utilise deux couches complementaires :

- notifications in-app dans Firestore
- push FCM pour prevenir l'utilisateur hors de l'application

## Architecture retenue

### In-app

- collection Firestore `notifications`
- historique conserve
- lecture dans l'application
- marquage `lu / non lu`

### Push

- tokens stockes dans `pushInstallations/{installationId}`
- compatibilite de lecture conservee temporairement avec
  `userPushTokens/{uid}/tokens/{token}`
- Cloud Function declenchee a la creation d'une notification
- envoi FCM a partir des notifications deja ecrites en base

## Flutter

Elements ajoutes :

- `firebase_messaging`
- service FCM : `lib/features/notifications/presentation/fcm_service.dart`
- depot tokens : `lib/features/notifications/data/push_token_repository.dart`
- navigation commune depuis les notifications et les push :
  `lib/features/notifications/presentation/notification_navigation.dart`

Comportement :

- demande de permission push
- creation d'un `installationId` persistant meme sans authentification
- enregistrement du token pour cette installation
- liaison optionnelle de l'installation au `uid` quand l'utilisateur se connecte
- conservation du push pour les invites apres deconnexion
- ouverture du bon ecran quand l'utilisateur touche une notification push

## Cloud Functions

Fichiers :

- `functions/package.json`
- `functions/index.js`
- `firebase.json`

Function ajoutee :

- `sendPushOnNotificationCreated`

Role :

- ecoute `notifications/{notificationId}`
- filtre les types autorises
- recupere les tokens actifs du destinataire par `userId` ou `installationId`
- envoie le push FCM
- supprime les tokens invalides

## Ciblage backend

Un document `notifications` peut cibler :

- un utilisateur connecte avec `userId`
- une installation invitee avec `installationId`
- les deux pendant une transition si necessaire

Champs minimaux :

- `userId`: string optionnel
- `installationId`: string optionnel
- au moins un des deux doit etre renseigne
- `domain`
- `type`
- `title`
- `body`
- `entityType`
- `entityId`
- `status: unread`
- `data`
- `createdAt`
- `updatedAt`

## Types actuellement prevus pour le push

- `booking_created`
- `booking_status_updated`
- `booking_cancelled`
- `trip_updated`
- `trip_cancelled`

## Mise en place locale

Le repo n'avait pas encore de configuration Firebase CLI complete.

Etapes a faire localement :

1. installer les dependances Flutter
   - `flutter pub get`
2. installer les dependances Functions
   - `cd functions`
   - `npm install`
3. lier le projet Firebase
   - `firebase login`
   - `firebase use --add`
4. deployer les functions
   - `firebase deploy --only functions`

## Points d'attention

### Android

- `POST_NOTIFICATIONS` ajoute dans le manifest
- verifier que le projet Firebase Android utilise bien les bons fichiers `google-services.json`

### iOS

- activer Push Notifications dans Xcode
- activer Background Modes > Remote notifications
- ajouter le fichier `GoogleService-Info.plist` si absent
- configurer la cle APNs dans Firebase

## Limite actuelle

- les notifications in-app restent volontairement en chargement a la demande
- pas de listener temps reel permanent pour limiter le cout Firestore
