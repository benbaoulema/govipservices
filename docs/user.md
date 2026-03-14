# User

La feature `user` couvre l'identite applicative, le profil et certains champs metier transverses.

## Routes Flutter

- `/auth/login`
- `/auth/signup`
- `/auth/forgot-password`
- `/user/account`

## Pages principales

- `login_page.dart`
- `create_account_page.dart`
- `forgot_password_page.dart`
- `account_page.dart`

## Authentification

## Login

Le login accepte :

- un email classique
- ou un numero de telephone a 10 chiffres

Quand un numero est saisi :

- il est converti en email technique de type `225XXXXXXXXXX@govipuser.local`
- le login Firebase se fait ensuite sur cet email technique

## Compte leger

Utilise notamment dans `parcels/offer-service`.

Principe :

- l'utilisateur saisit telephone + mot de passe
- un email synthétique est genere a partir du numero
- Firebase Auth cree un compte `email/password`
- `users/{uid}` est renseigne avec le profil utile

## Profil Firestore

Document :

- `users/{uid}`

Champs frequents :

- `uid`
- `email`
- `displayName`
- `role`
- `phone.countryCode`
- `phone.number`
- `service`
- `isServiceProvider`
- `capabilities`
- `availability`

## Capacites metier

Ces flags sont utilises pour conditionner certains comportements UI, notamment la mise en ligne.

- `capabilities.travelProvider`
  - pose apres publication d'un trajet
- `capabilities.parcelsProvider`
  - pose apres creation d'un service colis

## Disponibilite

La disponibilite geolocalisee est geree separement :

- `availability.isOnline`
- `availability.scope`
- `availability.location.lat`
- `availability.location.lng`
- `availability.location.geohash`

Voir :

- [Disponibilite et presence](./availability.md)
