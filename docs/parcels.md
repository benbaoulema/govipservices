# Parcels

La feature `parcels` couvre trois parcours distincts :

- expedier
- VIP shopping
- proposer un service

## Routes Flutter

- `/parcels/ship-package`
- `/parcels/vip-shopping`
- `/parcels/offer-service`

## Pages principales

- `ship_package_page.dart`
- `vip_shopping_page.dart`
- `offer_service_page.dart`

## Expedier

Le flux `Expedier` est un wizard mobile progressif.

Etapes actuellement posees :

- adresse de recuperation
- adresse de livraison
- contact destinataire

Le shape vise reste aligne avec le modele `demands` utilise cote web.

Champs cibles principaux :

- `pickupCityAddress`
- `pickupLatLng`
- `deliveryAddress`
- `deliveryLatLng`
- `receiverName`
- `receiverContactPhone`

## Proposer un service

Le flux `Proposer` est l'equivalent mobile de la creation d'annonce/service web.

Etapes principales :

- choix du type d'engin
- adresse de base
- zones tarifaires
- infos perso
- photo de l'engin
- poids max
- description

Effets metier :

- creation ou rattachement d'un compte leger si necessaire
- ecriture du document `services`
- activation de `capabilities.parcelsProvider`

## `services`

Champs frequents ecrits par le flux mobile :

- `title`
- `name`
- `ownerUid`
- `contactName`
- `contactPhone`
- `cityName`
- `pickupCityAddress`
- `pickupLatLng`
- `priceUnit`
- `priceZones`
- `maxWeight`
- `description`
- `photoUrl`
- `photoStoragePath`
- `typeVehicule`
- `isValidated`
- `status`

## Comptes legers

Pour les prestataires non connectes :

- le telephone est saisi sur 10 chiffres
- un email technique est genere a partir du numero
- un compte Firebase Auth `email/password` peut etre cree sans verification SMS
- le profil `users/{uid}` est alimente dans la foulee

Voir aussi :

- [User](./user.md)
