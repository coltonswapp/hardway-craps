/**
 * Multiplayer Blackjack — Cloud Functions
 * Authority for game state, deck, and payouts. See MULTIPLAYER_ARCHITECTURE.md.
 */

import * as admin from "firebase-admin";
import {onCall, HttpsError} from "firebase-functions/v2/https";
import {onSchedule} from "firebase-functions/v2/scheduler";
import * as logger from "firebase-functions/logger";
import {
  BASE_PATH,
  DEFAULT_SETTINGS,
  MAX_SEATS,
  MAX_HANDS_PER_SEAT,
  PHASES,
} from "./constants.js";
import {createShuffledDeck} from "./deck.js";
import {
  evaluateBonusBet,
  evaluateBuster,
  evaluateLucky7Complete,
  isDealerOutcomeBet,
} from "./bonusBetEvaluator.js";

if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.database();

/**
 * Get reference to table.
 * @param {string} tableCode - Table code.
 * @return {admin.database.Reference} Table reference.
 */
function tableRef(tableCode: string) {
  return db.ref(`${BASE_PATH}/${tableCode}`);
}

/**
 * Get reference to game state.
 * @param {string} tableCode - Table code.
 * @return {admin.database.Reference} Game reference.
 */
function gameRef(tableCode: string) {
  return db.ref(`${BASE_PATH}/${tableCode}/game`);
}

/**
 * Get reference to seats.
 * @param {string} tableCode - Table code.
 * @return {admin.database.Reference} Seats reference.
 */
function seatsRef(tableCode: string) {
  return db.ref(`${BASE_PATH}/${tableCode}/seats`);
}

/**
 * Get reference to settings.
 * @param {string} tableCode - Table code.
 * @return {admin.database.Reference} Settings reference.
 */
function settingsRef(tableCode: string) {
  return db.ref(`${BASE_PATH}/${tableCode}/settings`);
}

/**
 * Update the lastActivityAt timestamp for a table.
 * This is called whenever any game action occurs.
 * @param {string} tableCode - Table code.
 */
async function updateLastActivity(tableCode: string): Promise<void> {
  const now = Date.now();
  await tableRef(tableCode).child("lastActivityAt").set(now);
}

// ---------- createTable ----------
interface CreateTableData {
  deckCount?: number;
  deckPenetration?: number;
  bonusBetsEnabled?: boolean;
  selectedSideBets?: string[];
  startingBankroll?: number;
}

export const createTable = onCall<CreateTableData>(async (request) => {
  const options = (request.data ?? {}) as CreateTableData;
  const maxAttempts = 20;
  for (let attempt = 0; attempt < maxAttempts; attempt++) {
    const code = String(1000 + Math.floor(Math.random() * 9000));
    const ref = tableRef(code);
    const snap = await ref.once("value");
    if (snap.exists()) continue;

    const now = Date.now();
    const seatColors = ["Yellow Green", "Cyan", "Green", "Red", "Purple"];
    const seats: Record<string, unknown> = {};
    for (let i = 0; i < MAX_SEATS; i++) {
      seats[String(i)] = {
        playerId: null,
        displayName: "",
        balance: 0,
        chipColorName: seatColors[i] ?? "",
        ready: false,
        hands: [],
      };
    }
    const settings = {
      ...DEFAULT_SETTINGS,
      ...(options.deckCount != null &&
        {deckCount: options.deckCount}),
      ...(options.deckPenetration != null &&
        {deckPenetration: options.deckPenetration}),
      ...(options.bonusBetsEnabled != null &&
        {bonusBetsEnabled: options.bonusBetsEnabled}),
      ...(options.selectedSideBets != null &&
        {selectedSideBets: options.selectedSideBets}),
      ...(options.startingBankroll != null &&
        {startingBankroll: options.startingBankroll}),
    };
    await ref.set({
      inviteCode: code,
      createdAt: now,
      lastActivityAt: now,
      seats,
      settings,
    });
    await gameRef(code).set({
      phase: PHASES.BETTING,
      handNumber: 0,
      playerHands: {},
      dealerCards: [],
      deckIndex: 0,
      deckSeed: 0,
      dealerHoleRevealed: false,
      currentTurn: null,
      phaseResumeAt: 0,
    });
    logger.info("createTable", {code});
    return {tableCode: code};
  }
  throw new HttpsError(
    "resource-exhausted",
    "Could not generate unique table code"
  );
});

// ---------- updateTableSettings ----------
interface UpdateTableSettingsData {
  tableCode: string;
  deckCount?: number;
  deckPenetration?: number;
  bonusBetsEnabled?: boolean;
  selectedSideBets?: string[];
  startingBankroll?: number;
}

export const updateTableSettings = onCall<UpdateTableSettingsData>(
  async (request) => {
    const {tableCode, ...updates} =
      (request.data ?? {}) as UpdateTableSettingsData;
    if (!tableCode || typeof tableCode !== "string") {
      throw new HttpsError("invalid-argument", "tableCode is required");
    }
    const ref = settingsRef(tableCode);
    const snap = await ref.once("value");
    if (!snap.exists()) {
      throw new HttpsError("not-found", "Table not found");
    }
    const next: Record<string, unknown> = {};
    if (updates.deckCount != null) next.deckCount = updates.deckCount;
    if (updates.deckPenetration != null) {
      next.deckPenetration = updates.deckPenetration;
    }
    if (updates.bonusBetsEnabled != null) {
      next.bonusBetsEnabled = updates.bonusBetsEnabled;
    }
    if (updates.selectedSideBets != null) {
      next.selectedSideBets = updates.selectedSideBets;
    }
    if (updates.startingBankroll != null) {
      next.startingBankroll = updates.startingBankroll;
    }
    await ref.update(next);
    await updateLastActivity(tableCode);
    return {ok: true};
  }
);

// ---------- setReady ----------
interface SetReadyData {
  tableCode: string;
  seatIndex: number;
}

export const setReady = onCall<SetReadyData>(async (request) => {
  const {tableCode, seatIndex} = (request.data ?? {}) as SetReadyData;
  if (!tableCode || typeof seatIndex !== "number" ||
      seatIndex < 0 || seatIndex >= MAX_SEATS) {
    throw new HttpsError(
      "invalid-argument",
      "tableCode and valid seatIndex required"
    );
  }
  const seatRef = seatsRef(tableCode).child(String(seatIndex));
  const snap = await seatRef.once("value");
  if (!snap.exists() || !snap.val()?.playerId) {
    throw new HttpsError("failed-precondition", "Seat not occupied");
  }
  await seatRef.child("ready").set(true);
  await updateLastActivity(tableCode);
  return {ok: true};
});

// ---------- startGame ----------
interface StartGameData {
  tableCode: string;
}

export const startGame = onCall<StartGameData>(async (request) => {
  const {tableCode} = (request.data ?? {}) as StartGameData;
  if (!tableCode) {
    throw new HttpsError("invalid-argument", "tableCode required");
  }
  const game = gameRef(tableCode);
  const seats = seatsRef(tableCode);
  const gameSnap = await game.once("value");
  const seatsSnap = await seats.once("value");
  if (!gameSnap.exists() ||
      gameSnap.val()?.phase !== PHASES.WAITING_FOR_READY) {
    throw new HttpsError(
      "failed-precondition",
      "Game not in waiting_for_ready"
    );
  }
  const seatsVal = seatsSnap.val() ?? {};
  let allReady = true;
  const updates: Record<string, unknown> = {};
  for (let i = 0; i < MAX_SEATS; i++) {
    const s = seatsVal[String(i)];
    if (s?.playerId) {
      if (!s.ready) allReady = false;
      updates[`${i}/ready`] = false;
    }
  }
  if (!allReady) {
    throw new HttpsError(
      "failed-precondition",
      "Not all seated players are ready"
    );
  }
  await seats.update(updates);
  await game.update({phase: PHASES.BETTING});
  await updateLastActivity(tableCode);
  return {ok: true};
});

