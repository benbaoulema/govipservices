import { onCall, HttpsError } from "firebase-functions/v2/https";
import { evaluateScratchCampaigns } from "../scratch/engine";
import { getLogger } from "../utils/logger";

const logger = getLogger("register-app-launch");

/**
 * Callable: triggered by the Flutter app on each launch.
 * Evaluates all `first_app_launch` campaigns for the authenticated user.
 *
 * Returns: { cardIds: string[] }
 */
export const registerAppLaunch = onCall(
  { region: "europe-west1" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Authentication required.");
    }

    const uid = request.auth.uid;

    logger.info("App launch trigger", { uid });

    const cardIds = await evaluateScratchCampaigns({
      trigger: "first_app_launch",
      uid,
    });

    return { cardIds };
  }
);
