"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
exports.redeemReward = exports.revealScratchCard = exports.onDriverWalletTopup = exports.onPaymentCompleted = exports.registerAppLaunch = exports.sendPushOnNotificationCreated = void 0;
const firestore_1 = require("firebase-functions/v2/firestore");
const logger = __importStar(require("firebase-functions/logger"));
const admin = __importStar(require("firebase-admin"));
admin.initializeApp();
const db = admin.firestore();
const messaging = admin.messaging();
// ── Push notification types ───────────────────────────────────────────────────
const PUSH_TYPES = new Set([
    "parcel_request_created",
    "parcel_status_updated",
    "booking_created",
    "booking_status_updated",
    "booking_cancelled",
    "trip_updated",
    "trip_cancelled",
]);
// ── sendPushOnNotificationCreated ─────────────────────────────────────────────
exports.sendPushOnNotificationCreated = (0, firestore_1.onDocumentCreated)({
    document: "notifications/{notificationId}",
    region: "europe-west1",
}, async (event) => {
    var _a, _b, _c, _d, _e, _f, _g, _h;
    const snapshot = event.data;
    if (!snapshot)
        return;
    const notification = snapshot.data() || {};
    const userId = `${(_a = notification["userId"]) !== null && _a !== void 0 ? _a : ""}`.trim();
    const installationId = `${(_b = notification["installationId"]) !== null && _b !== void 0 ? _b : ""}`.trim();
    const type = `${(_c = notification["type"]) !== null && _c !== void 0 ? _c : ""}`.trim();
    const title = `${(_d = notification["title"]) !== null && _d !== void 0 ? _d : ""}`.trim();
    const body = `${(_e = notification["body"]) !== null && _e !== void 0 ? _e : ""}`.trim();
    const entityType = `${(_f = notification["entityType"]) !== null && _f !== void 0 ? _f : ""}`.trim();
    const entityId = `${(_g = notification["entityId"]) !== null && _g !== void 0 ? _g : ""}`.trim();
    const domain = `${(_h = notification["domain"]) !== null && _h !== void 0 ? _h : "system"}`.trim();
    if ((!userId && !installationId) || !PUSH_TYPES.has(type)) {
        logger.info("Push skipped", { userId, installationId, type });
        return;
    }
    const targets = await collectPushTargets({ userId, installationId });
    if (targets.length === 0) {
        logger.info("No push token found", { userId, installationId, type });
        return;
    }
    const tokens = targets.map((target) => target.token);
    if (tokens.length === 0) {
        logger.info("No enabled token value found", { userId, installationId, type });
        return;
    }
    const rawData = notification["data"] && typeof notification["data"] === "object"
        ? notification["data"]
        : {};
    const message = {
        tokens,
        notification: { title, body },
        data: normalizeData(Object.assign({ domain,
            type,
            entityType,
            entityId }, rawData)),
        android: { priority: "high" },
        apns: { payload: { aps: { sound: "default" } } },
    };
    const response = await messaging.sendEachForMulticast(message);
    if (response.failureCount === 0) {
        logger.info("Push sent", { userId, installationId, type, count: tokens.length });
        return;
    }
    const invalidTokenUpdates = [];
    response.responses.forEach((result, index) => {
        var _a, _b, _c;
        if (result.success)
            return;
        const target = targets[index];
        const token = (_a = target === null || target === void 0 ? void 0 : target.token) !== null && _a !== void 0 ? _a : tokens[index];
        const code = (_c = (_b = result.error) === null || _b === void 0 ? void 0 : _b.code) !== null && _c !== void 0 ? _c : "unknown";
        logger.error("Push send failure", { userId, installationId, type, token, code });
        if (code === "messaging/registration-token-not-registered" ||
            code === "messaging/invalid-registration-token") {
            invalidTokenUpdates.push(disableInvalidTarget(target));
        }
    });
    await Promise.all(invalidTokenUpdates);
});
async function collectPushTargets({ userId, installationId, }) {
    const targets = [];
    const seenTokens = new Set();
    if (installationId) {
        const installationSnapshot = await db
            .collection("pushInstallations")
            .doc(installationId)
            .get();
        if (installationSnapshot.exists) {
            pushTargetFromDoc({
                docs: [installationSnapshot],
                targets,
                seenTokens,
                source: "installation",
            });
        }
    }
    if (userId) {
        const [installationTargetsSnapshot, legacyTokensSnapshot] = await Promise.all([
            db
                .collection("pushInstallations")
                .where("userId", "==", userId)
                .where("enabled", "==", true)
                .get(),
            db
                .collection("userPushTokens")
                .doc(userId)
                .collection("tokens")
                .where("enabled", "==", true)
                .get(),
        ]);
        pushTargetFromDoc({
            docs: installationTargetsSnapshot.docs,
            targets,
            seenTokens,
            source: "installation",
        });
        pushTargetFromDoc({
            docs: legacyTokensSnapshot.docs,
            targets,
            seenTokens,
            source: "legacy",
        });
    }
    return targets;
}
function pushTargetFromDoc({ docs, targets, seenTokens, source, }) {
    docs.forEach((doc) => {
        var _a;
        const token = `${(_a = doc.get("token")) !== null && _a !== void 0 ? _a : ""}`.trim();
        const enabled = doc.get("enabled") !== false;
        if (!token || !enabled || seenTokens.has(token))
            return;
        seenTokens.add(token);
        targets.push({ token, ref: doc.ref, source });
    });
}
async function disableInvalidTarget(target) {
    if (!(target === null || target === void 0 ? void 0 : target.ref))
        return;
    if (target.source === "legacy") {
        await target.ref.delete();
        return;
    }
    await target.ref.set({
        enabled: false,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });
}
function normalizeData(input) {
    const output = {};
    for (const [key, value] of Object.entries(input)) {
        if (value === null || value === undefined)
            continue;
        output[key] = typeof value === "string" ? value : JSON.stringify(value);
    }
    return output;
}
// ── Scratch card system ───────────────────────────────────────────────────────
var register_app_launch_1 = require("./handlers/register-app-launch");
Object.defineProperty(exports, "registerAppLaunch", { enumerable: true, get: function () { return register_app_launch_1.registerAppLaunch; } });
var on_payment_completed_1 = require("./handlers/on-payment-completed");
Object.defineProperty(exports, "onPaymentCompleted", { enumerable: true, get: function () { return on_payment_completed_1.onPaymentCompleted; } });
var on_driver_wallet_topup_1 = require("./handlers/on-driver-wallet-topup");
Object.defineProperty(exports, "onDriverWalletTopup", { enumerable: true, get: function () { return on_driver_wallet_topup_1.onDriverWalletTopup; } });
var reveal_scratch_card_1 = require("./handlers/reveal-scratch-card");
Object.defineProperty(exports, "revealScratchCard", { enumerable: true, get: function () { return reveal_scratch_card_1.revealScratchCard; } });
var redeem_reward_1 = require("./handlers/redeem-reward");
Object.defineProperty(exports, "redeemReward", { enumerable: true, get: function () { return redeem_reward_1.redeemReward; } });
//# sourceMappingURL=index.js.map