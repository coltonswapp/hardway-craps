# Testing Multiplayer Blackjack

Quick steps to run and test the multiplayer blackjack flow (table code **0000** by default).

## 1. Firebase (one-time)

- **Realtime Database**  
  In Firebase Console: create a Realtime Database (not Firestore) if you don’t have one. For dev you can use test rules that allow read/write; lock them down when you add auth.

- **Functions: local emulator (no deploy)**  
  In **DEBUG** builds the app points at the **local Functions emulator** (localhost:5001). You can test without deploying:
  ```bash
  cd functions
  npm run serve
  ```
  Keep that terminal running, then run the app from Xcode (Simulator or device). **Simulator**: `localhost` is your Mac, so it works. **Physical device**: replace `localhost` in code with your Mac’s IP (e.g. `192.168.1.x`) or use Simulator.

- **Functions: production (deploy)**  
  For production or if you’re not running the emulator:
  ```bash
  cd functions
  npm install
  npm run build
  firebase deploy --only functions
  ```
  Release builds use production; they never use the emulator.

## 2. Run the app

- Open the project in Xcode, pick the **hardway-craps** scheme.
- Run on **Simulator** or a **device** (same Firebase project / `GoogleService-Info.plist`).
- Go to **Settings** (gear) → **Multiplayer Blackjack**.

## 3. Single-player test

1. **Join**  
   The app joins table **0000** and creates the table/game node if needed. You should see the table and your seat.

2. **Ready**  
   Tap **Ready?** → label becomes “Ready ✓”. This calls `setReady`.

3. **Start**  
   Tap **Start** → phase moves to **betting**. The instruction becomes “Place your bet, then tap Deal” and a **Deal** button appears on the right.

4. **Bet**  
   Tap chips to place a bet on your spot (this calls `placeBet` and updates your balance).

5. **Deal**  
   Tap **Deal** → the function deals two cards to you and two to the dealer (one hidden). Cards animate from the deck to the hands. Phase moves to **player_actions** (Hit/Stand will be wired next).

## 4. Two players (optional)

- Run the app on **two simulators** (or simulator + device), same Firebase project.
- Both go to Multiplayer Blackjack; each joins table 0000 (different seats).
- Both tap **Ready?**, then either tap **Start** → phase should go to betting on both devices.

## 5. If something fails

- **“Could not join table”**  
  Check Realtime Database exists and rules allow read/write. Check Xcode console for errors.

- **“Ready failed” / “Start failed” / NOT FOUND**  
  The app can’t reach the callables. Do this:
  1. **Deploy functions** from the project root:
     ```bash
     cd functions
     npm run build
     firebase deploy --only functions
     ```
  2. Confirm the **same Firebase project** is used by the app: in Firebase Console, note your project ID; in Xcode, open `GoogleService-Info.plist` and check that `PROJECT_ID` (or the project id in the file) matches.
  3. In Firebase Console → **Functions**, you should see `setReady`, `startGame`, etc. If the list is empty, deployment didn’t target this project (run `firebase use` in the `functions` directory and redeploy).

- **Database**  
  In Firebase Console → Realtime Database you should see `mp_blackjack/table/0000` with `seats`, `game` (phase, etc.) after join and after Start.

## 6. Default table code

The app uses table code **0000** by default (no typing). To use another table later, you’d add “Create table” / “Join by code” and switch to `MultiplayerTableCodeKey.value` in `loadTableCode()`.
