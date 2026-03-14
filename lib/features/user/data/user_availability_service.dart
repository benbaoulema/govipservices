import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';

enum UserAvailabilityScope { travel, parcels, all }

class UserAvailabilitySnapshot {
  const UserAvailabilitySnapshot({
    required this.isOnline,
    required this.scope,
    this.lat,
    this.lng,
    this.geohash,
    this.canProvideTravel = false,
    this.canProvideParcels = false,
  });

  final bool isOnline;
  final UserAvailabilityScope scope;
  final double? lat;
  final double? lng;
  final String? geohash;
  final bool canProvideTravel;
  final bool canProvideParcels;

  factory UserAvailabilitySnapshot.offline() {
    return const UserAvailabilitySnapshot(
      isOnline: false,
      scope: UserAvailabilityScope.travel,
    );
  }
}

class UserAvailabilityService {
  UserAvailabilityService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  Future<UserAvailabilitySnapshot> fetchCurrent() async {
    final User? user = _auth.currentUser;
    if (user == null) return UserAvailabilitySnapshot.offline();

    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('users').doc(user.uid).get();
    return _snapshotFromUserData(snapshot.data());
  }

  Future<UserAvailabilitySnapshot> goOnline({
    required UserAvailabilityScope scope,
  }) async {
    final User user = _requireUser();
    final Position position = await _resolvePosition();
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('users').doc(user.uid).get();
    final UserAvailabilitySnapshot current =
        _snapshotFromUserData(snapshot.data());
    final String geohash = _encodeGeohash(
      position.latitude,
      position.longitude,
    );

    final Map<String, dynamic> availability = <String, dynamic>{
      'isOnline': true,
      'scope': _scopeToStorage(scope),
      'updatedAt': FieldValue.serverTimestamp(),
      'lastSeenAt': FieldValue.serverTimestamp(),
      'source': 'mobile',
      'location': <String, dynamic>{
        'lat': position.latitude,
        'lng': position.longitude,
        'accuracy': position.accuracy,
        'geohash': geohash,
      },
    };

    await _firestore.collection('users').doc(user.uid).set(
      <String, dynamic>{'availability': availability},
      SetOptions(merge: true),
    );

    return UserAvailabilitySnapshot(
      isOnline: true,
      scope: scope,
      lat: position.latitude,
      lng: position.longitude,
      geohash: geohash,
      canProvideTravel: current.canProvideTravel,
      canProvideParcels: current.canProvideParcels,
    );
  }

  Future<UserAvailabilitySnapshot> goOffline() async {
    final User user = _requireUser();
    final DocumentSnapshot<Map<String, dynamic>> snapshot =
        await _firestore.collection('users').doc(user.uid).get();
    final UserAvailabilitySnapshot current =
        _snapshotFromUserData(snapshot.data());
    await _firestore.collection('users').doc(user.uid).set(
      <String, dynamic>{
        'availability': <String, dynamic>{
          'isOnline': false,
          'updatedAt': FieldValue.serverTimestamp(),
          'lastSeenAt': FieldValue.serverTimestamp(),
          'source': 'mobile',
        },
      },
      SetOptions(merge: true),
    );
    return UserAvailabilitySnapshot(
      isOnline: false,
      scope: current.scope,
      lat: current.lat,
      lng: current.lng,
      geohash: current.geohash,
      canProvideTravel: current.canProvideTravel,
      canProvideParcels: current.canProvideParcels,
    );
  }

  Future<UserAvailabilitySnapshot?> refreshIfOnline({
    UserAvailabilityScope? scope,
  }) async {
    final UserAvailabilitySnapshot current = await fetchCurrent();
    if (!current.isOnline) return null;
    return goOnline(scope: scope ?? current.scope);
  }

  Future<Position> _resolvePosition() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      throw Exception('Activez la localisation pour vous mettre en ligne.');
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw Exception('Autorisez la localisation pour vous mettre en ligne.');
    }

    return Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );
  }

  User _requireUser() {
    final User? user = _auth.currentUser;
    if (user == null) {
      throw Exception('Connexion requise.');
    }
    return user;
  }

  UserAvailabilityScope _scopeFromStorage(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'parcels':
        return UserAvailabilityScope.parcels;
      case 'all':
        return UserAvailabilityScope.all;
      case 'travel':
      default:
        return UserAvailabilityScope.travel;
    }
  }

  String _scopeToStorage(UserAvailabilityScope scope) {
    switch (scope) {
      case UserAvailabilityScope.travel:
        return 'travel';
      case UserAvailabilityScope.parcels:
        return 'parcels';
      case UserAvailabilityScope.all:
        return 'all';
    }
  }

  UserAvailabilitySnapshot _snapshotFromUserData(Map<String, dynamic>? data) {
    final Map<String, dynamic> availability =
        data?['availability'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(
                data!['availability'] as Map<String, dynamic>,
              )
            : <String, dynamic>{};
    final Map<String, dynamic> location =
        availability['location'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(
                availability['location'] as Map<String, dynamic>,
              )
            : <String, dynamic>{};
    final Map<String, dynamic> capabilities =
        data?['capabilities'] is Map<String, dynamic>
            ? Map<String, dynamic>.from(
                data!['capabilities'] as Map<String, dynamic>,
              )
            : <String, dynamic>{};

    return UserAvailabilitySnapshot(
      isOnline: availability['isOnline'] == true,
      scope: _scopeFromStorage(availability['scope'] as String?),
      lat: (location['lat'] as num?)?.toDouble(),
      lng: (location['lng'] as num?)?.toDouble(),
      geohash: location['geohash'] as String?,
      canProvideTravel: capabilities['travelProvider'] == true,
      canProvideParcels: capabilities['parcelsProvider'] == true ||
          data?['isServiceProvider'] == true,
    );
  }

  String _encodeGeohash(
    double latitude,
    double longitude, {
    int precision = 9,
  }) {
    const String base32 = '0123456789bcdefghjkmnpqrstuvwxyz';
    final List<double> latRange = <double>[-90, 90];
    final List<double> lngRange = <double>[-180, 180];
    final StringBuffer hash = StringBuffer();

    bool isEvenBit = true;
    int bit = 0;
    int currentChar = 0;

    while (hash.length < precision) {
      if (isEvenBit) {
        final double mid = (lngRange[0] + lngRange[1]) / 2;
        if (longitude >= mid) {
          currentChar = (currentChar << 1) + 1;
          lngRange[0] = mid;
        } else {
          currentChar <<= 1;
          lngRange[1] = mid;
        }
      } else {
        final double mid = (latRange[0] + latRange[1]) / 2;
        if (latitude >= mid) {
          currentChar = (currentChar << 1) + 1;
          latRange[0] = mid;
        } else {
          currentChar <<= 1;
          latRange[1] = mid;
        }
      }

      isEvenBit = !isEvenBit;
      bit++;

      if (bit == 5) {
        hash.write(base32[currentChar]);
        bit = 0;
        currentChar = 0;
      }
    }

    return hash.toString();
  }
}