// ---------- placeBet ----------
interface PlaceBetData {
  tableCode: string;
  seatIndex: number;
  amount: number;
}

export const placeBet = onCall<PlaceBetData>(async (request) => {
  const {tableCode, seatIndex, amount} =
    (request.data ?? {}) as PlaceBetData;
  if (!tableCode || typeof seatIndex !== "number" ||
      typeof amount !== "number" || amount <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "tableCode, seatIndex, amount required"
    );
  }
  const gameSnap = await gameRef(tableCode).once("value");
  const g = gameSnap.val();
  if (!g || g.phase !== PHASES.BETTING) {
    throw new HttpsError("failed-precondition", "Not in betting phase");
  }
  const seatRef = seatsRef(tableCode).child(String(seatIndex));
  const result = await seatRef.transaction((current) => {
    if (!current || !current.playerId) return current;
    const balance = current.balance ?? 0;
    if (balance < amount) return; // abort
    const hands = (current.hands ?? []) as Array<{
      bet?: number;
      playerId?: string;
    }>;
    const existingBet = hands[0]?.bet ?? 0;
    current.balance = balance - amount;
    current.hands = [{bet: existingBet + amount, playerId: current.playerId}];
    return current;
  });
  if (!result.committed) {
    throw new HttpsError(
      "failed-precondition",
      "Seat not occupied or insufficient balance"
    );
  }
  const snap = result.snapshot.val();
  const newBalance = snap?.balance ?? 0;
  const newBet = snap?.hands?.[0]?.bet ?? 0;
  await updateLastActivity(tableCode);
  return {ok: true, newBalance, newBet};
});

// ---------- removeBet ----------
interface RemoveBetData {
  tableCode: string;
  seatIndex: number;
  amount: number;
}

export const removeBet = onCall<RemoveBetData>(async (request) => {
  const {tableCode, seatIndex, amount} =
    (request.data ?? {}) as RemoveBetData;
  if (!tableCode || typeof seatIndex !== "number" ||
      typeof amount !== "number" || amount <= 0) {
    throw new HttpsError(
      "invalid-argument",
      "tableCode, seatIndex, amount (positive) required"
    );
  }
  const gameSnap = await gameRef(tableCode).once("value");
  const g = gameSnap.val();
  if (!g || g.phase !== PHASES.BETTING) {
    throw new HttpsError("failed-precondition", "Not in betting phase");
  }
  const seatRef = seatsRef(tableCode).child(String(seatIndex));
  const result = await seatRef.transaction((current) => {
    if (!current || !current.playerId) return current;
    const hands = (current.hands ?? []) as Array<{
      bet?: number;
      playerId?: string;
    }>;
    const currentBet = hands[0]?.bet ?? 0;
    const removeAmount = Math.min(amount, currentBet);
    if (removeAmount <= 0) return current;
    current.balance = (current.balance ?? 0) + removeAmount;
    current.hands = [{
      bet: currentBet - removeAmount,
      playerId: current.playerId,
    }];
    return current;
  });
  if (!result.committed) {
    throw new HttpsError("failed-precondition", "Seat not occupied");
  }
  const snap = result.snapshot.val();
  const newBalance = snap?.balance ?? 0;
  const newBet = snap?.hands?.[0]?.bet ?? 0;
  await updateLastActivity(tableCode);
  return {ok: true, newBalance, newBet};
});

// ---------- placeBonusBet ----------
interface PlaceBonusBetData {
  tableCode: string;
  seatIndex: number;
  betIndex: number;
  amount: number;
}

export const placeBonusBet = onCall<PlaceBonusBetData>(async (request) => {
  const {tableCode, seatIndex, betIndex, amount} =
    (request.data ?? {}) as PlaceBonusBetData;
  if (!tableCode || typeof seatIndex !== "number" ||
      typeof betIndex !== "number" ||
      typeof amount !== "number" || amount <= 0 ||
      betIndex < 0 || betIndex > 1) {
    throw new HttpsError(
      "invalid-argument",
      "tableCode, seatIndex, betIndex (0-1), amount required"
    );
  }
  const gameSnap = await gameRef(tableCode).once("value");
  const g = gameSnap.val();
  if (!g || g.phase !== PHASES.BETTING) {
    throw new HttpsError("failed-precondition", "Not in betting phase");
  }
  const seatRef = seatsRef(tableCode).child(String(seatIndex));
  const result = await seatRef.transaction((current) => {
    if (!current || !current.playerId) return current;
    const balance = current.balance ?? 0;
    if (balance < amount) return; // abort
    const bonusBets = current.bonusBets ?? {};
    const existing = bonusBets[String(betIndex)]?.amount ?? 0;
    bonusBets[String(betIndex)] = {amount: existing + amount};
    current.balance = balance - amount;
    current.bonusBets = bonusBets;
    return current;
  });
  if (!result.committed) {
    throw new HttpsError(
      "failed-precondition",
      "Seat not occupied or insufficient balance"
    );
  }
  const snap = result.snapshot.val();
  const newBalance = snap?.balance ?? 0;
  const newBonusBet = snap?.bonusBets?.[String(betIndex)]?.amount ?? 0;
  await updateLastActivity(tableCode);
  return {ok: true, newBalance, newBonusBet};
});

// ---------- removeBonusBet ----------
interface RemoveBonusBetData {
  tableCode: string;
  seatIndex: number;
  betIndex: number;
  amount: number;
}

export const removeBonusBet = onCall<RemoveBonusBetData>(async (request) => {
  const {tableCode, seatIndex, betIndex, amount} =
    (request.data ?? {}) as RemoveBonusBetData;
  if (!tableCode || typeof seatIndex !== "number" ||
      typeof betIndex !== "number" ||
      typeof amount !== "number" || amount <= 0 ||
      betIndex < 0 || betIndex > 1) {
    throw new HttpsError(
      "invalid-argument",
      "tableCode, seatIndex, betIndex (0-1), amount (positive) required"
    );
  }
  const gameSnap = await gameRef(tableCode).once("value");
  const g = gameSnap.val();
  if (!g || g.phase !== PHASES.BETTING) {
    throw new HttpsError("failed-precondition", "Not in betting phase");
  }
  const seatRef = seatsRef(tableCode).child(String(seatIndex));
  const result = await seatRef.transaction((current) => {
    if (!current || !current.playerId) return current;
    const bonusBets = current.bonusBets ?? {};
    const currentBet = bonusBets[String(betIndex)]?.amount ?? 0;
    const removeAmount = Math.min(amount, currentBet);
    if (removeAmount <= 0) return current;
    const newAmount = currentBet - removeAmount;
    if (newAmount > 0) {
      bonusBets[String(betIndex)] = {amount: newAmount};
    } else {
      bonusBets[String(betIndex)] = null;
    }
    current.balance = (current.balance ?? 0) + removeAmount;
    current.bonusBets = bonusBets;
    return current;
  });
  if (!result.committed) {
    throw new HttpsError("failed-precondition", "Seat not occupied");
  }
  const snap = result.snapshot.val();
  const newBalance = snap?.balance ?? 0;
  const newBonusBet = snap?.bonusBets?.[String(betIndex)]?.amount ?? 0;
  await updateLastActivity(tableCode);
  return {ok: true, newBalance, newBonusBet};
});

