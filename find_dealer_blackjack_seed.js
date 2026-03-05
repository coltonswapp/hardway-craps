/**
 * Script to find a deck seed that results in dealer blackjack on first hand
 * for a 3-player game (dealer gets 10 at position 3, Ace at position 7)
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
 * Check if a deck has the desired dealer blackjack configuration:
 * - Position 3 (0-indexed): rank "10"
 * - Position 7 (0-indexed): rank "A"
 */
function hasDealerBlackjack(deck) {
  return deck[3].rank === "10" && deck[7].rank === "A";
}

/**
 * Search for a seed that produces dealer blackjack
 */
function findSeed(deckCount = 1, maxAttempts = 10000000) {
  console.log(`Searching for seed with deckCount=${deckCount}...`);
  console.log(`Target: Position 3 = rank "10", Position 7 = rank "A"`);
  
  const startTime = Date.now();
  let attempts = 0;
  
  // Try random seeds
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    // Try a random seed in the valid range
    const seed = Math.floor(Math.random() * 0x7fffffff);
    const deck = createShuffledDeck(seed, deckCount);
    
    if (hasDealerBlackjack(deck)) {
      const elapsed = Date.now() - startTime;
      console.log(`\n✓ Found seed: ${seed}`);
      console.log(`  Attempts: ${attempts}`);
      console.log(`  Time: ${elapsed}ms`);
      console.log(`\nFirst 8 cards:`);
      for (let i = 0; i < 8; i++) {
        console.log(`  Position ${i}: ${deck[i].rank} of ${deck[i].suit}`);
      }
      console.log(`\nDealer cards:`);
      console.log(`  Card 1 (pos 3): ${deck[3].rank} of ${deck[3].suit}`);
      console.log(`  Card 2 (pos 7): ${deck[7].rank} of ${deck[7].suit}`);
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
const deckCount = 1; // Assuming single deck, can change if needed
const seed = findSeed(deckCount);

if (seed !== null) {
  console.log(`\n=== RESULT ===`);
  console.log(`deckSeed: ${seed}`);
  console.log(`deckCount: ${deckCount}`);
  console.log(`\nUse this seed in your game to get dealer blackjack on first hand!`);
}
