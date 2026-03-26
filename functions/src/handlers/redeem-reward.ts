import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { UserReward } from "../models/scratch";
import { getLogger } from "../utils/logger";

const logger = getLogger("redeem-reward");

interface RedeemRequest {
  rewardId: string;
  context?: Record<string, string>;
}

/**
 * Callable: redeems an available user reward.
 *
 * Input:  { rewardId: string, context?: Record<string, string> }
 * Output: { redemptionId: string }
 */
export const redeemReward = onCall(
  { region: "europe-west1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;
    const { rewardId, context } = request.data as RedeemRequest;

    if (!rewardId) {
      throw new HttpsError("invalid-argument", "rewardId is required.");
    }

    const db = getFirestore();
    const rewardRef = db.doc(`user_rewards/${uid}/rewards/${rewardId}`);

    const redemptionId = await db.runTransaction(async (tx) => {
      const rewardSnap = await tx.get(rewardRef);
      if (!rewardSnap.exists) {
        throw new HttpsError("not-found", "Reward not found.");
      }

      const reward = rewardSnap.data() as UserReward;

      if (reward.status !== "available") {
        throw new HttpsError(
          "failed-precondition",
          `Reward is already ${reward.status}.`
        );
      }

      // Check expiry
      const now = Timestamp.now();
      if (reward.expiresAt && now > reward.expiresAt) {
        tx.update(rewardRef, { status: "expired" });
        throw new HttpsError("failed-precondition", "Reward has expired.");
      }

      const redemptionRef = db.collection("reward_redemptions").doc();
      tx.set(redemptionRef, {
        uid,
        rewardId,
        type: reward.type,
        value: reward.value ?? null,
        redeemedAt: now,
        context: context ?? null,
      });

      tx.update(rewardRef, {
        status: "used",
        usedAt: now,
      });

      return redemptionRef.id;
    });

    logger.info("Reward redeemed", { uid, rewardId, redemptionId });
    return { redemptionId };
  }
);