// ---------- startDeal ----------
interface StartDealData {
  tableCode: string;
  debugSeed?: number;
}

export const startDeal = onCall<StartDealData>(async (request) => {
  const {tableCode, debugSeed} = (request.data ?? {}) as StartDealData;
  if (!tableCode) {
    throw new HttpsError("invalid-argument", "tableCode required");
  }
  logger.info("startDeal: received request", {
    tableCode,
    debugSeed,
    debugSeedType: typeof debugSeed,
  });
  const settingsSnap = await settingsRef(tableCode).once("value");
  const settings = settingsSnap.val() ?? DEFAULT_SETTINGS;
  const deckCount = Math.min(6, Math.max(1, Number(settings.deckCount) || 1));
  const game = gameRef(tableCode);
  const seats = seatsRef(tableCode);
  const [gameSnap, seatsSnap] = await Promise.all([
    game.once("value"),
    seats.once("value"),
  ]);
  const g = gameSnap.val();
  if (!g ||
      g.phase !== PHASES.BETTING) {
    throw new HttpsError("failed-precondition", "Not in betting phase");
  }

  // Find seats with bets FIRST (needed to calculate cards required)
  const seatsData = seatsSnap.val() ?? {};
  const seatKeys: number[] = [];
  for (let i = 0; i < MAX_SEATS; i++) {
    const seat = seatsData[i];
    if (!seat?.playerId || !seat.hands) continue;
    // Normalize hands to array (Firebase may store as object)
    const hands = (seat.hands != null && !Array.isArray(seat.hands)) ?
      Object.values(seat.hands) as Array<{bet?: number}> :
      (seat.hands ?? []) as Array<{bet?: number}>;
    const h0 = hands[0];
    if (h0?.bet) {
      seatKeys.push(i);
    }
  }
  seatKeys.sort((a, b) => a - b);
  if (seatKeys.length === 0) {
    throw new HttpsError("failed-precondition", "No players with bets");
  }

  const existingDeckSeed = Number(g.deckSeed) || 0;
  const existingDeckIndex = Number(g.deckIndex) || 0;
  const existingDeckCount = Number(g.deckCount) || deckCount;
  const totalCards = 52 * deckCount;
  const penetration = Number(settings.deckPenetration) || 0.75;
  const penetrationLimit = Math.floor(totalCards * penetration);

  let seed: number;
  let startIndex: number;

  // Check for debug seed (coerce to number in case it comes as string)
  const debugSeedNum = debugSeed != null ?
    Number(debugSeed) :
    null;
  if (debugSeedNum != null && !isNaN(debugSeedNum) &&
      debugSeedNum > 0 && debugSeedNum <= 0x7fffffff) {
    seed = Math.floor(debugSeedNum);
    startIndex = 0;
    logger.info("startDeal: using DEBUG seed", {
      debugSeed: seed,
      original: debugSeed,
    });
  } else if (existingDeckSeed === 0 ||
      existingDeckCount !== deckCount ||
      existingDeckIndex >= penetrationLimit) {
    seed = Math.floor(Math.random() * 0x7fffffff);
    startIndex = 0;
    const reason = existingDeckSeed === 0 ?
      "first_hand" :
      existingDeckCount !== deckCount ?
        "deck_count_changed" :
        "penetration_reached";
    logger.info("startDeal: new deck", {
      reason,
      penetrationLimit,
      existingDeckIndex,
      totalCards,
    });
  } else {
    seed = existingDeckSeed;
    startIndex = existingDeckIndex;
    logger.info("startDeal: reusing deck", {
      startIndex,
      penetrationLimit,
      totalCards,
    });
  }

  const deck = createShuffledDeck(seed, deckCount);

  const deckCopy = [...deck];
  let deckIndex = startIndex;
  const dealCard = () => {
    if (deckIndex >= deck.length) {
      throw new HttpsError("resource-exhausted", "Deck exhausted during deal");
    }
    return deckCopy[deckIndex++];
  };
  // Deal order: each player first card, dealer first card,
  // each player second card, dealer second card
  const firstCards: Array<{rank: string; suit: string}> = [];
  for (let i = 0; i < seatKeys.length; i++) {
    const card = dealCard();
    firstCards.push(card);
  }
  const dealerCard1 = dealCard();
  const secondCards: Array<{rank: string; suit: string}> =
    [];
  for (let i = 0; i < seatKeys.length; i++) {
    const card = dealCard();
    secondCards.push(card);
  }
  const dealerCard2 = dealCard();
  // Write cards to seats (don't auto-stand blackjacks)
  const updates: Record<string, unknown> = {};
  for (let i = 0; i < seatKeys.length; i++) {
    const seatIndex = seatKeys[i];
    const seat = seatsData[seatIndex];
    const cards = [firstCards[i], secondCards[i]];
    // Normalize hands to array (Firebase may store as object)
    const hands = (seat.hands != null && !Array.isArray(seat.hands)) ?
      Object.values(seat.hands) as Array<{bet?: number}> :
      (seat.hands ?? []) as Array<{bet?: number}>;
    const hand = {
      bet: hands[0].bet,
      playerId: seat.playerId,
      cards,
      stood: false, // Don't auto-stand blackjacks
      doubled: false,
      busted: false,
    };
    updates[`${seatIndex}/hands/0`] = hand;
  }
  await seats.update(updates);

  // Resolve pair-based bonus bets
  // (Perfect Pairs, Royal Match, Lucky Ladies, Lucky 7 initial)
  const selectedSideBets: string[] =
    settings.selectedSideBets ?? DEFAULT_SETTINGS.selectedSideBets;
  const bonusBetResults: Record<string, Record<string, {
    isWin: boolean;
    odds: number;
    payout: number;
    description: string;
  }>> = {};
  const bonusBetBalanceUpdates: Record<string, number> = {};

  for (let i = 0; i < seatKeys.length; i++) {
    const seatIndex = seatKeys[i];
    const seat = seatsData[seatIndex];
    const rawBonusBets = seat.bonusBets ??
      {};
    const playerCards = [firstCards[i], secondCards[i]];
    const seatResults: Record<string, {
      isWin: boolean;
      odds: number;
      payout: number;
      description: string;
    }> = {};

    for (let bi = 0; bi < selectedSideBets.length; bi++) {
      const betType = selectedSideBets[bi];
      const betAmount = rawBonusBets[String(bi)]?.amount ??
        0;
      if (betAmount <= 0) continue;
      if (isDealerOutcomeBet(betType)) continue;

      const result = evaluateBonusBet(
        betType,
        playerCards[0],
        playerCards[1],
        dealerCard1
      );
      const payout = result.isWin ?
        Math.floor(betAmount * result.odds) :
        0;
      seatResults[String(bi)] = {
        isWin: result.isWin,
        odds: result.odds,
        payout,
        description: result.description,
      };

      if (payout > 0) {
        const currentExtra =
          bonusBetBalanceUpdates[String(seatIndex)] ?? 0;
        bonusBetBalanceUpdates[String(seatIndex)] =
          currentExtra + payout + betAmount;
      }
    }
    if (Object.keys(seatResults).length > 0) {
      bonusBetResults[String(seatIndex)] = seatResults;
    }
  }

  for (const [seatIdx, returnAmount] of
    Object.entries(bonusBetBalanceUpdates)) {
    const seat = seatsData[Number(seatIdx)];
    await seats.child(seatIdx).child("balance")
      .set((seat.balance ?? 0) + returnAmount);
  }

  // Find first seat with a bet
  const firstSeat = seatKeys.length > 0 ?
    seatKeys[0] :
    null;

  // Check for dealer blackjack and resolve server-side
  // BUT: If dealer's upcard is an Ace, skip this check
  // Note: Client expects dealerCards as [holeCard, upCard]
  const dealerUpcardIsAce = dealerCard1.rank === "A";
  const dealerTotal = handTotal(
    [dealerCard1, dealerCard2] as Array<{rank: string}>
  );
  const dealerIsBlackjack = !dealerUpcardIsAce &&
      [dealerCard1, dealerCard2].length === 2 &&
      dealerTotal === 21;

  if (dealerIsBlackjack) {
    const handResults: Record<string,
      {outcome: string; payout: number; bet: number}[]> = {};
    for (let i = 0; i < seatKeys.length; i++) {
      const seatIndex = seatKeys[i];
      const seat = seatsData[seatIndex];
      const hands = (seat.hands != null && !Array.isArray(seat.hands)) ?
        Object.values(seat.hands) as Array<{bet?: number}> :
        (seat.hands ?? []) as Array<{bet?: number}>;
      const playerCards = [firstCards[i], secondCards[i]];
      const playerTotal = handTotal(
        playerCards as Array<{rank: string}>
      );
      const playerIsBlackjack = playerCards.length === 2 &&
        playerTotal === 21;
      const bet = hands[0].bet ?? 0;
      let returnAmount = 0;
      if (playerIsBlackjack) {
        returnAmount = bet;
        handResults[String(seatIndex)] = [
          {outcome: "push", payout: bet, bet},
        ];
      } else {
        handResults[String(seatIndex)] = [
          {outcome: "lose", payout: 0, bet},
        ];
      }
      if (returnAmount > 0) {
        await seats.child(String(seatIndex))
          .child("balance")
          .set((seat.balance ??
            0) + returnAmount);
      }
    }
    logger.info("startDeal: writing game state", {
      deckSeed: seed,
      deckIndex,
      deckCount,
      phase: PHASES.BETWEEN_HANDS,
    });
    // Client expects dealerCards as [holeCard, upCard]
    // So we need to swap: write [dealerCard2, dealerCard1]
    await game.update({
      phase: PHASES.BETWEEN_HANDS,
      deckSeed: seed,
      deckCount,
      deckIndex,
      dealerCards: [dealerCard2, dealerCard1],
      dealerHoleRevealed: true,
      dealerHasBlackjack: true,
      handNumber: (g.handNumber ?? 0) + 1,
      currentTurn: null,
      handResults,
      bonusBetResults: Object.keys(bonusBetResults).length > 0 ?
        bonusBetResults :
        null,
      phaseResumeAt: 0,
    });
    await updateLastActivity(tableCode);
    return {ok: true};
  }

  logger.info("startDeal: writing game state", {
    deckSeed: seed,
    deckIndex,
    deckCount,
    phase: PHASES.PLAYER_ACTIONS,
  });
  // Client expects dealerCards as [holeCard, upCard]
  // So we need to swap: write [dealerCard2, dealerCard1]
  await game.update({
    phase: PHASES.PLAYER_ACTIONS,
    deckSeed: seed,
    deckCount,
    deckIndex,
    dealerCards: [dealerCard2, dealerCard1],
    dealerHoleRevealed: false,
    dealerHasBlackjack: false,
    handNumber: (g.handNumber ?? 0) + 1,
    currentTurn: firstSeat != null ?
      {seatIndex: firstSeat, handIndex: 0} :
      null,
    bonusBetResults: Object.keys(bonusBetResults).length > 0 ?
      bonusBetResults :
      null,
    phaseResumeAt: 0,
  });
  await updateLastActivity(tableCode);
  return {ok: true};
});

