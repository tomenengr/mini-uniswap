import { getAddress, type Address, type PublicClient } from 'viem';
import { contracts, erc20Abi, faucetAbi, oracleAbi, pairAbi, routerAbi, tokens } from './contracts';
import { formatTokenAmount, getAmountOut, quote } from './amounts';

export type DemoState = {
  reserveA: bigint;
  reserveB: bigint;
  reserveTimestamp: number;
  lpTotalSupply: bigint;
  wallet?: {
    dta: bigint;
    dtb: bigint;
    lp: bigint;
    dtaAllowance: bigint;
    dtbAllowance: bigint;
    lpAllowance: bigint;
  };
  oracle: {
    period: bigint;
    blockTimestampLast: number;
    price0Average: bigint;
    price1Average: bigint;
    dtaQuote?: bigint;
    dtbQuote?: bigint;
  };
  faucet: {
    balanceA: bigint;
    balanceB: bigint;
    amountA: bigint;
    amountB: bigint;
    paused: boolean;
    claimed?: boolean;
  };
};

export async function readDemoState(client: PublicClient, account?: Address): Promise<DemoState> {
  const [
    reserves,
    lpTotalSupply,
    period,
    oracleTimestamp,
    price0Average,
    price1Average,
    faucetBalanceA,
    faucetBalanceB,
    faucetAmountA,
    faucetAmountB,
    faucetPaused
  ] = await Promise.all([
    client.readContract({ address: contracts.pair, abi: pairAbi, functionName: 'getReserves' }),
    client.readContract({ address: contracts.pair, abi: pairAbi, functionName: 'totalSupply' }),
    client.readContract({ address: contracts.oracle, abi: oracleAbi, functionName: 'period' }),
    client.readContract({ address: contracts.oracle, abi: oracleAbi, functionName: 'blockTimestampLast' }),
    client.readContract({ address: contracts.oracle, abi: oracleAbi, functionName: 'price0Average' }),
    client.readContract({ address: contracts.oracle, abi: oracleAbi, functionName: 'price1Average' }),
    client.readContract({ address: tokens.DTA.address, abi: erc20Abi, functionName: 'balanceOf', args: [contracts.faucet] }),
    client.readContract({ address: tokens.DTB.address, abi: erc20Abi, functionName: 'balanceOf', args: [contracts.faucet] }),
    client.readContract({ address: contracts.faucet, abi: faucetAbi, functionName: 'amountA' }),
    client.readContract({ address: contracts.faucet, abi: faucetAbi, functionName: 'amountB' }),
    client.readContract({ address: contracts.faucet, abi: faucetAbi, functionName: 'paused' })
  ]);

  const [reserve0, reserve1, reserveTimestamp] = reserves;
  const token0IsDta = getAddress(tokens.DTA.address).toLowerCase() < getAddress(tokens.DTB.address).toLowerCase();
  const reserveA = token0IsDta ? reserve0 : reserve1;
  const reserveB = token0IsDta ? reserve1 : reserve0;
  const oracleReads = await Promise.allSettled([
    client.readContract({
      address: contracts.oracle,
      abi: oracleAbi,
      functionName: 'consult',
      args: [tokens.DTA.address, 10n ** 18n]
    }),
    client.readContract({
      address: contracts.oracle,
      abi: oracleAbi,
      functionName: 'consult',
      args: [tokens.DTB.address, 10n ** 18n]
    })
  ]);

  const wallet = account
    ? await readWalletState(client, account)
    : undefined;
  const faucetClaimed = account
    ? await client.readContract({ address: contracts.faucet, abi: faucetAbi, functionName: 'claimed', args: [account] })
    : undefined;

  return {
    reserveA,
    reserveB,
    reserveTimestamp,
    lpTotalSupply,
    wallet,
    oracle: {
      period,
      blockTimestampLast: oracleTimestamp,
      price0Average,
      price1Average,
      dtaQuote: oracleReads[0].status === 'fulfilled' ? oracleReads[0].value : undefined,
      dtbQuote: oracleReads[1].status === 'fulfilled' ? oracleReads[1].value : undefined
    },
    faucet: {
      balanceA: faucetBalanceA,
      balanceB: faucetBalanceB,
      amountA: faucetAmountA,
      amountB: faucetAmountB,
      paused: faucetPaused,
      claimed: faucetClaimed
    }
  };
}

async function readWalletState(client: PublicClient, account: Address): Promise<DemoState['wallet']> {
  const [dta, dtb, lp, dtaAllowance, dtbAllowance, lpAllowance] = await Promise.all([
    client.readContract({ address: tokens.DTA.address, abi: erc20Abi, functionName: 'balanceOf', args: [account] }),
    client.readContract({ address: tokens.DTB.address, abi: erc20Abi, functionName: 'balanceOf', args: [account] }),
    client.readContract({ address: contracts.pair, abi: pairAbi, functionName: 'balanceOf', args: [account] }),
    client.readContract({
      address: tokens.DTA.address,
      abi: erc20Abi,
      functionName: 'allowance',
      args: [account, contracts.router]
    }),
    client.readContract({
      address: tokens.DTB.address,
      abi: erc20Abi,
      functionName: 'allowance',
      args: [account, contracts.router]
    }),
    client.readContract({
      address: contracts.pair,
      abi: pairAbi,
      functionName: 'allowance',
      args: [account, contracts.router]
    })
  ]);
  return { dta, dtb, lp, dtaAllowance, dtbAllowance, lpAllowance };
}

export function estimateSwapOut(symbolIn: 'DTA' | 'DTB', amountIn: bigint, state?: DemoState): bigint {
  if (!state) return 0n;
  return symbolIn === 'DTA'
    ? getAmountOut(amountIn, state.reserveA, state.reserveB)
    : getAmountOut(amountIn, state.reserveB, state.reserveA);
}

export function estimateLiquidityCounterpart(symbol: 'DTA' | 'DTB', amount: bigint, state?: DemoState): bigint {
  if (!state) return 0n;
  return symbol === 'DTA'
    ? quote(amount, state.reserveA, state.reserveB)
    : quote(amount, state.reserveB, state.reserveA);
}

export function stateRows(state?: DemoState): Array<[string, string]> {
  return [
    ['DTA reserve', formatTokenAmount(state?.reserveA)],
    ['DTB reserve', formatTokenAmount(state?.reserveB)],
    ['LP supply', formatTokenAmount(state?.lpTotalSupply)],
    ['Last reserve timestamp', state?.reserveTimestamp ? String(state.reserveTimestamp) : '-']
  ];
}

export { erc20Abi, faucetAbi, oracleAbi, pairAbi, routerAbi };
