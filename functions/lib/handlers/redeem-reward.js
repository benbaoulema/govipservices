"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.redeemReward = void 0;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const logger_1 = require("../utils/logger");
const logger = (0, logger_1.getLogger)("redeem-reward");
/**
 * Callable: redeems an available user reward.
 *
 * Input:  { rewardId: string, context?: Record<string, string> }
 * Output: { redemptionId: string }
 */
exports.redeemReward = (0, https_1.onCall)({ region: "europe-west1" }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { rewardId, context } = request.data;
    if (!rewardId) {
        throw new https_1.HttpsError("invalid-argument", "rewardId is required.");
    }
    const db = (0, firestore_1.getFirestore)();
    const rewardRef = db.doc(`user_rewards/${uid}/rewards/${rewardId}`);
    const redemptionId = await db.runTransaction(async (tx) => {
        var _a;
        const rewardSnap = await tx.get(rewardRef);
        if (!rewardSnap.exists) {
            throw new https_1.HttpsError("not-found", "Reward not found.");
        }
        const reward = rewardSnap.data();
        if (reward.status !== "available") {
            throw new https_1.HttpsError("failed-precondition", `Reward is already ${reward.status}.`);
        }
        // Check expiry
        const now = firestore_1.Timestamp.now();
        if (reward.expiresAt && now > reward.expiresAt) {
            tx.update(rewardRef, { status: "expired" });
            throw new https_1.HttpsError("failed-precondition", "Reward has expired.");
        }
        const redemptionRef = db.collection("reward_redemptions").doc();
        tx.set(redemptionRef, {
            uid,
            rewardId,
            type: reward.type,
            value: (_a = reward.value) !== null && _a !== void 0 ? _a : null,
            redeemedAt: now,
            context: context !== null && context !== void 0 ? context : null,
        });
        tx.update(rewardRef, {
            status: "used",
            usedAt: now,
        });
        return redemptionRef.id;
    });
    logger.info("Reward redeemed", { uid, rewardId, redemptionId });
    return { redemptionId };
});
//# sourceMappingURL=redeem-reward.js.map