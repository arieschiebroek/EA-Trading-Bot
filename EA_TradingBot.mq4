//+------------------------------------------------------------------+
//| EA: Strategie Switch met FTMO en Multi-EA BreakEven coordination (v4.0)
//| Full implementation with multi-EA coordination and 8% monthly target
//+------------------------------------------------------------------+
#property strict
#property version "4.00"
#property description "Multi-strategy EA with FTMO compliance and multi-EA coordination"

//+------------------------------------------------------------------+
enum StrategyType { STRAT_TURTLE=0, STRAT_MACROSS=1, STRAT_MEANREVERT=2 };

input StrategyType StrategyToRun = STRAT_TURTLE; // Kies strategie
input string Symbol = "XAUUSD"; // Test-instrument

// Position sizing: fixedlot default for FTMO comfort
input bool UseFixedLot = true;
input double FixedLot = 0.05;
input double Risk_Percent_PerTrade = 0.25;

// Fallback behavior when calc lot < minLot
input bool UseMinLotWhenTooSmall = true;

// Exposure / safety
input int MaxTradesPerDay = 20;
input int MaxConcurrentTrades = 1;
input int LossStreakLimit = 5;
input int Slippage = 20;
input int MagicNumber = 10101;

// Turtle tuning
input int TURTLE_Entry = 19;
input int TURTLE_Exit = 10;
input double TURTLE_ADX_Min = 1.0;
input double TURTLE_ATR_Min = 1.2;
input double Turtle_TP_Factor = 2.2;

// MA Cross
input int MA_Fast = 10;
input int MA_Slow = 50;
input double MA_ADX_Min = 1.2;

// MeanReversion
input int MR_Period = 20;
input double MR_Dev = 1.2;
input double MR_ATR_Max = 1.2;

// FTMO / trading window
input double FTMO_InitialBalance = 10000.0;
input double MaxDrawdownPercent = 5.0; // absolute account drawdown (FTMO)
input double MaxDailyLossPercent = 5.0; // dagelijkse limiet (VRAAG 3: changed from 2% to 5%)
input int TradingStartHour = 0;
input int TradingEndHour = 24;

// Break-even & multi-EA coordination
input int BreakEvenPips = 50;
input double BE_ATR_Multiplier = 2.0;
input string GlobalRiskPrefix = "EA_RISK_LOCK_";

// NEW: Multi-EA coordination variables (VRAAG 1 & 2)
input string GlobalBreakEvenSignal = "EA_BREAK_EVEN_SIGNAL_";
input string GlobalTradeSlot = "EA_TRADE_SLOT_";
input string GlobalDailyStop = "EA_DAILY_STOP_";

// NEW: Monthly profit target (VRAAG 4)
input double MonthlyProfitTarget = 8.0; // Target 8% per month
input string GlobalMonthlyProfit = "EA_MONTHLY_PROFIT_";

// Retry settings
input int CloseRetryCount = 3;
input int CloseRetryDelayMs = 250;

// ----------------- Notification settings (v3.3) -----------------
input bool EnableMT4Alerts = true; // shows MT4 Alert(...) popups
input bool EnableEmailAlerts = true; // uses MT4 SendMail (must be configured in Tools->Options->Email)
input bool EmailOnFTMOTigger = true; // send email when FTMO absolute drawdown triggers
input bool EmailOnDailyTrigger = true; // send email when daily drawdown triggers
input bool EmailOnBlockTrading = true; // send email when EA blocks trading for the day due to other reasons
input int NotificationCooldownSec = 300; // don't send duplicate notifications within this period (seconds)

// ----------------- State -----------------
datetime dayStart = 0;
int tradesToday = 0;
bool BlockTradingToday = false;
double dayStartEquity = 0.0;
int ConsecutiveLosses = 0;
datetime LastProcessedHistoryTime = 0;
datetime lastNotificationTime = 0;

// NEW: Monthly tracking
datetime monthStart = 0;
double monthStartBalance = 0.0;

//+------------------------------------------------------------------+
//| Utility functions                                                 |
//+------------------------------------------------------------------+
bool IsSymbolValid(string symbol) {
   for(int i=0; i<SymbolsTotal(true); i++)
      if(SymbolName(i,true) == symbol) return true;
   return false;
}

double MinStopDistance(string symbol) {
   double stopLevel = MarketInfo(symbol, MODE_STOPLEVEL) * MarketInfo(symbol, MODE_POINT);
   double spread = MarketInfo(symbol, MODE_SPREAD) * MarketInfo(symbol, MODE_POINT);
   return stopLevel + spread;
}

double minLot(string symbol) { return MarketInfo(symbol, MODE_MINLOT); }
double maxLot(string symbol) { return MarketInfo(symbol, MODE_MAXLOT); }

double CorrectStopLoss(string symbol, int type, double entry, double candidateSL) {
   double minDist = MinStopDistance(symbol);
   if(type == OP_BUY && candidateSL > entry - minDist) return entry - minDist;
   if(type == OP_SELL && candidateSL < entry + minDist) return entry + minDist;
   return candidateSL;
}

