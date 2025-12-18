# Quick Start Guide - EA Trading Bot v4.0

## Snelle Setup in 5 Stappen

### Stap 1: Installeer de EA
1. Kopieer `EA_TradingBot.mq4` naar je MT4 `Experts` folder
2. Herstart MT4 of druk F4 om MetaEditor te openen en compileer (F7)

### Stap 2: Configureer Email Alerts (Optioneel maar Aanbevolen)
1. MT4 → Tools → Options → Email
2. Vink "Enable" aan
3. Vul SMTP gegevens in (bijv. Gmail SMTP)
4. Test de verbinding

### Stap 3: Sleep EA naar Chart
1. Open een H1 chart voor je gewenste symbool (bijv. XAUUSD)
2. Sleep `EA_TradingBot` vanaf Navigator → Expert Advisors naar de chart
3. In het popup venster:
   - Controleer "Allow live trading" is aangevinkt
   - Controleer "Allow DLL imports" indien nodig

### Stap 4: Configureer Parameters

#### Minimale Configuratie:
```
MagicNumber = 10101        (uniek per EA!)
Symbol = "XAUUSD"          (het symbool dat je wilt traden)
StrategyToRun = 0          (0=Turtle, 1=MA Cross, 2=Mean Reversion)
UseFixedLot = true         (aanbevolen voor FTMO)
FixedLot = 0.05           (conservatieve lot size)
FTMO_InitialBalance = 10000
```

#### Voor Meerdere EAs op 1 Account:
**EA #1 (XAUUSD):**
```
MagicNumber = 10101
Symbol = "XAUUSD"
```

**EA #2 (EURUSD):**
```
MagicNumber = 10201
Symbol = "EURUSD"
```

**EA #3 (GBPUSD):**
```
MagicNumber = 10301
Symbol = "GBPUSD"
```

**Belangrijk:** Gebruik ALTIJD verschillende MagicNumbers!

### Stap 5: Start de EA
1. Klik "OK" in het parameters venster
2. Controleer of de smiley rechts boven in de chart verschijnt
3. Check de "Experts" tab in de Terminal voor log berichten

## Belangrijke Features en Hoe Ze Werken

### ✅ Break-Even Coördinatie
**Wat doet het:**
- Als EA #1 een trade opent, kunnen EA #2 en #3 NIET traden
- Zodra de trade van EA #1 op break-even staat, kunnen anderen weer traden

**Hoe te monitoren:**
- In MT4 Terminal → Tools → Global Variables
- Kijk naar `EA_TRADE_SLOT_[AccountNumber]`
- Waarde = 0: Slot is vrij
- Waarde = MagicNumber: Die EA heeft het slot

### ✅ 5% Daily Loss Protection
**Wat doet het:**
- Bij 5% dagverlies: ALLE trades worden direct gesloten
- ALLE EAs op het account worden geblokkeerd voor die dag
- Volgende dag start automatisch weer normaal

**Hoe te monitoren:**
- Check `EA_DAILY_STOP_[AccountNumber]` in Global Variables
- Als deze bestaat EN timestamp is van vandaag = trading geblokkeerd
- Je krijgt een email alert (als ingesteld)

### ✅ 8% Monthly Target
**Wat doet het:**
- Trakt je maandelijkse winst automatisch
- Logt progress elk uur in de Experts tab
- Kan trading agressiviteit aanpassen als je achter loopt

**Hoe te monitoren:**
- Check logs: "Monthly profit progress: X.XX% / Target: 8.00%"
- Check `EA_MONTHLY_PROFIT_[AccountNumber]_[Date]` in Global Variables

## Dagelijkse Monitoring Checklist

### Elke Ochtend:
- [ ] Check of alle EAs draaien (smiley icons zichtbaar)
- [ ] Controleer Global Variables (Tools → Global Variables):
  - `EA_TRADE_SLOT_` should be 0 (vrij) of een MagicNumber
  - `EA_DAILY_STOP_` should NOT exist of van gisteren zijn
- [ ] Check current drawdown vs. 5% limiet
- [ ] Check monthly progress in Experts log

### Bij Elk Trade:
- [ ] Verify correct lot size
- [ ] Check SL en TP zijn correct gezet
- [ ] Monitor wanneer trade naar break-even gaat
- [ ] Verify andere EAs kunnen traden nadat BE bereikt is

### Einde van de Dag:
- [ ] Check total profit/loss voor de dag
- [ ] Review closed trades in Account History
- [ ] Check of 5% limit NIET werd getriggerd
- [ ] Backup de Experts log indien nodig

## Troubleshooting

### "Trade slot is held by EA with MagicNumber=XXXXX"
**Oorzaak:** Een andere EA heeft momenteel een trade open die niet op BE staat  
**Oplossing:** Wacht tot die trade BE bereikt of gesloten wordt (dit is normaal gedrag)

