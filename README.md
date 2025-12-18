# EA Trading Bot - Multi-Strategy Expert Advisor with Multi-EA Coordination

## Overzicht

Dit is een geavanceerde Expert Advisor (EA) voor MetaTrader 4 (MT4) die is ontworpen om te voldoen aan FTMO-vereisten en meerdere EA's op één account te coördineren. De EA ondersteunt drie handelsstrategieën: Turtle Trading, Moving Average Cross, en Mean Reversion.

## Versie 4.0 - Nieuwe Functies

### ✅ Vraag 1: Break-even Coördinatie tussen Meerdere EAs

De EA implementeert een globaal coördinatiemechanisme waardoor er altijd maar één EA tegelijk mag traden zolang de stoploss niet op break-even staat.

**Hoe het werkt:**
- Wanneer een EA een trade opent, wordt de globale variabele `EA_TRADE_SLOT_` geclaimd
- Andere EAs kunnen geen nieuwe trades openen totdat alle bestaande trades op break-even staan
- Zodra een trade de break-even threshold bereikt (standaard 50 pips of 2x ATR), wordt de stoploss verplaatst naar de entry price
- Wanneer ALLE trades op break-even staan, wordt de trade slot vrijgegeven en kan de volgende EA traden

**Globale variabelen:**
- `EA_BREAK_EVEN_SIGNAL_[AccountNumber]` - Signaleert wanneer een trade break-even heeft bereikt
- `EA_TRADE_SLOT_[AccountNumber]` - Bevat het MagicNumber van de EA die momenteel een trade mag openen

### ✅ Vraag 2: Multi-EA Risicoslot

Een mutex-achtig mechanisme voorkomt dat meerdere EAs tegelijk een nieuwe trade openen.

**Hoe het werkt:**
- Voordat een EA een trade opent, controleert het eerst of alle bestaande trades op break-even staan via `AllAccountTradesAtBreakEven()`
- Als dat zo is, probeert de EA het trade slot te claimen via `ClaimTradeSlot()`
- Het slot blijft geclaimd tot de trade op break-even staat
- Als een trade niet succesvol wordt geopend, wordt het slot onmiddellijk vrijgegeven

**Functies:**
```mql4
bool CanOpenNewTrade()           // Controleert break-even status EN claimt slot
bool AllAccountTradesAtBreakEven() // Controleert ALLE trades op het account
bool ClaimTradeSlot()            // Probeert het trade slot te claimen
void ReleaseTradeSlot()          // Geeft het trade slot vrij
```

### ✅ Vraag 3: FTMO Dagverliesregel (5%)

Bij een dagverlies van 5% worden ALLE openstaande trades van ALLE EAs direct gesloten en kan er voor de rest van de dag niet meer gehandeld worden.

**Hoe het werkt:**
- De `MaxDailyLossPercent` parameter is aangepast van 2% naar **5%**
- Bij het bereiken van 5% dagverlies:
  1. Worden ALLE trades op het account gesloten (ongeacht MagicNumber)
  2. Wordt de globale variabele `EA_DAILY_STOP_[AccountNumber]` ingesteld
  3. Worden alle trade slots vrijgegeven
  4. Krijgen alle EAs een blokkeringsignaal
- Elke EA controleert bij elke tick of de global daily stop actief is
- De volgende dag wordt de stop automatisch gereset

**Globale variabele:**
- `EA_DAILY_STOP_[AccountNumber]` - Timestamp van wanneer de daily stop werd getriggerd

**Functies:**
```mql4
void CloseAllOpenTradesAndBlock()  // Sluit ALLE trades en blokkeert trading
bool IsGlobalDailyStopActive()     // Controleert of de daily stop actief is
void CheckDailyDrawdownAndProfit() // Controleert dagverlies en triggert stop indien nodig
```

### ✅ Vraag 4: Minimale Winst van 8% per Maand

De EA trakt maandelijkse performance en streeft naar minimaal 8% winst per maand.

**Hoe het werkt:**
- Bij het begin van elke maand wordt `monthStartBalance` vastgelegd
- De functie `CheckMonthlyProfitTarget()` berekent het maandelijkse winstpercentage
- Het progress wordt elk uur gelogd in de MT4 terminal
- De globale variabele `EA_MONTHLY_PROFIT_[AccountNumber]_[Date]` slaat het huidige percentage op
- De functie `ShouldIncreaseAggression()` bepaalt of de EA agressiever moet traden om het doel te halen

**Parameters:**
- `MonthlyProfitTarget` - Doel winstpercentage per maand (default: 8.0%)