// ---------- playerAction ----------
interface PlayerActionData {
  tableCode: string;
  seatIndex: number;
  handIndex: number;
  action: "hit" | "stand" | "double" | "split";
}

/**
 * Calculate the total value of a hand of cards.
 * @param {Array<{rank: string}>} cards - Array of cards.
 * @return {number} Total value.
 */
function handTotal(cards: Array<{rank: string}>): number {
  let total = 0;
  let aces = 0;
  for (const c of cards) {
    if (c.rank === "A") {
      aces++;
      total += 11;
    } else if (["K", "Q", "J", "10"].includes(c.rank)) total += 10;
    else total += Number(c.rank) || 0;
  }
  while (total > 21 && aces) {
    total -= 10;
    aces--;
  }
  return total;
}

export const playerAction = onCall<PlayerActionData>(async (request) => {
  const {tableCode, seatIndex, handIndex, action} =
    (request.data ?? {}) as PlayerActionData;
  if (!tableCode || typeof seatIndex !== "number" ||
      typeof handIndex !== "number" || !action) {
    throw new HttpsError(
      "invalid-argument",
      "tableCode, seatIndex, handIndex, action required"
    );
  }
  const game = gameRef(tableCode);
  const seats = seatsRef(tableCode);
  const [gameSnap, seatsSnap] = await Promise.all([
    game.once("value"),
    seats.once("value"),
  ]);
  const g = gameSnap.val();
  if (!g || g.phase !== PHASES.PLAYER_ACTIONS) {
    throw new HttpsError(
      "failed-precondition",
      "Not player_actions phase"
    );
  }
  const turn = g.currentTurn;
  if (!turn || turn.seatIndex !== seatIndex || turn.handIndex !== handIndex) {
    throw new HttpsError("failed-precondition", "Not your turn");
  }
  const seatsData = seatsSnap.val() ?? {};
  const seat = seatsData[seatIndex];
  if (!seat?.hands?.[handIndex]) {
    throw new HttpsError("failed-precondition", "Hand not found");
  }
  const hand = seat.hands[handIndex];
  if (hand.stood || hand.busted) {
    throw new HttpsError("failed-precondition", "Hand already done");
  }

  const settingsSnap = await settingsRef(tableCode).once("value");
  const settings = settingsSnap.val() ?? DEFAULT_SETTINGS;
  const deckCount = Math.min(6, Math.max(1, Number(settings.deckCount) || 1));
  let deckSeed = Number(g.deckSeed) || 0;
  let deck = createShuffledDeck(deckSeed, deckCount);
  let deckIndex = g.deckIndex ?? 0;
  const seatRef = seats.child(String(seatIndex));
  const handUpdates: Record<string, unknown> = {};
  let handStood = hand.stood ?? false;
  let handBusted = hand.busted ?? false;
  let handDoubled = hand.doubled ?? false;
  let deckWasReshuffled = false;

  // Check if player has blackjack (2 cards totaling 21) - auto-resolve it
  const handCards = hand.cards ?? [];
  const handTotalValue = handTotal(handCards as Array<{rank: string}>);
  const isBlackjack = handCards.length === 2 && handTotalValue === 21;

  if (isBlackjack) {
    // Auto-stand on blackjack - mark as stood and advance turn (ignore action)
    handUpdates[`hands/${handIndex}/stood`] = true;
    handStood = true;
  } else if (action === "hit" || action === "double") {
    // Validate double action: must have exactly 2 cards,
    // not already doubled, and have enough balance
    if (action === "double") {
      const currentCards = hand.cards ?? [];
      if (currentCards.length !== 2) {
        throw new HttpsError(
          "failed-precondition",
          "Double can only be done with exactly 2 cards"
        );
      }
      if (hand.doubled) {
        throw new HttpsError(
          "failed-precondition",
          "Hand already doubled"
        );
      }
      const bet = hand.bet ?? 0;
      const balance = seat.balance ?? 0;
      if (balance < bet) {
        throw new HttpsError(
          "failed-precondition",
          "Insufficient balance to double"
        );
      }
    }
    if (deckIndex >= deck.length) {
      logger.warn("playerAction: deck exhausted mid-hand, reshuffling", {
        deckIndex,
        deckLength: deck.length,
        seatIndex,
        action,
      });
      deckSeed = Math.floor(Math.random() * 0x7fffffff);
      deck = createShuffledDeck(deckSeed, deckCount);
      deckIndex = 0;
      deckWasReshuffled = true;
    }
    const card = deck[deckIndex];
    const newCards = [...(hand.cards ?? []), card];
    deckIndex++;
    if (action === "double") {
      const bet = hand.bet ?? 0;
      const newBalance = (seat.balance ?? 0) - bet;
      handUpdates["balance"] = newBalance;
      handUpdates[`hands/${handIndex}/doubled`] = true;
      handUpdates[`hands/${handIndex}/bet`] = bet * 2;
      handDoubled = true;
    }
    handUpdates[`hands/${handIndex}/cards`] = newCards;
    const total = handTotal(newCards as Array<{rank: string}>);
    if (total > 21) {
      handUpdates[`hands/${handIndex}/busted`] = true;
      handBusted = true;
    } else if (total === 21) {
      // Auto-stand on 21: turn advances to next player or dealer
      handUpdates[`hands/${handIndex}/stood`] = true;
      handStood = true;
    }
  } else if (action === "stand") {
    handUpdates[`hands/${handIndex}/stood`] = true;
    handStood = true;
  } else if (action === "split") {
    const cards = hand.cards ?? [];
    if (cards.length !== 2) {
      throw new HttpsError(
        "failed-precondition",
        "Split requires exactly 2 cards"
      );
    }
    if (cards[0].rank !== cards[1].rank) {
      throw new HttpsError(
        "failed-precondition",
        "Cards must match to split"
      );
    }
    if (hand.stood) {
      throw new HttpsError(
        "failed-precondition",
        "Cannot split a hand that has already stood"
      );
    }
    if (hand.doubled) {
      throw new HttpsError(
        "failed-precondition",
        "Cannot split a hand that has already doubled"
      );
    }
    if (hand.busted) {
      throw new HttpsError(
        "failed-precondition",
        "Cannot split a hand that has already busted"
      );
    }
    const allHands: unknown[] = Array.isArray(seat.hands) ?
      [...seat.hands] :
      (seat.hands ? Object.values(seat.hands) : []);
    if (allHands.length >= MAX_HANDS_PER_SEAT) {
      throw new HttpsError(
        "failed-precondition",
        `Cannot split beyond ${MAX_HANDS_PER_SEAT} hands`
      );
    }
    const bet = hand.bet ?? 0;
    if ((seat.balance ?? 0) < bet) {
      throw new HttpsError(
        "failed-precondition",
        "Insufficient balance to split"
      );
    }
    handUpdates["balance"] = (seat.balance ?? 0) - bet;

    // Each new hand starts with just the one original card
    const hand0 = {
      bet,
      playerId: seat.playerId,
      cards: [cards[0]],
      stood: false,
      doubled: false,
      busted: false,
    };
    const hand1 = {
      bet,
      playerId: seat.playerId,
      cards: [cards[1]],
      stood: false,
      doubled: false,
      busted: false,
    };

    allHands.splice(handIndex, 1, hand0, hand1);
    handUpdates["hands"] = allHands;
  }
  await seatRef.update(handUpdates);
  const allSeatsData = seatsSnap.val() ??
    {};

  // After a split the current seat's hands array changed
  const currentSeatHands: Array<{
    stood?: boolean;
    busted?: boolean;
    doubled?: boolean;
    bet?: number;
  }> = action === "split" && handUpdates["hands"] ?
    handUpdates["hands"] as typeof currentSeatHands :
    (Array.isArray(seat.hands) ?
      seat.hands :
      (seat.hands ?
        Object.values(seat.hands) :
        []));

  const handDone = handStood || handBusted || handDoubled;

  const handsForSeat = (i: number): Array<{
    stood?: boolean;
    busted?: boolean;
    doubled?: boolean;
    bet?: number;
  }> => {
    if (i === seatIndex) return currentSeatHands;
    const s = allSeatsData[i];
    if (!s?.hands) return [];
    return (s.hands != null && !Array.isArray(s.hands)) ?
      Object.values(s.hands) :
      (s.hands ?? []);
  };

  const allDone = () => {
    for (let i = 0; i < MAX_SEATS; i++) {
      const list = handsForSeat(i);
      for (let j = 0; j < list.length; j++) {
        const isThisHand = i === seatIndex && j === handIndex;
        const done = isThisHand ?
          handDone :
          !!(list[j].stood ||
            list[j].busted ||
            list[j].doubled);
        if (!done) return false;
      }
    }
    return true;
  };

  let nextTurn = turn;
  const seatHandCount = currentSeatHands.length;
  if (handDone) {
    if (handIndex + 1 < seatHandCount) {
      nextTurn = {seatIndex, handIndex: handIndex + 1};
    } else {
      const seatKeys: number[] = [];
      for (let i = 0; i < MAX_SEATS; i++) {
        const hands = handsForSeat(i);
        const s = i === seatIndex ? seat : allSeatsData[i];
        const h0 = hands[0];
        if (s?.playerId && h0?.bet) {
          seatKeys.push(i);
        }
      }
      seatKeys.sort((a, b) => a - b);
      const idx = seatKeys.indexOf(
        seatIndex
      );
      let nextSeat: number | null = null;
      for (let k = idx + 1; k < seatKeys.length; k++) {
        const candidateHands = handsForSeat(seatKeys[k]);
        let found = false;
        for (const h of candidateHands) {
          if (h && !h.stood && !h.busted && !h.doubled) {
            found = true;
            break;
          }
        }
        if (found) {
          nextSeat = seatKeys[k];
          break;
        }
      }
      if (nextSeat != null) {
        nextTurn = {seatIndex: nextSeat, handIndex: 0};
      } else {
        nextTurn = {seatIndex: 0, handIndex: 0};
      }
    }
  }
  const everyoneDone = allDone();
  const gameUpdates: Record<string, unknown> = {
    deckIndex,
    currentTurn: everyoneDone ?
      null :
      nextTurn,
  };
  if (deckWasReshuffled) {
    gameUpdates.deckSeed = deckSeed;
    gameUpdates.deckCount = deckCount;
  }
  if (everyoneDone) {
    gameUpdates.phase = PHASES.DEALER_TURN;
  }
  await game.update(gameUpdates);
  await updateLastActivity(tableCode);
  return {ok: true};
});

