import { onDocumentCreated } from "firebase-functions/v2/firestore";
import * as logger from "firebase-functions/logger";
import * as admin from "firebase-admin";

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

export const sendPushOnNotificationCreated = onDocumentCreated(
  {
    document: "notifications/{notificationId}",
    region: "europe-west1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const notification = snapshot.data() || {};
    const userId = `${notification["userId"] ?? ""}`.trim();
    const installationId = `${notification["installationId"] ?? ""}`.trim();
    const type = `${notification["type"] ?? ""}`.trim();
    const title = `${notification["title"] ?? ""}`.trim();
    const body = `${notification["body"] ?? ""}`.trim();
    const entityType = `${notification["entityType"] ?? ""}`.trim();
    const entityId = `${notification["entityId"] ?? ""}`.trim();
    const domain = `${notification["domain"] ?? "system"}`.trim();

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

    const rawData =
      notification["data"] && typeof notification["data"] === "object"
        ? (notification["data"] as Record<string, unknown>)
        : {};

    const message: admin.messaging.MulticastMessage = {
      tokens,
      notification: { title, body },
      data: normalizeData({
        domain,
        type,
        entityType,
        entityId,
        ...rawData,
      }),
      android: { priority: "high" },
      apns: { payload: { aps: { sound: "default" } } },
    };

    const response = await messaging.sendEachForMulticast(message);

    if (response.failureCount === 0) {
      logger.info("Push sent", { userId, installationId, type, count: tokens.length });
      return;
    }

    const invalidTokenUpdates: Promise<void>[] = [];
    response.responses.forEach((result, index) => {
      if (result.success) return;
      const target = targets[index];
      const token = target?.token ?? tokens[index];
      const code = result.error?.code ?? "unknown";
      logger.error("Push send failure", { userId, installationId, type, token, code });
      if (
        code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token"
      ) {
        invalidTokenUpdates.push(disableInvalidTarget(target));
      }
    });

    await Promise.all(invalidTokenUpdates);
  }
);

// ── Helpers ───────────────────────────────────────────────────────────────────

interface PushTarget {
  token: string;
  ref: admin.firestore.DocumentReference;
  source: "installation" | "legacy";
}

async function collectPushTargets({
  userId,
  installationId,
}: {
  userId: string;
  installationId: string;
}): Promise<PushTarget[]> {
  const targets: PushTarget[] = [];
  const seenTokens = new Set<string>();

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

function pushTargetFromDoc({
  docs,
  targets,
  seenTokens,
  source,
}: {
  docs: admin.firestore.DocumentSnapshot[];
  targets: PushTarget[];
  seenTokens: Set<string>;
  source: "installation" | "legacy";
}): void {
  docs.forEach((doc) => {
    const token = `${doc.get("token") ?? ""}`.trim();
    const enabled = doc.get("enabled") !== false;
    if (!token || !enabled || seenTokens.has(token)) return;

    seenTokens.add(token);
    targets.push({ token, ref: doc.ref, source });
  });
}

async function disableInvalidTarget(target: PushTarget | undefined): Promise<void> {
  if (!target?.ref) return;

  if (target.source === "legacy") {
    await target.ref.delete();
    return;
  }

  await target.ref.set(
    {
      enabled: false,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true }
  );
}

function normalizeData(input: Record<string, unknown>): Record<string, string> {
  const output: Record<string, string> = {};
  for (const [key, value] of Object.entries(input)) {
    if (value === null || value === undefined) continue;
    output[key] = typeof value === "string" ? value : JSON.stringify(value);
  }
  return output;
}

// ── Scratch card system ───────────────────────────────────────────────────────

export { registerAppLaunch } from "./handlers/register-app-launch";
export { onPaymentCompleted } from "./handlers/on-payment-completed";
export { onDriverWalletTopup } from "./handlers/on-driver-wallet-topup";
export { revealScratchCard } from "./handlers/reveal-scratch-card";
export { redeemReward } from "./handlers/redeem-reward";
export { notifyTripPassengers } from "./handlers/notify-trip-passengers";
