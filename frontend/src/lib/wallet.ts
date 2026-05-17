import {
  createPublicClient,
  createWalletClient,
  custom,
  fallback,
  http,
  type Address,
  type EIP1193Provider
} from 'viem';
import { sepolia } from 'viem/chains';
import { SEPOLIA_CHAIN_ID_HEX } from './contracts';

declare global {
  interface Window {
    ethereum?: EIP1193Provider;
  }
}

const rpcUrl = import.meta.env.VITE_SEPOLIA_RPC_URL as string | undefined;

export function makePublicClient(provider?: EIP1193Provider) {
  const transports = [];
  if (provider) transports.push(custom(provider));
  if (rpcUrl) transports.push(http(rpcUrl));
  transports.push(http());

  return createPublicClient({
    chain: sepolia,
    transport: fallback(transports)
  });
}

export function makeWalletClient(account: Address) {
  if (!window.ethereum) throw new Error('No injected wallet found');
  return createWalletClient({
    account,
    chain: sepolia,
    transport: custom(window.ethereum)
  });
}

export async function requestAccounts(): Promise<Address[]> {
  if (!window.ethereum) throw new Error('Please install MetaMask or another EIP-1193 wallet.');
  return (await window.ethereum.request({ method: 'eth_requestAccounts' })) as Address[];
}

export async function getWalletChainId(): Promise<number | undefined> {
  if (!window.ethereum) return undefined;
  const chainId = (await window.ethereum.request({ method: 'eth_chainId' })) as string;
  return Number.parseInt(chainId, 16);
}

export async function requestSepoliaSwitch(): Promise<void> {
  if (!window.ethereum) throw new Error('No injected wallet found');
  await window.ethereum.request({
    method: 'wallet_switchEthereumChain',
    params: [{ chainId: SEPOLIA_CHAIN_ID_HEX }]
  });
}
