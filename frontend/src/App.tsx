import { useCallback, useEffect, useMemo, useState, type ReactNode } from 'react';
import { type Address } from 'viem';
import { applySlippageMin, formatTokenAmount, isPositiveInput, parseTokenAmount } from './lib/amounts';
import { contracts, erc20Abi, explorerBaseUrl, faucetAbi, oracleAbi, routerAbi, SEPOLIA_CHAIN_ID, tokens, type TokenSymbol } from './lib/contracts';
import { estimateLiquidityCounterpart, estimateSwapOut, readDemoState, stateRows, type DemoState } from './lib/demoState';
import { getWalletChainId, makePublicClient, makeWalletClient, requestAccounts, requestSepoliaSwitch } from './lib/wallet';

type TxStatus = {
  label: string;
  hash?: string;
};

export default function App() {
  const [account, setAccount] = useState<Address>();
  const [chainId, setChainId] = useState<number>();
  const [state, setState] = useState<DemoState>();
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState<string>();
  const [txStatus, setTxStatus] = useState<TxStatus>();

  const [swapTokenIn, setSwapTokenIn] = useState<TokenSymbol>('DTA');
  const [swapAmount, setSwapAmount] = useState('1');
  const [liquidityA, setLiquidityA] = useState('1');
  const [liquidityB, setLiquidityB] = useState('1');
  const [removeLp, setRemoveLp] = useState('');
  const [approveDta, setApproveDta] = useState('10');
  const [approveDtb, setApproveDtb] = useState('10');
  const [approveLp, setApproveLp] = useState('1');

  const publicClient = useMemo(() => makePublicClient(window.ethereum), []);
  const wrongNetwork = chainId !== undefined && chainId !== SEPOLIA_CHAIN_ID;

  const refresh = useCallback(async () => {
    setLoading(true);
    setError(undefined);
    try {
      setChainId(await getWalletChainId());
      setState(await readDemoState(publicClient, account));
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setLoading(false);
    }
  }, [account, publicClient]);

  useEffect(() => {
    void refresh();
  }, [refresh]);

  useEffect(() => {
    if (!window.ethereum) return;
    const onAccountsChanged = (accounts: unknown) => {
      const next = Array.isArray(accounts) ? (accounts[0] as Address | undefined) : undefined;
      setAccount(next);
    };
    const onChainChanged = () => {
      void getWalletChainId().then(setChainId).catch(() => setChainId(undefined));
    };
    window.ethereum.on?.('accountsChanged', onAccountsChanged);
    window.ethereum.on?.('chainChanged', onChainChanged);
    return () => {
      window.ethereum?.removeListener?.('accountsChanged', onAccountsChanged);
      window.ethereum?.removeListener?.('chainChanged', onChainChanged);
    };
  }, []);

  const connect = async () => {
    setError(undefined);
    try {
      const accounts = await requestAccounts();
      setAccount(accounts[0]);
      setChainId(await getWalletChainId());
    } catch (err) {
      setError(errorMessage(err));
    }
  };

  const runTx = async (label: string, action: () => Promise<`0x${string}`>) => {
    if (!account) {
      setError('Connect a Sepolia wallet first.');
      return;
    }
    if (wrongNetwork) {
      setError('Switch wallet to Sepolia before sending a transaction.');
      return;
    }
    setError(undefined);
    setTxStatus({ label: `${label}: waiting for wallet` });
    try {
      const hash = await action();
      setTxStatus({ label: `${label}: pending`, hash });
      await publicClient.waitForTransactionReceipt({ hash });
      setTxStatus({ label: `${label}: confirmed`, hash });
      await refresh();
    } catch (err) {
      setError(errorMessage(err));
      setTxStatus(undefined);
    }
  };

  const approve = async (token: TokenSymbol | 'LP', amount: bigint) => {
    await runTx(`Approve ${token}`, async () => {
      const wallet = makeWalletClient(account!);
      const address = token === 'LP' ? contracts.pair : tokens[token].address;
      return wallet.writeContract({
        address,
        abi: erc20Abi,
        functionName: 'approve',
        args: [contracts.router, amount]
      });
    });
  };

  const swapAmountIn = safeParse(swapAmount);
  const swapOut = estimateSwapOut(swapTokenIn, swapAmountIn, state);
  const swapTokenOut: TokenSymbol = swapTokenIn === 'DTA' ? 'DTB' : 'DTA';
  const swapWalletBalance = state?.wallet?.[swapTokenIn.toLowerCase() as 'dta' | 'dtb'] ?? 0n;
  const swapAllowance = state?.wallet?.[`${swapTokenIn.toLowerCase()}Allowance` as 'dtaAllowance' | 'dtbAllowance'] ?? 0n;
  const needsSwapApproval = swapAmountIn > 0n && swapAllowance < swapAmountIn;
  const canSwap = Boolean(account && !wrongNetwork && swapAmountIn > 0n && swapOut > 0n && swapWalletBalance >= swapAmountIn && !needsSwapApproval);

  const doSwap = async () => {
    await runTx('Swap', async () => {
      const wallet = makeWalletClient(account!);
      return wallet.writeContract({
        address: contracts.router,
        abi: routerAbi,
        functionName: 'swapExactTokensForTokens',
        args: [
          swapAmountIn,
          applySlippageMin(swapOut),
          [tokens[swapTokenIn].address, tokens[swapTokenOut].address],
          account!,
          deadline()
        ]
      });
    });
  };

  const liquidityAmountA = safeParse(liquidityA);
  const liquidityAmountB = safeParse(liquidityB);
  const suggestedB = estimateLiquidityCounterpart('DTA', liquidityAmountA, state);
  const needsDtaApproval = liquidityAmountA > 0n && (state?.wallet?.dtaAllowance ?? 0n) < liquidityAmountA;
  const needsDtbApproval = liquidityAmountB > 0n && (state?.wallet?.dtbAllowance ?? 0n) < liquidityAmountB;
  const hasLiquidityBalances =
    (state?.wallet?.dta ?? 0n) >= liquidityAmountA && (state?.wallet?.dtb ?? 0n) >= liquidityAmountB;
  const canAddLiquidity = Boolean(
    account &&
      !wrongNetwork &&
      liquidityAmountA > 0n &&
      liquidityAmountB > 0n &&
      hasLiquidityBalances &&
      !needsDtaApproval &&
      !needsDtbApproval
  );

  const addLiquidity = async () => {
    await runTx('Add liquidity', async () => {
      const wallet = makeWalletClient(account!);
      return wallet.writeContract({
        address: contracts.router,
        abi: routerAbi,
        functionName: 'addLiquidity',
        args: [
          tokens.DTA.address,
          tokens.DTB.address,
          liquidityAmountA,
          liquidityAmountB,
          applySlippageMin(liquidityAmountA),
          applySlippageMin(liquidityAmountB),
          account!,
          deadline()
        ]
      });
    });
  };

  const removeAmount = safeParse(removeLp);
  const needsLpApproval = removeAmount > 0n && (state?.wallet?.lpAllowance ?? 0n) < removeAmount;
  const canRemoveLiquidity = Boolean(
    account && !wrongNetwork && removeAmount > 0n && (state?.wallet?.lp ?? 0n) >= removeAmount && !needsLpApproval
  );

  const removeLiquidity = async () => {
    await runTx('Remove liquidity', async () => {
      const wallet = makeWalletClient(account!);
      return wallet.writeContract({
        address: contracts.router,
        abi: routerAbi,
        functionName: 'removeLiquidity',
        args: [
          tokens.DTA.address,
          tokens.DTB.address,
          removeAmount,
          0n,
          0n,
          account!,
          deadline()
        ]
      });
    });
  };

  const updateOracle = async () => {
    await runTx('Oracle update', async () => {
      const wallet = makeWalletClient(account!);
      return wallet.writeContract({
        address: contracts.oracle,
        abi: oracleAbi,
        functionName: 'update'
      });
    });
  };

  const canClaim = Boolean(
    account &&
      !wrongNetwork &&
      state &&
      !state.faucet.paused &&
      !state.faucet.claimed &&
      state.faucet.balanceA >= state.faucet.amountA &&
      state.faucet.balanceB >= state.faucet.amountB
  );

  const claimTokens = async () => {
    await runTx('Claim demo tokens', async () => {
      const wallet = makeWalletClient(account!);
      return wallet.writeContract({
        address: contracts.faucet,
        abi: faucetAbi,
        functionName: 'claim'
      });
    });
  };

  return (
    <main className="app-shell">
      <section className="topbar">
        <div>
          <p className="eyebrow">Sepolia · Mini Uniswap V2</p>
          <h1>DTA / DTB Demo</h1>
        </div>
        <div className="wallet-box">
          {account ? <code>{shortAddress(account)}</code> : <button onClick={connect}>Connect wallet</button>}
          {wrongNetwork ? <button onClick={() => void requestSepoliaSwitch().then(refresh).catch((err) => setError(errorMessage(err)))}>Switch Sepolia</button> : null}
          <button className="secondary" onClick={() => void refresh()} disabled={loading}>
            {loading ? 'Refreshing' : 'Refresh'}
          </button>
        </div>
      </section>

      {error ? <div className="banner error">{error}</div> : null}
      {txStatus ? (
        <div className="banner">
          {txStatus.label}
          {txStatus.hash ? (
            <a href={`${explorerBaseUrl}/tx/${txStatus.hash}`} target="_blank" rel="noreferrer">
              View tx
            </a>
          ) : null}
        </div>
      ) : null}
      {!account ? <div className="banner">Read-only mode. Connect a Sepolia wallet to approve and send demo transactions.</div> : null}
      {wrongNetwork ? <div className="banner error">Wallet is not on Sepolia. Chain ID: {chainId ?? '-'}</div> : null}

      <section className="grid two">
        <Panel title="Demo faucet">
          <DataGrid
            rows={[
              ['Claim amount', `${formatTokenAmount(state?.faucet.amountA)} DTA + ${formatTokenAmount(state?.faucet.amountB)} DTB`],
              ['Faucet DTA', formatTokenAmount(state?.faucet.balanceA)],
              ['Faucet DTB', formatTokenAmount(state?.faucet.balanceB)],
              ['Your status', faucetStatus(state, account)]
            ]}
          />
          <button onClick={() => void claimTokens()} disabled={!canClaim}>Claim demo tokens</button>
          <p className="hint">{faucetHint(state, account, wrongNetwork)}</p>
        </Panel>

        <Panel title="Pool">
          <DataGrid rows={stateRows(state)} />
          <div className="price-row">
            <span>Spot price</span>
            <strong>1 DTA = {formatTokenAmount(estimateSwapOut('DTA', 10n ** 18n, state), 18, 6)} DTB</strong>
          </div>
        </Panel>

        <Panel title="Wallet">
          <DataGrid
            rows={[
              ['DTA balance', formatTokenAmount(state?.wallet?.dta)],
              ['DTB balance', formatTokenAmount(state?.wallet?.dtb)],
              ['LP balance', formatTokenAmount(state?.wallet?.lp)],
              ['DTA allowance', formatTokenAmount(state?.wallet?.dtaAllowance)],
              ['DTB allowance', formatTokenAmount(state?.wallet?.dtbAllowance)],
              ['LP allowance', formatTokenAmount(state?.wallet?.lpAllowance)]
            ]}
          />
        </Panel>
      </section>

      <section className="grid two">
        <Panel title="Allowances">
          <div className="approval-grid">
            <ApproveRow
              label="DTA"
              value={approveDta}
              allowance={state?.wallet?.dtaAllowance}
              disabled={!account || wrongNetwork || !isPositiveInput(approveDta)}
              onChange={setApproveDta}
              onApprove={() => void approve('DTA', safeParse(approveDta))}
            />
            <ApproveRow
              label="DTB"
              value={approveDtb}
              allowance={state?.wallet?.dtbAllowance}
              disabled={!account || wrongNetwork || !isPositiveInput(approveDtb)}
              onChange={setApproveDtb}
              onApprove={() => void approve('DTB', safeParse(approveDtb))}
            />
            <ApproveRow
              label="LP"
              value={approveLp}
              allowance={state?.wallet?.lpAllowance}
              disabled={!account || wrongNetwork || !isPositiveInput(approveLp)}
              onChange={setApproveLp}
              onApprove={() => void approve('LP', safeParse(approveLp))}
            />
          </div>
          <p className="hint">Approve only the amount you want Router to spend. Swaps and liquidity actions consume this allowance.</p>
        </Panel>
      </section>

      <section className="grid three">
        <Panel title="Swap">
          <div className="row">
            <select value={swapTokenIn} onChange={(event) => setSwapTokenIn(event.target.value as TokenSymbol)}>
              <option value="DTA">DTA to DTB</option>
              <option value="DTB">DTB to DTA</option>
            </select>
            <input value={swapAmount} onChange={(event) => setSwapAmount(event.target.value)} inputMode="decimal" />
          </div>
          <p className="muted">Estimated out: {formatTokenAmount(swapOut)} {swapTokenOut}</p>
          <button onClick={() => void doSwap()} disabled={!canSwap}>Swap</button>
          <p className="hint">{swapHint(canSwap, needsSwapApproval, swapWalletBalance, swapAmountIn)}</p>
        </Panel>

        <Panel title="Add liquidity">
          <label>DTA</label>
          <input value={liquidityA} onChange={(event) => setLiquidityA(event.target.value)} inputMode="decimal" />
          <label>DTB</label>
          <input value={liquidityB} onChange={(event) => setLiquidityB(event.target.value)} inputMode="decimal" />
          <p className="muted">Pool ratio suggests {formatTokenAmount(suggestedB)} DTB for this DTA amount.</p>
          <button onClick={() => void addLiquidity()} disabled={!canAddLiquidity}>Add liquidity</button>
          <p className="hint">{liquidityHint(hasLiquidityBalances, needsDtaApproval, needsDtbApproval)}</p>
        </Panel>

        <Panel title="Remove liquidity">
          <label>LP amount</label>
          <input value={removeLp} onChange={(event) => setRemoveLp(event.target.value)} inputMode="decimal" placeholder="0.0" />
          <p className="muted">Your LP: {formatTokenAmount(state?.wallet?.lp)}</p>
          <button onClick={() => void removeLiquidity()} disabled={!canRemoveLiquidity}>Remove liquidity</button>
          <p className="hint">{removeHint(needsLpApproval)}</p>
        </Panel>
      </section>

      <section className="grid two">
        <Panel title="TWAP Oracle">
          <DataGrid
            rows={[
              ['Period', `${state?.oracle.period ?? '-'} sec`],
              ['Last update', state?.oracle.blockTimestampLast ? String(state.oracle.blockTimestampLast) : '-'],
              ['1 DTA TWAP', state?.oracle.dtaQuote ? `${formatTokenAmount(state.oracle.dtaQuote, 18, 6)} DTB` : 'missing average'],
              ['1 DTB TWAP', state?.oracle.dtbQuote ? `${formatTokenAmount(state.oracle.dtbQuote, 18, 6)} DTA` : 'missing average']
            ]}
          />
          <button onClick={() => void updateOracle()} disabled={!account || wrongNetwork}>Update oracle</button>
        </Panel>

        <Panel title="Contracts">
          <AddressLinks />
        </Panel>
      </section>
    </main>
  );
}