### "Cannot open new trade: Not all account trades are at break-even"
**Oorzaak:** Er zijn trades actief die nog niet op break-even staan  
**Oplossing:** 
1. Check welke trades niet op BE staan
2. Wacht tot ze profit maken en automatisch naar BE gaan
3. Of close ze handmatig als nodig

### "Global daily stop is active - trading blocked"
**Oorzaak:** 5% dagverlies werd bereikt vandaag  
**Oplossing:** 
1. Accept dat trading geblokkeerd is voor vandaag
2. Review wat fout ging
3. Volgende dag start automatisch weer

### EA Trade Niet Terwijl Hij Zou Moeten
**Check deze dingen:**
1. Is "Allow live trading" aangevinkt?
2. Is de trading window actief? (default: 0-24 uur)
3. Is MaxTradesPerDay bereikt?
4. Zijn er andere EAs die het trade slot vasthouden?
5. Is BlockTradingToday = true door loss streak of dagverlies?

### Geen Break-Even Movement
**Check deze dingen:**
1. Is BreakEvenPips te hoog ingesteld? (default: 50)
2. Heeft de trade genoeg winst gemaakt?
3. Check BE_ATR_Multiplier waarde
4. Verify broker minimum stop level

## Best Practices

### ✅ DO's:
- Test eerst ALTIJD op demo account
- Gebruik verschillende MagicNumbers voor elke EA
- Stel email alerts in
- Monitor daily drawdown regelmatig
- Start met conservatieve instellingen (kleine lot sizes)
- Backup je settings regelmatig
- Review je trades wekelijks

### ❌ DON'Ts:
- Gebruik NOOIT dezelfde MagicNumber voor meerdere EAs
- Open GEEN handmatige trades op hetzelfde account (kan coördinatie verstoren)
- Verander parameters NIET tijdens open trades
- Disable email alerts NIET (je mist belangrijke waarschuwingen)
- Test NIET gelijk op live account
- Force close global variables NIET handmatig

## Common Scenarios

### Scenario 1: Eerste Trade van de Dag
1. EA #1 opent trade om 10:00
2. `EA_TRADE_SLOT_` wordt 10101
3. Trade maakt winst, bereikt 50 pips
4. EA #1 moved SL naar break-even
5. `EA_TRADE_SLOT_` wordt 0 (vrij)
6. EA #2 kan nu traden

### Scenario 2: Dagverlies 5% Bereikt
1. Meerdere verliestrades leiden tot 5% equity drop
2. `CheckDailyDrawdownAndProfit()` detecteert dit
3. `CloseAllOpenTradesAndBlock()` wordt aangeroepen
4. ALLE trades van ALLE EAs worden gesloten
5. `EA_DAILY_STOP_[Account]` wordt gezet
6. Email notificatie wordt verstuurd
7. Geen enkele EA kan meer traden vandaag
8. Morgen 00:00: automatisch reset

### Scenario 3: Maandelijks Target Tracking
1. 1e van de maand: `monthStartBalance` = 10000
2. Week 1: profit = 1.5% (logt elk uur)
3. Week 2: profit = 3.2%
4. Week 3: profit = 5.8%
5. Week 4: profit bereikt 8.1% ✅ Target gehaald!

## Parameter Reference - Quick Guide

| Parameter | Default | Aanbevolen Range | Doel |
|-----------|---------|------------------|------|
| FixedLot | 0.05 | 0.01 - 0.10 | Lot size per trade |
| MaxDailyLossPercent | 5.0 | 2.0 - 5.0 | Daily stop loss % |
| BreakEvenPips | 50 | 30 - 100 | Pips voor BE move |
| MonthlyProfitTarget | 8.0 | 5.0 - 15.0 | Target winst % |
| MaxTradesPerDay | 20 | 5 - 50 | Max trades per dag |
| LossStreakLimit | 5 | 3 - 10 | Opeenvolgende verliezen |

## Support Contacts

Voor technische vragen:
1. Check eerst de README.md
2. Check TECHNICAL_IMPLEMENTATION.md voor details
3. Review de code comments in EA_TradingBot.mq4

## Belangrijke Waarschuwingen

⚠️ **FTMO Compliance:**
- Verify dat je settings voldoen aan je FTMO challenge regels
- 5% dagverlies is het MAXIMUM
- Test je strategie uitgebreid op demo

⚠️ **Risk Management:**
- Start met kleine lot sizes
- Monitor je trades actief
- Gebruik ALTIJD stop losses
- Overschrijd NOOIT je risk limits

⚠️ **Multi-EA Coordination:**
- Alle EAs moeten dezelfde globale variable prefixes gebruiken
- Test de coördinatie eerst op demo
- Monitor de global variables in real-time

## Version Info
- **Versie:** 4.0
- **Release Datum:** December 2025
- **Compatibiliteit:** MetaTrader 4
- **Minimum Balance:** €10,000 (FTMO standard)

---

**Succes met traden! 🚀**
