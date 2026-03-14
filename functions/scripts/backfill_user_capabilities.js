const admin = require("firebase-admin");

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();
const WRITE_MODE = process.argv.includes("--write");
const USERS_BATCH_SIZE = 200;

async function main() {
  console.log(
    WRITE_MODE
      ? "Running user backfill in write mode."
      : "Running user backfill in dry-run mode. Add --write to persist changes.",
  );

  const [travelOwners, parcelOwners] = await Promise.all([
    collectOwnerIds("voyageTrips"),
    collectOwnerIds("services"),
  ]);

  console.log(
    `Found ${travelOwners.size} travel providers and ${parcelOwners.size} parcel providers from collections.`,
  );

  let updated = 0;
  let inspected = 0;
  let lastDoc = null;

  while (true) {
    let query = db.collection("users").orderBy(admin.firestore.FieldPath.documentId()).limit(USERS_BATCH_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    const batch = db.batch();
    let batchChanges = 0;

    for (const doc of snapshot.docs) {
      inspected += 1;
      const data = doc.data() || {};
      const patch = buildUserPatch({
        uid: doc.id,
        data,
        travelOwners,
        parcelOwners,
      });

      if (!patch) continue;

      batchChanges += 1;
      updated += 1;

      if (WRITE_MODE) {
        batch.set(doc.ref, patch, { merge: true });
      } else {
        console.log(`[dry-run] users/${doc.id}`, JSON.stringify(patch));
      }
    }

    if (WRITE_MODE && batchChanges > 0) {
      await batch.commit();
      console.log(`Committed ${batchChanges} user updates.`);
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }

  console.log(`Inspected ${inspected} users.`);
  console.log(`${WRITE_MODE ? "Updated" : "Would update"} ${updated} users.`);
}

async function collectOwnerIds(collectionName) {
  const ownerIds = new Set();
  let lastDoc = null;

  while (true) {
    let query = db.collection(collectionName)
      .orderBy(admin.firestore.FieldPath.documentId())
      .limit(USERS_BATCH_SIZE);
    if (lastDoc) {
      query = query.startAfter(lastDoc);
    }

    const snapshot = await query.get();
    if (snapshot.empty) break;

    for (const doc of snapshot.docs) {
      const data = doc.data() || {};
      const ownerUid = `${data.ownerUid || ""}`.trim();
      if (ownerUid) {
        ownerIds.add(ownerUid);
      }
    }

    lastDoc = snapshot.docs[snapshot.docs.length - 1];
  }

  return ownerIds;
}

function buildUserPatch({ uid, data, travelOwners, parcelOwners }) {
  const currentCapabilities = isPlainObject(data.capabilities)
    ? { ...data.capabilities }
    : {};

  const shouldTravelProvider =
    currentCapabilities.travelProvider === true || travelOwners.has(uid);
  const shouldParcelsProvider =
    currentCapabilities.parcelsProvider === true ||
    data.isServiceProvider === true ||
    parcelOwners.has(uid);

  const patch = {};
  let hasChanges = false;

  if (
    currentCapabilities.travelProvider !== shouldTravelProvider ||
    currentCapabilities.parcelsProvider !== shouldParcelsProvider
  ) {
    patch.capabilities = {
      ...currentCapabilities,
      travelProvider: shouldTravelProvider,
      parcelsProvider: shouldParcelsProvider,
    };
    hasChanges = true;
  }

  const availability = isPlainObject(data.availability) ? { ...data.availability } : null;
  const location = availability && isPlainObject(availability.location)
    ? { ...availability.location }
    : null;

  if (location) {
    const lat = toFiniteNumber(location.lat);
    const lng = toFiniteNumber(location.lng);
    const currentGeohash = typeof location.geohash === "string" ? location.geohash.trim() : "";

    if (lat != null && lng != null) {
      const nextGeohash = encodeGeohash(lat, lng);
      if (currentGeohash !== nextGeohash) {
        patch.availability = {
          ...availability,
          location: {
            ...location,
            geohash: nextGeohash,
          },
        };
        hasChanges = true;
      }
    }
  }

  if (!hasChanges) return null;

  patch.updatedAt = admin.firestore.FieldValue.serverTimestamp();
  return patch;
}

function isPlainObject(value) {
  return Boolean(value) && typeof value === "object" && !Array.isArray(value);
}

function toFiniteNumber(value) {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim()) {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function encodeGeohash(latitude, longitude, precision = 9) {
  const base32 = "0123456789bcdefghjkmnpqrstuvwxyz";
  const latRange = [-90, 90];
  const lngRange = [-180, 180];
  let hash = "";
  let isEvenBit = true;
  let bit = 0;
  let currentChar = 0;

  while (hash.length < precision) {
    if (isEvenBit) {
      const mid = (lngRange[0] + lngRange[1]) / 2;
      if (longitude >= mid) {
        currentChar = (currentChar << 1) + 1;
        lngRange[0] = mid;
      } else {
        currentChar <<= 1;
        lngRange[1] = mid;
      }
    } else {
      const mid = (latRange[0] + latRange[1]) / 2;
      if (latitude >= mid) {
        currentChar = (currentChar << 1) + 1;
        latRange[0] = mid;
      } else {
        currentChar <<= 1;
        latRange[1] = mid;
      }
    }

    isEvenBit = !isEvenBit;
    bit += 1;

    if (bit === 5) {
      hash += base32[currentChar];
      bit = 0;
      currentChar = 0;
    }
  }

  return hash;
}

main().catch((error) => {
  console.error("Backfill failed:", error);
  process.exitCode = 1;
});
