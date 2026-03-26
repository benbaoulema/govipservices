import * as logger from "firebase-functions/logger";

export function getLogger(context: string) {
  return {
    info: (msg: string, data?: object) => logger.info(`[${context}] ${msg}`, data),
    warn: (msg: string, data?: object) => logger.warn(`[${context}] ${msg}`, data),
    error: (msg: string, data?: object) => logger.error(`[${context}] ${msg}`, data),
  };
}
