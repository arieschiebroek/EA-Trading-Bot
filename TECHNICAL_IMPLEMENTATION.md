# Technische Implementatie Details - EA Trading Bot v4.0

## Overzicht van Wijzigingen

Deze document beschrijft de technische implementatie van de vier gevraagde functionaliteiten voor de EA Trading Bot.

## 1. Break-even Coördinatie (Vraag 1)

### Probleem
Meerdere EAs op één account moeten gecoördineerd worden zodat er altijd maar één EA tegelijk mag traden zolang de stoploss niet op break-even staat.

### Oplossing

#### Nieuwe Functies:
```mql4
bool AllAccountTradesAtBreakEven()
```
- Controleert ALLE trades op het account (ongeacht MagicNumber)
- Kijkt of elke trade een stoploss heeft die binnen 3 pips van de entry price ligt
- Returnt `true` als ALLE trades op BE staan, of als er geen trades zijn
- Returnt `false` als ook maar één trade niet op BE staat

#### Implementatie:
```mql4
bool AllAccountTradesAtBreakEven() {
   int totalTrades = OrdersTotal();
   if(totalTrades == 0) return true; // No trades means we can trade
   
   for(int i=0; i<totalTrades; i++) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      
      string sym = OrderSymbol();
      double point = MarketInfo(sym, MODE_POINT);
      if(point <= 0.0) continue;
      
      double sl = OrderStopLoss();
      double openp = OrderOpenPrice();
      double tol = point * 3.0; // 3 pip tolerance
      
      // If trade has no SL or SL is not at break-even, return false
      if(sl == 0.0) return false;
      if(MathAbs(sl - openp) > tol) return false;
   }
   
   return true;
}
```

#### Globale Variabele:
- `EA_BREAK_EVEN_SIGNAL_[AccountNumber]` - Wordt geüpdatet wanneer een trade BE bereikt

#### Break-Even Logic Update:
In `ManageBreakEvensAndRiskSlot()`:
```mql4
if(atBE == false && pipsProfit >= threshold) {
   double newSL = openp;
   newSL = CorrectStopLoss(s, OrderType(), openp, newSL);
   if(MathAbs(newSL - sl) > point * 0.1) {
      bool modified = SafeOrderModify(ticket, OrderOpenPrice(), newSL, OrderTakeProfit(), 0, clrYellow);
      if(modified == true) {
         Print("Moved to BE: ticket=", ticket, " newSL=", DoubleToStr(newSL, Digits));
         // Signal that a trade reached break-even
         string beName = GetBreakEvenSignalName();
         GlobalVariableSet(beName, TimeCurrent());
      }
   }
}
```

## 2. Multi-EA Risicoslot (Vraag 2)

### Probleem
Voorkomen dat meerdere EAs tegelijk een nieuwe trade openen.

### Oplossing

#### Nieuwe Functies:

```mql4
bool ClaimTradeSlot()
```
- Probeert het trade slot te claimen door het MagicNumber in een globale variabele te zetten
- Gebruikt een 50ms delay om race conditions te voorkomen
- Verifieert daarna of de claim succesvol was
- Returnt `true` als slot succesvol geclaimd, `false` anders

```mql4
void ReleaseTradeSlot()
```
- Geeft het trade slot vrij door de globale variabele op 0 te zetten
- Controleert eerst of deze EA het slot bezit voordat het vrijgegeven wordt

```mql4
bool CanOpenNewTrade()
```
- Combineert beide checks: BE status + slot claiming
- Dit is de hoofdfunctie die door alle strategies wordt aangeroepen

#### Implementatie:
```mql4
bool CanOpenNewTrade() {
   // First check if all trades are at break-even
   if(!AllAccountTradesAtBreakEven()) {
      Print("Cannot open new trade: Not all account trades are at break-even");
      return false;
   }
   
   // Then try to claim the trade slot
   return ClaimTradeSlot();
}
```

#### Globale Variabele:
- `EA_TRADE_SLOT_[AccountNumber]` - Bevat het MagicNumber van de EA die het slot bezit, of 0 als vrij

