# Design Notes

Mini Uniswap V2 is a simplified Uniswap V2-style AMM implemented with Solidity and Foundry. The goal is to keep the core mechanics visible: deterministic pair deployment, LP token minting and burning, constant-product swaps, reserve accounting, and router-level slippage checks.

This project is for learning and portfolio demonstration. It is not production-ready.

## Architecture

The system is split into four core layers:

| Layer | Contract | Responsibility |
| --- | --- | --- |
| Factory | `Factory.sol` | Creates token pairs with CREATE2 and records pair addresses |
| Pair | `Pair.sol` | Holds token reserves, mints/burns LP tokens, executes swaps |
| Router | `Router.sol` | User-facing entry point for liquidity and swap flows |
| Library | `Library.sol` | Pure/view helpers for sorting, address prediction, reserves, and pricing |

Typical flow:

```text
User -> Router -> Factory
              -> Pair
              -> ERC20 tokens
```

Users normally interact with the Router. The Router calculates optimal amounts, transfers tokens into the Pair, and calls Pair functions. The Pair remains the source of truth for balances, reserves, LP token supply, and swap invariant checks.

## Pair Creation

The Factory creates one Pair per token pair. Token order is normalized first:

```solidity
(token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
```

This guarantees that `getPair[tokenA][tokenB]` and `getPair[tokenB][tokenA]` resolve to the same Pair.

Pair deployment uses CREATE2:

```text
pair = address(keccak256(0xff ++ factory ++ salt ++ init_code_hash))
salt = keccak256(token0 ++ token1)
```

`Library.pairFor` mirrors the same formula, which lets the Router predict the Pair address without an external call to `getPair`.

## Reserves And Balances

Each Pair stores:

```solidity
uint112 reserve0;
uint112 reserve1;
uint32 blockTimestampLast;
```

The ERC20 token balances are the actual token holdings. The reserves are the last synchronized accounting values. Pair operations follow this pattern:

1. Read current token balances.
2. Compare balances with previous reserves.
3. Calculate input/output amounts.
4. Validate liquidity or invariant rules.
5. Update reserves to match balances.

`skim` transfers balances above reserves to a target address. `sync` updates reserves to match current balances.

## Liquidity Minting

Liquidity providers deposit both tokens directly into the Pair, then call `mint`.

For the first mint:

```text
liquidity = sqrt(amount0 * amount1) - MINIMUM_LIQUIDITY
```

`MINIMUM_LIQUIDITY` is permanently minted to `address(0)`. This follows the original Uniswap V2 design and prevents the first LP from fully removing all pool shares.

For later mints:

```text
liquidity = min(
    amount0 * totalSupply / reserve0,
    amount1 * totalSupply / reserve1
)
```

The lower side determines the LP amount. If a user deposits an imbalanced ratio, the extra balance remains in the Pair until handled by future operations or `skim`.

## Liquidity Burning

To remove liquidity, LP tokens are transferred to the Pair first, then `burn` is called.

```text
amount0 = liquidity * balance0 / totalSupply
amount1 = liquidity * balance1 / totalSupply
```

The Pair burns its own LP balance and sends the underlying tokens to the recipient. The Router wraps this flow by pulling LP tokens from the user, calling `burn`, translating token order, and checking minimum output amounts.

## Swap Formula

The AMM uses the constant-product model:

```text
x * y = k
```

For exact input swaps, the output is calculated with a 0.3% fee:

```text
amountInWithFee = amountIn * 997
amountOut = amountInWithFee * reserveOut / (reserveIn * 1000 + amountInWithFee)
```

For exact output swaps:

```text
amountIn = reserveIn * amountOut * 1000 / ((reserveOut - amountOut) * 997) + 1
```

The `+ 1` rounds up so the input is sufficient after integer division.

## K Invariant

The Pair validates swaps after token transfers. It calculates the real input amounts from the post-swap balances:

```text
amount0In = balance0 > reserve0 - amount0Out ? balance0 - (reserve0 - amount0Out) : 0
amount1In = balance1 > reserve1 - amount1Out ? balance1 - (reserve1 - amount1Out) : 0
```

Then it applies the fee-adjusted invariant:

```text
balance0Adjusted = balance0 * 1000 - amount0In * 3
balance1Adjusted = balance1 * 1000 - amount1In * 3

balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000^2
```

This is the core swap safety check.

## Router Behavior

The Router provides safer user-facing flows:

- `addLiquidity` creates the Pair if needed, calculates the optimal deposit ratio, pulls tokens, and mints LP tokens.
- `removeLiquidity` pulls LP tokens, burns them, maps token order, and checks minimum outputs.
- `swapExactTokensForTokens` supports exact-input swaps and output slippage checks.
- `swapTokensForExactTokens` supports exact-output swaps and input ceiling checks.
- `ensure(deadline)` rejects expired operations.

For multi-hop swaps, the output of each intermediate Pair is sent directly to the next Pair. Only the final output is sent to the user.

## Testing Strategy

The test suite is organized by module:

| Test | Scope |
| --- | --- |
| `Factory.t.sol` | Pair creation, duplicate checks, token order, fee setter permissions |
| `Library.t.sol` | Sorting, quote, swap math, path amount calculations |
| `Pair.t.sol` | Mint, burn, swap, invariant reverts, reserve updates, skim, sync |
| `Router.t.sol` | Add/remove liquidity, slippage, deadline, exact input/output swaps, multi-hop |
| `PairForAndReserves.t.sol` | CREATE2 pair prediction and reserve order mapping |

The current suite focuses on deterministic unit and integration tests. Future improvements should add fuzz tests and invariant tests for reserve/balance consistency and K preservation.

