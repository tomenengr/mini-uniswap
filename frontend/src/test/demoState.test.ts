import { describe, expect, it } from 'vitest';
import { estimateLiquidityCounterpart, estimateSwapOut, type DemoState } from '../lib/demoState';

const state = {
  reserveA: 1010n * 10n ** 18n,
  reserveB: 990128419656029387012n,
  reserveTimestamp: 1778943636,
  lpTotalSupply: 1000n * 10n ** 18n,
  oracle: {
    period: 600n,
    blockTimestampLast: 1778943636,
    price0Average: 0n,
    price1Average: 0n
  },
  faucet: {
    balanceA: 10000n * 10n ** 18n,
    balanceB: 10000n * 10n ** 18n,
    amountA: 100n * 10n ** 18n,
    amountB: 100n * 10n ** 18n,
    paused: false,
    claimed: false
  }
} satisfies DemoState;

describe('demo state projections', () => {
  it('estimates DTA to DTB swaps from DTA/DTB reserves', () => {
    expect(estimateSwapOut('DTA', 10n * 10n ** 18n, state)).toBeGreaterThan(0n);
  });

  it('estimates liquidity counterpart using display token order', () => {
    const counterpart = estimateLiquidityCounterpart('DTA', 10n * 10n ** 18n, state);
    expect(counterpart).toBe(9803251679762667198n);
  });
});
