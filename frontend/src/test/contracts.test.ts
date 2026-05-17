import { describe, expect, it } from 'vitest';
import { getAddress } from 'viem';
import { contracts, SEPOLIA_CHAIN_ID, tokens } from '../lib/contracts';

describe('Sepolia contract config', () => {
  it('uses the expected Sepolia chain id', () => {
    expect(SEPOLIA_CHAIN_ID).toBe(11155111);
  });

  it('contains valid checksum-able addresses', () => {
    for (const address of Object.values(contracts)) {
      expect(getAddress(address)).toMatch(/^0x[a-fA-F0-9]{40}$/);
    }
  });

  it('keeps demo token symbols mapped to the deployed addresses', () => {
    expect(tokens.DTA.address).toBe(contracts.tokenA);
    expect(tokens.DTB.address).toBe(contracts.tokenB);
  });
});