// ---------- runDealer ----------
interface RunDealerData {
  tableCode: string;
}

export const runDealer = onCall<RunDealerData>(async (request) => {
  const {tableCode} = (request.data ?? {}) as RunDealerData;
  if (!tableCode) {
    throw new HttpsError("invalid-argument", "tableCode required");
  }
  const game = gameRef(tableCode);
  const [gameSnap, settingsSnap] = await Promise.all([
    game.once("value"),
    settingsRef(tableCode).once("value"),
  ]);
  const g = gameSnap.val();
  if (!g || g.phase !== PHASES.DEALER_TURN) {
    throw new HttpsError("failed-precondition", "Not dealer_turn phase");
  }
  const settings = settingsSnap.val() ?? DEFAULT_SETTINGS;
  const deckCount = Math.min(6, Math.max(1, Number(settings.deckCount) || 1));
  let deckSeed = Number(g.deckSeed) || 0;
  let deck = createShuffledDeck(deckSeed, deckCount);
  let deckIndex = g.deckIndex ?? 0;
  const dealerCards = [...(g.dealerCards ?? [])] as Array<{
    rank: string;
    suit: string;
  }>;

  // Check if dealer needs to draw:
  // skip when every hand is either busted or a natural blackjack
  const seats = seatsRef(tableCode);
  const seatsSnap = await seats.once("value");
  const seatsData = seatsSnap.val() ?? {};
  let needsDealerDraw = false;
  for (let i = 0; i < MAX_SEATS; i++) {
    const seat = seatsData[i];
    if (!seat?.playerId || !seat.hands) continue;
    const list = (seat.hands != null && !Array.isArray(seat.hands)) ?
      (Object.values(seat.hands) as Array<{
        busted?: boolean;
        cards?: Array<{rank: string}>;
      }>) :
      (seat.hands ?? []) as Array<{
        busted?: boolean;
        cards?: Array<{rank: string}>;
      }>;
    for (const h of list) {
      if (h.busted) continue;
      const cards = h.cards ?? [];
      const isBlackjack = cards.length === 2 && handTotal(cards) === 21;
      if (!isBlackjack) {
        needsDealerDraw = true;
        break;
      }
    }
    if (needsDealerDraw) break;
  }

  if (!needsDealerDraw) {
    await game.update({dealerHoleRevealed: true});
  } else {
    const soft17 = (cards: Array<{rank: string}>) => {
      const t = handTotal(cards);
      if (t !== 17) return false;
      return cards.some((c) => c.rank === "A");
    };
    // eslint-disable-next-line no-constant-condition
    while (true) {
      const total = handTotal(dealerCards as Array<{rank: string}>);
      if (total > 21) break;
      if (total >= 17 &&
          !soft17(dealerCards as Array<{rank: string}>)) break;
      if (deckIndex >= deck.length) {
        logger.warn("runDealer: deck exhausted, reshuffling", {
          deckIndex,
          deckLength: deck.length,
        });
        deckSeed = Math.floor(Math.random() * 0x7fffffff);
        deck = createShuffledDeck(deckSeed, deckCount);
        deckIndex = 0;
      }
      dealerCards.push(deck[deckIndex++]);
      await game.update({
        dealerCards, deckIndex, deckSeed, dealerHoleRevealed: true,
      });
      await updateLastActivity(tableCode);
    }
  }
  const dealerTotal = handTotal(dealerCards as Array<{rank: string}>);
  const dealerBusted = dealerTotal > 21;
  const dealerIsBlackjack = dealerCards.length === 2 &&
    dealerTotal === 21;
  const handResults: Record<string, Array<{
    outcome: string;
    payout: number;
    bet: number;
  }>> = {};
  for (let i = 0; i < MAX_SEATS; i++) {
    const seat = seatsData[i];
    if (!seat?.playerId || !seat.hands) continue;
    // returnAmount is the total chips returned to the player
    // When a bet is placed the balance is immediately reduced, so:
    //   win     → return bet*2 (original bet + profit)
    //   loss    → return 0     (bet already deducted)
    //   push    → return bet   (original bet returned, no profit)
    //   blackjack → return bet + floor(bet*1.5)
    let returnAmount = 0;
    const seatResults: Array<{
      outcome: string;
      payout: number;
      bet: number;
    }> = [];
    for (const h of seat.hands ?? []) {
      const bet = h.bet ?? 0;
      const playerCards = (h.cards ?? []) as Array<{rank: string}>;
      const playerTotal = handTotal(playerCards);
      const playerIsBlackjack = playerCards.length === 2 &&
        playerTotal === 21;
      if (h.busted) {
        // returnAmount += 0 (nothing returned on a bust)
        seatResults.push({outcome: "lose", payout: 0, bet});
      } else if (playerIsBlackjack && !dealerIsBlackjack) {
        const bjWin = Math.floor(bet * 1.5);
        returnAmount += bet + bjWin;
        seatResults.push({
          outcome: "blackjack",
          payout: bet + bjWin,
          bet,
        });
      } else if (playerIsBlackjack && dealerIsBlackjack) {
        returnAmount += bet;
        seatResults.push({outcome: "push", payout: bet, bet});
      } else if (dealerBusted) {
        returnAmount += bet * 2;
        seatResults.push({outcome: "win", payout: bet * 2, bet});
      } else if (playerTotal > dealerTotal) {
        returnAmount += bet * 2;
        seatResults.push({outcome: "win", payout: bet * 2, bet});
      } else if (playerTotal < dealerTotal) {
        // returnAmount += 0 (nothing returned on a loss)
        seatResults.push({outcome: "lose", payout: 0, bet});
      } else {
        returnAmount += bet;
        seatResults.push({outcome: "push", payout: bet, bet});
      }
    }
    handResults[String(i)] = seatResults;
    if (returnAmount > 0) {
      const seatRef = seats.child(String(i));
      await seatRef.child("balance").set((seat.balance ?? 0) + returnAmount);
    }
  }

  // Resolve dealer-outcome bonus bets (Buster, Lucky 7 complete)
  const settingsForBonus = settings ?? DEFAULT_SETTINGS;
  const selectedSideBetsDealer: string[] =
    (settingsForBonus as {selectedSideBets?: string[]})
      .selectedSideBets ??
    DEFAULT_SETTINGS.selectedSideBets;
  const existingBonusBetResults: Record<string, Record<string, {
    isWin: boolean;
    odds: number;
    payout: number;
    description: string;
  }>> = g.bonusBetResults ?? {};
  const bonusBetBalanceUpdatesDealer: Record<string, number> = {};

  for (let i = 0; i < MAX_SEATS; i++) {
    const seat = seatsData[i];
    if (!seat?.playerId) continue;
    const rawBonusBets = seat.bonusBets ?? {};

    for (let bi = 0; bi < selectedSideBetsDealer.length; bi++) {
      const betType = selectedSideBetsDealer[bi];
      const betAmount = rawBonusBets[String(bi)]?.amount ?? 0;
      if (betAmount <= 0) continue;

      let result: {
        isWin: boolean;
        odds: number;
        payout: number;
        description: string;
      } | null = null;
      if (betType === "Buster") {
        result = evaluateBuster(dealerTotal, dealerCards.length);
      } else if (betType === "Lucky 7") {
        const hands = (seat.hands != null &&
            !Array.isArray(seat.hands)) ?
          Object.values(seat.hands) as Array<{
            cards?: Array<{rank: string; suit: string}>;
          }> :
          (seat.hands ?? []) as Array<{
            cards?: Array<{rank: string; suit: string}>;
          }>;
        const playerCards = (hands[0]?.cards ??
          []) as Array<{
          rank: string;
          suit: string;
        }>;
        result = evaluateLucky7Complete(playerCards);
      } else {
        continue;
      }

      if (result) {
        const payout = result.isWin ?
          Math.floor(betAmount * result.odds) :
          0;
        result.payout = payout;

        if (!existingBonusBetResults[String(i)]) {
          existingBonusBetResults[String(i)] =
            {};
        }
        existingBonusBetResults[String(i)][String(bi)] = result;

        if (payout > 0) {
          const currentExtra =
            bonusBetBalanceUpdatesDealer[String(i)] ?? 0;
          bonusBetBalanceUpdatesDealer[String(i)] =
            currentExtra + payout + betAmount;
        }
      }
    }
  }

  for (const [seatIdx, bonusReturn] of
    Object.entries(bonusBetBalanceUpdatesDealer)) {
    const seatRef = seats.child(seatIdx);
    const currentSnap = await seatRef.child("balance").once("value");
    const currentBalance = (currentSnap.val() as number) ?? 0;
    await seatRef.child("balance").set(currentBalance + bonusReturn);
  }

  await game.update({
    phase: PHASES.BETWEEN_HANDS,
    dealerHoleRevealed: true,
    dealerCards,
    handResults,
    bonusBetResults: Object.keys(existingBonusBetResults).length > 0 ?
      existingBonusBetResults :
      null,
  });
  await updateLastActivity(tableCode);
  return {ok: true};
});

