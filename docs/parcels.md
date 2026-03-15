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

- ecran d'entree unique avec :
  - depart detecte automatiquement
  - destination de l'envoi
- affichage inline sur la carte de max `3` correspondances au-dessus du sheet
- contact destinataire

Le shape vise reste aligne avec le modele `demands` utilise cote web.

Sur l'ecran map, le tracé visuel entre départ et arrivée utilise maintenant
Google Directions quand les deux points sont connus. En cas d'échec API, le
fallback reste une liaison simple entre les deux coordonnées.

Champs cibles principaux :

- `pickupCityAddress`
- `pickupLatLng`
- `deliveryAddress`
- `deliveryLatLng`
- `receiverName`
- `receiverContactPhone`

## Matching V1 pour `Expedier`

Apres saisie du depart et de l'arrivee, l'application :

1. requete les `services` actifs avec `search.isSearchable == true`
2. calcule localement un score de correspondance
3. garde au maximum `3` resultats
4. laisse le client choisir un livreur avant la suite

Priorites actuelles :

1. couvre la zone et proche du depart
2. ne couvre pas la zone mais proche du depart
3. couvre la zone mais plus loin

Le prix affiche suit cette regle :

- si une ligne `priceZones` couvre la course :
  - `Tarif prestataire`
- sinon :
  - `Tarif GoVIP`

Le matching reste volontairement simple en V1 :

- couverture de zone par correspondance souple sur les libelles `departZone` / `arrivZone`
- proximite calculee avec la position live du prestataire vers le pickup
- fallback tarifaire plateforme en local

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
- `pickupGeohash`
- `ownerAvailability`
- `search`

## `services` et matching colis

La collection `services/{serviceId}` reste la source metier principale, meme si un utilisateur peut avoir plusieurs services.

Pour preparer `Expedier`, chaque service actif porte des champs derives de recherche :

- `pickupGeohash`
  - geohash de l'adresse de base du service
- `ownerAvailability`
  - copie resumee de la disponibilite du proprietaire
- `search`
  - bloc optimisé pour le matching colis

Exemple de shape :

```json
{
  "ownerUid": "uid_123",
  "status": "active",
  "isValidated": false,
  "pickupLatLng": {
    "lat": 5.348,
    "lng": -4.027
  },
  "pickupGeohash": "s06g7h0k4",
  "ownerAvailability": {
    "isOnline": true,
    "scope": "parcels",
    "lat": 5.349,
    "lng": -4.028,
    "geohash": "s06g7h3b2",
    "updatedAt": "..."
  },
  "search": {
    "isSearchable": true,
    "serviceStatus": "active",
    "isValidated": false,
    "ownerOnline": true,
    "ownerScope": "parcels",
    "ownerLat": 5.349,
    "ownerLng": -4.028,
    "ownerGeohash": "s06g7h3b2",
    "ownerAvailabilityUpdatedAt": "..."
  }
}
```

## Synchronisation disponibilite -> services

Quand un utilisateur passe :

- en ligne
- hors ligne
- ou quand sa position est rafraichie

le service Flutter de disponibilite met a jour tous ses `services` actifs pour recopier :

- `ownerAvailability`
- `search`

Cela permet ensuite a `Expedier` de requeter directement `services` sans jointure runtime systematique avec `users`.

## Comptes legers

Pour les prestataires non connectes :

- le telephone est saisi sur 10 chiffres
- un email technique est genere a partir du numero
- un compte Firebase Auth `email/password` peut etre cree sans verification SMS
- le profil `users/{uid}` est alimente dans la foulee

Voir aussi :

- [User](./user.md)