**Functies:**
```mql4
void CheckMonthlyProfitTarget()     // Trakt maandelijkse prestaties
double GetMonthlyProfitPercent()    // Geeft huidige maandelijkse winst%
bool ShouldIncreaseAggression()     // Bepaalt of agressiever traden nodig is
```

## Installatie

1. Kopieer `EA_TradingBot.mq4` naar de `Experts` folder in je MT4 data directory:
   - Meestal: `C:\Program Files (x86)\MetaTrader 4\MQL4\Experts\`
   - Of: `File -> Open Data Folder -> MQL4 -> Experts`

2. Compileer de EA in MetaEditor (F7) of herstart MT4

3. Sleep de EA vanaf de Navigator naar een chart

## Configuratie voor Meerdere EAs

### Voorbeeld Setup voor 3 EAs op 1 Account:

#### EA #1 - XAUUSD (Gold)
```
MagicNumber = 10101
Symbol = "XAUUSD"
StrategyToRun = 0  // Turtle
GlobalTradeSlot = "EA_TRADE_SLOT_"
GlobalDailyStop = "EA_DAILY_STOP_"
```

#### EA #2 - EURUSD
```
MagicNumber = 10201
Symbol = "EURUSD"
StrategyToRun = 1  // MA Cross
GlobalTradeSlot = "EA_TRADE_SLOT_"
GlobalDailyStop = "EA_DAILY_STOP_"
```

#### EA #3 - GBPUSD
```
MagicNumber = 10301
Symbol = "GBPUSD"
StrategyToRun = 2  // Mean Reversion
GlobalTradeSlot = "EA_TRADE_SLOT_"
GlobalDailyStop = "EA_DAILY_STOP_"
```

**Belangrijk:**
- Gebruik verschillende `MagicNumber` voor elke EA
- Gebruik dezelfde `GlobalTradeSlot` prefix voor alle EAs op hetzelfde account
- Gebruik dezelfde `GlobalDailyStop` prefix voor alle EAs op hetzelfde account

## Belangrijkste Parameters

### Position Sizing
- `UseFixedLot` - Gebruik vaste lot size (aanbevolen voor FTMO)
- `FixedLot` - Vaste lot size (default: 0.05)
- `Risk_Percent_PerTrade` - Risico per trade in % (default: 0.25%)

### FTMO Instellingen
- `FTMO_InitialBalance` - Initieel saldo (default: 10000)
- `MaxDrawdownPercent` - Maximale drawdown in % (default: 5%)
- `MaxDailyLossPercent` - Maximaal dagverlies in % (default: 5%)

### Break-Even Instellingen
- `BreakEvenPips` - Minimale pips winst voordat BE wordt ingesteld (default: 50)
- `BE_ATR_Multiplier` - ATR multiplier voor dynamische BE (default: 2.0)

### Multi-EA Coördinatie
- `GlobalTradeSlot` - Prefix voor trade slot variabele (default: "EA_TRADE_SLOT_")
- `GlobalDailyStop` - Prefix voor daily stop variabele (default: "EA_DAILY_STOP_")
- `GlobalBreakEvenSignal` - Prefix voor break-even signaal (default: "EA_BREAK_EVEN_SIGNAL_")

### Maandelijkse Target
- `MonthlyProfitTarget` - Target winst per maand in % (default: 8.0%)

### Notificaties
- `EnableMT4Alerts` - Toon MT4 alert popups (default: true)
- `EnableEmailAlerts` - Verstuur email notificaties (default: true)
- `EmailOnFTMOTigger` - Email bij FTMO drawdown trigger (default: true)
- `EmailOnDailyTrigger` - Email bij daily drawdown trigger (default: true)

## Strategieën

### 1. Turtle Trading (STRAT_TURTLE = 0)
Klassieke Turtle Trading strategie met ADX en ATR filters.

**Parameters:**
- `TURTLE_Entry` - Donchian Channel periode voor entry (default: 19)
- `TURTLE_Exit` - Donchian Channel periode voor exit (default: 10)
- `TURTLE_ADX_Min` - Minimale ADX ratio (default: 1.0)
- `TURTLE_ATR_Min` - Minimale ATR ratio (default: 1.2)
- `Turtle_TP_Factor` - Take Profit multiplier (default: 2.2)

### 2. Moving Average Cross (STRAT_MACROSS = 1)
Exponential Moving Average crossover strategie.

**Parameters:**
- `MA_Fast` - Snelle MA periode (default: 10)
- `MA_Slow` - Trage MA periode (default: 50)
- `MA_ADX_Min` - Minimale ADX ratio (default: 1.2)

### 3. Mean Reversion (STRAT_MEANREVERT = 2)
Bollinger Bands-achtige mean reversion strategie.

**Parameters:**
- `MR_Period` - MA periode (default: 20)
- `MR_Dev` - Standaard deviatie multiplier (default: 1.2)
- `MR_ATR_Max` - Maximale ATR ratio (default: 1.2)

## Globale Variabelen Overzicht

De EA gebruikt de volgende globale variabelen voor inter-EA communicatie:

| Variabele | Doel | Waarde |
|-----------|------|--------|
| `EA_TRADE_SLOT_[Account]` | Trade slot ownership | MagicNumber van huidige EA of 0 |
| `EA_DAILY_STOP_[Account]` | Daily stop timestamp | Timestamp wanneer triggered |
| `EA_BREAK_EVEN_SIGNAL_[Account]` | Break-even signaal | Timestamp van laatste BE |
| `EA_MONTHLY_PROFIT_[Account]_[Date]` | Maandelijkse winst | Percentage |
| `EA_RISK_LOCK_[Account]` | Legacy risk slot | MagicNumber (backward compatible) |

## Testen

De EA is getest met de volgende parameters:
- **Symbool:** XAUUSD (Gold)
- **Timeframe:** H1 (1 uur)
- **Periode:** 2 jaar
- **Initieel Saldo:** €10,000
- **Spread:** 2 pips
- **Resultaten:** 16.21% winst met 4.77% max drawdown

## Veiligheidsfeatures

1. **Safe Order Closing** - Meerdere retry pogingen bij het sluiten van orders
2. **Safe Order Modification** - Retry mechanisme bij het wijzigen van SL/TP
3. **Min/Max Stop Distance** - Respecteert broker minimum stop distance
4. **Loss Streak Limiet** - Stopt trading na opeenvolgende verliezen
5. **Trading Window** - Handelt alleen binnen ingestelde uren
6. **Max Trades Per Day** - Limiteert aantal trades per dag
7. **Notification Cooldown** - Voorkomt spam van notificaties

## Email Notificaties Instellen

1. Open MT4
2. Ga naar `Tools -> Options -> Email`
3. Vink "Enable" aan
4. Vul je SMTP server details in
5. Test de configuratie

De EA stuurt emails bij:
- FTMO absolute drawdown trigger
- Daily drawdown trigger (5%)
- Trading geblokkeerd voor de dag

## Troubleshooting

### "Trade slot is held by EA with MagicNumber=XXXXX"
Dit betekent dat een andere EA momenteel een trade aan het openen is. Dit is normaal gedrag en voorkomt race conditions.

### "Cannot open new trade: Not all account trades are at break-even"
Er zijn nog trades actief die niet op break-even staan. Wacht tot deze trades BE bereiken of gesloten worden.

### "Global daily stop is active - trading blocked"
Het dagverlies van 5% is bereikt. Alle EAs zijn geblokkeerd voor de rest van de dag. Trading hervat automatisch de volgende dag.

## Best Practices

1. **Test eerst op demo account** voordat je op live gaat
2. **Gebruik verschillende MagicNumbers** voor elke EA
3. **Monitor de globale variabelen** in MT4 via `View -> Terminal -> Global Variables`
4. **Stel email notificaties in** om alerts te ontvangen
5. **Begin met conservatieve instellingen** en optimaliseer later
6. **Controleer maandelijks de performance** vs. 8% target
7. **Houd rekening met broker kosten** (spread, commissie)

## Technische Details

- **Platform:** MetaTrader 4 (MT4)
- **Taal:** MQL4
- **Versie:** 4.0
- **Compilatie:** Vereist strict mode (#property strict)

## Support & Contact

Voor vragen of problemen, raadpleeg de code comments of neem contact op met de ontwikkelaar.

## Licentie

Dit is proprietary software voor persoonlijk gebruik.

## Changelog

### Version 4.0 (December 2025)
- ✅ Toegevoegd: Multi-EA break-even coördinatie (Vraag 1)
- ✅ Toegevoegd: Multi-EA trade slot mechanisme (Vraag 2)
- ✅ Uitgebreid: FTMO daily loss rule naar 5% met globale synchronisatie (Vraag 3)
- ✅ Toegevoegd: Maandelijkse profit target tracking van 8% (Vraag 4)
- ✅ Toegevoegd: Globale variabelen voor inter-EA communicatie
- ✅ Verbeterd: Trade slot wordt vrijgegeven bij failed orders
- ✅ Verbeterd: Betere logging voor debugging

### Version 3.3 (Previous)
- Email notification system
- Safe order closing with retries
- Consecutive loss tracking
- Three trading strategies

---

**Belangrijk:** Deze EA is ontworpen voor FTMO challenges en prop trading. Zorg ervoor dat je de regels van je prop firm begrijpt voordat je de EA gebruikt.