// ---------- resolveDealerBlackjack ----------
// Called when dealer blackjack is detected during player_actions phase.
// Resolves all bets immediately and transitions to between_hands.
interface ResolveDealerBlackjackData {
  tableCode: string;
}

export const resolveDealerBlackjack = onCall<ResolveDealerBlackjackData>(
  async (request) => {
    const {tableCode} =
      (request.data ?? {}) as ResolveDealerBlackjackData;
    if (!tableCode) {
      throw new HttpsError("invalid-argument", "tableCode required");
    }
    const game = gameRef(tableCode);
    const gameSnap = await game.once("value");
    const g = gameSnap.val();
    if (!g) {
      throw new HttpsError("failed-precondition", "Game not found");
    }
    // Allow during player_actions or dealer_turn;
    // treat as no-op if already resolved
    if (g.phase === PHASES.BETWEEN_HANDS && g.dealerHasBlackjack) {
      return {ok: true};
    }
    if (g.phase !== PHASES.PLAYER_ACTIONS &&
        g.phase !== PHASES.DEALER_TURN) {
      throw new HttpsError(
        "failed-precondition",
        `Not player_actions or dealer_turn phase (current: ${g.phase})`
      );
    }

    const dealerCards = [...(g.dealerCards ?? [])] as Array<{
      rank: string;
      suit: string;
    }>;
    const dealerTotal = handTotal(dealerCards as Array<{rank: string}>);
    const dealerIsBlackjack = dealerCards.length === 2 &&
      dealerTotal === 21;

    if (!dealerIsBlackjack) {
      throw new HttpsError(
        "failed-precondition",
        "Dealer does not have blackjack"
      );
    }

    const seats = seatsRef(tableCode);
    const seatsSnap = await seats.once("value");
    const seatsData = seatsSnap.val() ?? {};
    const handResults: Record<string, Array<{
      outcome: string;
      payout: number;
      bet: number;
    }>> = {};

    for (let i = 0; i < MAX_SEATS; i++) {
      const seat = seatsData[i];
      if (!seat?.playerId || !seat.hands) continue;
      let returnAmount = 0;
      const seatResults: Array<{
        outcome: string;
        payout: number;
        bet: number;
      }> = [];
      for (const h of seat.hands ?? []) {
        const bet = h.bet ?? 0;
        const playerCards = (h.cards ?? []) as Array<{rank: string}>;
        const playerTotal = handTotal(playerCards);
        const playerIsBlackjack = playerCards.length === 2 &&
          playerTotal === 21;

        if (playerIsBlackjack) {
          // Push: player blackjack vs dealer blackjack
          returnAmount += bet;
          seatResults.push({outcome: "push", payout: bet, bet});
        } else {
          // Loss: dealer blackjack beats all non-blackjack hands
          returnAmount += 0;
          seatResults.push({outcome: "lose", payout: 0, bet});
        }
      }
      handResults[String(i)] = seatResults;
      if (returnAmount > 0) {
        const seatRef = seats.child(String(i));
        await seatRef.child("balance")
          .set((seat.balance ??
            0) + returnAmount);
      }
    }

    await game.update({
      phase: PHASES.BETWEEN_HANDS,
      dealerHoleRevealed: true,
      dealerHasBlackjack: true,
      dealerCards,
      handResults,
    });
    await updateLastActivity(tableCode);
    return {ok: true};
  }
);

