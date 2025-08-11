# Sui.fun - Bonding Curve Token Marketplace

Sui.fun is a bonding curve Token Marketplace built on the Sui blockchain that allows for creation of various types of coins and enables trading between them using an innovative bonding curve mechanism.

## Bonding Curve Implementation

### Curve Type: Constant Product AMM with Virtual Reserves

The marketplace uses a **Constant Product AMM (Automated Market Maker) bonding curve** with virtual reserves.

### Mathematical Formula

The bonding curve follows the constant product formula:

**For Buying Tokens:**
```
SUI Cost = (Token Amount × Virtual SUI Reserves) / (Virtual Token Reserves - Token Amount) + 1
```

**For Selling Tokens:**
```
SUI Output = (Token Amount × Virtual SUI Reserves) / (Virtual Token Reserves + Token Amount)
```

**Tokens Received for SUI:**
```
Tokens Out = (Virtual Token Reserves × SUI Input) / (Virtual SUI Reserves + SUI Input)
```

### Virtual Reserves System

The curve maintains two types of reserves:

1. **Virtual Reserves**: Fixed parameters that determine the curve's shape and initial pricing
   - `virtual_token_reserves`: Initial virtual token supply (1,000,000,000,000)
   - `virtual_sui_reserves`: Initial virtual SUI reserves (30,000,000,000)

2. **Real Reserves**: Actual balances that change with trades
   - `real_token_reserves`: Actual tokens in the curve
   - `real_sui_reserves`: Actual SUI in the curve
