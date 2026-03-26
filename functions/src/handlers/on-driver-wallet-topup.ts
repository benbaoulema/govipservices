import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { evaluateScratchCampaigns } from "../scratch/engine";
import { getLogger } from "../utils/logger";

const logger = getLogger("on-driver-wallet-topup");

/**
 * Firestore trigger: fires when a new transaction is created in a driver wallet.
 * Only processes credit transactions (amount > 0) with status = 'completed'.
 * Evaluates `wallet_topup` campaigns for the driver (uid from path).
 */
export const onDriverWalletTopup = onDocumentCreated(
  {
    document: "wallets/{uid}/transactions/{transactionId}",
    region: "europe-west1",
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    const amount = typeof data.amount === "number" ? data.amount : 0;
    const status = `${data.status ?? ""}`.toLowerCase().trim();
    const type = `${data.type ?? ""}`.toLowerCase().trim();

    // Only fire on completed credit (recharge) transactions
    if (amount <= 0 || status !== "completed" || type !== "recharge") return;

    const uid = event.params.uid;

    logger.info("Wallet topup trigger", { uid, amount, transactionId: event.params.transactionId });

    const cardIds = await evaluateScratchCampaigns({
      trigger: "wallet_topup",
      uid,
      rechargeAmount: amount,
    });

    logger.info("Cards assigned for topup", { uid, cardIds });
  }
);
