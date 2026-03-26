"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.revealScratchCard = void 0;
const https_1 = require("firebase-functions/v2/https");
const firestore_1 = require("firebase-admin/firestore");
const weighted_random_1 = require("../scratch/weighted-random");
const logger_1 = require("../utils/logger");
const logger = (0, logger_1.getLogger)("reveal-scratch-card");
/**
 * Callable: reveals a pending scratch card by drawing a reward.
 * The draw is done server-side using weighted random.
 *
 * Input:  { cardId: string }
 * Output: { rewardType, rewardLabel, rewardValue, rewardId }
 */
exports.revealScratchCard = (0, https_1.onCall)({ region: "europe-west1" }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    const { cardId } = request.data;
    if (!cardId) {
        throw new https_1.HttpsError("invalid-argument", "cardId is required.");
    }
    const db = (0, firestore_1.getFirestore)();
    const cardRef = db.doc(`user_scratch_cards/${uid}/cards/${cardId}`);
    const result = await db.runTransaction(async (tx) => {
        var _a, _b, _c, _d, _e, _f, _g;
        const cardSnap = await tx.get(cardRef);
        if (!cardSnap.exists) {
            throw new https_1.HttpsError("not-found", "Scratch card not found.");
        }
        const card = cardSnap.data();
        if (card.status !== "pending") {
            throw new https_1.HttpsError("failed-precondition", `Card is already ${card.status}.`);
        }
        // Check expiry
        const now = firestore_1.Timestamp.now();
        if (card.expiresAt && now > card.expiresAt) {
            tx.update(cardRef, { status: "expired" });
            throw new https_1.HttpsError("failed-precondition", "Scratch card has expired.");
        }
        // Fetch campaign for rewards pool
        const campaignRef = db.doc(`scratchCampaigns/${card.campaignId}`);
        const campaignSnap = await tx.get(campaignRef);
        if (!campaignSnap.exists) {
            throw new https_1.HttpsError("not-found", "Campaign not found.");
        }
        const campaign = campaignSnap.data();
        // Draw reward (server-side)
        const drawn = (0, weighted_random_1.weightedDraw)((_a = campaign.rewardsPool) !== null && _a !== void 0 ? _a : []);
        if (!drawn) {
            throw new https_1.HttpsError("internal", "No rewards available in campaign.");
        }
        // Decrement remaining count if limited
        if (drawn.totalAvailable !== undefined && drawn.totalAvailable !== -1) {
            const rewardIndex = ((_b = campaign.rewardsPool) !== null && _b !== void 0 ? _b : []).findIndex((r) => r.id === drawn.id);
            if (rewardIndex >= 0) {
                const remainingKey = `rewardsPool.${rewardIndex}.remainingCount`;
                tx.update(campaignRef, {
                    [remainingKey]: firestore_1.FieldValue.increment(-1),
                });
            }
        }
        // Compute reward expiry from campaign or drawn reward
        const expiresInDays = (_d = (_c = drawn.expiresInDays) !== null && _c !== void 0 ? _c : campaign.rewardExpiresInDays) !== null && _d !== void 0 ? _d : null;
        const rewardExpiresAt = expiresInDays
            ? firestore_1.Timestamp.fromMillis(now.toMillis() + expiresInDays * 24 * 60 * 60 * 1000)
            : null;
        // Create user reward doc
        const rewardRef = db.collection(`user_rewards/${uid}/rewards`).doc();
        tx.set(rewardRef, {
            campaignId: card.campaignId,
            cardId,
            type: drawn.type,
            label: drawn.label,
            value: (_e = drawn.value) !== null && _e !== void 0 ? _e : null,
            status: "available",
            earnedAt: now,
            expiresAt: rewardExpiresAt,
        });
        // Update card
        tx.update(cardRef, {
            status: "revealed",
            revealedAt: now,
            rewardId: rewardRef.id,
            rewardType: drawn.type,
            rewardLabel: drawn.label,
            rewardValue: (_f = drawn.value) !== null && _f !== void 0 ? _f : null,
        });
        return {
            rewardId: rewardRef.id,
            rewardType: drawn.type,
            rewardLabel: drawn.label,
            rewardValue: (_g = drawn.value) !== null && _g !== void 0 ? _g : null,
        };
    });
    logger.info("Card revealed", { uid, cardId, rewardType: result.rewardType });
    return result;
});
//# sourceMappingURL=reveal-scratch-card.js.map