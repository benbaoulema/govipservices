"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onPaymentCompleted = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const engine_1 = require("../scratch/engine");
const logger_1 = require("../utils/logger");
const logger = (0, logger_1.getLogger)("on-payment-completed");
/**
 * Firestore trigger: fires when a voyageBookings document is updated.
 * Detects the transition to status = 'confirmed' (i.e., payment confirmed).
 * Evaluates `payment_completed` campaigns for the booking's userId.
 */
exports.onPaymentCompleted = (0, firestore_1.onDocumentUpdated)({
    document: "voyageBookings/{bookingId}",
    region: "europe-west1",
}, async (event) => {
    var _a, _b, _c, _d, _e, _f, _g;
    const before = (_b = (_a = event.data) === null || _a === void 0 ? void 0 : _a.before) === null || _b === void 0 ? void 0 : _b.data();
    const after = (_d = (_c = event.data) === null || _c === void 0 ? void 0 : _c.after) === null || _d === void 0 ? void 0 : _d.data();
    if (!before || !after)
        return;
    const prevStatus = `${(_e = before.status) !== null && _e !== void 0 ? _e : ""}`.toLowerCase().trim();
    const newStatus = `${(_f = after.status) !== null && _f !== void 0 ? _f : ""}`.toLowerCase().trim();
    // Only fire on transition to 'confirmed'
    if (newStatus !== "confirmed" || prevStatus === "confirmed")
        return;
    const uid = `${(_g = after.userId) !== null && _g !== void 0 ? _g : ""}`.trim();
    if (!uid) {
        logger.warn("Booking has no userId", { bookingId: event.params.bookingId });
        return;
    }
    const totalPrice = typeof after.totalPrice === "number" ? after.totalPrice : 0;
    logger.info("Payment completed trigger", { uid, totalPrice, bookingId: event.params.bookingId });
    const cardIds = await (0, engine_1.evaluateScratchCampaigns)({
        trigger: "payment_completed",
        uid,
        paymentAmount: totalPrice,
    });
    logger.info("Cards assigned for payment", { uid, cardIds });
});
//# sourceMappingURL=on-payment-completed.js.map