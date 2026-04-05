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
exports.notifyTripPassengers = void 0;
const https_1 = require("firebase-functions/v2/https");
const admin = __importStar(require("firebase-admin"));
const logger_1 = require("../utils/logger");
const logger = (0, logger_1.getLogger)("notify-trip-passengers");
const db = admin.firestore();
/**
 * Callable — envoie une notification push à tous les passagers
 * d'un voyage donné (bookings confirmés ou en attente).
 *
 * Appelé depuis l'app driver ou une interface admin.
 */
exports.notifyTripPassengers = (0, https_1.onCall)({ region: "europe-west1" }, async (request) => {
    var _a, _b;
    // Authentification requise
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentification requise.");
    }
    const payload = request.data;
    const { tripId, title, body } = payload;
    const type = (_a = payload.type) !== null && _a !== void 0 ? _a : "trip_updated";
    const extraData = (_b = payload.data) !== null && _b !== void 0 ? _b : {};
    if (!(tripId === null || tripId === void 0 ? void 0 : tripId.trim()) || !(title === null || title === void 0 ? void 0 : title.trim()) || !(body === null || body === void 0 ? void 0 : body.trim())) {
        throw new https_1.HttpsError("invalid-argument", "tripId, title et body sont requis.");
    }
    // ── Récupérer les bookings actifs du trip ─────────────────────────────
    const bookingsSnap = await db
        .collection("voyageBookings")
        .where("tripId", "==", tripId.trim())
        .where("status", "in", ["pending", "confirmed", "approved", "accepted"])
        .get();
    if (bookingsSnap.empty) {
        logger.info("No active bookings for trip", { tripId });
        return { sent: 0 };
    }
    // Dédoublonner par UID (un passager peut avoir plusieurs réservations)
    const uids = new Set();
    bookingsSnap.docs.forEach((doc) => {
        var _a;
        const uid = `${(_a = doc.data()["requesterUid"]) !== null && _a !== void 0 ? _a : ""}`.trim();
        if (uid)
            uids.add(uid);
    });
    if (uids.size === 0) {
        logger.warn("Bookings found but no requesterUid", { tripId });
        return { sent: 0 };
    }
    // ── Écrire un doc notifications/ par passager ─────────────────────────
    // sendPushOnNotificationCreated (index.ts) prend le relais automatiquement.
    const batch = db.batch();
    const now = admin.firestore.FieldValue.serverTimestamp();
    for (const uid of uids) {
        const ref = db.collection("notifications").doc();
        batch.set(ref, {
            userId: uid,
            type,
            title,
            body,
            entityType: "trip",
            entityId: tripId,
            domain: "travel",
            data: extraData,
            read: false,
            createdAt: now,
        });
    }
    await batch.commit();
    logger.info("Notifications written for trip passengers", {
        tripId,
        count: uids.size,
    });
    return { sent: uids.size };
});
//# sourceMappingURL=notify-trip-passengers.js.map