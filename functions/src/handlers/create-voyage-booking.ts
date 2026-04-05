import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { getLogger } from "../utils/logger";

const logger = getLogger("create-voyage-booking");
const db = admin.firestore();
const MAX_INT = 1 << 30;

// ── Payload ───────────────────────────────────────────────────────────────────

interface TravelerInput {
  name: string;
  contact: string;
}

interface CreateVoyageBookingPayload {
  source: "mobile" | "counter";
  tripId: string;
  requestedSeats: number;
  requesterName: string;
  requesterContact: string;
  requesterEmail?: string;
  requesterTrackNum?: string;
  segmentFrom: string;
  segmentTo: string;
  travelers: TravelerInput[];
  idempotencyKey?: string;
  effectiveDepartureDate?: string;
  comfortOptions?: string[];
  // Intentions client — le montant est plafonné côté serveur
  appliedRewardIds?: string[];
  studentDiscount?: number;
  checkoutDiscount?: number;
  paymentDiscount?: number;
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function toInt(value: unknown, fallback: number): number {
  if (typeof value === "number") return Math.trunc(value);
  const parsed = parseInt(`${value}`, 10);
  return isNaN(parsed) ? fallback : parsed;
}

function toStr(value: unknown): string {
  return typeof value === "string" ? value.trim() : "";
}

function normalizedTripFrequency(raw: string): "daily" | "weekly" | "monthly" | "none" {
  switch (raw.trim().toLowerCase()) {
    case "daily":   return "daily";
    case "weekly":  return "weekly";
    case "monthly": return "monthly";
    default:        return "none";
  }
}

function generateTrackingNumber(): string {
  const nowMs = Date.now();
  const entropy = Math.floor(Math.random() * 100);
  const mixed = `${nowMs}${entropy}`;
  return mixed.slice(-8);
}

// ── Address matching (portage du Dart) ────────────────────────────────────────

function normalizeAddress(value: string): string {
  let s = value.toLowerCase().trim();
  const replacements: Record<string, string> = {
    a: "àáâãäå", c: "ç", e: "èéêë", i: "ìíîï",
    n: "ñ", o: "òóôõö", u: "ùúûü", y: "ýÿ",
  };
  for (const [ascii, chars] of Object.entries(replacements)) {
    for (const ch of chars) s = s.split(ch).join(ascii);
  }
  return s.replace(/\s+/g, " ");
}

function normalizeLoose(value: string): string {
  return value.replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim();
}

function isGenericGeoToken(value: string): boolean {
  const v = normalizeLoose(value);
  return !v || v === "ci" || v === "cote d ivoire" || v === "cote divoire" || v === "ivory coast";
}

function similarToken(a: string, b: string): boolean {
  const left = normalizeLoose(a);
  const right = normalizeLoose(b);
  if (!left || !right) return false;
  if (isGenericGeoToken(left) || isGenericGeoToken(right)) return false;
  if (left === right) return true;
  if (left.length >= 4 && right.length >= 4) {
    if (left.startsWith(right) || right.startsWith(left)) return true;
  }
  const leftWords = new Set(left.split(" ").filter((w) => w.length >= 4));
  const rightWords = new Set(right.split(" ").filter((w) => w.length >= 4));
  for (const lw of leftWords) {
    if (rightWords.has(lw)) return true;
  }
  return false;
}

function addressTokens(address: string): string[] {
  const out: string[] = [];
  const first = normalizeAddress(address.split(",")[0].trim());
  if (first && !out.includes(first)) out.push(first);
  for (const part of address.split(",")) {
    const token = normalizeAddress(part);
    if (token && !out.includes(token)) out.push(token);
  }
  return out;
}

function matchesAddressQuery(queryAddress: string, candidateAddress: string): boolean {
  const queryTokens = addressTokens(queryAddress);
  const candidateTokens = addressTokens(candidateAddress);
  if (queryTokens.length === 0) return true;
  if (candidateTokens.length === 0) return false;
  for (const q of queryTokens) {
    for (const c of candidateTokens) {
      if (similarToken(c, q)) return true;
    }
  }
  return false;
}

// ── Route nodes & segment price ───────────────────────────────────────────────

interface RouteNode {
  address: string;
  priceFromDeparture: number;
}

function buildRouteNodes(trip: Record<string, unknown>): RouteNode[] {
  const stops = ((trip["intermediateStops"] as unknown[]) ?? [])
    .filter((s): s is Record<string, unknown> => typeof s === "object" && s !== null)
    .filter((s) => s["bookable"] !== false && s["toStop"] == null)
    .map((s) => ({
      address: toStr(s["address"]),
      priceFromDeparture: Math.min(Math.max(toInt(s["priceFromDeparture"], 0), 0), MAX_INT),
    }));

  return [
    { address: toStr(trip["departurePlace"]), priceFromDeparture: 0 },
    ...stops,
    { address: toStr(trip["arrivalPlace"]), priceFromDeparture: Math.min(Math.max(toInt(trip["pricePerSeat"] ?? trip["price"], 0), 0), MAX_INT) },
  ].filter((n) => n.address.length > 0);
}

function resolveServerSegmentPrice(
  trip: Record<string, unknown>,
  segmentFrom: string,
  segmentTo: string,
): number {
  const nodes = buildRouteNodes(trip);

  let fromIdx = -1;
  for (let i = 0; i < nodes.length; i++) {
    if (matchesAddressQuery(segmentFrom, nodes[i].address)) { fromIdx = i; break; }
  }
  if (fromIdx < 0) return -1; // segment introuvable

  let toIdx = -1;
  for (let i = fromIdx + 1; i < nodes.length; i++) {
    if (matchesAddressQuery(segmentTo, nodes[i].address)) { toIdx = i; break; }
  }
  if (toIdx < 0) return -1;

  return Math.min(Math.max(nodes[toIdx].priceFromDeparture - nodes[fromIdx].priceFromDeparture, 0), MAX_INT);
}

// ── Segment occupancy helpers ─────────────────────────────────────────────────

function parseSegmentOccupancy(value: unknown): Record<string, number> {
  if (typeof value !== "object" || value === null || Array.isArray(value)) return {};
  return Object.fromEntries(
    Object.entries(value as Record<string, unknown>).map(([k, v]) => [k, toInt(v, 0)])
  );
}

function resolveOccurrenceSegmentOccupancy(
  occurrence: Record<string, unknown> | null,
  fallback: Record<string, number>,
): Record<string, number> {
  if (occurrence) {
    const occ = parseSegmentOccupancy(occurrence["segmentOccupancy"]);
    if (Object.keys(occ).length > 0) return occ;
  }
  return { ...fallback };
}

function coveredSegmentKeys(
  segmentPoints: string[],
  segmentOccupancy: Record<string, number>,
  from: string,
  to: string,
): string[] {
  if (segmentPoints.length < 2) return [];

  let fromIdx = -1;
  for (let i = 0; i < segmentPoints.length; i++) {
    if (matchesAddressQuery(from, segmentPoints[i])) { fromIdx = i; break; }
  }
  if (fromIdx < 0) return [];

  let toIdx = -1;
  for (let i = fromIdx + 1; i < segmentPoints.length; i++) {
    if (matchesAddressQuery(to, segmentPoints[i])) { toIdx = i; break; }
  }
  if (toIdx < 0 || toIdx <= fromIdx) return [];

  const covered: string[] = [];
  for (let i = fromIdx; i < toIdx; i++) {
    const key = `${segmentPoints[i]}__${segmentPoints[i + 1]}`;
    if (key in segmentOccupancy) covered.push(key);
  }
  return covered;
}

function checkSegmentCapacity(
  segmentOccupancy: Record<string, number>,
  coveredKeys: string[],
  requestedSeats: number,
  capacity: number,
): void {
  for (const key of coveredKeys) {
    if ((segmentOccupancy[key] ?? 0) + requestedSeats > capacity) {
      throw new HttpsError("resource-exhausted", "Plus de places disponibles pour ce parcours.");
    }
  }
}

function updatedOccupancy(
  segmentOccupancy: Record<string, number>,
  coveredKeys: string[],
  seats: number,
  increment: boolean,
): Record<string, number> {
  const updated = { ...segmentOccupancy };
  for (const key of coveredKeys) {
    const current = updated[key] ?? 0;
    updated[key] = increment ? current + seats : Math.max(0, current - seats);
  }
  return updated;
}

function computeRemainingSeatsFromOccupancy(
  segmentOccupancy: Record<string, number>,
  capacity: number,
): number {
  const maxOccupied = Math.max(0, ...Object.values(segmentOccupancy));
  return Math.min(Math.max(capacity - maxOccupied, 0), capacity);
}

// ── Cloud Function ────────────────────────────────────────────────────────────

export const createVoyageBooking = onCall(
  { region: "europe-west1" },
  async (request) => {
    const uid = request.auth?.uid ?? "";
    const payload = request.data as CreateVoyageBookingPayload;

    // ── Validation basique ────────────────────────────────────────────────────
    const tripId = toStr(payload.tripId);
    const requestedSeats = toInt(payload.requestedSeats, 0);
    const requesterName = toStr(payload.requesterName);
    const requesterContact = toStr(payload.requesterContact);
    const segmentFrom = toStr(payload.segmentFrom);
    const segmentTo = toStr(payload.segmentTo);
    const travelers: TravelerInput[] = Array.isArray(payload.travelers) ? payload.travelers : [];
    const comfortOptions: string[] = Array.isArray(payload.comfortOptions) ? payload.comfortOptions : [];
    const appliedRewardIds: string[] = Array.isArray(payload.appliedRewardIds) ? payload.appliedRewardIds : [];
    const effectiveDepartureDate = toStr(payload.effectiveDepartureDate);
    const source = payload.source ?? "mobile";

    if (!tripId) throw new HttpsError("invalid-argument", "tripId manquant.");
    if (requestedSeats < 1) throw new HttpsError("invalid-argument", "Nombre de places invalide.");
    if (travelers.length !== requestedSeats) throw new HttpsError("invalid-argument", "Le nombre de passagers doit correspondre au nombre de places.");
    if (travelers.some((t) => !toStr(t.name))) throw new HttpsError("invalid-argument", "Nom passager manquant.");
    if (!requesterName) throw new HttpsError("invalid-argument", "Nom du demandeur manquant.");
    if (!segmentFrom || !segmentTo) throw new HttpsError("invalid-argument", "Veuillez préciser votre point de départ et d'arrivée.");
    // Même règle que le client Dart : anonyme autorisé, mais contact obligatoire
    const isAnonymous = uid === "";
    if (isAnonymous && !requesterContact) {
      throw new HttpsError("invalid-argument", "Contact du demandeur manquant.");
    }

    // ── Idempotency key ───────────────────────────────────────────────────────
    const idempotencyKey = toStr(payload.idempotencyKey);
    const tripRef = db.collection("voyageTrips").doc(tripId);
    const bookingRef = idempotencyKey
      ? db.collection("voyageBookings").doc(idempotencyKey)
      : db.collection("voyageBookings").doc();

    let bookingData: Record<string, unknown> = {};
    let isNew = false;

    await db.runTransaction(async (tx) => {
      // ── Idempotency check ─────────────────────────────────────────────────
      const existingSnap = await tx.get(bookingRef);
      if (existingSnap.exists) {
        bookingData = existingSnap.data() as Record<string, unknown>;
        return;
      }
      isNew = true;

      // ── Lecture du trajet ─────────────────────────────────────────────────
      const tripSnap = await tx.get(tripRef);
      if (!tripSnap.exists) throw new HttpsError("not-found", "Trajet introuvable.");
      const trip = tripSnap.data() as Record<string, unknown>;

      // ── Validation du statut ──────────────────────────────────────────────
      if (toStr(trip["status"]) !== "published") {
        throw new HttpsError("failed-precondition", "Trajet non disponible à la réservation.");
      }

      const tripFrequency = normalizedTripFrequency(toStr(trip["tripFrequency"]));
      const usesOccurrences = tripFrequency !== "none";
      const isBus = trip["isBus"] === true;
      const baseCapacity = toInt(trip["seats"], 0);

      // Résolution de la date effective
      const resolvedDepartureDate = effectiveDepartureDate || toStr(trip["departureDate"]);

      // ── Validation côté serveur du prix du segment ────────────────────────
      const serverSegmentPrice = resolveServerSegmentPrice(trip, segmentFrom, segmentTo);
      if (serverSegmentPrice < 0) {
        throw new HttpsError("invalid-argument", "Ce trajet ne dessert pas ce parcours.");
      }

      // ── Vérification des places disponibles ──────────────────────────────
      const tripSegmentOccupancy = parseSegmentOccupancy(trip["segmentOccupancy"]);
      const segmentPoints = ((trip["segmentPoints"] as unknown[]) ?? [])
        .map((e) => `${e}`.trim())
        .filter((e) => e.length > 0);
      const usesSegments = Object.keys(tripSegmentOccupancy).length > 0 && segmentPoints.length >= 2;

      const occurrenceRef = usesOccurrences
        ? tripRef.collection("occurrences").doc(resolvedDepartureDate)
        : null;
      const occurrenceSnap = occurrenceRef ? await tx.get(occurrenceRef) : null;
      const occurrence = occurrenceSnap?.exists ? occurrenceSnap.data() as Record<string, unknown> : null;

      const effectiveSegmentOccupancy = usesOccurrences
        ? resolveOccurrenceSegmentOccupancy(occurrence, tripSegmentOccupancy)
        : tripSegmentOccupancy;

      if (usesSegments) {
        const keys = coveredSegmentKeys(segmentPoints, effectiveSegmentOccupancy, segmentFrom, segmentTo);
        if (keys.length === 0) throw new HttpsError("invalid-argument", "Ce trajet ne dessert pas ce parcours.");
        checkSegmentCapacity(effectiveSegmentOccupancy, keys, requestedSeats, baseCapacity);
      } else if (!usesOccurrences) {
        if (baseCapacity < requestedSeats) {
          throw new HttpsError("resource-exhausted", "Places insuffisantes.");
        }
      } else {
        const remaining = occurrence ? toInt(occurrence["remainingSeats"], baseCapacity) : baseCapacity;
        if (remaining < requestedSeats) {
          throw new HttpsError("resource-exhausted", "Places insuffisantes pour cette date.");
        }
      }

      // ── Prix total côté serveur ───────────────────────────────────────────
      const baseTotal = serverSegmentPrice * requestedSeats;

      // Réductions scratch (plafonnées — on fait confiance au flux UI)
      const rawStudentDiscount = source === "mobile" ? Math.max(0, toInt(payload.studentDiscount, 0)) : 0;
      const rawCheckoutDiscount = source === "mobile" ? Math.max(0, toInt(payload.checkoutDiscount, 0)) : 0;
      const rawPaymentDiscount = source === "mobile" ? Math.max(0, toInt(payload.paymentDiscount, 0)) : 0;

      // ── Rewards FIFO ──────────────────────────────────────────────────────
      let discountAmount = 0;
      const rewardUpdates: Array<{ ref: FirebaseFirestore.DocumentReference; data: Record<string, unknown> }> = [];

      if (appliedRewardIds.length > 0 && !isAnonymous) {
        const rewardRefs = appliedRewardIds.map((id) =>
          db.doc(`user_rewards/${uid}/rewards/${id}`)
        );
        const rewardSnaps = await Promise.all(rewardRefs.map((r) => tx.get(r)));
        let remaining = baseTotal;

        for (let i = 0; i < rewardSnaps.length; i++) {
          if (remaining <= 0) break;
          const snap = rewardSnaps[i];
          if (!snap.exists) continue;
          const rData = snap.data() as Record<string, unknown>;
          if (toStr(rData["status"]) !== "available") continue;
          const effectiveValue = toInt(rData["remainingValue"] ?? rData["value"], 0);
          if (effectiveValue <= 0) continue;
          const consumed = Math.min(effectiveValue, remaining);
          discountAmount += consumed;
          remaining -= consumed;
          rewardUpdates.push({
            ref: rewardRefs[i],
            data: consumed >= effectiveValue
              ? { status: "used", usedAt: admin.firestore.FieldValue.serverTimestamp(), remainingValue: 0 }
              : { remainingValue: effectiveValue - consumed },
          });
        }
      }

      // Total final — ne peut jamais être négatif
      const totalScratchDiscount = Math.max(rawStudentDiscount, rawCheckoutDiscount) + rawPaymentDiscount;
      const totalPrice = Math.max(0, baseTotal - discountAmount - totalScratchDiscount);

      const trackNum = generateTrackingNumber();

      bookingData = {
        trackNum,
        tripId,
        tripTrackNum: toStr(trip["trackNum"]),
        tripOwnerUid: toStr(trip["ownerUid"]),
        tripOwnerTrackNum: toStr(trip["ownerTrackNum"]),
        tripCurrency: toStr(trip["currency"]) || "XOF",
        tripDepartureDate: resolvedDepartureDate,
        tripDepartureTime: toStr(trip["departureTime"]),
        tripFrequency,
        tripDeparturePlace: toStr(trip["departurePlace"]),
        tripArrivalEstimatedTime: toStr(trip["arrivalEstimatedTime"]),
        tripArrivalPlace: toStr(trip["arrivalPlace"]),
        tripDriverName: toStr(trip["driverName"]),
        tripVehicleModel: toStr(trip["vehicleModel"]),
        tripContactPhone: toStr(trip["contactPhone"]),
        tripIntermediateStops: ((trip["intermediateStops"] as unknown[]) ?? [])
          .filter((s): s is Record<string, unknown> => typeof s === "object" && s !== null),
        requestedSeats,
        requesterUid: uid,
        requesterTrackNum: toStr(payload.requesterTrackNum),
        requesterName,
        requesterContact,
        requesterEmail: toStr(payload.requesterEmail),
        segmentFrom,
        segmentTo,
        segmentPrice: serverSegmentPrice,
        totalPrice,
        travelers: travelers.map((t) => ({ name: toStr(t.name), contact: toStr(t.contact) })),
        comfortOptions: source === "mobile" ? comfortOptions : [],
        ...(appliedRewardIds.length > 0 && { appliedRewardIds }),
        ...(discountAmount > 0 && { discountAmount }),
        ...(rawStudentDiscount > 0 && { studentDiscount: rawStudentDiscount }),
        ...(rawCheckoutDiscount > 0 && { checkoutDiscount: rawCheckoutDiscount }),
        ...(rawPaymentDiscount > 0 && { paymentDiscount: rawPaymentDiscount }),
        source,
        unreadForDriver: 0,
        unreadForPassenger: 0,
        status: isBus ? "accepted" : "pending",
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      };

      // ── Mise à jour de la capacité ────────────────────────────────────────
      if (usesSegments) {
        const keys = coveredSegmentKeys(segmentPoints, effectiveSegmentOccupancy, segmentFrom, segmentTo);
        const newOcc = updatedOccupancy(effectiveSegmentOccupancy, keys, requestedSeats, true);

        if (usesOccurrences && occurrenceRef) {
          const nextRemaining = computeRemainingSeatsFromOccupancy(newOcc, baseCapacity);
          tx.set(occurrenceRef, {
            date: resolvedDepartureDate,
            capacity: baseCapacity,
            segmentPoints,
            segmentOccupancy: newOcc,
            bookedSeats: Math.min(baseCapacity - nextRemaining, baseCapacity),
            remainingSeats: nextRemaining,
            status: nextRemaining > 0 ? "active" : "full",
            createdAt: admin.firestore.FieldValue.serverTimestamp(),
            updatedAt: admin.firestore.FieldValue.serverTimestamp(),
          }, { merge: true });
        } else {
          tx.set(tripRef, { segmentOccupancy: newOcc, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
        }
      } else if (usesOccurrences && occurrenceRef) {
        const currentRemaining = occurrence ? toInt(occurrence["remainingSeats"], baseCapacity) : baseCapacity;
        const nextRemaining = Math.min(Math.max(currentRemaining - requestedSeats, 0), baseCapacity);
        tx.set(occurrenceRef, {
          date: resolvedDepartureDate,
          capacity: baseCapacity,
          bookedSeats: baseCapacity - nextRemaining,
          remainingSeats: nextRemaining,
          status: nextRemaining > 0 ? "active" : "full",
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        }, { merge: true });
      } else {
        tx.update(tripRef, {
          seats: baseCapacity - requestedSeats,
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      // Consommation des rewards
      for (const { ref, data } of rewardUpdates) {
        tx.update(ref, data);
      }

      tx.set(bookingRef, bookingData);
    });

    // ── Notification au propriétaire du trajet ────────────────────────────────
    if (isNew) {
      const ownerUid = toStr(bookingData["tripOwnerUid"]);
      const seats = toInt(bookingData["requestedSeats"], 0);
      if (ownerUid) {
        await db.collection("notifications").add({
          userId: ownerUid,
          domain: "travel",
          type: "booking_created",
          title: "Nouvelle réservation",
          body: `${requesterName} a réservé ${seats} place${seats > 1 ? "s" : ""}.`,
          entityType: "booking",
          entityId: bookingRef.id,
          data: {
            bookingId: bookingRef.id,
            bookingTrackNum: toStr(bookingData["trackNum"]),
            tripId,
            tripTrackNum: toStr(bookingData["tripTrackNum"]),
          },
          read: false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }

      logger.info("Booking created", {
        bookingId: bookingRef.id,
        uid,
        tripId,
        source: bookingData["source"],
        totalPrice: bookingData["totalPrice"],
      });
    } else {
      logger.info("Booking already exists (idempotent)", { bookingId: bookingRef.id, uid });
    }

    return {
      bookingId: bookingRef.id,
      trackNum: toStr(bookingData["trackNum"]),
      status: toStr(bookingData["status"]),
      totalPrice: toInt(bookingData["totalPrice"], 0),
      segmentPrice: toInt(bookingData["segmentPrice"], 0),
    };
  }
);
