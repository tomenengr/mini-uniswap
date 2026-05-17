import { formatUnits, parseUnits } from 'viem';

export const BPS = 10_000n;
export const DEFAULT_SLIPPAGE_BPS = 50n;

export function parseTokenAmount(value: string, decimals = 18): bigint {
  const trimmed = value.trim();
  if (!trimmed) return 0n;
  if (!/^\d*(\.\d*)?$/.test(trimmed) || trimmed === '.') {
    throw new Error('Invalid amount');
  }
  return parseUnits(trimmed, decimals);
}

export function formatTokenAmount(value: bigint | undefined, decimals = 18, precision = 4): string {
  if (value === undefined) return '-';
  const raw = formatUnits(value, decimals);
  const [whole, fraction = ''] = raw.split('.');
  const compactFraction = fraction.slice(0, precision).replace(/0+$/, '');
  return compactFraction ? `${whole}.${compactFraction}` : whole;
}

export function getAmountOut(amountIn: bigint, reserveIn: bigint, reserveOut: bigint): bigint {
  if (amountIn <= 0n || reserveIn <= 0n || reserveOut <= 0n) return 0n;
  const amountInWithFee = amountIn * 997n;
  return (amountInWithFee * reserveOut) / (reserveIn * 1000n + amountInWithFee);
}

export function applySlippageMin(amount: bigint, slippageBps = DEFAULT_SLIPPAGE_BPS): bigint {
  return (amount * (BPS - slippageBps)) / BPS;
}

export function quote(amountA: bigint, reserveA: bigint, reserveB: bigint): bigint {
  if (amountA <= 0n || reserveA <= 0n || reserveB <= 0n) return 0n;
  return (amountA * reserveB) / reserveA;
}

export function isPositiveInput(value: string): boolean {
  try {
    return parseTokenAmount(value) > 0n;
  } catch {
    return false;
  }
}