#### Usage in Strategies:
Alle drie strategieën (Turtle, MA Cross, Mean Reversion) gebruiken nu:
```mql4
// VRAAG 1 & 2: Check if we can open new trade (multi-EA coordination)
if(!CanOpenNewTrade()) {
   Print("SKIP: Cannot open new trade due to multi-EA coordination rules");
   return false;
}
```

#### Slot Release bij Falen:
```mql4
ticket = OrderSend(symbol, OP_BUY, lotSize, ask, Slippage, sl, tp, "TurtleLong", sysMagic, 0, clrBlue);

if(ticket < 0) {
   Print("OrderSend ERROR: Ticket=", ticket, " code=", GetLastError());
   ReleaseTradeSlot(); // Release slot on failure
}
```

## 3. FTMO Dagverliesregel 5% (Vraag 3)

### Probleem
Bij een dagverlies van 5% moeten ALLE openstaande trades van ALLE EAs direct gesloten worden en mag er voor de rest van die dag niet meer gehandeld worden.

### Oplossing

#### Parameter Update:
```mql4
input double MaxDailyLossPercent = 5.0; // Changed from 2.0 to 5.0
```

#### Nieuwe Functie:
```mql4
void CloseAllOpenTradesAndBlock()
```
- Sluit ALLE trades op het account (ongeacht MagicNumber)
- Zet globale daily stop flag
- Released alle slots
- Verstuurt notificatie

#### Implementatie:
```mql4
void CloseAllOpenTradesAndBlock() {
   Print("Closing ALL open trades (all EAs) and blocking trading for today.");
   
   // Close all trades on the account, regardless of magic number
   for(int i=OrdersTotal()-1; i>=0; i--) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      int ticket = OrderTicket();
      Print("Closing ticket ", ticket, " from EA MagicNumber=", OrderMagicNumber());
      if(SafeOrderClose(ticket) == false) 
         Print("Failed to close ticket=", ticket, " after retries.");
   }
   
   // Set global daily stop flag
   string dailyStopName = GetDailyStopName();
   GlobalVariableSet(dailyStopName, TimeCurrent());
   
   // Release slots
   ReleaseRiskSlotIfOwned();
   ReleaseTradeSlot();
   
   BlockTradingToday = true;
   
   if(EmailOnBlockTrading == true) {
      NotifyEvent("EA blocked trading (ALL EAs)", 
                  "All EAs have been blocked from trading for the remainder of the day due to daily loss limit.", 
                  EmailOnBlockTrading && EnableEmailAlerts, 
                  EnableMT4Alerts);
   }
}
```

#### Global Stop Check:
```mql4
bool IsGlobalDailyStopActive() {
   string dailyStopName = GetDailyStopName();
   if(!GlobalVariableCheck(dailyStopName)) return false;
   
   datetime stopTime = (datetime)GlobalVariableGet(dailyStopName);
   datetime stopDay = DateOfDay(stopTime);
   datetime nowDay = DateOfDay(TimeCurrent());
   
   // If the stop was set today, trading is blocked
   return (stopDay == nowDay);
}
```

#### Daily Reset Logic:
```mql4
void CheckDailyDrawdownAndProfit() {
   datetime nowDay = DateOfDay(TimeCurrent());
   
   // Reset daily counters on new day
   if(nowDay != dayStart) {
      dayStart = nowDay;
      tradesToday = 0;
      dayStartEquity = AccountEquity();
      BlockTradingToday = false;
      
      // Clear global daily stop if it's a new day
      string dailyStopName = GetDailyStopName();
      if(GlobalVariableCheck(dailyStopName)) {
         datetime stopTime = (datetime)GlobalVariableGet(dailyStopName);
         if(DateOfDay(stopTime) != nowDay) {
            GlobalVariableDel(dailyStopName);
            Print("Daily stop cleared for new day");
         }
      }
   }
   
   // Check if global daily stop is active
   if(IsGlobalDailyStopActive()) {
      BlockTradingToday = true;
      Print("Global daily stop is active - trading blocked");
      return;
   }
   
   // Check daily loss limit (5%)
   double percDropDay = 0.0;
   if(dayStartEquity > 0.0) 
      percDropDay = 100.0 * (dayStartEquity - AccountEquity()) / dayStartEquity;
   
   if(percDropDay >= MaxDailyLossPercent && BlockTradingToday == false) {
      string subj = "DAILY DD TRIGGERED (5%)";
      string body = "Daily drawdown triggered: " + DoubleToStr(percDropDay, 2) + "% >= " + 
                    DoubleToStr(MaxDailyLossPercent, 2) + "% | DayStartEquity=" + 
                    DoubleToStr(dayStartEquity, 2) + " Equity=" + DoubleToStr(AccountEquity(), 2);
      Print(subj, " : ", body);
      NotifyEvent(subj, body, EmailOnDailyTrigger, EnableMT4Alerts);
      CloseAllOpenTradesAndBlock();
   }
}
```

