"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.createVoyageBooking = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("../utils/logger");
const logger = (0, logger_1.getLogger)("create-voyage-booking");
const db = admin.firestore();
const MAX_INT = 1 << 30;
// ── Helpers ───────────────────────────────────────────────────────────────────
function toInt(value, fallback) {
    if (typeof value === "number")
        return Math.trunc(value);
    const parsed = parseInt(`${value}`, 10);
    return isNaN(parsed) ? fallback : parsed;
}
function toStr(value) {
    return typeof value === "string" ? value.trim() : "";
}
function normalizedTripFrequency(raw) {
    switch (raw.trim().toLowerCase()) {
        case "daily": return "daily";
        case "weekly": return "weekly";
        case "monthly": return "monthly";
        default: return "none";
    }
}
function generateTrackingNumber() {
    const nowMs = Date.now();
    const entropy = Math.floor(Math.random() * 100);
    const mixed = `${nowMs}${entropy}`;
    return mixed.slice(-8);
}
// ── Address matching (portage du Dart) ────────────────────────────────────────
function normalizeAddress(value) {
    let s = value.toLowerCase().trim();
    const replacements = {
        a: "àáâãäå", c: "ç", e: "èéêë", i: "ìíîï",
        n: "ñ", o: "òóôõö", u: "ùúûü", y: "ýÿ",
    };
    for (const [ascii, chars] of Object.entries(replacements)) {
        for (const ch of chars)
            s = s.split(ch).join(ascii);
    }
    return s.replace(/\s+/g, " ");
}
function normalizeLoose(value) {
    return value.replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim();
}
function isGenericGeoToken(value) {
    const v = normalizeLoose(value);
    return !v || v === "ci" || v === "cote d ivoire" || v === "cote divoire" || v === "ivory coast";
}
function similarToken(a, b) {
    const left = normalizeLoose(a);
    const right = normalizeLoose(b);
    if (!left || !right)
        return false;
    if (isGenericGeoToken(left) || isGenericGeoToken(right))
        return false;
    if (left === right)
        return true;
    if (left.length >= 4 && right.length >= 4) {
        if (left.startsWith(right) || right.startsWith(left))
            return true;
    }
    const leftWords = new Set(left.split(" ").filter((w) => w.length >= 4));
    const rightWords = new Set(right.split(" ").filter((w) => w.length >= 4));
    for (const lw of leftWords) {
        if (rightWords.has(lw))
            return true;
    }
    return false;
}
function addressTokens(address) {
    const out = [];
    const first = normalizeAddress(address.split(",")[0].trim());
    if (first && !out.includes(first))
        out.push(first);
    for (const part of address.split(",")) {
        const token = normalizeAddress(part);
        if (token && !out.includes(token))
            out.push(token);
    }
    return out;
}
function matchesAddressQuery(queryAddress, candidateAddress) {
    const queryTokens = addressTokens(queryAddress);
    const candidateTokens = addressTokens(candidateAddress);
    if (queryTokens.length === 0)
        return true;
    if (candidateTokens.length === 0)
        return false;
    for (const q of queryTokens) {
        for (const c of candidateTokens) {
            if (similarToken(c, q))
                return true;
        }
    }
    return false;
}
function buildRouteNodes(trip) {
    var _a, _b;
    const stops = ((_a = trip["intermediateStops"]) !== null && _a !== void 0 ? _a : [])
        .filter((s) => typeof s === "object" && s !== null)
        .filter((s) => s["bookable"] !== false && s["toStop"] == null)
        .map((s) => ({
        address: toStr(s["address"]),
        priceFromDeparture: Math.min(Math.max(toInt(s["priceFromDeparture"], 0), 0), MAX_INT),
    }));
    return [
        { address: toStr(trip["departurePlace"]), priceFromDeparture: 0 },
        ...stops,
        { address: toStr(trip["arrivalPlace"]), priceFromDeparture: Math.min(Math.max(toInt((_b = trip["pricePerSeat"]) !== null && _b !== void 0 ? _b : trip["price"], 0), 0), MAX_INT) },
    ].filter((n) => n.address.length > 0);
}
function resolveServerSegmentPrice(trip, segmentFrom, segmentTo) {
    const nodes = buildRouteNodes(trip);
    let fromIdx = -1;
    for (let i = 0; i < nodes.length; i++) {
        if (matchesAddressQuery(segmentFrom, nodes[i].address)) {
            fromIdx = i;
            break;
        }
    }
    if (fromIdx < 0)
        return -1; // segment introuvable
    let toIdx = -1;
    for (let i = fromIdx + 1; i < nodes.length; i++) {
        if (matchesAddressQuery(segmentTo, nodes[i].address)) {
            toIdx = i;
            break;
        }
    }
    if (toIdx < 0)
        return -1;
    return Math.min(Math.max(nodes[toIdx].priceFromDeparture - nodes[fromIdx].priceFromDeparture, 0), MAX_INT);
}
// ── Segment occupancy helpers ─────────────────────────────────────────────────
function parseSegmentOccupancy(value) {
    if (typeof value !== "object" || value === null || Array.isArray(value))
        return {};
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, toInt(v, 0)]));
}
function resolveOccurrenceSegmentOccupancy(occurrence, fallback) {
    if (occurrence) {
        const occ = parseSegmentOccupancy(occurrence["segmentOccupancy"]);
        if (Object.keys(occ).length > 0)
            return occ;
    }
    return Object.assign({}, fallback);
}
function coveredSegmentKeys(segmentPoints, segmentOccupancy, from, to) {
    if (segmentPoints.length < 2)
        return [];
    let fromIdx = -1;
    for (let i = 0; i < segmentPoints.length; i++) {
        if (matchesAddressQuery(from, segmentPoints[i])) {
            fromIdx = i;
            break;
        }
    }
    if (fromIdx < 0)
        return [];
    let toIdx = -1;
    for (let i = fromIdx + 1; i < segmentPoints.length; i++) {
        if (matchesAddressQuery(to, segmentPoints[i])) {
            toIdx = i;
            break;
        }
    }
    if (toIdx < 0 || toIdx <= fromIdx)
        return [];
    const covered = [];
    for (let i = fromIdx; i < toIdx; i++) {
        const key = `${segmentPoints[i]}__${segmentPoints[i + 1]}`;
        if (key in segmentOccupancy)
            covered.push(key);
    }
    return covered;
}
function checkSegmentCapacity(segmentOccupancy, coveredKeys, requestedSeats, capacity) {
    var _a;
    for (const key of coveredKeys) {
        if (((_a = segmentOccupancy[key]) !== null && _a !== void 0 ? _a : 0) + requestedSeats > capacity) {
            throw new https_1.HttpsError("resource-exhausted", "Plus de places disponibles pour ce parcours.");
        }
    }
}
function updatedOccupancy(segmentOccupancy, coveredKeys, seats, increment) {
    var _a;
    const updated = Object.assign({}, segmentOccupancy);
    for (const key of coveredKeys) {
        const current = (_a = updated[key]) !== null && _a !== void 0 ? _a : 0;
        updated[key] = increment ? current + seats : Math.max(0, current - seats);
    }
    return updated;
}
function computeRemainingSeatsFromOccupancy(segmentOccupancy, capacity) {
    const maxOccupied = Math.max(0, ...Object.values(segmentOccupancy));
    return Math.min(Math.max(capacity - maxOccupied, 0), capacity);
}
// ── Cloud Function ────────────────────────────────────────────────────────────
exports.createVoyageBooking = (0, https_1.onCall)({ region: "europe-west1" }, async (request) => {
    var _a, _b, _c;
    const uid = (_b = (_a = request.auth) === null || _a === void 0 ? void 0 : _a.uid) !== null && _b !== void 0 ? _b : "";
    const payload = request.data;
    // ── Validation basique ────────────────────────────────────────────────────
    const tripId = toStr(payload.tripId);
    const requestedSeats = toInt(payload.requestedSeats, 0);
    const requesterName = toStr(payload.requesterName);
    const requesterContact = toStr(payload.requesterContact);
    const segmentFrom = toStr(payload.segmentFrom);
    const segmentTo = toStr(payload.segmentTo);
    const travelers = Array.isArray(payload.travelers) ? payload.travelers : [];
    const comfortOptions = Array.isArray(payload.comfortOptions) ? payload.comfortOptions : [];
    const appliedRewardIds = Array.isArray(payload.appliedRewardIds) ? payload.appliedRewardIds : [];
    const effectiveDepartureDate = toStr(payload.effectiveDepartureDate);
    const source = (_c = payload.source) !== null && _c !== void 0 ? _c : "mobile";
    if (!tripId)
        throw new https_1.HttpsError("invalid-argument", "tripId manquant.");
    if (requestedSeats < 1)
        throw new https_1.HttpsError("invalid-argument", "Nombre de places invalide.");
    if (travelers.length !== requestedSeats)
        throw new https_1.HttpsError("invalid-argument", "Le nombre de passagers doit correspondre au nombre de places.");
    if (travelers.some((t) => !toStr(t.name)))
        throw new https_1.HttpsError("invalid-argument", "Nom passager manquant.");
    if (!requesterName)
        throw new https_1.HttpsError("invalid-argument", "Nom du demandeur manquant.");
    if (!segmentFrom || !segmentTo)
        throw new https_1.HttpsError("invalid-argument", "Veuillez préciser votre point de départ et d'arrivée.");
    // Même règle que le client Dart : anonyme autorisé, mais contact obligatoire
    const isAnonymous = uid === "";
    if (isAnonymous && !requesterContact) {
        throw new https_1.HttpsError("invalid-argument", "Contact du demandeur manquant.");
    }
    // ── Idempotency key ───────────────────────────────────────────────────────
    const idempotencyKey = toStr(payload.idempotencyKey);
    const tripRef = db.collection("voyageTrips").doc(tripId);
    const bookingRef = idempotencyKey
        ? db.collection("voyageBookings").doc(idempotencyKey)
        : db.collection("voyageBookings").doc();
    let bookingData = {};
    let isNew = false;
    await db.runTransaction(async (tx) => {
        var _a, _b, _c;
        // ── Idempotency check ─────────────────────────────────────────────────
        const existingSnap = await tx.get(bookingRef);
        if (existingSnap.exists) {
            bookingData = existingSnap.data();
            return;
        }
        isNew = true;
        // ── Lecture du trajet ─────────────────────────────────────────────────
        const tripSnap = await tx.get(tripRef);
        if (!tripSnap.exists)
            throw new https_1.HttpsError("not-found", "Trajet introuvable.");
        const trip = tripSnap.data();
        // ── Validation du statut ──────────────────────────────────────────────
        if (toStr(trip["status"]) !== "published") {
            throw new https_1.HttpsError("failed-precondition", "Trajet non disponible à la réservation.");
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
            throw new https_1.HttpsError("invalid-argument", "Ce trajet ne dessert pas ce parcours.");
        }
        // ── Vérification des places disponibles ──────────────────────────────
        const tripSegmentOccupancy = parseSegmentOccupancy(trip["segmentOccupancy"]);
        const segmentPoints = ((_a = trip["segmentPoints"]) !== null && _a !== void 0 ? _a : [])
            .map((e) => `${e}`.trim())
            .filter((e) => e.length > 0);
        const usesSegments = Object.keys(tripSegmentOccupancy).length > 0 && segmentPoints.length >= 2;
        const occurrenceRef = usesOccurrences
            ? tripRef.collection("occurrences").doc(resolvedDepartureDate)
            : null;
        const occurrenceSnap = occurrenceRef ? await tx.get(occurrenceRef) : null;
        const occurrence = (occurrenceSnap === null || occurrenceSnap === void 0 ? void 0 : occurrenceSnap.exists) ? occurrenceSnap.data() : null;
        const effectiveSegmentOccupancy = usesOccurrences
            ? resolveOccurrenceSegmentOccupancy(occurrence, tripSegmentOccupancy)
            : tripSegmentOccupancy;
        if (usesSegments) {
            const keys = coveredSegmentKeys(segmentPoints, effectiveSegmentOccupancy, segmentFrom, segmentTo);
            if (keys.length === 0)
                throw new https_1.HttpsError("invalid-argument", "Ce trajet ne dessert pas ce parcours.");
            checkSegmentCapacity(effectiveSegmentOccupancy, keys, requestedSeats, baseCapacity);
        }
        else if (!usesOccurrences) {
            if (baseCapacity < requestedSeats) {
                throw new https_1.HttpsError("resource-exhausted", "Places insuffisantes.");
            }
        }
        else {
            const remaining = occurrence ? toInt(occurrence["remainingSeats"], baseCapacity) : baseCapacity;
            if (remaining < requestedSeats) {
                throw new https_1.HttpsError("resource-exhausted", "Places insuffisantes pour cette date.");
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
        const rewardUpdates = [];
        if (appliedRewardIds.length > 0 && !isAnonymous) {
            const rewardRefs = appliedRewardIds.map((id) => db.doc(`user_rewards/${uid}/rewards/${id}`));
            const rewardSnaps = await Promise.all(rewardRefs.map((r) => tx.get(r)));
            let remaining = baseTotal;
            for (let i = 0; i < rewardSnaps.length; i++) {
                if (remaining <= 0)
                    break;
                const snap = rewardSnaps[i];
                if (!snap.exists)
                    continue;
                const rData = snap.data();
                if (toStr(rData["status"]) !== "available")
                    continue;
                const effectiveValue = toInt((_b = rData["remainingValue"]) !== null && _b !== void 0 ? _b : rData["value"], 0);
                if (effectiveValue <= 0)
                    continue;
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
        bookingData = Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign(Object.assign({ trackNum,
            tripId, tripTrackNum: toStr(trip["trackNum"]), tripOwnerUid: toStr(trip["ownerUid"]), tripOwnerTrackNum: toStr(trip["ownerTrackNum"]), tripCurrency: toStr(trip["currency"]) || "XOF", tripDepartureDate: resolvedDepartureDate, tripDepartureTime: toStr(trip["departureTime"]), tripFrequency, tripDeparturePlace: toStr(trip["departurePlace"]), tripArrivalEstimatedTime: toStr(trip["arrivalEstimatedTime"]), tripArrivalPlace: toStr(trip["arrivalPlace"]), tripDriverName: toStr(trip["driverName"]), tripVehicleModel: toStr(trip["vehicleModel"]), tripContactPhone: toStr(trip["contactPhone"]), tripIntermediateStops: ((_c = trip["intermediateStops"]) !== null && _c !== void 0 ? _c : [])
                .filter((s) => typeof s === "object" && s !== null), requestedSeats, requesterUid: uid, requesterTrackNum: toStr(payload.requesterTrackNum), requesterName,
            requesterContact, requesterEmail: toStr(payload.requesterEmail), segmentFrom,
            segmentTo, segmentPrice: serverSegmentPrice, totalPrice, travelers: travelers.map((t) => ({ name: toStr(t.name), contact: toStr(t.contact) })), comfortOptions: source === "mobile" ? comfortOptions : [] }, (appliedRewardIds.length > 0 && { appliedRewardIds })), (discountAmount > 0 && { discountAmount })), (rawStudentDiscount > 0 && { studentDiscount: rawStudentDiscount })), (rawCheckoutDiscount > 0 && { checkoutDiscount: rawCheckoutDiscount })), (rawPaymentDiscount > 0 && { paymentDiscount: rawPaymentDiscount })), (toStr(payload.paymentMethod) && { paymentMethod: toStr(payload.paymentMethod) })), { source, unreadForDriver: 0, unreadForPassenger: 0, status: isBus ? "accepted" : "pending", createdAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
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
            }
            else {
                tx.set(tripRef, { segmentOccupancy: newOcc, updatedAt: admin.firestore.FieldValue.serverTimestamp() }, { merge: true });
            }
        }
        else if (usesOccurrences && occurrenceRef) {
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
        }
        else {
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
    }
    else {
        logger.info("Booking already exists (idempotent)", { bookingId: bookingRef.id, uid });
    }
    return {
        bookingId: bookingRef.id,
        trackNum: toStr(bookingData["trackNum"]),
        status: toStr(bookingData["status"]),
        totalPrice: toInt(bookingData["totalPrice"], 0),
        segmentPrice: toInt(bookingData["segmentPrice"], 0),
    };
});
//# sourceMappingURL=create-voyage-booking.js.map