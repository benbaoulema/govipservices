"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.evaluateScratchCampaigns = evaluateScratchCampaigns;
const firestore_1 = require("firebase-admin/firestore");
const logger_1 = require("../utils/logger");
const logger = (0, logger_1.getLogger)("scratch-engine");
/**
 * Evaluates all active campaigns for a given trigger + user.
 * For each eligible campaign, assigns a new scratch card.
 * Returns the list of newly created card IDs.
 */
async function evaluateScratchCampaigns(ctx) {
    var _a, _b;
    const db = (0, firestore_1.getFirestore)();
    const now = firestore_1.Timestamp.now();
    // 1. Fetch all active campaigns matching this trigger
    const snapshot = await db
        .collection("scratchCampaigns")
        .where("isActive", "==", true)
        .where("trigger", "==", ctx.trigger)
        .get();
    if (snapshot.empty) {
        logger.info("No active campaigns for trigger", { trigger: ctx.trigger });
        return [];
    }
    const assignedCardIds = [];
    for (const campaignDoc of snapshot.docs) {
        const campaign = campaignDoc.data();
        const campaignId = campaignDoc.id;
        // 2. Check date range
        if (campaign.startAt && now < campaign.startAt)
            continue;
        if (campaign.endAt && now > campaign.endAt)
            continue;
        // 3. Check trigger conditions
        if (!meetsConditions(ctx, campaign.triggerConditions)) {
            logger.info("Trigger conditions not met", { campaignId, trigger: ctx.trigger });
            continue;
        }
        // 4. Check per-user cap
        const userCardsSnap = await db
            .collection(`user_scratch_cards/${ctx.uid}/cards`)
            .where("campaignId", "==", campaignId)
            .count()
            .get();
        const userCardCount = userCardsSnap.data().count;
        const maxPerUser = (_a = campaign.maxAwardsPerUser) !== null && _a !== void 0 ? _a : 1;
        if (userCardCount >= maxPerUser) {
            logger.info("User card cap reached", { campaignId, uid: ctx.uid, userCardCount });
            continue;
        }
        // 5. Assign N cards (cardsToAssign) inside a transaction
        const cardsToAssign = (_b = campaign.cardsToAssign) !== null && _b !== void 0 ? _b : 1;
        for (let i = 0; i < cardsToAssign; i++) {
            try {
                const cardId = await db.runTransaction(async (tx) => {
                    var _a;
                    const campaignRef = db.collection("scratchCampaigns").doc(campaignId);
                    const cardRef = db.collection(`user_scratch_cards/${ctx.uid}/cards`).doc();
                    // Compute expiry: rewardExpiresInDays ?? 30 days default
                    const expiresInDays = (_a = campaign.rewardExpiresInDays) !== null && _a !== void 0 ? _a : 30;
                    const expiresAt = firestore_1.Timestamp.fromMillis(now.toMillis() + expiresInDays * 24 * 60 * 60 * 1000);
                    tx.set(cardRef, {
                        campaignId,
                        status: "pending",
                        assignedAt: now,
                        expiresAt,
                    });
                    tx.update(campaignRef, {
                        assignedCount: firestore_1.FieldValue.increment(1),
                        updatedAt: firestore_1.FieldValue.serverTimestamp(),
                    });
                    return cardRef.id;
                });
                assignedCardIds.push(cardId);
                logger.info("Scratch card assigned", { campaignId, uid: ctx.uid, cardId });
            }
            catch (err) {
                logger.error("Failed to assign scratch card", { campaignId, uid: ctx.uid, err });
            }
        }
    }
    return assignedCardIds;
}
function meetsConditions(ctx, conditions) {
    var _a, _b;
    if (!conditions)
        return true;
    if (ctx.trigger === "payment_completed" &&
        conditions.minPaymentAmount !== undefined) {
        return ((_a = ctx.paymentAmount) !== null && _a !== void 0 ? _a : 0) >= conditions.minPaymentAmount;
    }
    if (ctx.trigger === "wallet_topup" &&
        conditions.minRechargeAmount !== undefined) {
        return ((_b = ctx.rechargeAmount) !== null && _b !== void 0 ? _b : 0) >= conditions.minRechargeAmount;
    }
    return true;
}
//# sourceMappingURL=engine.js.map