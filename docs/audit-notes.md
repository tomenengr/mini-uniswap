# Audit Notes

This document records known risks, design limits, and review notes for Mini Uniswap V2.

The project is educational and has not been audited. It must not be used with real funds.

## Scope

Reviewed components:

- `Factory.sol`
- `Pair.sol`
- `Router.sol`
- `Library.sol`
- `TransferHelper.sol`
- ERC20 and LP token helpers

Out of scope:

- Mainnet deployment readiness
- Formal verification
- Gas optimization review
- Economic attack simulation
- Production oracle design

## Known Limitations

### Not Production Ready

The implementation is intentionally simplified. It is useful for learning AMM mechanics, but it does not include the full hardening expected from production DeFi contracts.

### Simplified Token Assumptions

The Router and Pair assume standard ERC20 behavior. Fee-on-transfer, rebasing, pausable, blacklist, callback-heavy, or non-standard ERC20 tokens are not supported.

Impact:

- Actual received amounts may differ from requested transfer amounts.
- Reserve accounting may become inaccurate.
- Router amount calculations may be invalid.

### ETH/WETH Paths Need More Testing

The Router includes ETH/WETH liquidity functions, but the current test suite focuses on pure ERC20 flows. ETH/WETH tests should be added with a WETH mock before treating those paths as complete.

### Oracle / TWAP Is Not Production Complete

`Pair.sol` includes cumulative price fields, but this project does not implement a full production oracle integration.

Missing pieces include:

- Consumer-facing TWAP library
- Manipulation-resistance analysis
- Windowing strategy
- Tests across block timestamps and reserve changes

### Flash Swap Callback Risk

`swap` supports callback data and calls `uniswapV2Call` when `data.length > 0`.

The Pair performs invariant checks after the callback, which is the core safety pattern, but the broader flash swap flow still needs focused tests:

- valid repayment
- underpayment revert
- callback receiver behavior
- reentrancy assumptions

### Protocol Fee Path Needs Dedicated Tests

`Pair._mintFee` supports the `feeTo` protocol fee path, but the current test suite does not deeply cover:

- `kLast` updates
- fee-on versus fee-off transitions
- protocol LP minting amount
- behavior after swaps and liquidity changes

### Permit Is Present But Not Covered

`UniERC20` includes a `permit` implementation for LP tokens. This is not yet tested.

Recommended tests:

- valid EIP-712 signature
- expired permit
- invalid signer
- nonce replay prevention

### Minimal Access Control

The Factory restricts `setFeeTo` and `setFeeToSetter` to `feeToSetter`. There is no timelock, multisig, or governance delay. This is acceptable for a learning project but insufficient for production governance.

## Implemented Safety Checks

### Pair Reentrancy Lock

Pair state-changing functions use a simple lock:

```solidity
modifier lock()
```

Covered functions include:

- `mint`
- `burn`
- `swap`
- `skim`
- `sync`

### Swap Invariant Check

Swaps enforce the fee-adjusted constant product invariant:

```text
balance0Adjusted * balance1Adjusted >= reserve0 * reserve1 * 1000^2
```

The test suite includes a revert case for breaking K.

### Router Deadline Checks

Router user-facing operations use:

```solidity
modifier ensure(uint256 deadline)
```

Expired operations revert with `expired`.

### Router Slippage Checks

The Router validates minimum outputs and maximum inputs:

- add liquidity minimum token amounts
- remove liquidity minimum token amounts
- exact-input minimum output
- exact-output maximum input

### CREATE2 Pair Determinism

`Factory.createPair` and `Library.pairFor` share the same salt and init code hash logic. Tests verify that predicted Pair addresses match deployed Pair addresses.

## Recommended Next Reviews

1. Add ETH/WETH integration tests with a WETH mock.
2. Add protocol fee tests for `feeTo` and `kLast`.
3. Add LP `permit` tests.
4. Add fuzz tests for `Library.getAmountOut`, `getAmountIn`, and Router paths.
5. Add invariant tests for reserve/balance consistency and K behavior.
6. Review revert messages and normalize naming style across contracts.
7. Add deployment scripts only after the test suite and documentation are stable.