double CorrectTakeProfit(string symbol, int type, double entry, double candidateTP) {
   double minDist = MinStopDistance(symbol);
   if(type == OP_BUY && candidateTP < entry + minDist) return entry + minDist;
   if(type == OP_SELL && candidateTP > entry - minDist) return entry - minDist;
   return candidateTP;
}

// Notification helper (MT4 Alert + SendMail with cooldown)
void NotifyEvent(string subject, string body, bool sendEmail, bool showAlert) {
   datetime nowt = TimeCurrent();
   if((nowt - lastNotificationTime) < NotificationCooldownSec) {
      Print("NotifyEvent suppressed due to cooldown: ", subject);
      return;
   }
   lastNotificationTime = nowt;
   string full = subject + " | " + body;
   Print(full);
   if(showAlert == true && EnableMT4Alerts == true) Alert(full);
   if(sendEmail == true && EnableEmailAlerts == true) {
      bool mailOk = SendMail(subject, body + CharToStr(10) + "Time: " + TimeToStr(nowt, TIME_DATE|TIME_SECONDS) + CharToStr(10) + "Account: " + IntegerToString(AccountNumber()));
      if(mailOk == true) Print("Notification email sent: ", subject);
      else Print("Failed to send notification email, err=", GetLastError());
   }
}

// Safe close with retries
bool SafeOrderClose(int ticket) {
   for(int attempt=0; attempt<CloseRetryCount; attempt++) {
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return true;
      double lots = OrderLots();
      double price = (OrderType()==OP_BUY) ? Bid : Ask;
      RefreshRates();
      bool closed = OrderClose(ticket, lots, price, Slippage, clrRed);
      if(closed) return true;
      int err = GetLastError();
      Print("SafeOrderClose attempt ", attempt+1, " failed for ticket=", ticket, " err=", err);
      Sleep(CloseRetryDelayMs);
      RefreshRates();
   }
   if(OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) {
      bool finalClosed = OrderClose(ticket, OrderLots(), (OrderType()==OP_BUY?Bid:Ask), Slippage, clrRed);
      if(finalClosed) return true;
      Print("SafeOrderClose final attempt failed for ticket=", ticket, " err=", GetLastError());
      return false;
   }
   return true;
}

// Safe modify with retries
bool SafeOrderModify(int ticket, double price, double sl, double tp, datetime expiration, color arrow_color) {
   for(int attempt=0; attempt<CloseRetryCount; attempt++) {
      if(!OrderSelect(ticket, SELECT_BY_TICKET, MODE_TRADES)) return false;
      bool mod = OrderModify(ticket, price, sl, tp, expiration, arrow_color);
      if(mod) return true;
      Print("SafeOrderModify attempt ", attempt+1, " failed ticket=", ticket, " err=", GetLastError());
      Sleep(CloseRetryDelayMs);
      RefreshRates();
   }
   return false;
}

datetime DateOfDay(datetime t) {
   string s = TimeToStr(t, TIME_DATE);
   return StringToTime(s);
}

datetime DateOfMonth(datetime t) {
   string s = TimeToStr(t, TIME_DATE);
   return StringToTime(StringSubstr(s, 0, 7) + ".01"); // First day of month
}

double ATR_RatioVal(string symbol, int tf) {
   double curr = iATR(symbol, tf, 14, 0);
   double ref = iATR(symbol, tf, 105, 0);
   if(ref <= 0.0) return 1.0;
   return curr / ref;
}

double ADX_RatioVal(string symbol, int tf) {
   double curr = iADX(symbol, tf, 14, PRICE_CLOSE, MODE_MAIN, 0);
   double sum = 0.0; 
   int count = 0;
   for(int i=0; i<44; i++) {
      double adx = iADX(symbol, tf, 14, PRICE_CLOSE, MODE_MAIN, i);
      if(adx > 0.0) {
         sum += adx;
         count++;
      }
   }
   double avg = (count > 0) ? (sum / count) : 1.0;
   if(avg <= 0.0) return 1.0;
   return curr / avg;
}

bool IsTradingTime() {
   int hour = TimeHour(TimeCurrent());
   return (hour >= TradingStartHour && hour < TradingEndHour);
}

string GlobalRiskName() {
   return GlobalRiskPrefix + IntegerToString(AccountNumber());
}

//+------------------------------------------------------------------+
//| NEW: Multi-EA Coordination Functions (VRAAG 1 & 2)              |
//+------------------------------------------------------------------+

// Get global variable name for break-even signal (account-wide)
string GetBreakEvenSignalName() {
   return GlobalBreakEvenSignal + IntegerToString(AccountNumber());
}

// Get global variable name for trade slot (account-wide)
string GetTradeSlotName() {
   return GlobalTradeSlot + IntegerToString(AccountNumber());
}

// Get global variable name for daily stop (account-wide)
string GetDailyStopName() {
   return GlobalDailyStop + IntegerToString(AccountNumber());
}

// Get global variable name for monthly profit tracking
string GetMonthlyProfitName() {
   return GlobalMonthlyProfit + IntegerToString(AccountNumber()) + "_" + TimeToStr(monthStart, TIME_DATE);
}

