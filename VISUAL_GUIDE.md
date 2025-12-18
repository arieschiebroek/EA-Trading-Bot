# EA Trading Bot v4.0 - Visual Overview

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      MT4 Account                                 │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐         │
│  │   EA #1      │  │   EA #2      │  │   EA #3      │         │
│  │  XAUUSD      │  │  EURUSD      │  │  GBPUSD      │         │
│  │ Magic:10101  │  │ Magic:10201  │  │ Magic:10301  │         │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘         │
│         │                  │                  │                  │
│         └──────────────────┼──────────────────┘                  │
│                            │                                     │
│                    ┌───────▼────────┐                           │
│                    │ Global Variables│                           │
│                    │ Coordination Hub│                           │
│                    └────────────────┘                            │
└─────────────────────────────────────────────────────────────────┘
```

## Trading Flow Diagram

### Normal Trading Scenario

```
┌─────────────┐
│  EA #1      │
│  No trades  │
│  active     │
└──────┬──────┘
       │
       ▼
┌─────────────────────────┐
│ Check: Can Open Trade?  │
│ ✓ All trades at BE: YES │ (no trades exist)
│ ✓ Trade slot free: YES  │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Claim Trade Slot        │
│ EA_TRADE_SLOT = 10101   │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Open Trade              │
│ Ticket: 12345           │
│ SL: 2580.00             │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ EA #2 & #3 Try to Trade │
│ ✗ Trade slot held       │
│ → BLOCKED               │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Trade Makes 50+ Pips    │
│ Move SL to Break-Even   │
│ SL = Entry Price        │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Release Trade Slot      │
│ EA_TRADE_SLOT = 0       │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ EA #2 Can Now Trade     │
│ Cycle Repeats           │
└─────────────────────────┘
```

### 5% Daily Loss Scenario

```
┌─────────────────────────┐
│ Multiple EAs Trading    │
│ EA #1: -2% loss         │
│ EA #2: -1.5% loss       │
│ EA #3: -1.8% loss       │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Daily Loss Check        │
│ Total: -5.3% ≥ 5%      │
│ ⚠️ TRIGGER ACTIVATED   │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Close ALL Trades        │
│ • Close EA #1 trades    │
│ • Close EA #2 trades    │
│ • Close EA #3 trades    │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Set Global Daily Stop   │
│ EA_DAILY_STOP = Now     │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Block All EAs           │
│ ALL: BlockTrading=TRUE  │
│ 📧 Send Email Alert     │
└──────┬──────────────────┘
       │
       ▼
┌─────────────────────────┐
│ Next Day 00:00          │
│ Auto Reset              │
│ Trading Resumes         │
└─────────────────────────┘
```

## Global Variables Map

```
┌─────────────────────────────────────────────────────┐
│          MT4 Global Variables Registry               │
├─────────────────────────────────────────────────────┤
│                                                      │
│  EA_TRADE_SLOT_[Account]                            │
│  ├─ Value: 0 (FREE) or MagicNumber (HELD)          │
│  └─ Purpose: Prevent simultaneous trade opening     │
│                                                      │
│  EA_DAILY_STOP_[Account]                            │
│  ├─ Value: Timestamp or Empty                       │
│  └─ Purpose: Signal 5% daily loss triggered         │
│                                                      │
│  EA_BREAK_EVEN_SIGNAL_[Account]                     │
│  ├─ Value: Timestamp of last BE event               │
│  └─ Purpose: Signal when trade reaches BE           │
│                                                      │
│  EA_MONTHLY_PROFIT_[Account]_[Date]                 │
│  ├─ Value: Current month profit %                   │
│  └─ Purpose: Track progress to 8% target            │
│                                                      │
│  EA_RISK_LOCK_[Account] (Legacy)                    │
│  ├─ Value: 0 or MagicNumber                         │
│  └─ Purpose: Backward compatibility                 │
│                                                      │
└─────────────────────────────────────────────────────┘
```

## State Machine Diagram

```
                    ┌──────────────┐
                    │   EA Init    │
                    └──────┬───────┘
                           │
                           ▼
                    ┌──────────────┐
                    │  Waiting for │
                    │  Tick Event  │
                    └──────┬───────┘
                           │
                           ▼
                ┌──────────────────────┐
                │   Check Global       │
         ┌──────│   Daily Stop?        │
         │      └──────┬───────────────┘
         │             │ No
         │ Yes         ▼
         │      ┌──────────────┐
         │      │ Check FTMO   │
         │      │ Limits?      │
         │      └──────┬───────┘
         │             │ OK
         │             ▼
         │      ┌──────────────┐
         │      │ Check Time   │
         │      │ Window?      │
         │      └──────┬───────┘
         │             │ OK
         │             ▼
         │      ┌──────────────────┐
         │      │ All Trades at BE?│
         │      └──────┬───────────┘
         │             │ Yes
         │             ▼
         │      ┌──────────────────┐
         │      │ Claim Trade Slot?│
         │      └──────┬───────────┘
         │             │ Success
         │             ▼
         │      ┌──────────────────┐
         │      │ Strategy Signal? │
         │      └──────┬───────────┘
         │             │ Yes
         │             ▼
         │      ┌──────────────────┐
         │      │   Open Trade     │
         │      └──────┬───────────┘
         │             │
         ▼             ▼
    ┌────────────────────────┐
    │  Block Trading Today   │
    │  Wait for Next Day     │
    └────────────────────────┘
