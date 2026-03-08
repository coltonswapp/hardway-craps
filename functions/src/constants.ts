/**
 * Shared constants for multiplayer blackjack Cloud Functions.
 * Paths and defaults match MULTIPLAYER_ARCHITECTURE.md.
 */

export const BASE_PATH = "mp_blackjack/table";

export const MAX_SEATS = 5;

export const MAX_HANDS_PER_SEAT = 4;

export const DEFAULT_SETTINGS = {
  bonusBetsEnabled: true,
  deckCount: 1,
  deckPenetration: 0.75,
  selectedSideBets: ["Royal Match", "Perfect Pairs"] as string[],
  startingBankroll: 500,
};

export const PHASES = {
  WAITING_FOR_READY: "waiting_for_ready",
  BETTING: "betting",
  DEALING: "dealing",
  PLAYER_ACTIONS: "player_actions",
  DEALER_TURN: "dealer_turn",
  RESOLVING: "resolving",
  GAME_OVER: "game_over",
  BETWEEN_HANDS: "between_hands",
} as const;

export type Phase = (typeof PHASES)[keyof typeof PHASES];