// VRAAG 1: Check if ALL trades across ALL EAs are at break-even
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
      double tol = point * 3.0;
      
      // If trade has no SL or SL is not at break-even, return false
      if(sl == 0.0) return false;
      if(MathAbs(sl - openp) > tol) return false;
   }
   
   return true;
}

// VRAAG 2: Try to claim the trade slot (mutex-like mechanism)
bool ClaimTradeSlot() {
   string slotName = GetTradeSlotName();
   
   // Check if slot is free
   if(GlobalVariableCheck(slotName)) {
      double currentHolder = GlobalVariableGet(slotName);
      if(currentHolder > 0.5 && MathAbs(currentHolder - (double)MagicNumber) > 0.5) {
         // Slot is held by another EA
         Print("Trade slot is held by EA with MagicNumber=", (int)currentHolder);
         return false;
      }
   }
   
   // Try to claim the slot
   GlobalVariableSet(slotName, (double)MagicNumber);
   Sleep(50); // Small delay to avoid race conditions
   
   // Verify we own it
   if(GlobalVariableCheck(slotName)) {
      double holder = GlobalVariableGet(slotName);
      if(MathAbs(holder - (double)MagicNumber) < 0.5) {
         Print("Trade slot claimed successfully by MagicNumber=", MagicNumber);
         return true;
      }
   }
   
   return false;
}

// Release the trade slot
void ReleaseTradeSlot() {
   string slotName = GetTradeSlotName();
   if(GlobalVariableCheck(slotName)) {
      double holder = GlobalVariableGet(slotName);
      if(MathAbs(holder - (double)MagicNumber) < 0.5) {
         GlobalVariableSet(slotName, 0.0);
         Print("Trade slot released by MagicNumber=", MagicNumber);
      }
   }
}

// Check if we can open a new trade (VRAAG 1 & 2 combined)
bool CanOpenNewTrade() {
   // First check if all trades are at break-even
   if(!AllAccountTradesAtBreakEven()) {
      Print("Cannot open new trade: Not all account trades are at break-even");
      return false;
   }
   
   // Then try to claim the trade slot
   return ClaimTradeSlot();
}

//+------------------------------------------------------------------+
//| Legacy Risk Slot Functions (kept for compatibility)              |
//+------------------------------------------------------------------+
bool IsRiskSlotFree() {
   string gname = GlobalRiskName();
   if(GlobalVariableCheck(gname) == false) return true;
   double v = (double)GlobalVariableGet(gname);
   if(v <= 0.5) return true;
   return false;
}

bool IsRiskSlotOwnedByThisEA() {
   string gname = GlobalRiskName();
   if(GlobalVariableCheck(gname) == false) return false;
   double v = (double)GlobalVariableGet(gname);
   if(MathAbs(v - (double)MagicNumber) < 0.5) return true;
   return false;
}

bool ClaimRiskSlot() {
   string gname = GlobalRiskName();
   if(!IsRiskSlotFree()) return false;
   bool ok = GlobalVariableSet(gname, (double)MagicNumber);
   if(ok && IsRiskSlotOwnedByThisEA()) return true;
   return false;
}

bool ReleaseRiskSlotIfOwned() {
   string gname = GlobalRiskName();
   if(GlobalVariableCheck(gname) == false) return true;
   bool owned = IsRiskSlotOwnedByThisEA();
   if(owned == true) {
      bool setOk = GlobalVariableSet(gname, 0.0);
      if(setOk == true) return true;
      else return false;
   }
   return true;
}

// Count open trades for given sysMagic
int OpenTradesCountForMagic(int sysMagic) {
   int cnt = 0;
   for(int i=0; i<OrdersTotal(); i++) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() == sysMagic) cnt++;
   }
   return cnt;
}

//+------------------------------------------------------------------+
//| History processing for consecutive losses                        |
//+------------------------------------------------------------------+
void UpdateConsecutiveLossesFromHistory() {
   int total = OrdersHistoryTotal();
   if(total <= 0) return;
   
   for(int i=0; i<total; i++) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_HISTORY)) continue;
      datetime closeTime = OrderCloseTime();
      if(closeTime <= LastProcessedHistoryTime) continue;
      
      double profit = OrderProfit();
      if(profit > 0.0) ConsecutiveLosses = 0;
      else ConsecutiveLosses++;
      
      if(closeTime > LastProcessedHistoryTime) LastProcessedHistoryTime = closeTime;
      Print("History processed: ticket=", OrderTicket(), " profit=", DoubleToStr(profit, 2), " ConsecutiveLosses=", ConsecutiveLosses);
   }
}

//+------------------------------------------------------------------+
//| Lot sizing                                                        |
//+------------------------------------------------------------------+
double CalcLotSize(string symbol, double riskPercent, double stopLossPips) {
   double accountRisk = AccountBalance() * riskPercent / 100.0;
   double tickValue = MarketInfo(symbol, MODE_TICKVALUE);
   if(tickValue <= 0.0 || stopLossPips <= 0.0) return 0.0;
   double lot = accountRisk / (stopLossPips * tickValue);
   lot = NormalizeDouble(lot, 2);
   return lot;
}

