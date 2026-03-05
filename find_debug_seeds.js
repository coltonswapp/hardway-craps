#!/usr/bin/env node
/**
 * Generates pre-computed deck seeds for debug hand scenarios.
 * For each scenario and player count (1–4), finds a seed that produces
 * the desired card configuration when dealt by startDeal.
 *
 * Deal order with N players:
 *   positions 0..N-1    = player first cards (seat 0 is pos 0)
 *   position  N         = dealer card 1 (face-up)
 *   positions N+1..2N   = player second cards (seat 0 is pos N+1)
 *   position  2N+1      = dealer card 2 (hole card)
 *
 * Usage:  node find_debug_seeds.js
 * Output: prints a Swift-embeddable dictionary literal to stdout.
 */

const SUITS = ["hearts", "clubs", "diamonds", "spades"];
const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];
const TEN_VALUES = new Set(["10", "J", "Q", "K"]);

function seededRandom(seed) {
  let state = seed;
  return () => {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return state / 0x7fffffff;
  };
}

function createShuffledDeck(seed, deckCount) {
  const cards = [];
  for (let d = 0; d < deckCount; d++)
    for (const suit of SUITS)
      for (const rank of RANKS)
        cards.push({ rank, suit });
  const rng = seededRandom(seed);
  for (let i = cards.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [cards[i], cards[j]] = [cards[j], cards[i]];
  }
  return cards;
}

function cardValue(rank) {
  if (rank === "A") return 11;
  if (TEN_VALUES.has(rank)) return 10;
  return parseInt(rank, 10);
}

function isBlackjack(c1, c2) {
  return (TEN_VALUES.has(c1.rank) && c2.rank === "A") ||
         (c1.rank === "A" && TEN_VALUES.has(c2.rank));
}

// N = number of players with bets
// Dealer card 1 index = N, dealer card 2 index = 2N+1
// Player 0 card 1 index = 0, player 0 card 2 index = N+1
const scenarios = {
  // --- Dealer scenarios ---
  dealer_blackjack: (deck, N) => {
    const d1 = deck[N], d2 = deck[2 * N + 1];
    return isBlackjack(d1, d2);
  },
  dealer_ace_up: (deck, N) => {
    const d1 = deck[N], d2 = deck[2 * N + 1];
    // Ace up, but NOT blackjack (hole card must not be 10-value)
    return d1.rank === "A" && !TEN_VALUES.has(d2.rank);
  },
  dealer_10_up: (deck, N) => {
    return TEN_VALUES.has(deck[N].rank);
  },

  // --- Player (seat 0) scenarios ---
  player_blackjack: (deck, N) => {
    const p1 = deck[0], p2 = deck[N + 1];
    return isBlackjack(p1, p2);
  },
  player_pair: (deck, N) => {
    return deck[0].rank === deck[N + 1].rank;
  },
  player_hard_20: (deck, N) => {
    const p1 = deck[0], p2 = deck[N + 1];
    return TEN_VALUES.has(p1.rank) && TEN_VALUES.has(p2.rank);
  },
  player_double_11: (deck, N) => {
    const v = cardValue(deck[0].rank) + cardValue(deck[N + 1].rank);
    // Hard 11 (no aces counted as 11 making soft)
    return v === 11 && deck[0].rank !== "A" && deck[N + 1].rank !== "A";
  },
  player_double_10: (deck, N) => {
    const v = cardValue(deck[0].rank) + cardValue(deck[N + 1].rank);
    return v === 10 && deck[0].rank !== "A" && deck[N + 1].rank !== "A";
  },
  player_double_9: (deck, N) => {
    const v = cardValue(deck[0].rank) + cardValue(deck[N + 1].rank);
    return v === 9 && deck[0].rank !== "A" && deck[N + 1].rank !== "A";
  },
  player_soft_17: (deck, N) => {
    const p1 = deck[0], p2 = deck[N + 1];
    return (p1.rank === "A" && cardValue(p2.rank) === 6) ||
           (p2.rank === "A" && cardValue(p1.rank) === 6);
  },

  // --- Combined scenarios ---
  dealer_blackjack_player_blackjack: (deck, N) => {
    const d1 = deck[N], d2 = deck[2 * N + 1];
    const p1 = deck[0], p2 = deck[N + 1];
    return isBlackjack(d1, d2) && isBlackjack(p1, p2);
  },
};

const DECK_COUNT = 1;
const MAX_ATTEMPTS = 20_000_000;

function findSeed(scenarioFn, playerCount) {
  for (let attempt = 0; attempt < MAX_ATTEMPTS; attempt++) {
    const seed = Math.floor(Math.random() * 0x7fffffff);
    const deck = createShuffledDeck(seed, DECK_COUNT);
    if (scenarioFn(deck, playerCount)) {
      return seed;
    }
  }
  return null;
}

console.log("Generating debug seeds for all scenarios and player counts...\n");

const results = {};

for (const [name, fn] of Object.entries(scenarios)) {
  results[name] = {};
  for (let N = 1; N <= 4; N++) {
    process.stdout.write(`  ${name} (${N} players)...`);
    const seed = findSeed(fn, N);
    if (seed !== null) {
      results[name][N] = seed;
      // Verify
      const deck = createShuffledDeck(seed, DECK_COUNT);
      const d1 = deck[N], d2 = deck[2 * N + 1];
      const p1 = deck[0], p2 = deck[N + 1];
      console.log(` seed=${seed}  dealer=[${d1.rank},${d2.rank}] player0=[${p1.rank},${p2.rank}]`);
    } else {
      results[name][N] = -1;
      console.log(" NOT FOUND");
    }
  }
}

// Output as Swift dictionary literal
console.log("\n// === Swift-embeddable seed table ===");
console.log("// Paste into DebugHandsViewController.swift");
console.log("private static let debugSeeds: [String: [Int: Int]] = [");
for (const [name, byCount] of Object.entries(results)) {
  const entries = Object.entries(byCount).map(([n, s]) => `${n}: ${s}`).join(", ");
  console.log(`    "${name}": [${entries}],`);
}
console.log("]");

// Also output JSON
console.log("\n// === JSON ===");
console.log(JSON.stringify(results, null, 2));
