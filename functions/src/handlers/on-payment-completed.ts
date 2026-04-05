import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { evaluateScratchCampaigns } from "../scratch/engine";
import { getLogger } from "../utils/logger";

const logger = getLogger("on-payment-completed");

/**
 * Firestore trigger: fires when a voyageBookings document is updated.
 * Detects the transition to status = 'confirmed' (i.e., payment confirmed).
 * Evaluates `payment_completed` campaigns for the booking's userId.
 */
export const onPaymentCompleted = onDocumentUpdated(
  {
    document: "voyageBookings/{bookingId}",
    region: "europe-west1",
  },
  async (event) => {
    const before = event.data?.before?.data();
    const after = event.data?.after?.data();

    if (!before || !after) return;

    const prevStatus = `${before.status ?? ""}`.toLowerCase().trim();
    const newStatus = `${after.status ?? ""}`.toLowerCase().trim();

    // Only fire on transition to 'confirmed'
    if (newStatus !== "confirmed" || prevStatus === "confirmed") return;

    const uid = `${after.requesterUid ?? after.userId ?? ""}`.trim();
    if (!uid) {
      logger.warn("Booking has no requesterUid/userId", { bookingId: event.params.bookingId });
      return;
    }

    const totalPrice = typeof after.totalPrice === "number" ? after.totalPrice : 0;

    logger.info("Payment completed trigger", { uid, totalPrice, bookingId: event.params.bookingId });

    const cardIds = await evaluateScratchCampaigns({
      trigger: "payment_completed",
      uid,
      paymentAmount: totalPrice,
    });

    logger.info("Cards assigned for payment", { uid, cardIds });
  }
);
