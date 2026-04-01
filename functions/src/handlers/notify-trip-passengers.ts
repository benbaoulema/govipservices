import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as admin from "firebase-admin";
import { getLogger } from "../utils/logger";

const logger = getLogger("notify-trip-passengers");
const db = admin.firestore();

interface NotifyTripPassengersPayload {
  tripId: string;
  title: string;
  body: string;
  /** Type de notification — doit être dans PUSH_TYPES de index.ts */
  type?: string;
  /** Données extra optionnelles passées dans le payload FCM */
  data?: Record<string, string>;
}

/**
 * Callable — envoie une notification push à tous les passagers
 * d'un voyage donné (bookings confirmés ou en attente).
 *
 * Appelé depuis l'app driver ou une interface admin.
 */
export const notifyTripPassengers = onCall(
  { region: "europe-west1" },
  async (request) => {
    // Authentification requise
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentification requise.");
    }

    const payload = request.data as NotifyTripPassengersPayload;
    const { tripId, title, body } = payload;
    const type = payload.type ?? "trip_updated";
    const extraData = payload.data ?? {};

    if (!tripId?.trim() || !title?.trim() || !body?.trim()) {
      throw new HttpsError("invalid-argument", "tripId, title et body sont requis.");
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
    const uids = new Set<string>();
    bookingsSnap.docs.forEach((doc) => {
      const uid = `${doc.data()["requesterUid"] ?? ""}`.trim();
      if (uid) uids.add(uid);
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
  }
);