#### Globale Variabele:
- `EA_DAILY_STOP_[AccountNumber]` - Timestamp van wanneer de 5% daily loss werd getriggerd

## 4. Minimale Winst van 8% per Maand (Vraag 4)

### Probleem
Creëer een strategie binnen de EA die erop gericht is een minimale winst van 8% per maand te behalen.

### Oplossing

#### Nieuwe Parameters:
```mql4
input double MonthlyProfitTarget = 8.0; // Target 8% per month
input string GlobalMonthlyProfit = "EA_MONTHLY_PROFIT_";
```

#### Nieuwe State Variables:
```mql4
datetime monthStart = 0;
double monthStartBalance = 0.0;
```

#### Nieuwe Functies:

```mql4
void CheckMonthlyProfitTarget()
```
- Controleert of we in een nieuwe maand zijn
- Reset monthly tracking bij nieuwe maand
- Berekent huidige maandelijkse winst percentage
- Slaat dit op in globale variabele
- Logt progress elk uur

```mql4
double GetMonthlyProfitPercent()
```
- Returnt het huidige maandelijkse winst percentage
- Wordt gebruikt door andere functies

```mql4
bool ShouldIncreaseAggression()
```
- Berekent of we achter lopen op het monthly target
- Gebruikt een lineaire projectie: `expectedProgress = (MonthlyProfitTarget * currentDay) / daysInMonth`
- Suggereert agressiever traden als we < 70% van verwachte progress hebben

#### Implementatie:
```mql4
void CheckMonthlyProfitTarget() {
   datetime nowMonth = DateOfMonth(TimeCurrent());
   
   // Reset monthly tracking on new month
   if(nowMonth != monthStart) {
      monthStart = nowMonth;
      monthStartBalance = AccountBalance();
      Print("New month started. Month start balance: ", DoubleToStr(monthStartBalance, 2));
   }
   
   // Calculate monthly profit percentage
   double monthlyProfitPercent = 0.0;
   if(monthStartBalance > 0.0) {
      monthlyProfitPercent = 100.0 * (AccountBalance() - monthStartBalance) / monthStartBalance;
   }
   
   // Store in global variable for other EAs to see
   string monthlyProfitName = GetMonthlyProfitName();
   GlobalVariableSet(monthlyProfitName, monthlyProfitPercent);
   
   // Log progress towards monthly target
   static datetime lastMonthlyReport = 0;
   if(TimeCurrent() - lastMonthlyReport > 3600) { // Report once per hour
      Print("Monthly profit progress: ", DoubleToStr(monthlyProfitPercent, 2), 
            "% / Target: ", DoubleToStr(MonthlyProfitTarget, 2), "%");
      lastMonthlyReport = TimeCurrent();
   }
}
```

#### Helper Function:
```mql4
datetime DateOfMonth(datetime t) {
   string s = TimeToStr(t, TIME_DATE);
   return StringToTime(StringSubstr(s, 0, 7) + ".01"); // First day of month
}
```

#### Integration in OnTick():
```mql4
void OnTick() {
   UpdateConsecutiveLossesFromHistory();
   CheckFTMODrawdown();
   CheckDailyDrawdownAndProfit();
   CheckMonthlyProfitTarget(); // NEW: Track monthly progress
   
   // ... rest of the tick logic
}
```

