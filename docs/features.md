# Features

Ce document sert de vue rapide sur les features du projet et leur role.

## Structure

- `lib/app`
  - shell applicatif, routes, page d'accueil
- `lib/features`
  - features metier par domaine
- `lib/shared`
  - composants reutilisables transverses

## Features metier

### `travel`

Fonctionnalites principales :

- recherche et reservation de trajets
- publication et gestion de trajets
- detail trajet
- detail reservation
- gestion des reservations associees a un trajet

Organisation dominante :

- `data`
  - acces Firestore et services metier
- `domain`
  - modeles et contrats
- `presentation`
  - pages, etats, navigation, widgets

Notes :

- `TravelRepository` gere les trajets publies, la recherche et la mise a jour
- `VoyageBookingService` gere les reservations
- `TripDetailPage` est le point de detail principal pour un trajet

### `parcels`

Fonctionnalites actuelles :

- expedition
- VIP shopping
- proposition de service

Etat :

- feature encore plus legere que `travel`
- prevue pour reutiliser aussi le systeme de notifications transverse

### `user`

Fonctionnalites principales :

- connexion
- creation de compte
- mot de passe oublie
- compte utilisateur

## Feature transverse

### `notifications`

Objectif :

- centraliser les notifications in-app pour tous les domaines
- preparer le terrain pour les push plus tard

Structure :

- `domain/models/app_notification.dart`
  - modele metier generique
- `domain/repositories/notifications_repository.dart`
  - contrat de la feature
- `data/firestore_notifications_repository.dart`
  - implementation Firestore
- `presentation/pages/notifications_page.dart`
  - centre de notifications
- `presentation/widgets/notifications_app_bar_button.dart`
  - cloche + badge

Champs importants :

- `domain`
  - `travel`, `parcel`, `system`
- `type`
  - type fonctionnel
- `entityType`
  - ressource cible : `trip`, `booking`, etc.
- `entityId`
  - identifiant de la ressource
- `data`
  - metadonnees pour ouvrir le bon ecran

Regle d'architecture :

- chaque feature produit ses notifications via le repository commun
- la logique d'affichage et de lecture reste dans `notifications`
- on evite de melanger messages et notifications

Fonctionnalites deja en place :

- centre de notifications in-app
- badge de notifications non lues dans l'app bar
- filtres `Toutes` et `Non lues`
- marquage individuel `lu / non lu`
- marquage global `Tout lire`
- navigation directe depuis une notification vers le bon ecran `travel`
- chargement a la demande, sans listener temps reel permanent
- base FCM preparee cote Flutter et Cloud Functions

Choix technique actuel :

- pas de realtime Firestore sur les notifications internes
- chargement ponctuel a l'ouverture des ecrans
- refresh manuel dans la page notifications
- cout Firestore mieux maitrise pour cette partie

Types `travel` deja emis :

- `booking_created`
- `booking_status_updated`
- `booking_cancelled`
- `trip_updated`
- `trip_cancelled`

Push :

- les push FCM sont declenches par Cloud Functions a partir des notifications Firestore
- la navigation a l'ouverture d'un push reutilise la meme logique que les notifications in-app
- voir aussi [Notifications et FCM](./notifications.md)

## Documentation existante

- [Arrets intermediaires](./travel/intermediate_stops.md)

## Prochaine extension recommandee

- ajouter les notifications `parcel`
- rendre chaque type de notification profondement navigable
- brancher FCM apres stabilisation de la couche in-app