// Compute BE threshold in pips
double ComputeBEThresholdPips(string symbol) {
   double atr = iATR(symbol, PERIOD_H1, 14, 0);
   double point = MarketInfo(symbol, MODE_POINT);
   if(point <= 0.0) return (double)BreakEvenPips;
   double atrPips = atr / point;
   double threshold = MathMax((double)BreakEvenPips, BE_ATR_Multiplier * atrPips);
   return threshold;
}

// Move orders to BE when profit >= threshold
void ManageBreakEvensAndRiskSlot() {
   RefreshRates();
   double threshold = ComputeBEThresholdPips(Symbol);
   
   for(int i=OrdersTotal()-1; i>=0; i--) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      
      string s = OrderSymbol();
      double point = MarketInfo(s, MODE_POINT);
      if(point <= 0.0) continue;
      
      int ticket = OrderTicket();
      double pipsProfit = 0.0;
      
      if(OrderType() == OP_BUY) 
         pipsProfit = (Bid - OrderOpenPrice()) / point;
      else 
         pipsProfit = (OrderOpenPrice() - Ask) / point;
      
      double openp = OrderOpenPrice();
      double sl = OrderStopLoss();
      bool atBE = (sl != 0.0 && MathAbs(sl - openp) <= point * 3.0);
      
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
   }
   
   // Release legacy risk slot if all our trades are at BE
   if(AllOurTradesAtBreakEven() == true) {
      if(IsRiskSlotOwnedByThisEA() == true) {
         ReleaseRiskSlotIfOwned();
         Print("Risk slot released by EA Magic=", MagicNumber);
      }
      // Also release trade slot
      ReleaseTradeSlot();
   }
}

// Check whether all our trades have SL approx == open price (break-even)
bool AllOurTradesAtBreakEven() {
   double tol = MarketInfo(Symbol, MODE_POINT) * 3.0;
   for(int i=OrdersTotal()-1; i>=0; i--) {
      if(!OrderSelect(i, SELECT_BY_POS, MODE_TRADES)) continue;
      if(OrderMagicNumber() != MagicNumber) continue;
      
      double sl = OrderStopLoss();
      double openp = OrderOpenPrice();
      if(sl == 0.0) return false;
      if(MathAbs(sl - openp) > tol) return false;
   }
   return true;
}

//+------------------------------------------------------------------+
//| FTMO enforcement & daily checks (ENHANCED FOR VRAAG 3)          |
//+------------------------------------------------------------------+

// VRAAG 3: Close ALL trades from ALL EAs and block trading globally
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

// Check if trading is blocked globally
bool IsGlobalDailyStopActive() {
   string dailyStopName = GetDailyStopName();
   if(!GlobalVariableCheck(dailyStopName)) return false;
   
   datetime stopTime = (datetime)GlobalVariableGet(dailyStopName);
   datetime stopDay = DateOfDay(stopTime);
   datetime nowDay = DateOfDay(TimeCurrent());
   
   // If the stop was set today, trading is blocked
   return (stopDay == nowDay);
}

void CheckFTMODrawdown() {
   double percDrop = 0.0;
   if(FTMO_InitialBalance > 0.0) 
      percDrop = 100.0 * (FTMO_InitialBalance - AccountEquity()) / FTMO_InitialBalance;
   
   if(percDrop >= MaxDrawdownPercent && BlockTradingToday == false) {
      string subj = "FTMO ABSOLUTE DD TRIGGERED";
      string body = "Absolute drawdown triggered: " + DoubleToStr(percDrop, 2) + "% >= " + 
                    DoubleToStr(MaxDrawdownPercent, 2) + "% | Equity=" + 
                    DoubleToStr(AccountEquity(), 2) + " Balance=" + DoubleToStr(AccountBalance(), 2);
      Print(subj, " : ", body);
      NotifyEvent(subj, body, EmailOnFTMOTigger, EnableMT4Alerts);
      CloseAllOpenTradesAndBlock();
   }
}

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
   
   // VRAAG 3: Check daily loss limit (5%)
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

//+------------------------------------------------------------------+
//| NEW: Monthly Profit Tracking (VRAAG 4)                          |
//+------------------------------------------------------------------+

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

// Get current monthly profit percentage
double GetMonthlyProfitPercent() {
   if(monthStartBalance <= 0.0) return 0.0;
   return 100.0 * (AccountBalance() - monthStartBalance) / monthStartBalance;
}

