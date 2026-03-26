import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { getLogger } from "../utils/logger";
import { ScratchCampaign, TriggerConditions, TriggerType } from "../models/scratch";

const logger = getLogger("scratch-engine");

export interface TriggerContext {
  trigger: TriggerType;
  uid: string;
  /** For payment_completed */
  paymentAmount?: number;
  /** For wallet_topup */
  rechargeAmount?: number;
}

/**
 * Evaluates all active campaigns for a given trigger + user.
 * For each eligible campaign, assigns a new scratch card.
 * Returns the list of newly created card IDs.
 */
export async function evaluateScratchCampaigns(ctx: TriggerContext): Promise<string[]> {
  const db = getFirestore();
  const now = Timestamp.now();

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

  const assignedCardIds: string[] = [];

  for (const campaignDoc of snapshot.docs) {
    const campaign = campaignDoc.data() as ScratchCampaign;
    const campaignId = campaignDoc.id;

    // 2. Check date range
    if (campaign.startAt && now < campaign.startAt) continue;
    if (campaign.endAt && now > campaign.endAt) continue;

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
    const maxPerUser = campaign.maxAwardsPerUser ?? 1;

    if (userCardCount >= maxPerUser) {
      logger.info("User card cap reached", { campaignId, uid: ctx.uid, userCardCount });
      continue;
    }

    // 5. Assign N cards (cardsToAssign) inside a transaction
    const cardsToAssign = campaign.cardsToAssign ?? 1;

    for (let i = 0; i < cardsToAssign; i++) {
      try {
        const cardId = await db.runTransaction(async (tx) => {
          const campaignRef = db.collection("scratchCampaigns").doc(campaignId);
          const cardRef = db.collection(`user_scratch_cards/${ctx.uid}/cards`).doc();

          // Compute expiry: rewardExpiresInDays ?? 30 days default
          const expiresInDays = campaign.rewardExpiresInDays ?? 30;
          const expiresAt = Timestamp.fromMillis(
            now.toMillis() + expiresInDays * 24 * 60 * 60 * 1000
          );

          tx.set(cardRef, {
            campaignId,
            status: "pending",
            assignedAt: now,
            expiresAt,
          });

          tx.update(campaignRef, {
            assignedCount: FieldValue.increment(1),
            updatedAt: FieldValue.serverTimestamp(),
          });

          return cardRef.id;
        });

        assignedCardIds.push(cardId);
        logger.info("Scratch card assigned", { campaignId, uid: ctx.uid, cardId });
      } catch (err: unknown) {
        logger.error("Failed to assign scratch card", { campaignId, uid: ctx.uid, err });
      }
    }
  }

  return assignedCardIds;
}

function meetsConditions(
  ctx: TriggerContext,
  conditions?: TriggerConditions
): boolean {
  if (!conditions) return true;

  if (
    ctx.trigger === "payment_completed" &&
    conditions.minPaymentAmount !== undefined
  ) {
    return (ctx.paymentAmount ?? 0) >= conditions.minPaymentAmount;
  }

  if (
    ctx.trigger === "wallet_topup" &&
    conditions.minRechargeAmount !== undefined
  ) {
    return (ctx.rechargeAmount ?? 0) >= conditions.minRechargeAmount;
  }

  return true;
}