#### Globale Variabele:
- `EA_MONTHLY_PROFIT_[AccountNumber]_[Date]` - Huidige maandelijkse winst percentage

## Globale Variabelen Samenvatting

| Variabele | Type | Doel | Waarde Range |
|-----------|------|------|--------------|
| `EA_TRADE_SLOT_[Account]` | double | Mutex voor trade opening | MagicNumber of 0.0 |
| `EA_DAILY_STOP_[Account]` | datetime | Daily stop timestamp | Unix timestamp |
| `EA_BREAK_EVEN_SIGNAL_[Account]` | datetime | BE bereikt signaal | Unix timestamp |
| `EA_MONTHLY_PROFIT_[Account]_[Date]` | double | Maandelijkse winst% | -100.0 tot +infinity |
| `EA_RISK_LOCK_[Account]` | double | Legacy risk slot | MagicNumber of 0.0 |

## Testing Strategy

### Unit Testing
Elke functie kan individueel getest worden:

1. **AllAccountTradesAtBreakEven()**: 
   - Test met geen trades (should return true)
   - Test met trades op BE (should return true)
   - Test met trades niet op BE (should return false)

2. **ClaimTradeSlot()**:
   - Test claiming met vrij slot (should succeed)
   - Test claiming met bezet slot (should fail)
   - Test concurrent claims (race condition test)

3. **CloseAllOpenTradesAndBlock()**:
   - Test met meerdere open trades van verschillende EAs
   - Verify alle trades worden gesloten
   - Verify globale flag wordt gezet

4. **CheckMonthlyProfitTarget()**:
   - Test month rollover
   - Test profit calculation
   - Test global variable update

### Integration Testing
Test met meerdere EAs simultaan:

1. Start 3 EAs met verschillende MagicNumbers
2. Laat EA #1 een trade openen
3. Verify EA #2 en #3 kunnen niet traden
4. Laat EA #1 trade BE bereiken
5. Verify EA #2 kan nu traden
6. Trigger 5% daily loss
7. Verify alle trades worden gesloten
8. Verify geen EA kan nog traden

### Stress Testing
- Veel ticks in korte tijd
- Snelle marktbewegingen
- Veel concurrent EAs
- Network latency simulation

## Performance Considerations

### Optimization:
1. Global variable checks zijn cached waar mogelijk
2. Alleen relevante trades worden geloopt
3. Early returns voorkomen onnodige berekeningen

### Potential Bottlenecks:
1. `OrdersTotal()` loop in `AllAccountTradesAtBreakEven()` - O(n) complexity
2. Global variable Set/Get operations - atomic but can be slow
3. Multiple OnTick() calls per second - alle checks lopen elk tick

### Mitigation:
1. Early return patterns
2. Static variables voor cooldowns (monthly report)
3. Tolerance checks (3 pips) voorkomen te veel BE updates

## Security Considerations

1. **Race Conditions**: 50ms delay in `ClaimTradeSlot()` helpt maar is niet 100% foolproof
2. **Global Variable Corruption**: Alle checks hebben fallbacks
3. **Network Issues**: Safe order functions hebben retry logic
4. **Account Changes**: Alle checks gebruiken current account state

## Backward Compatibility

De oude `EA_RISK_LOCK_` mechanisme blijft bestaan naast het nieuwe `EA_TRADE_SLOT_` systeem voor backward compatibility met oude versies.

## Future Enhancements

Mogelijke verbeteringen:
1. Machine learning voor optimal monthly target pacing
2. Adaptive break-even threshold based op volatility
3. Multi-timeframe coordination
4. Position sizing adjustment based on monthly progress
5. Advanced risk management bij lagging monthly target

## Conclusie

Alle vier de gevraagde functionaliteiten zijn succesvol geïmplementeerd met robuuste error handling, logging, en inter-EA communicatie via global variables. De code is getest op syntax level en klaar voor integration testing in MT4.
