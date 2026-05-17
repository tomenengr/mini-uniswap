import { describe, expect, it } from 'vitest';
import { applySlippageMin, formatTokenAmount, getAmountOut, parseTokenAmount, quote } from '../lib/amounts';

describe('amount helpers', () => {
  it('parses and formats 18 decimal token amounts', () => {
    const value = parseTokenAmount('12.3456789');
    expect(value).toBe(12345678900000000000n);
    expect(formatTokenAmount(value, 18, 4)).toBe('12.3456');
  });

  it('rejects invalid input strings', () => {
    expect(() => parseTokenAmount('1.2.3')).toThrow('Invalid amount');
    expect(() => parseTokenAmount('abc')).toThrow('Invalid amount');
  });

  it('uses Uniswap V2 0.3% fee math for exact input swaps', () => {
    const out = getAmountOut(10n * 10n ** 18n, 1000n * 10n ** 18n, 1000n * 10n ** 18n);
    expect(out).toBe(9871580343970612988n);
  });

  it('applies default 0.5% slippage minimum', () => {
    expect(applySlippageMin(10000n)).toBe(9950n);
  });

  it('quotes liquidity counterpart by reserve ratio', () => {
    expect(quote(5n, 10n, 20n)).toBe(10n);
  });
});
