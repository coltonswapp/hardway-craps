/**
 * Server-side bonus bet evaluator for multiplayer blackjack.
 * Ported from BlackjackBonusBetEvaluator.swift.
 */

export interface Card {
  rank: string;
  suit: string;
}

export interface BonusBetResult {
  isWin: boolean;
  odds: number;
  payout: number;
  description: string;
}

const RANKS_VALUE: Record<string, number> = {
  "A": 11, "K": 10, "Q": 10, "J": 10, "10": 10,
  "9": 9, "8": 8, "7": 7, "6": 6, "5": 5, "4": 4, "3": 3, "2": 2,
};

/**
 * Get the numeric value of a card rank.
 * @param {string} rank - The card rank.
 * @return {number} The numeric value.
 */
function cardValue(rank: string): number {
  return RANKS_VALUE[rank] ?? 0;
}

/**
 * Check if a suit is red (hearts or diamonds).
 * @param {string} suit - The card suit.
 * @return {boolean} True if red.
 */
function isRed(suit: string): boolean {
  return suit === "hearts" || suit === "diamonds";
}

/**
 * Evaluate a Perfect Pairs bonus bet.
 * @param {Card} first - First card.
 * @param {Card} second - Second card.
 * @return {BonusBetResult} The result.
 */
function evaluatePerfectPairs(first: Card, second: Card): BonusBetResult {
  if (first.rank !== second.rank) {
    return {isWin: false, odds: 0, payout: 0, description: ""};
  }
  if (first.suit === second.suit) {
    return {isWin: true, odds: 30, payout: 0, description: "PERFECT PAIR"};
  }
  if (isRed(first.suit) === isRed(second.suit)) {
    return {isWin: true, odds: 10, payout: 0, description: "COLORED PAIR"};
  }
  return {isWin: true, odds: 5, payout: 0, description: "MIXED PAIR"};
}

/**
 * Evaluate a Royal Match bonus bet.
 * @param {Card} first - First card.
 * @param {Card} second - Second card.
 * @return {BonusBetResult} The result.
 */
function evaluateRoyalMatch(first: Card, second: Card): BonusBetResult {
  if (first.suit !== second.suit) {
    return {isWin: false, odds: 0, payout: 0, description: ""};
  }
  const hasKing = first.rank === "K" || second.rank === "K";
  const hasQueen = first.rank === "Q" || second.rank === "Q";
  if (hasKing && hasQueen) {
    return {isWin: true, odds: 25, payout: 0, description: "ROYAL MATCH"};
  }
  return {isWin: true, odds: 3, payout: 0, description: "SUITED MATCH"};
}

/**
 * Evaluate a Lucky Ladies bonus bet.
 * @param {Card} first - First card.
 * @param {Card} second - Second card.
 * @return {BonusBetResult} The result.
 */
function evaluateLuckyLadies(first: Card, second: Card): BonusBetResult {
  const total = cardValue(first.rank) + cardValue(second.rank);
  if (total !== 20) {
    return {isWin: false, odds: 0, payout: 0, description: ""};
  }
  if (first.rank === "Q" && second.rank === "Q" &&
      first.suit === "hearts" && second.suit === "hearts") {
    return {
      isWin: true,
      odds: 200,
      payout: 0,
      description: "LUCKY LADIES Q♥Q♥",
    };
  }
  if (first.rank === second.rank) {
    return {
      isWin: true,
      odds: 10,
      payout: 0,
      description: "LUCKY LADIES MATCHED",
    };
  }
  if (first.suit === second.suit) {
    return {
      isWin: true,
      odds: 25,
      payout: 0,
      description: "LUCKY LADIES SUITED",
    };
  }
  return {isWin: true, odds: 4, payout: 0, description: "LUCKY LADIES"};
}

/**
 * Evaluate a Lucky 7 initial bonus bet (after deal).
 * @param {Card} first - First card.
 * @param {Card} second - Second card.
 * @param {Card} [dealerUpcard] - Dealer's upcard.
 * @return {BonusBetResult} The result.
 */
