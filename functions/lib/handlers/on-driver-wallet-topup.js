"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.onDriverWalletTopup = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const engine_1 = require("../scratch/engine");
const logger_1 = require("../utils/logger");
const logger = (0, logger_1.getLogger)("on-driver-wallet-topup");
/**
 * Firestore trigger: fires when a new transaction is created in a driver wallet.
 * Only processes credit transactions (amount > 0) with status = 'completed'.
 * Evaluates `wallet_topup` campaigns for the driver (uid from path).
 */
exports.onDriverWalletTopup = (0, firestore_1.onDocumentCreated)({
    document: "wallets/{uid}/transactions/{transactionId}",
    region: "europe-west1",
}, async (event) => {
    var _a, _b, _c;
    const data = (_a = event.data) === null || _a === void 0 ? void 0 : _a.data();
    if (!data)
        return;
    const amount = typeof data.amount === "number" ? data.amount : 0;
    const status = `${(_b = data.status) !== null && _b !== void 0 ? _b : ""}`.toLowerCase().trim();
    const type = `${(_c = data.type) !== null && _c !== void 0 ? _c : ""}`.toLowerCase().trim();
    // Only fire on completed credit (recharge) transactions
    if (amount <= 0 || status !== "completed" || type !== "recharge")
        return;
    const uid = event.params.uid;
    logger.info("Wallet topup trigger", { uid, amount, transactionId: event.params.transactionId });
    const cardIds = await (0, engine_1.evaluateScratchCampaigns)({
        trigger: "wallet_topup",
        uid,
        rechargeAmount: amount,
    });
    logger.info("Cards assigned for topup", { uid, cardIds });
});
//# sourceMappingURL=on-driver-wallet-topup.js.map