// ---------- startNextHand (host only) ----------
// Host is identified by hostPlayerId stored at the table root.
// Fallback: lowest occupied seat index (for tables created before
// hostPlayerId existed).
interface StartNextHandData {
  tableCode: string;
  playerId: string;
}

export const startNextHand = onCall<StartNextHandData>(async (request) => {
  const {tableCode, playerId} =
    (request.data ?? {}) as StartNextHandData;
  if (!tableCode || !playerId) {
    throw new HttpsError(
      "invalid-argument",
      "tableCode and playerId required"
    );
  }
  const game = gameRef(tableCode);
  const seats = seatsRef(tableCode);
  const tRef = tableRef(tableCode);
  const [gameSnap, seatsSnap, hostSnap] = await Promise.all([
    game.once("value"),
    seats.once("value"),
    tRef.child("hostPlayerId").once("value"),
  ]);
  const g = gameSnap.val();
  const seatsVal = seatsSnap.val() ?? {};

  // Determine host: prefer stored hostPlayerId,
  // fall back to lowest occupied seat
  let hostPlayerId = hostSnap.val() as string | null;
  let callerIsAtTable = false;
  if (!hostPlayerId) {
    const occupiedSeatIndices: number[] = [];
    for (let i = 0; i < MAX_SEATS; i++) {
      const s = seatsVal[String(i)];
      if (s?.playerId) {
        occupiedSeatIndices.push(i);
      }
    }
    occupiedSeatIndices.sort((a, b) => a - b);
    if (occupiedSeatIndices.length > 0) {
      hostPlayerId = seatsVal[String(occupiedSeatIndices[0])]?.playerId ?? null;
    }
  }
  for (let i = 0; i < MAX_SEATS; i++) {
    if (seatsVal[String(i)]?.playerId === playerId) {
      callerIsAtTable = true;
      break;
    }
  }
  if (!callerIsAtTable) {
    throw new HttpsError("permission-denied", "Player not at this table");
  }
  if (playerId !== hostPlayerId) {
    throw new HttpsError(
      "permission-denied",
      "Only the host can start the next hand"
    );
  }

  // Allow host to reset from any phase (for recovery purposes)
  // Normal flow requires between_hands phase, but host can force reset
  if (!g) {
    throw new HttpsError(
      "failed-precondition",
      "Game state not found"
    );
  }
  if (g.phase !== PHASES.BETWEEN_HANDS) {
    logger.warn("startNextHand: Host forcing reset from phase", {
      phase: g.phase,
      tableCode,
    });
  }
  const updates: Record<string, unknown> = {};
  for (let i = 0; i < MAX_SEATS; i++) {
    const seat = seatsVal[String(i)];
    if (seat?.playerId) {
      updates[`${i}/hands`] = null;
      updates[`${i}/bonusBets`] = null;
    }
  }
  await seats.update(updates);
  await game.update({
    phase: PHASES.BETTING,
    dealerCards: [],
    currentTurn: null,
    handResults: null,
    bonusBetResults: null,
    dealerHasBlackjack: false,
  });
  await updateLastActivity(tableCode);
  return {ok: true};
});

