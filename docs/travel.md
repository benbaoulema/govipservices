# Travel

La feature `travel` couvre la publication, la recherche et la reservation de trajets.

## Routes Flutter

- `/travel/add-trip`
- `/travel/book-trip`
- `/travel/trip-detail`
- `/travel/my-trips`
- `/travel/messages`

## Pages principales

- `add_trip_page.dart`
- `book_trip_page.dart`
- `trip_detail_page.dart`
- `my_trips_page.dart`
- `booking_detail_page.dart`

## Flux principaux

### Publier un trajet

Fichier principal :

- `lib/features/travel/presentation/pages/add_trip_page.dart`

Le flux collecte notamment :

- depart
- arrivee
- date et heure
- places
- prix
- conducteur
- contact
- vehicule
- options confort
- arrets intermediaires

Effets metier :

- ecriture dans `voyageTrips`
- mise a jour du profil user
- activation de `capabilities.travelProvider`

### Reserver un trajet

Services principaux :

- `TravelRepository`
- `VoyageBookingService`

Effets metier :

- creation d'une reservation dans `voyageBookings`
- creation d'une notification `booking_created` pour le conducteur
- mise a jour des places selon le statut de reservation

### Detail trajet conducteur

Le detail trajet permet notamment :

- voir les reservations
- accepter ou refuser une demande
- recevoir une popup globale quand une nouvelle reservation arrive

## Collections et champs principaux

### `voyageTrips`

Champs frequents :

- `ownerUid`
- `departurePlace`
- `arrivalPlace`
- `departureDate`
- `departureTime`
- `seats`
- `pricePerSeat`
- `currency`
- `vehicleModel`
- `vehiclePhotoUrl`
- `status`

### `voyageBookings`

Champs frequents :

- `tripId`
- `tripOwnerUid`
- `requesterUid`
- `requestedSeats`
- `status`
- `segmentFrom`
- `segmentTo`
- `segmentPrice`

## Notes

- la logique d'arrets intermediaires est documentee separement
- les notifications `travel` sont branchees sur Firestore + Cloud Functions

Voir aussi :

- [Arrets intermediaires](./travel/intermediate_stops.md)
- [Notifications et FCM](./notifications.md)
