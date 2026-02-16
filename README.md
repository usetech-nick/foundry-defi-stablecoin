# Decentralized Stablecoin Protocol

A decentralized, overcollateralized stablecoin system with algorithmic stability, oracle-based pricing, and automated liquidations.

## Overview

This protocol implements a USD-pegged stablecoin (DSC) backed by cryptocurrency collateral (WETH & WBTC). Users can deposit collateral to mint stablecoins while maintaining a healthy collateralization ratio. The system features automated liquidation mechanisms to ensure protocol solvency.

### Key Features

- **Overcollateralized**: Minimum 200% collateralization ratio (50% LTV)
- **Multi-Collateral**: Supports WETH and WBTC as collateral assets
- **Oracle-Powered**: Chainlink price feeds for real-time asset pricing
- **Liquidation System**: Incentivized liquidations to maintain protocol health
- **Algorithmic Stability**: No governance, fully algorithmic peg maintenance

## Architecture
```
┌─────────────────────────────────────────────────┐
│                                                 │
│  User deposits WETH/WBTC → Mints DSC           │
│  Maintains health factor > 1.0                  │
│  Can redeem collateral or burn DSC              │
│                                                 │
└─────────────────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────┐
│              DSCEngine (Core Logic)             │
│  • Collateral management                        │
│  • DSC minting/burning                          │
│  • Health factor calculations                   │
│  • Liquidation logic                            │
└─────────────────────────────────────────────────┘
         │                           │
         ▼                           ▼
┌──────────────────┐      ┌──────────────────────┐
│   OracleLib      │      │ DecentralizedStable  │
│  (Price Feeds)   │      │     Coin (ERC20)     │
│  • Stale checks  │      │  • Mint/Burn         │
│  • USD conversion│      │  • Access control    │
└──────────────────┘      └──────────────────────┘
```

## Smart Contracts

### DSCEngine.sol
The core protocol logic handling:
- Collateral deposits and withdrawals
- DSC minting and burning
- Health factor calculations
- Liquidation mechanics
- Position management

### DecentralizedStableCoin.sol
ERC20 implementation of the stablecoin with:
- Mintable/burnable by DSCEngine only
- Standard ERC20 functionality
- Access control for minting/burning

### OracleLib.sol
Library for Chainlink oracle interactions:
- Stale price detection (3-hour timeout)
- USD value conversions
- Price feed validation

## Getting Started

