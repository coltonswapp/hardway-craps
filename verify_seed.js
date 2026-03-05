/**
 * Verify that the found seed produces the correct dealer blackjack
 */

const SUITS = ["hearts", "clubs", "diamonds", "spades"];
const RANKS = ["A", "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K"];

function seededRandom(seed) {
  let state = seed;
  return () => {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    return state / 0x7fffffff;
  };
}

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

const seed = 225948659;
const deckCount = 1;

console.log(`Verifying seed: ${seed}, deckCount: ${deckCount}\n`);

const deck = createShuffledDeck(seed, deckCount);

console.log("First 8 cards (dealing order for 3 players + dealer):");
console.log("  Position 0: Player 1, Card 1");
console.log("  Position 1: Player 2, Card 1");
console.log("  Position 2: Player 3, Card 1");
console.log("  Position 3: Dealer, Card 1 ← Should be rank '10'");
console.log("  Position 4: Player 1, Card 2");
console.log("  Position 5: Player 2, Card 2");
console.log("  Position 6: Player 3, Card 2");
console.log("  Position 7: Dealer, Card 2 ← Should be rank 'A'\n");

for (let i = 0; i < 8; i++) {
  const role = i === 3 ? "DEALER CARD 1" : i === 7 ? "DEALER CARD 2" : `Player ${Math.floor(i / 4) + 1}, Card ${i % 4 === 0 ? 1 : 2}`;
  console.log(`  Position ${i}: ${deck[i].rank.padEnd(2)} of ${deck[i].suit.padEnd(8)} [${role}]`);
}

console.log("\n✓ Verification:");
console.log(`  Position 3 rank: ${deck[3].rank} ${deck[3].rank === "10" ? "✓" : "✗"}`);
console.log(`  Position 7 rank: ${deck[7].rank} ${deck[7].rank === "A" ? "✓" : "✗"}`);

if (deck[3].rank === "10" && deck[7].rank === "A") {
  console.log("\n✓ SUCCESS: Dealer will have blackjack!");
  console.log(`\nUse deckSeed: ${seed} for debugging`);
} else {
  console.log("\n✗ FAILED: Cards don't match expected values");
}
