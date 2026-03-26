"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.registerAppLaunch = void 0;
const https_1 = require("firebase-functions/v2/https");
const engine_1 = require("../scratch/engine");
const logger_1 = require("../utils/logger");
const logger = (0, logger_1.getLogger)("register-app-launch");
/**
 * Callable: triggered by the Flutter app on each launch.
 * Evaluates all `first_app_launch` campaigns for the authenticated user.
 *
 * Returns: { cardIds: string[] }
 */
exports.registerAppLaunch = (0, https_1.onCall)({ region: "europe-west1" }, async (request) => {
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "Authentication required.");
    }
    const uid = request.auth.uid;
    logger.info("App launch trigger", { uid });
    const cardIds = await (0, engine_1.evaluateScratchCampaigns)({
        trigger: "first_app_launch",
        uid,
    });
    return { cardIds };
});
//# sourceMappingURL=register-app-launch.js.map