```

## Multi-EA Interaction Timeline

```
Time    EA #1 (XAUUSD)          EA #2 (EURUSD)          EA #3 (GBPUSD)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
10:00   Opens Long Trade        Waiting...              Waiting...
        [Slot Claimed: 10101]   [Slot Held]             [Slot Held]
        SL: 2580.00
        Entry: 2600.00

10:30   Trade at +30 pips       Checking slot...        Checking slot...
        [Still held]            [Still blocked]          [Still blocked]

11:00   Trade at +55 pips       Checking slot...        Checking slot...
        ✓ Move SL to 2600       [Still blocked]          [Still blocked]
        [Slot Released: 0]

11:01   Monitoring trade        Opens Short Trade       Waiting...
        [At BE, safe]           [Slot Claimed: 10201]   [Slot Held]

11:30   Monitoring trade        Trade at +40 pips       Checking slot...
        [At BE, safe]           [Still held]            [Still blocked]

12:00   Monitoring trade        Trade at +62 pips       Checking slot...
        [At BE, safe]           ✓ Move SL to entry      [Still blocked]
                                [Slot Released: 0]

12:01   Monitoring trade        Monitoring trade        Opens Long Trade
        [At BE, safe]           [At BE, safe]           [Slot Claimed: 10301]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Result: All 3 trades safely at break-even, no additional risk
```

## Monthly Target Progress Visualization

```
Month: January 2025
Target: 8.00%

Week 1:  [███░░░░░░░] 1.2%  (Behind - Day 7, Expected: 1.8%)
Week 2:  [█████░░░░░] 3.5%  (On Track - Day 14, Expected: 3.7%)
Week 3:  [████████░░] 6.1%  (Ahead - Day 21, Expected: 5.6%)
Week 4:  [██████████] 8.3%  (✓ TARGET ACHIEVED - Day 28)

