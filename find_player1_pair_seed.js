/**
 * Script to find a deck seed that results in a pair for player 1 (seat index 0)
 * 
 * Deal order: each player first card, dealer first card, each player second card, dealer second card
 * For player 1 (seat 0) with N players:
 *   - First card: position 0
 *   - Second card: position N + 1
 */

const SUITS = ["hearts", "clubs", "diamonds", "spades"];
const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];

/** Seeded PRNG (simple LCG). Returns 0..1. */
function seededRandom(seed) {
  let state = seed;
  return () => {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return state / 0x7fffffff;
  };
}

/**
 * Create a shuffled deck of 52 * deckCount cards.
 * Shuffle is deterministic given seed.
 */
function createShuffledDeck(seed, deckCount) {
  const cards = [];
  for (let d = 0; d < deckCount; d++) {
    for (const suit of SUITS) {
      for (const rank of RANKS) {
        cards.push({ rank, suit });
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

/**
 * Check if player 1 gets a pair (same rank on first two cards)
 * @param {Array} deck - The shuffled deck
 * @param {number} numPlayers - Number of players (default 1)
 * @returns {boolean} True if player 1's two cards have the same rank
 */
function hasPlayer1Pair(deck, numPlayers = 1) {
  const firstCardPos = 0;
  const secondCardPos = numPlayers + 1;
  return deck[firstCardPos].rank === deck[secondCardPos].rank;
}

/**
 * Search for a seed that produces a pair for player 1
 */
function findSeed(deckCount = 1, numPlayers = 1, maxAttempts = 10000000) {
  console.log(`Searching for seed with deckCount=${deckCount}, numPlayers=${numPlayers}...`);
  console.log(`Target: Player 1 gets pair (positions ${0} and ${numPlayers + 1} have same rank)`);
  
  const startTime = Date.now();
  let attempts = 0;
  
  // Try random seeds
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    // Try a random seed in the valid range
    const seed = Math.floor(Math.random() * 0x7fffffff);
    const deck = createShuffledDeck(seed, deckCount);
    
    if (hasPlayer1Pair(deck, numPlayers)) {
      const elapsed = Date.now() - startTime;
      const firstCardPos = 0;
      const secondCardPos = numPlayers + 1;
      console.log(`\n✓ Found seed: ${seed}`);
      console.log(`  Attempts: ${attempts}`);
      console.log(`  Time: ${elapsed}ms`);
      console.log(`\nPlayer 1 cards:`);
      console.log(`  Card 1 (pos ${firstCardPos}): ${deck[firstCardPos].rank} of ${deck[firstCardPos].suit}`);
      console.log(`  Card 2 (pos ${secondCardPos}): ${deck[secondCardPos].rank} of ${deck[secondCardPos].suit}`);
      console.log(`\nFirst ${secondCardPos + 2} cards:`);
      for (let i = 0; i < secondCardPos + 2; i++) {
        console.log(`  Position ${i}: ${deck[i].rank} of ${deck[i].suit}`);
      }
      return seed;
    }
    
    attempts++;
    
    // Progress update every 100k attempts
    if (attempts % 100000 === 0) {
      const elapsed = Date.now() - startTime;
      const rate = attempts / (elapsed / 1000);
      console.log(`  Attempts: ${attempts.toLocaleString()}, Rate: ${Math.floor(rate)}/sec`);
    }
  }
  
  console.log(`\n✗ No seed found after ${attempts} attempts`);
  return null;
}

// Run the search
// Default: single deck, single player (positions 0 and 2)
const deckCount = 1;
const numPlayers = 1; // Change this if you want to test with more players
const seed = findSeed(deckCount, numPlayers);

if (seed !== null) {
  console.log(`\n=== RESULT ===`);
  console.log(`deckSeed: ${seed}`);
  console.log(`deckCount: ${deckCount}`);
  console.log(`numPlayers: ${numPlayers}`);
  console.log(`\nUse this seed in your game to get a pair for player 1 on first hand!`);
}