function Panel({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="panel">
      <h2>{title}</h2>
      {children}
    </section>
  );
}

function DataGrid({ rows }: { rows: Array<[string, string]> }) {
  return (
    <dl className="data-grid">
      {rows.map(([label, value]) => (
        <div key={label}>
          <dt>{label}</dt>
          <dd>{value}</dd>
        </div>
      ))}
    </dl>
  );
}

function ApproveRow({
  label,
  value,
  allowance,
  disabled,
  onChange,
  onApprove
}: {
  label: string;
  value: string;
  allowance: bigint | undefined;
  disabled: boolean;
  onChange: (value: string) => void;
  onApprove: () => void;
}) {
  return (
    <div className="approve-row">
      <label>{label}</label>
      <input value={value} onChange={(event) => onChange(event.target.value)} inputMode="decimal" />
      <button onClick={onApprove} disabled={disabled}>Approve {label}</button>
      <span>Current allowance: {formatTokenAmount(allowance)}</span>
    </div>
  );
}

function AddressLinks() {
  const entries = [
    ['Router', contracts.router],
    ['Factory', contracts.factory],
    ['DTA', contracts.tokenA],
    ['DTB', contracts.tokenB],
    ['Pair', contracts.pair],
    ['Oracle', contracts.oracle],
    ['Faucet', contracts.faucet]
  ] as const;
  return (
    <div className="address-list">
      {entries.map(([label, address]) => (
        <a key={label} href={`${explorerBaseUrl}/address/${address}`} target="_blank" rel="noreferrer">
          <span>{label}</span>
          <code>{shortAddress(address)}</code>
        </a>
      ))}
    </div>
  );
}

