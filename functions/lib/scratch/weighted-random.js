"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.weightedDraw = weightedDraw;
/**
 * Draws one reward from the pool using weighted random selection.
 * Rewards with weight 0 or remainingCount === 0 are excluded.
 */
function weightedDraw(rewards) {
    const eligible = rewards.filter((r) => {
        if (r.weight <= 0)
            return false;
        if (r.remainingCount !== undefined && r.remainingCount === 0)
            return false;
        return true;
    });
    if (eligible.length === 0)
        return null;
    const totalWeight = eligible.reduce((sum, r) => sum + r.weight, 0);
    if (totalWeight <= 0)
        return null;
    let random = Math.random() * totalWeight;
    for (const reward of eligible) {
        random -= reward.weight;
        if (random <= 0)
            return reward;
    }
    // Fallback — should never happen due to floating point edge cases
    return eligible[eligible.length - 1];
}
//# sourceMappingURL=weighted-random.js.map