function evaluateLucky7Initial(
  first: Card,
  second: Card,
  dealerUpcard?: Card
): BonusBetResult {
  const playerSevens = (first.rank === "7" ? 1 : 0) +
    (second.rank === "7" ? 1 : 0);
  const dealerSeven = dealerUpcard?.rank === "7" ? 1 : 0;
  const totalSevens = playerSevens + dealerSeven;

  if (totalSevens === 3) {
    return {isWin: true, odds: 500, payout: 0, description: "LUCKY 7 TRIPLE"};
  }
  if (playerSevens === 2) {
    if (first.suit === second.suit) {
      return {isWin: true, odds: 100, payout: 0, description: "LUCKY 7 SUITED"};
    }
    return {isWin: true, odds: 50, payout: 0, description: "LUCKY 7 PAIR"};
  }
  if (playerSevens === 1) {
    return {isWin: true, odds: 3, payout: 0, description: "LUCKY 7"};
  }
  return {isWin: false, odds: 0, payout: 0, description: ""};
}

/**
 * Evaluate a pair-based bonus bet (resolved right after the deal).
 * Returns result with odds filled in; caller computes payout = bet * odds.
 * @param {string} betType - The type of bonus bet.
 * @param {Card} firstCard - First card.
 * @param {Card} secondCard - Second card.
 * @param {Card} [dealerUpcard] - Dealer's upcard.
 * @return {BonusBetResult} The result.
 */
export function evaluateBonusBet(
  betType: string,
  firstCard: Card,
  secondCard: Card,
  dealerUpcard?: Card
): BonusBetResult {
  switch (betType) {
  case "Perfect Pairs":
    return evaluatePerfectPairs(firstCard, secondCard);
  case "Royal Match":
    return evaluateRoyalMatch(firstCard, secondCard);
  case "Lucky Ladies":
    return evaluateLuckyLadies(firstCard, secondCard);
  case "Lucky 7":
    return evaluateLucky7Initial(firstCard, secondCard, dealerUpcard);
  default:
    return {isWin: false, odds: 0, payout: 0, description: ""};
  }
}

/**
 * Evaluate a Buster bet (resolved after dealer finishes drawing).
 * @param {number} dealerTotal - Dealer's total.
 * @param {number} dealerCardCount - Number of dealer cards.
 * @return {BonusBetResult} The result.
 */
export function evaluateBuster(
  dealerTotal: number,
  dealerCardCount: number
): BonusBetResult {
  if (dealerTotal <= 21) {
    return {isWin: false, odds: 0, payout: 0, description: ""};
  }
  if (dealerCardCount >= 6) {
    return {
      isWin: true,
      odds: 250,
      payout: 0,
      description: "BUSTER 6+",
    };
  }
  if (dealerCardCount === 5) {
    return {isWin: true, odds: 6, payout: 0, description: "BUSTER 5"};
  }
  if (dealerCardCount === 4) {
    return {isWin: true, odds: 4, payout: 0, description: "BUSTER 4"};
  }
  return {isWin: true, odds: 2, payout: 0, description: "BUSTER 3"};
}

/**
 * Evaluate Lucky 7 at hand completion (uses all player cards).
 * @param {Card[]} playerCards - All player cards.
 * @return {BonusBetResult} The result.
 */
export function evaluateLucky7Complete(playerCards: Card[]): BonusBetResult {
  const sevens = playerCards.filter((c) => c.rank === "7");
  if (sevens.length === 0) {
    return {isWin: false, odds: 0, payout: 0, description: ""};
  }
  if (sevens.length >= 3) {
    return {isWin: true, odds: 500, payout: 0, description: "LUCKY 7 TRIPLE"};
  }
  if (sevens.length === 2) {
    if (sevens[0].suit === sevens[1].suit) {
      return {isWin: true, odds: 100, payout: 0, description: "LUCKY 7 SUITED"};
    }
    return {isWin: true, odds: 50, payout: 0, description: "LUCKY 7 PAIR"};
  }
  return {isWin: true, odds: 3, payout: 0, description: "LUCKY 7"};
}

/**
 * Returns true if the bet type requires the dealer's final hand to resolve
 * (i.e., it should NOT be resolved at deal time).
 * @param {string} betType - The bet type.
 * @return {boolean} True if dealer outcome bet.
 */
export function isDealerOutcomeBet(betType: string): boolean {
  return betType === "Buster";
}