function safeParse(value: string): bigint {
  try {
    return parseTokenAmount(value);
  } catch {
    return 0n;
  }
}

function deadline(): bigint {
  return BigInt(Math.floor(Date.now() / 1000) + 20 * 60);
}

function shortAddress(address: string): string {
  return `${address.slice(0, 6)}...${address.slice(-4)}`;
}

function errorMessage(err: unknown): string {
  if (err instanceof Error) return err.message;
  return String(err);
}

function swapHint(canSwap: boolean, needsApproval: boolean, balance: bigint, amount: bigint): string {
  if (needsApproval) return 'Increase allowance in the Allowances panel before swapping.';
  if (canSwap) return 'Uses 0.5% slippage protection.';
  if (amount <= 0n) return 'Enter a positive amount.';
  if (balance < amount) return 'Insufficient token balance for this wallet.';
  return 'Connect wallet and use Sepolia to swap.';
}

function liquidityHint(hasBalances: boolean, needsDtaApproval: boolean, needsDtbApproval: boolean): string {
  if (!hasBalances) return 'Insufficient DTA or DTB balance.';
  if (needsDtaApproval && needsDtbApproval) return 'Increase DTA and DTB allowances in the Allowances panel.';
  if (needsDtaApproval) return 'Increase DTA allowance in the Allowances panel.';
  if (needsDtbApproval) return 'Increase DTB allowance in the Allowances panel.';
  return 'Uses 0.5% slippage min amounts.';
}

function removeHint(needsLpApproval: boolean): string {
  if (needsLpApproval) return 'Increase LP allowance in the Allowances panel.';
  return 'Removal uses zero minimums for demo simplicity.';
}

function faucetStatus(state: DemoState | undefined, account: Address | undefined): string {
  if (!account) return 'wallet not connected';
  if (!state) return '-';
  if (state.faucet.paused) return 'paused';
  return state.faucet.claimed ? 'already claimed' : 'available';
}

function faucetHint(state: DemoState | undefined, account: Address | undefined, wrongNetwork: boolean): string {
  if (!account) return 'Connect a Sepolia wallet to claim DTA and DTB.';
  if (wrongNetwork) return 'Switch to Sepolia before claiming.';
  if (!state) return 'Loading faucet status.';
  if (state.faucet.paused) return 'Faucet is paused.';
  if (state.faucet.claimed) return 'This wallet has already claimed demo tokens.';
  if (state.faucet.balanceA < state.faucet.amountA || state.faucet.balanceB < state.faucet.amountB) {
    return 'Faucet needs more DTA or DTB before new claims.';
  }
  return 'Each wallet can claim once.';
}