// ---------- advanceGameAfterPlayerRemoved ----------
interface AdvanceGameAfterPlayerRemovedData {
  tableCode: string;
  removedSeatIndex: number;
}

export const advanceGameAfterPlayerRemoved =
  onCall<AdvanceGameAfterPlayerRemovedData>(async (request) => {
    const {tableCode, removedSeatIndex} =
      (request.data ?? {}) as AdvanceGameAfterPlayerRemovedData;
    if (!tableCode || typeof removedSeatIndex !== "number") {
      throw new HttpsError(
        "invalid-argument",
        "tableCode and removedSeatIndex required"
      );
    }
    const game = gameRef(tableCode);
    const seats = seatsRef(tableCode);
    const [gameSnap, seatsSnap] = await Promise.all([
      game.once("value"),
      seats.once("value"),
    ]);
    const g = gameSnap.val();
    if (!g) {
      return {ok: true}; // No game state, nothing to advance
    }

    // Only advance if we're in player_actions phase
    if (g.phase !== PHASES.PLAYER_ACTIONS) {
      return {ok: true}; // Not in player_actions, no need to advance
    }

    const turn = g.currentTurn;
    if (!turn) {
      return {ok: true}; // No current turn, nothing to advance
    }

    // If the removed player wasn't the current turn, no need to advance
    if (turn.seatIndex !== removedSeatIndex) {
      return {ok: true};
    }

    const seatsData = seatsSnap.val() ?? {};

    // Find all seats with active (not yet stood/busted) hands
    const seatKeys: number[] = [];
    for (let i = 0; i < MAX_SEATS; i++) {
      const s = seatsData[i];
      if (!s?.playerId) continue; // Skip empty seats
      const hands = s.hands != null && !Array.isArray(s.hands) ?
        Object.values(s.hands) as Array<{
          bet?: number;
          stood?: boolean;
          busted?: boolean;
          doubled?: boolean;
        }> :
        (s.hands ?? []) as Array<{
          bet?: number;
          stood?: boolean;
          busted?: boolean;
          doubled?: boolean;
        }>;
      const h0 = hands[0];
      if (h0
        ?.bet) {
        seatKeys.push(i);
      }
    }
    seatKeys.sort((a, b) => a - b);

    // Find next seat with active hands (after the removed one)
    let nextSeat: number | null = null;
    for (const seatKey of seatKeys) {
      if (seatKey === removedSeatIndex) continue; // Skip the removed seat
      const candidateSeat = seatsData[seatKey];
      const candidateHands =
        candidateSeat?.hands != null &&
        !Array.isArray(candidateSeat.hands) ?
          Object.values(candidateSeat.hands) as Array<{
            stood?: boolean;
            busted?: boolean;
            doubled?: boolean;
          }> :
          (candidateSeat?.hands ?? []) as Array<{
            stood?: boolean;
            busted?: boolean;
            doubled?: boolean;
          }>;
      const h = candidateHands[0];
      if (h && !h.stood && !h.busted && !h.doubled) {
        nextSeat = seatKey;
        break;
      }
    }

    // Check if everyone is done
    const allDone = () => {
      for (let i = 0; i < MAX_SEATS; i++) {
        const s = seatsData[i];
        if (!s?.playerId || !s.hands) continue;
        const list = (s.hands != null &&
            !Array.isArray(s.hands)) ?
          (Object.values(s.hands) as Array<{
            stood?: boolean;
            busted?: boolean;
            doubled?: boolean;
          }>) :
          (s.hands ?? []) as Array<{
            stood?: boolean;
            busted?: boolean;
            doubled?: boolean;
          }>;
        for (const hand of list) {
          if (!hand.stood && !hand.busted && !hand.doubled) {
            return false;
          }
        }
      }
      return true;
    };

    const everyoneDone = allDone();
    const gameUpdates: Record<string, unknown> = {
      currentTurn: everyoneDone ?
        null :
        (nextSeat != null ?
          {seatIndex: nextSeat, handIndex: 0} :
          null),
    };

    if (everyoneDone) {
      gameUpdates.phase = PHASES.DEALER_TURN;
    }

    await game.update(gameUpdates);
    await updateLastActivity(tableCode);
    return {ok: true};
  }
  );

// ---------- cleanupStaleTables ----------
// Scheduled function that runs daily to delete tables inactive for 24+ hours.
// Tables are considered stale if:
// - lastActivityAt is older than 24 hours, OR
// - createdAt is older than 24 hours and lastActivityAt doesn't exist
//   (legacy tables)
// Note: Deletes tables regardless of whether they have active players, since
// player removal logic may not perfectly clean up all players.
export const cleanupStaleTables = onSchedule(
  {
    schedule: "every day 03:00",
    timeZone: "America/Los_Angeles",
  },
  async () => {
    const now = Date.now();
    const staleThreshold = 24 * 60 * 60 * 1000; // 24 hours in milliseconds
    const tablesRef = db.ref(BASE_PATH);
    const tablesSnap = await tablesRef.once("value");
    const tables = tablesSnap.val() ?? {};
    const tableCodes = Object.keys(tables);
    let deletedCount = 0;
    let skippedCount = 0;

    logger.info("cleanupStaleTables: Starting cleanup", {
      totalTables: tableCodes.length,
    });

    for (const code of tableCodes) {
      const table = tables[code];
      const lastActivityAt = table?.lastActivityAt ?? null;
      const createdAt = table?.createdAt ?? null;

      // Determine the timestamp to check
      const checkTime = lastActivityAt ?? createdAt;
      if (!checkTime) {
        // Skip tables without timestamps (shouldn't happen, but be safe)
        logger.warn("cleanupStaleTables: Table missing timestamps", {code});
        skippedCount++;
        continue;
      }

      const age = now - checkTime;
      if (age >= staleThreshold) {
        // Count players for logging purposes
        const seats = table?.seats ?? {};
        let playerCount = 0;
        for (const seatKey in seats) {
          if (Object.prototype.hasOwnProperty.call(seats, seatKey)) {
            const seat = seats[seatKey];
            if (seat?.playerId) {
              playerCount++;
            }
          }
        }

        // Delete stale tables regardless of player count
        try {
          await tableRef(code).remove();
          deletedCount++;
          logger.info("cleanupStaleTables: Deleted stale table", {
            code,
            ageHours: Math.round(age / (60 * 60 * 1000)),
            playerCount,
            lastActivityAt: lastActivityAt ?
              new Date(lastActivityAt).toISOString() :
              null,
          });
        } catch (error) {
          logger.error("cleanupStaleTables: Error deleting table", {
            code,
            error: String(error),
          });
          skippedCount++;
        }
      } else {
        skippedCount++;
      }
    }

    logger.info("cleanupStaleTables: Cleanup complete", {
      deletedCount,
      skippedCount,
      totalTables: tableCodes.length,
    });
  }
);
