import { Timestamp } from "firebase-admin/firestore";

// ── Reward config inside a campaign ──────────────────────────────────────────

export interface RewardConfig {
  id: string;
  type: "discount_percent" | "discount_fixed" | "free_trip" | "wallet_credit" | "nothing";
  label: string;
  /** Monetary value or percentage, depending on type */
  value?: number;
  /** Relative weight for random draw (e.g. 10 = 10x more likely than weight 1) */
  weight: number;
  /** Reward validity in days after earning (null = no expiry) */
  expiresInDays?: number | null;
  /** -1 = unlimited */
  totalAvailable?: number;
  /** Decremented on each draw; managed inside a Firestore transaction */
  remainingCount?: number;
}

// ── Trigger condition guards ──────────────────────────────────────────────────

export interface TriggerConditions {
  /** For payment_completed: minimum booking amount in XOF */
  minPaymentAmount?: number;
  /** For wallet_topup: minimum recharge amount in XOF */
  minRechargeAmount?: number;
}

// ── Scratch campaign ──────────────────────────────────────────────────────────

export type TriggerType = "first_app_launch" | "payment_completed" | "wallet_topup";

export interface ScratchCampaign {
  title: string;
  slug?: string;
  description?: string;
  isActive: boolean;
  /** Single trigger value (matches TriggerType) */
  trigger: TriggerType;
  triggerConditions?: TriggerConditions;
  /** Max scratch cards a single user can receive from this campaign */
  maxAwardsPerUser: number;
  /** How many cards to assign per trigger event */
  cardsToAssign: number;
  /** Running total of cards assigned so far */
  assignedCount: number;
  startAt?: Timestamp | null;
  endAt?: Timestamp | null;
  rewardsPool: RewardConfig[];
  /** Default reward validity in days (null = no expiry) */
  rewardExpiresInDays?: number | null;
}

// ── User scratch card ─────────────────────────────────────────────────────────

export type CardStatus = "pending" | "revealed" | "expired";

export interface UserScratchCard {
  campaignId: string;
  status: CardStatus;
  assignedAt: Timestamp;
  expiresAt?: Timestamp;
  revealedAt?: Timestamp;
  /** Populated after reveal */
  rewardId?: string;
  rewardType?: RewardConfig["type"];
  rewardLabel?: string;
  rewardValue?: number;
}

// ── User reward ───────────────────────────────────────────────────────────────

export type RewardStatus = "available" | "used" | "expired";

export interface UserReward {
  campaignId: string;
  cardId: string;
  type: RewardConfig["type"];
  label: string;
  value?: number;
  status: RewardStatus;
  earnedAt: Timestamp;
  expiresAt?: Timestamp;
  usedAt?: Timestamp;
}

// ── Reward redemption ─────────────────────────────────────────────────────────

export interface RewardRedemption {
  uid: string;
  rewardId: string;
  type: RewardConfig["type"];
  value?: number;
  redeemedAt: Timestamp;
  /** e.g. { bookingId: 'xxx' } */
  context?: Record<string, string>;
}

// ── Trigger event tracking (per user) ────────────────────────────────────────

export interface TriggerEvent {
  count: number;
  lastTriggeredAt: Timestamp;
}
