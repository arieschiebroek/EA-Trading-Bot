# Changelog - EA Trading Bot

All notable changes to this project will be documented in this file.

## [4.0] - 2025-12-18

### Added - Multi-EA Coordination & Enhanced FTMO Compliance

#### Vraag 1: Break-Even Coördinatie
- **NEW**: Global variable `EA_BREAK_EVEN_SIGNAL_[AccountNumber]` for signaling break-even status
- **NEW**: Function `AllAccountTradesAtBreakEven()` - Checks if ALL trades across ALL EAs are at break-even
- **NEW**: Automatic coordination between multiple EAs on same account
- **ENHANCED**: `ManageBreakEvensAndRiskSlot()` now signals when trades reach break-even
- **FEATURE**: Only one EA can trade at a time unless all trades are at break-even

#### Vraag 2: Multi-EA Risicoslot
- **NEW**: Global variable `EA_TRADE_SLOT_[AccountNumber]` for trade slot coordination
- **NEW**: Function `ClaimTradeSlot()` - Mutex-like mechanism to claim trading rights
- **NEW**: Function `ReleaseTradeSlot()` - Releases trading slot when done
- **NEW**: Function `CanOpenNewTrade()` - Combined check for BE status and slot availability
- **NEW**: 50ms delay in slot claiming to prevent race conditions
- **ENHANCED**: All three strategies (Turtle, MA Cross, Mean Reversion) now use slot coordination
- **FEATURE**: Automatic slot release on failed order sends

#### Vraag 3: FTMO Dagverliesregel 5%
- **CHANGED**: `MaxDailyLossPercent` default value from 2% to 5%
- **NEW**: Global variable `EA_DAILY_STOP_[AccountNumber]` for account-wide trading stop
- **NEW**: Function `CloseAllOpenTradesAndBlock()` - Closes ALL trades from ALL EAs
- **NEW**: Function `IsGlobalDailyStopActive()` - Checks if daily stop is active
- **ENHANCED**: `CheckDailyDrawdownAndProfit()` now affects all EAs on account
- **ENHANCED**: Daily stop automatically resets at midnight
- **FEATURE**: Email notification when daily stop is triggered
- **FEATURE**: All EAs on account respect the global daily stop

#### Vraag 4: Minimale Winst 8% per Maand
- **NEW**: Input parameter `MonthlyProfitTarget` (default: 8.0%)
- **NEW**: Global variable `EA_MONTHLY_PROFIT_[AccountNumber]_[Date]` for tracking
- **NEW**: State variables `monthStart` and `monthStartBalance`
- **NEW**: Function `CheckMonthlyProfitTarget()` - Tracks monthly performance
- **NEW**: Function `GetMonthlyProfitPercent()` - Returns current monthly profit
- **NEW**: Function `ShouldIncreaseAggression()` - Determines if more aggressive trading needed
- **NEW**: Function `DateOfMonth()` - Helper for month start calculation
- **FEATURE**: Automatic monthly reset on first day of new month
- **FEATURE**: Hourly progress logging towards monthly target
- **FEATURE**: Framework for adaptive trading based on monthly progress

### Improved
- **LOGGING**: Enhanced logging for all new coordination features
- **DOCUMENTATION**: Added comprehensive README.md with all features explained
- **DOCUMENTATION**: Added TECHNICAL_IMPLEMENTATION.md with detailed technical docs
- **DOCUMENTATION**: Added QUICK_START.md for easy user onboarding
- **ERROR HANDLING**: Better error handling in slot claiming and release
- **COMMENTS**: Extensive code comments explaining new features
- **VERSIONING**: Updated version to 4.0 in header comments

### Fixed
- **COORDINATION**: Prevents race conditions when multiple EAs try to trade simultaneously
- **SAFETY**: Trade slot is released if OrderSend fails
- **CONSISTENCY**: All global variable names follow consistent naming pattern

### Technical Details
- **Lines of Code**: 1,111 (EA_TradingBot.mq4)
- **New Functions**: 11
- **New Global Variables**: 4
- **New Input Parameters**: 4
- **Backward Compatibility**: Legacy risk slot mechanism maintained

## [3.3] - Previous Version

### Features
- Three trading strategies: Turtle, MA Cross, Mean Reversion
- FTMO compliance with 2% daily loss limit
- Break-even management
- Email notification system
- Safe order closing with retries
- Consecutive loss tracking
- Trading time windows
- Max trades per day limit
- Loss streak protection

## Migration Guide from 3.3 to 4.0

### Breaking Changes
- **MaxDailyLossPercent** default changed from 2% to 5%
  - Action: Review and adjust if you want different limit

### New Required Parameters
None - all new parameters have sensible defaults

### Recommended Actions
1. **Review new parameters**:
   - `MonthlyProfitTarget` - Set to your desired monthly goal
   - `GlobalTradeSlot` - Ensure consistent across all EAs
   - `GlobalDailyStop` - Ensure consistent across all EAs

2. **Update all EAs on account**:
   - If running multiple EAs, update ALL to version 4.0
   - Mixing versions may cause coordination issues

3. **Test on demo first**:
   - Test multi-EA coordination
   - Verify daily stop works across all EAs
   - Monitor monthly tracking

4. **Monitor global variables**:
   - Check Tools → Global Variables in MT4
   - Ensure coordination variables are working

### New Global Variables to Monitor
```
EA_TRADE_SLOT_[AccountNumber]       - Trading slot ownership
EA_DAILY_STOP_[AccountNumber]       - Daily stop timestamp
EA_BREAK_EVEN_SIGNAL_[AccountNumber] - BE signal
EA_MONTHLY_PROFIT_[AccountNumber]_[Date] - Monthly profit %
```

## Future Roadmap

### Planned for 5.0
- [ ] Machine learning for optimal monthly target pacing
- [ ] Adaptive break-even threshold based on volatility
- [ ] Multi-timeframe coordination
- [ ] Advanced position sizing based on monthly progress
- [ ] Trade correlation analysis across EAs
- [ ] Performance analytics dashboard

### Under Consideration
- [ ] Web-based monitoring interface
- [ ] Mobile app for alerts
- [ ] Cloud backup of settings
- [ ] Trade copy functionality
- [ ] Advanced ML-based strategy selection

## Support

For issues, questions, or feature requests:
1. Review the documentation in README.md
2. Check TECHNICAL_IMPLEMENTATION.md for technical details
3. Consult QUICK_START.md for common scenarios
4. Review code comments in EA_TradingBot.mq4

## Version Compatibility

| Version | MT4 Build | Tested On |
|---------|-----------|-----------|
| 4.0 | 1400+ | Build 1420 |
| 3.3 | 1300+ | Build 1380 |

## License

Proprietary - For personal use only

---

**Note**: Always test new versions on demo account before deploying to live trading.
