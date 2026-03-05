/**
 * Deterministic deck creation for multiplayer blackjack.
 * Same seed + deckCount => same deck order (for replay/verification).
 */

export interface Card {
  rank: string;
  suit: string;
}

const SUITS = ["hearts", "clubs", "diamonds", "spades"];
const RANKS = [
  "A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K",
];

/**
 * Seeded PRNG (simple LCG). Returns 0..1.
 * @param {number} seed - Random seed.
 * @return {Function} Random number generator function.
 */
function seededRandom(seed: number): () => number {
  let state = seed;
  return () => {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return state / 0x7fffffff;
  };
}

/**
 * Create a shuffled deck of 52 * deckCount cards.
 * Shuffle is deterministic given seed.
 * @param {number} seed - Random seed.
 * @param {number} deckCount - Number of decks.
 * @return {Card[]} Shuffled deck.
 */
export function createShuffledDeck(seed: number, deckCount: number): Card[] {
  const cards: Card[] = [];
  for (let d = 0; d < deckCount; d++) {
    for (const suit of SUITS) {
      for (const rank of RANKS) {
        cards.push({rank, suit});
      }
    }
  }
  const rng = seededRandom(seed);
  for (let i = cards.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [cards[i], cards[j]] = [cards[j], cards[i]];
  }
  return cards;
}