// Adjust trading aggressiveness based on monthly progress (VRAAG 4)
bool ShouldIncreaseAggression() {
   double currentProfit = GetMonthlyProfitPercent();
   
   // Get days in current month
   int daysInMonth = 30; // Simplified
   int currentDay = TimeDayOfYear(TimeCurrent()) - TimeDayOfYear(monthStart);
   
   if(currentDay <= 0) return false;
   
   // Calculate expected progress
   double expectedProgress = (MonthlyProfitTarget * currentDay) / daysInMonth;
   
   // If we're behind target, we might need to trade more aggressively
   if(currentProfit < expectedProgress * 0.7) { // Less than 70% of expected
      Print("Behind monthly target - consider increasing aggression");
      return true;
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Strategy implementations                                          |
//+------------------------------------------------------------------+

bool TurtleSystem(string symbol, int sysMagic) {
   int tf = PERIOD_H4;
   Print("TURTLE_START: Symbol=", symbol, " BarTime=", TimeToStr(Time[0]), " Valid=", IsSymbolValid(symbol));
   
   if(IsSymbolValid(symbol) == false) {
      Print("SKIP: Symbol not valid voor broker?!");
      return false;
   }
   
   if(ConsecutiveLosses >= LossStreakLimit) {
      BlockTradingToday = true;
      string body = "Loss streak limit reached: " + IntegerToString(ConsecutiveLosses) + 
                    " >= " + IntegerToString(LossStreakLimit);
      NotifyEvent("Loss streak triggered", body, EmailOnBlockTrading && EnableEmailAlerts, EnableMT4Alerts);
      Print("SKIP: Loss streak limit reached - blocking trading for today.");
      return false;
   }
   
   if(OpenTradesCountForMagic(sysMagic) >= MaxConcurrentTrades) {
      Print("SKIP: MaxConcurrentTrades reached for sysMagic=", sysMagic);
      return false;
   }
   
   double adxVal = ADX_RatioVal(symbol, tf);
   double atrVal = ATR_RatioVal(symbol, tf);
   Print("TURTLE_FILTER: ADX=", adxVal, " ATR=", atrVal, " MinADX=", TURTLE_ADX_Min, " MinATR=", TURTLE_ATR_Min);
   
   if(adxVal < TURTLE_ADX_Min) {
      Print("SKIP: ADX te laag voor entry.");
      return false;
   }
   if(atrVal < TURTLE_ATR_Min) {
      Print("SKIP: ATR te laag voor entry.");
      return false;
   }
   
   int currBar = iBarShift(symbol, tf, Time[0], true);
   double high = iHigh(symbol, tf, iHighest(symbol, tf, MODE_HIGH, TURTLE_Entry, currBar + 1));
   double low = iLow(symbol, tf, iLowest(symbol, tf, MODE_LOW, TURTLE_Entry, currBar + 1));
   double stopLossPips = MathAbs(high - low) / MarketInfo(symbol, MODE_POINT);
   
   if(stopLossPips <= 0.0) return false;
   
   double calcLot = (UseFixedLot == true) ? FixedLot : CalcLotSize(symbol, Risk_Percent_PerTrade, stopLossPips);
   double minL = minLot(symbol);
   double maxL = maxLot(symbol);
   double lotSize = 0.0;
   
   if(UseFixedLot == false) {
      if(calcLot <= 0.0) {
         Print("SKIP: calcLot invalid (", DoubleToStr(calcLot, 2), ") - skipping.");
         return false;
      }
      if(calcLot < minL) {
         if(UseMinLotWhenTooSmall == true) {
            lotSize = minL;
            Print("NOTICE: calcLot ", DoubleToStr(calcLot, 2), " < minLot ", DoubleToStr(minL, 2), 
                  " -> using minLot due to UseMinLotWhenTooSmall=true");
         } else {
            Print("SKIP: Calculated lot ", DoubleToStr(calcLot, 2), " < broker minLot ", 
                  DoubleToStr(minL, 2), " for risk ", DoubleToStr(Risk_Percent_PerTrade, 2), "%");
            return false;
         }
      } else {
         lotSize = calcLot;
      }
   } else {
      lotSize = FixedLot;
   }
   
   if(lotSize > maxL) lotSize = maxL;
   lotSize = NormalizeDouble(lotSize, 2);
   
   // Ensure FTMO checks before opening new trades
   CheckFTMODrawdown();
   CheckDailyDrawdownAndProfit();
   
   if(BlockTradingToday == true) {
      Print("SKIP: BlockTradingToday actief, no new trades.");
      return false;
   }
   
   // VRAAG 1 & 2: Check if we can open new trade (multi-EA coordination)
   if(!CanOpenNewTrade()) {
      Print("SKIP: Cannot open new trade due to multi-EA coordination rules");
      return false;
   }
   
   double ask = MarketInfo(symbol, MODE_ASK);
   double bid = MarketInfo(symbol, MODE_BID);
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   double sl, tp;
   int ticket = -1;
   
   if(iClose(symbol, tf, currBar) > high) { // LONG
      sl = NormalizeDouble(ask - stopLossPips * MarketInfo(symbol, MODE_POINT), digits);
      tp = NormalizeDouble(ask + stopLossPips * Turtle_TP_Factor * MarketInfo(symbol, MODE_POINT), digits);
      sl = CorrectStopLoss(symbol, OP_BUY, ask, sl);
      tp = CorrectTakeProfit(symbol, OP_BUY, ask, tp);
      Print("TURTLE_ORDER LONG: Ask=", ask, " SL=", sl, " TP=", tp, " Lot=", lotSize);
      ticket = OrderSend(symbol, OP_BUY, lotSize, ask, Slippage, sl, tp, "TurtleLong", sysMagic, 0, clrBlue);
      
      if(ticket < 0) {
         Print("OrderSend ERROR: Ticket=", ticket, " code=", GetLastError());
         ReleaseTradeSlot(); // Release slot on failure
      }
      if(ticket > 0) {
         tradesToday++;
         Print("Trade opened successfully, ticket=", ticket);
      }
      return ticket > 0;
   }
   
   if(iClose(symbol, tf, currBar) < low) { // SHORT
      sl = NormalizeDouble(bid + stopLossPips * MarketInfo(symbol, MODE_POINT), digits);
      tp = NormalizeDouble(bid - stopLossPips * Turtle_TP_Factor * MarketInfo(symbol, MODE_POINT), digits);
      sl = CorrectStopLoss(symbol, OP_SELL, bid, sl);
      tp = CorrectTakeProfit(symbol, OP_SELL, bid, tp);
      Print("TURTLE_ORDER SHORT: Bid=", bid, " SL=", sl, " TP=", tp, " Lot=", lotSize);
      ticket = OrderSend(symbol, OP_SELL, lotSize, bid, Slippage, sl, tp, "TurtleShort", sysMagic, 0, clrRed);
      
      if(ticket < 0) {
         Print("OrderSend ERROR: Ticket=", ticket, " code=", GetLastError());
         ReleaseTradeSlot(); // Release slot on failure
      }
      if(ticket > 0) {
         tradesToday++;
         Print("Trade opened successfully, ticket=", ticket);
      }
      return ticket > 0;
   }
   
   // No trade opened, release the slot
   ReleaseTradeSlot();
   Print("SKIP: Geen Turtle LONG/SHORT entry dit bar.");
   return false;
}

// MACrossSystem (full implementation)
bool MACrossSystem(string symbol, int sysMagic) {
   int tf = PERIOD_H4;
   Print("MACROSS_START: Symbol=", symbol);
   
   if(IsSymbolValid(symbol) == false) {
      Print("SKIP: Symbol not valid");
      return false;
   }
   
   if(ConsecutiveLosses >= LossStreakLimit) {
      BlockTradingToday = true;
      string body = "Loss streak limit reached: " + IntegerToString(ConsecutiveLosses) + 
                    " >= " + IntegerToString(LossStreakLimit);
      NotifyEvent("Loss streak triggered", body, EmailOnBlockTrading && EnableEmailAlerts, EnableMT4Alerts);
      Print("SKIP: Loss streak limit reached - blocking.");
      return false;
   }
   
   if(OpenTradesCountForMagic(sysMagic) >= MaxConcurrentTrades) {
      Print("SKIP: MaxConcurrentTrades reached for sysMagic=", sysMagic);
      return false;
   }
   
   double adxVal = ADX_RatioVal(symbol, tf);
   if(adxVal < MA_ADX_Min) {
      Print("SKIP: MACross ADX te laag");
      return false;
   }
   
   CheckFTMODrawdown();
   CheckDailyDrawdownAndProfit();
   
   if(BlockTradingToday == true) return false;
   
   // VRAAG 1 & 2: Check multi-EA coordination
   if(!CanOpenNewTrade()) {
      Print("SKIP: Cannot open new trade due to multi-EA coordination rules");
      return false;
   }
   
   int currBar = iBarShift(symbol, tf, Time[0], true);
   double maFastPrev = iMA(symbol, tf, MA_Fast, 0, MODE_EMA, PRICE_CLOSE, currBar + 1);
   double maSlowPrev = iMA(symbol, tf, MA_Slow, 0, MODE_EMA, PRICE_CLOSE, currBar + 1);
   double maFastNow = iMA(symbol, tf, MA_Fast, 0, MODE_EMA, PRICE_CLOSE, currBar);
   double maSlowNow = iMA(symbol, tf, MA_Slow, 0, MODE_EMA, PRICE_CLOSE, currBar);
   
   double stopLossPips = MathAbs(maFastNow - maSlowNow) / MarketInfo(symbol, MODE_POINT);
   stopLossPips = MathMax(stopLossPips, 3.0);
   
   double calcLot = (UseFixedLot == true) ? FixedLot : CalcLotSize(symbol, Risk_Percent_PerTrade, stopLossPips);
   double minL = minLot(symbol);
   double maxL = maxLot(symbol);
   double lotSize = 0.0;
   
   if(UseFixedLot == false) {
      if(calcLot <= 0.0) {
         Print("SKIP: calcLot invalid - skipping.");
         ReleaseTradeSlot();
         return false;
      }
      if(calcLot < minL) {
         if(UseMinLotWhenTooSmall == true) {
            lotSize = minL;
            Print("NOTICE: calcLot ", DoubleToStr(calcLot, 2), " < minLot ", DoubleToStr(minL, 2), 
                  " -> using minLot due to UseMinLotWhenTooSmall=true");
         } else {
            Print("SKIP: Calculated lot ", DoubleToStr(calcLot, 2), " < minLot ", DoubleToStr(minL, 2));
            ReleaseTradeSlot();
            return false;
         }
      } else {
         lotSize = calcLot;
      }
   } else {
      lotSize = FixedLot;
   }
   
   if(lotSize > maxL) lotSize = maxL;
   lotSize = NormalizeDouble(lotSize, 2);
   
   double ask = MarketInfo(symbol, MODE_ASK);
   double bid = MarketInfo(symbol, MODE_BID);
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   int ticket = -1;
   
   if(maFastPrev < maSlowPrev && maFastNow > maSlowNow) {
      double sl = NormalizeDouble(ask - stopLossPips * MarketInfo(symbol, MODE_POINT), digits);
      double tp = NormalizeDouble(ask + stopLossPips * 1.7 * MarketInfo(symbol, MODE_POINT), digits);
      sl = CorrectStopLoss(symbol, OP_BUY, ask, sl);
      tp = CorrectTakeProfit(symbol, OP_BUY, ask, tp);
      ticket = OrderSend(symbol, OP_BUY, lotSize, ask, Slippage, sl, tp, "MACrossLong", sysMagic, 0, clrGreen);
      if(ticket > 0) {
         tradesToday++;
      } else {
         ReleaseTradeSlot();
      }
      return ticket > 0;
   }
   
   if(maFastPrev > maSlowPrev && maFastNow < maSlowNow) {
      double sl = NormalizeDouble(bid + stopLossPips * MarketInfo(symbol, MODE_POINT), digits);
      double tp = NormalizeDouble(bid - stopLossPips * 1.7 * MarketInfo(symbol, MODE_POINT), digits);
      sl = CorrectStopLoss(symbol, OP_SELL, bid, sl);
      tp = CorrectTakeProfit(symbol, OP_SELL, bid, tp);
      ticket = OrderSend(symbol, OP_SELL, lotSize, bid, Slippage, sl, tp, "MACrossShort", sysMagic, 0, clrOrange);
      if(ticket > 0) {
         tradesToday++;
      } else {
         ReleaseTradeSlot();
      }
      return ticket > 0;
   }
   
   ReleaseTradeSlot();
   return false;
}

bool MeanReversionSystem(string symbol, int sysMagic) {
   int tf = PERIOD_H4;
   Print("MEANREV_START: Symbol=", symbol);
   
   if(IsSymbolValid(symbol) == false) return false;
   
   if(ConsecutiveLosses >= LossStreakLimit) {
      BlockTradingToday = true;
      string body = "Loss streak limit reached: " + IntegerToString(ConsecutiveLosses) + 
                    " >= " + IntegerToString(LossStreakLimit);
      NotifyEvent("Loss streak triggered", body, EmailOnBlockTrading && EnableEmailAlerts, EnableMT4Alerts);
      Print("SKIP: Loss streak limit reached - blocking.");
      return false;
   }
   
   if(OpenTradesCountForMagic(sysMagic) >= MaxConcurrentTrades) {
      Print("SKIP: MaxConcurrentTrades reached for sysMagic=", sysMagic);
      return false;
   }
   
   double atrVal = ATR_RatioVal(symbol, tf);
   if(atrVal > MR_ATR_Max) {
      Print("SKIP: MR ATR te hoog");
      return false;
   }
   
   CheckFTMODrawdown();
   CheckDailyDrawdownAndProfit();
   
   if(BlockTradingToday == true) return false;
   
   // VRAAG 1 & 2: Check multi-EA coordination
   if(!CanOpenNewTrade()) {
      Print("SKIP: Cannot open new trade due to multi-EA coordination rules");
      return false;
   }
   
   int currBar = iBarShift(symbol, tf, Time[0], true);
   double ma = iMA(symbol, tf, MR_Period, 0, MODE_SMA, PRICE_CLOSE, currBar);
   double stdDev = iStdDev(symbol, tf, MR_Period, 0, MODE_SMA, PRICE_CLOSE, currBar);
   double upper = ma + MR_Dev * stdDev;
   double lower = ma - MR_Dev * stdDev;
   double close = iClose(symbol, tf, currBar);
   
   double stopLossPips = MathAbs((upper - lower) / MarketInfo(symbol, MODE_POINT));
   stopLossPips = MathMax(stopLossPips, 5.0);
   
   double calcLot = (UseFixedLot == true) ? FixedLot : CalcLotSize(symbol, Risk_Percent_PerTrade, stopLossPips);
   double minL = minLot(symbol);
   double maxL = maxLot(symbol);
   double lotSize = 0.0;
   
   if(UseFixedLot == false) {
      if(calcLot <= 0.0) {
         Print("SKIP: calcLot invalid - skipping.");
         ReleaseTradeSlot();
         return false;
      }
      if(calcLot < minL) {
         if(UseMinLotWhenTooSmall == true) {
            lotSize = minL;
            Print("NOTICE: calcLot ", DoubleToStr(calcLot, 2), " < minLot ", DoubleToStr(minL, 2), 
                  " -> using minLot due to UseMinLotWhenTooSmall=true");
         } else {
            Print("SKIP: Calculated lot ", DoubleToStr(calcLot, 2), " < minLot ", DoubleToStr(minL, 2));
            ReleaseTradeSlot();
            return false;
         }
      } else {
         lotSize = calcLot;
      }
   } else {
      lotSize = FixedLot;
   }
   
   if(lotSize > maxL) lotSize = maxL;
   lotSize = NormalizeDouble(lotSize, 2);
   
   double ask = MarketInfo(symbol, MODE_ASK);
   double bid = MarketInfo(symbol, MODE_BID);
   int digits = (int)MarketInfo(symbol, MODE_DIGITS);
   int ticket = -1;
   
   if(close < lower) {
      double sl = NormalizeDouble(ask - stopLossPips * MarketInfo(symbol, MODE_POINT), digits);
      double tp = NormalizeDouble(ask + stopLossPips * 1.7 * MarketInfo(symbol, MODE_POINT), digits);
      sl = CorrectStopLoss(symbol, OP_BUY, ask, sl);
      tp = CorrectTakeProfit(symbol, OP_BUY, ask, tp);
      ticket = OrderSend(symbol, OP_BUY, lotSize, ask, Slippage, sl, tp, "MRLong", sysMagic, 0, clrViolet);
      if(ticket > 0) {
         tradesToday++;
      } else {
         ReleaseTradeSlot();
      }
      return ticket > 0;
   }
   
   if(close > upper) {
      double sl = NormalizeDouble(bid + stopLossPips * MarketInfo(symbol, MODE_POINT), digits);
      double tp = NormalizeDouble(bid - stopLossPips * 1.7 * MarketInfo(symbol, MODE_POINT), digits);
      sl = CorrectStopLoss(symbol, OP_SELL, bid, sl);
      tp = CorrectTakeProfit(symbol, OP_SELL, bid, tp);
      ticket = OrderSend(symbol, OP_SELL, lotSize, bid, Slippage, sl, tp, "MRShort", sysMagic, 0, clrMagenta);
      if(ticket > 0) {
         tradesToday++;
      } else {
         ReleaseTradeSlot();
      }
      return ticket > 0;
   }
   
   ReleaseTradeSlot();
   return false;
}

//+------------------------------------------------------------------+
//| MAIN LOOP                                                         |
//+------------------------------------------------------------------+
void OnTick() {
   UpdateConsecutiveLossesFromHistory();
   CheckFTMODrawdown();
   CheckDailyDrawdownAndProfit();
   CheckMonthlyProfitTarget(); // VRAAG 4
   
   if(BlockTradingToday == true) {
      return;
   }
   
   if(IsTradingTime() == false) {
      return;
   }
   
   if(tradesToday >= MaxTradesPerDay) {
      return;
   }
   
   ManageBreakEvensAndRiskSlot();
   
   if(StrategyToRun == STRAT_TURTLE) 
      TurtleSystem(Symbol, MagicNumber);
   else if(StrategyToRun == STRAT_MACROSS) 
      MACrossSystem(Symbol, MagicNumber + 100);
   else if(StrategyToRun == STRAT_MEANREVERT) 
      MeanReversionSystem(Symbol, MagicNumber + 200);
}

int start() {
   OnTick();
   return 0;
}

//+------------------------------------------------------------------+
//| Initialization                                                    |
//+------------------------------------------------------------------+
int OnInit() {
   Print("EA Strategie Switch gestart (ENHANCED v4.0) Symbol=", Symbol, 
         " UseFixedLot=", UseFixedLot, " FixedLot=", FixedLot, 
         " Risk%=", Risk_Percent_PerTrade, " UseMinLotFallback=", UseMinLotWhenTooSmall);
   
   dayStart = DateOfDay(TimeCurrent());
   dayStartEquity = AccountEquity();
   tradesToday = 0;
   BlockTradingToday = false;
   ConsecutiveLosses = 0;
   LastProcessedHistoryTime = TimeCurrent();
   lastNotificationTime = 0;
   
   // Initialize monthly tracking (VRAAG 4)
   monthStart = DateOfMonth(TimeCurrent());
   monthStartBalance = AccountBalance();
   
   if(IsSymbolValid(Symbol) == false) 
      Print("WARNING: Symbol '", Symbol, "' not valid voor broker!");
   
   // Initialize global variables
   string g = GlobalRiskName();
   if(GlobalVariableCheck(g) == false) GlobalVariableSet(g, 0.0);
   
   string tradeSlot = GetTradeSlotName();
   if(GlobalVariableCheck(tradeSlot) == false) GlobalVariableSet(tradeSlot, 0.0);
   
   if(EnableEmailAlerts == true) {
      Print("Email alerts enabled. Ensure MT4 email (Tools->Options->Email) is configured and 'Enable' is checked.");
   }
   
   Print("Multi-EA coordination enabled:");
   Print("  - Only one EA can trade at a time unless all trades are at break-even");
   Print("  - Daily loss limit (5%) will close ALL trades from ALL EAs");
   Print("  - Monthly profit target: ", DoubleToStr(MonthlyProfitTarget, 2), "%");
   
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Deinitialization                                                  |
//+------------------------------------------------------------------+
void OnDeinit(const int reason) {
   Print("EA Strategie Switch gestopt (v4.0)");
   ReleaseRiskSlotIfOwned();
   ReleaseTradeSlot();
}
//+------------------------------------------------------------------+