### Prerequisites

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- [Git](https://git-scm.com/downloads)

### Installation
```bash
git clone https://github.com/yourusername/foundry-defi-stablecoin
cd foundry-defi-stablecoin
forge install
```

### Build
```bash
forge build
```

### Test
```bash
# Run all tests
forge test

# Run with verbosity
forge test -vvv

# Run specific test file
forge test --match-path test/DSCEngineTest.t.sol

# Run coverage report
forge coverage
```

## Testing Strategy

This project implements a comprehensive testing approach:

### Test Coverage
- **86.15% line coverage**
- **88.44% statement coverage**
- **23 unit tests** covering all core functionality
- **Handler-based invariant testing** with 16,384+ fuzz calls

### Unit Tests (`test/DSCEngineTest.t.sol`)
Comprehensive tests covering:
- Collateral deposits and redemptions
- DSC minting and burning
- Health factor calculations
- Liquidation scenarios
- Edge cases and failure modes

### Invariant Tests (`test/fuzz/Invariants.t.sol`)
Critical protocol properties verified:
- **Protocol Overcollateralization**: `totalCollateralValue >= totalDebtValue`
- **Getter Functions**: All view functions never revert
- **Handler-guided fuzzing**: Realistic state transitions only

### Handler (`test/fuzz/Handler.t.sol`)
Guides the fuzzer through valid protocol interactions:
- Deposits only approved collateral
- Mints DSC respecting health factors
- Redeems collateral within safe limits
- Tracks ghost variables for invariant verification

## Core Mechanics

### Depositing Collateral & Minting DSC
```solidity
// 1. Approve collateral token
IERC20(weth).approve(address(dscEngine), amount);

// 2. Deposit and mint in one transaction
dscEngine.depositCollateralAndMintDsc(
    wethAddress,
    collateralAmount,
    dscToMint
);
```

### Health Factor

Health factor determines if a position is safe from liquidation:
```
healthFactor = (collateralValue * LIQUIDATION_THRESHOLD) / totalDscMinted
```

- Health factor > 1.0: Position is safe
- Health factor < 1.0: Position can be liquidated
- Minimum collateralization: 200% (50% LTV)

### Liquidation

Anyone can liquidate undercollateralized positions:
```solidity
dscEngine.liquidate(
    collateralAddress,
    userToLiquidate,
    debtToCover
);
```

Liquidators receive:
- The debt amount in collateral
- 10% liquidation bonus
- Helps maintain protocol solvency

## Deployment

### Local Deployment
```bash
# Start local Anvil chain
anvil

# Deploy (in new terminal)
forge script script/DeployDSC.s.sol --rpc-url http://localhost:8545 --broadcast
```

### Sepolia Testnet
```bash
forge script script/DeployDSC.s.sol \
    --rpc-url $SEPOLIA_RPC_URL \
    --private-key $PRIVATE_KEY \
    --broadcast \
    --verify \
    --etherscan-api-key $ETHERSCAN_API_KEY
```

## Security Considerations

### Implemented Protections
- ✅ Reentrancy guards on state-changing functions
- ✅ Oracle staleness checks (3-hour timeout)
- ✅ Health factor enforcement before all operations
- ✅ Collateral validation (only approved assets)
- ✅ Zero-amount checks
- ✅ Overcollateralization requirements

### Known Limitations
- Oracle dependency (relies on Chainlink price feeds)
- Liquidation relies on external actors (MEV risk)
- No governance mechanism (fully algorithmic)
- Limited to two collateral types (WETH, WBTC)

### Audit Status
⚠️ **This protocol has NOT been audited. Use at your own risk.**

## Technical Details

### Technologies Used
- **Solidity ^0.8.19**: Smart contract language
- **Foundry**: Development framework and testing
- **Chainlink**: Decentralized oracle network
- **OpenZeppelin**: Battle-tested contract libraries

### Gas Optimization
- Efficient storage patterns
- Minimal external calls
- Batch operations where possible
- View functions for off-chain calculations

## Project Structure
```
foundry-defi-stablecoin/
├── src/
│   ├── DSCEngine.sol              # Core protocol logic
│   ├── DecentralizedStableCoin.sol # ERC20 stablecoin
│   └── libraries/
│       └── OracleLib.sol          # Oracle helper library
├── script/
│   ├── DeployDSC.s.sol            # Deployment script
│   └── HelperConfig.s.sol         # Network configurations
├── test/
│   ├── DSCEngineTest.t.sol        # Unit tests
│   ├── fuzz/
│   │   ├── Handler.t.sol          # Fuzz handler
│   │   ├── Invariants.t.sol       # Invariant tests
│   │   └── OpenInvariantsTest.t.sol
│   └── mocks/                     # Mock contracts for testing
└── foundry.toml                   # Foundry configuration
```

## Learning Resources

This project was built as part of learning DeFi protocol development. Key concepts implemented:
- Overcollateralized stablecoin mechanics
- Oracle integration and staleness checks
- Liquidation systems and incentives
- Handler-based invariant testing
- Foundry testing frameworks

## License

MIT License - see LICENSE file for details

## Acknowledgments

- [Patrick Collins](https://twitter.com/PatrickAlphaC) - Cyfrin Updraft course
- [Foundry Book](https://book.getfoundry.sh/)
- [MakerDAO](https://makerdao.com/) - Inspiration for stablecoin mechanics
- [Encode Club](https://www.encode.club/) - Bootcamp education

## Contact

- GitHub: [@usetech-nick](https://github.com/usetech-nick)
- Twitter: [@Nishant18335767](https://twitter.com/Nishant18335767)
- LinkedIn: [Nishant Kumar](https://linkedin.com/in/nishant-kumar-67a876284)

---

**⚠️ Disclaimer**: This is an educational project. Do not use in production without a professional audit.
