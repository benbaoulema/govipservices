import { onCall, HttpsError } from "firebase-functions/v2/https";
import { FieldValue, getFirestore, Timestamp } from "firebase-admin/firestore";
import { weightedDraw } from "../scratch/weighted-random";
import { ScratchCampaign, UserScratchCard } from "../models/scratch";
import { getLogger } from "../utils/logger";

const logger = getLogger("reveal-scratch-card");

interface RevealRequest {
  cardId: string;
}

/**
 * Callable: reveals a pending scratch card by drawing a reward.
 * The draw is done server-side using weighted random.
 *
 * Input:  { cardId: string }
 * Output: { rewardType, rewardLabel, rewardValue, rewardId }
 */
export const revealScratchCard = onCall(
  { region: "europe-west1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { cardId } = request.data as RevealRequest;

    if (!cardId) {
      throw new HttpsError("invalid-argument", "cardId is required.");
    }

    const db = getFirestore();
    const cardRef = db.doc(`user_scratch_cards/${uid}/cards/${cardId}`);

    const result = await db.runTransaction(async (tx) => {
      const cardSnap = await tx.get(cardRef);
      if (!cardSnap.exists) {
        throw new HttpsError("not-found", "Scratch card not found.");
      }

      const card = cardSnap.data() as UserScratchCard;

      if (card.status !== "pending") {
        throw new HttpsError(
          "failed-precondition",
          `Card is already ${card.status}.`
        );
      }

      // Check expiry
      const now = Timestamp.now();
      if (card.expiresAt && now > card.expiresAt) {
        tx.update(cardRef, { status: "expired" });
        throw new HttpsError("failed-precondition", "Scratch card has expired.");
      }

      // Fetch campaign for rewards pool
      const campaignRef = db.doc(`scratchCampaigns/${card.campaignId}`);
      const campaignSnap = await tx.get(campaignRef);
      if (!campaignSnap.exists) {
        throw new HttpsError("not-found", "Campaign not found.");
      }

      const campaign = campaignSnap.data() as ScratchCampaign;

      // Draw reward (server-side)
      const drawn = weightedDraw(campaign.rewardsPool ?? []);
      if (!drawn) {
        throw new HttpsError("internal", "No rewards available in campaign.");
      }

      // Decrement remaining count if limited
      if (drawn.totalAvailable !== undefined && drawn.totalAvailable !== -1) {
        const rewardIndex = (campaign.rewardsPool ?? []).findIndex((r) => r.id === drawn.id);
        if (rewardIndex >= 0) {
          const remainingKey = `rewardsPool.${rewardIndex}.remainingCount`;
          tx.update(campaignRef, {
            [remainingKey]: FieldValue.increment(-1),
          });
        }
      }

      // Compute reward expiry from campaign or drawn reward
      const expiresInDays = drawn.expiresInDays ?? campaign.rewardExpiresInDays ?? null;
      const rewardExpiresAt = expiresInDays
        ? Timestamp.fromMillis(now.toMillis() + expiresInDays * 24 * 60 * 60 * 1000)
        : null;

      // Create user reward doc
      const rewardRef = db.collection(`user_rewards/${uid}/rewards`).doc();
      tx.set(rewardRef, {
        campaignId: card.campaignId,
        cardId,
        type: drawn.type,
        label: drawn.label,
        value: drawn.value ?? null,
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
        rewardValue: drawn.value ?? null,
      });

      return {
        rewardId: rewardRef.id,
        rewardType: drawn.type,
        rewardLabel: drawn.label,
        rewardValue: drawn.value ?? null,
      };
    });

    logger.info("Card revealed", { uid, cardId, rewardType: result.rewardType });
    return result;
  }
);