Status Messages:
Day 7:  "Behind monthly target - consider increasing aggression"
Day 14: "Monthly profit progress: 3.50% / Target: 8.00%"
Day 21: "Ahead of schedule - maintain current performance"
Day 28: "Monthly target achieved! 8.30% profit"
```

## Risk Management Layers

```
┌─────────────────────────────────────────────────────────┐
│                    Risk Protection                       │
├─────────────────────────────────────────────────────────┤
│                                                          │
│  Layer 1: Per-Trade Stop Loss                           │
│  └─ Each trade has individual SL                        │
│                                                          │
│  Layer 2: Break-Even Protection                         │
│  └─ SL moved to entry at 50+ pips profit                │
│                                                          │
│  Layer 3: Multi-EA Coordination                         │
│  └─ Only 1 EA trades if any not at BE                   │
│                                                          │
│  Layer 4: Daily Loss Limit (5%)                         │
│  └─ Close ALL trades at 5% daily loss                   │
│                                                          │
│  Layer 5: Absolute FTMO Drawdown (5%)                   │
│  └─ Close all & block at 5% from initial balance        │
│                                                          │
│  Layer 6: Loss Streak Limit                             │
│  └─ Stop trading after 5 consecutive losses             │
│                                                          │
│  Layer 7: Max Trades Per Day                            │
│  └─ Default: 20 trades maximum per day                  │
│                                                          │
└─────────────────────────────────────────────────────────┘
```

## Configuration Matrix

```
┌────────────────────────────────────────────────────────────────┐
│              Multi-EA Configuration Example                     │
├────────────────────────────────────────────────────────────────┤
│                                                                 │
│  Parameter              EA #1      EA #2      EA #3            │
│  ───────────────────────────────────────────────────────────── │
│  MagicNumber            10101      10201      10301            │
│  Symbol                 XAUUSD     EURUSD     GBPUSD           │
│  StrategyToRun          Turtle     MA Cross   Mean Rev         │
│  FixedLot               0.05       0.05       0.05             │
│                                                                 │
│  # MUST BE SAME:                                                │
│  GlobalTradeSlot        "EA_TRADE_SLOT_"  (all same)           │
│  GlobalDailyStop        "EA_DAILY_STOP_"  (all same)           │
│  MaxDailyLossPercent    5.0        5.0        5.0              │
│  MonthlyProfitTarget    8.0        8.0        8.0              │
│  FTMO_InitialBalance    10000      10000      10000            │
│                                                                 │
│  # CAN BE DIFFERENT:                                            │
│  BreakEvenPips          50         40         60               │
│  MaxTradesPerDay        20         15         25               │
│  TURTLE_Entry           19         -          -                │
│  MA_Fast                -          10         -                │
│  MR_Period              -          -          20               │
│                                                                 │
└────────────────────────────────────────────────────────────────┘
```

## Monitoring Dashboard (MT4 Terminal)

```
┌─────────────────────────────────────────────────────────────┐
│  What to Monitor in MT4                                      │
├─────────────────────────────────────────────────────────────┤
│                                                              │
│  1. Charts:                                                  │
│     ✓ Smiley face icon visible on each EA                   │
│     ✓ EA name shown in top-right corner                     │
│                                                              │
│  2. Terminal → Experts Tab:                                  │
│     ✓ "Multi-EA coordination enabled" message               │
│     ✓ "Trade slot claimed" / "released" logs                │
│     ✓ "Monthly profit progress: X.X%" hourly updates        │
│                                                              │
│  3. Terminal → Trade Tab:                                    │
│     ✓ Open trades with correct SL/TP                        │
│     ✓ Monitor when SL moves to break-even                   │
│                                                              │
│  4. Tools → Global Variables:                                │
│     ✓ EA_TRADE_SLOT_[Account] = 0 or MagicNumber           │
│     ✓ EA_DAILY_STOP_[Account] should NOT exist normally     │
│     ✓ EA_MONTHLY_PROFIT_[Account]_[Date] shows % progress   │
│                                                              │
│  5. Inbox (if email configured):                             │
│     ✓ Alerts when daily loss triggered                      │
│     ✓ Alerts when FTMO limit hit                            │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Common Scenarios Quick Reference

```
┌─────────────────────────────────────────────────────────────┐
│  Scenario                          Expected Behavior         │
├─────────────────────────────────────────────────────────────┤
│  First trade of day                Slot claimed, trade opens │
│  Second EA tries to trade          BLOCKED until BE          │
│  First trade reaches +50 pips      SL → BE, slot released   │
│  Second EA tries again             Slot claimed, trade opens │
│  Total loss hits -5% for day       ALL trades close, STOP    │
│  Next day starts                   Auto reset, trading OK    │
│  Month changes                     Reset monthly tracking    │
│  Trade slot held too long          Check if trade is at BE   │
│  EA stops trading suddenly         Check daily stop flag     │
└─────────────────────────────────────────────────────────────┘
```

---

This visual guide provides a comprehensive overview of how the EA Trading Bot v4.0 system works with multiple EAs coordinating on a single account.
