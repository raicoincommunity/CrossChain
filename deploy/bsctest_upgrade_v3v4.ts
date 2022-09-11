import { ethers, network, upgrades } from "hardhat";
import { INVALID_DEPLOYED_ADDRESS, BSC_TEST_CONTRACTS } from './deployed';

async function main() {
  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 97) {
    console.error(`Chain ID mismatch: expected=97, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }

  const core = BSC_TEST_CONTRACTS.core;
  if ( core === INVALID_DEPLOYED_ADDRESS) {
    console.error('Core not deployed');
    process.exitCode = 1;
    return;
  }

  const prevImpl = await upgrades.erc1967.getImplementationAddress(core);
  const BSCTestV4 = await ethers.getContractFactory("BSCTestV4");
  const proxy = await upgrades.upgradeProxy(core, BSCTestV4,
    { kind: 'uups', useDeployedImplementation: true, call: 'initializeV4' });
  await proxy.deployTransaction.wait();
  const newImpl = await upgrades.erc1967.getImplementationAddress(core);
  console.log(`BSCTest upgrade V3 to V4: network=${network.name}, core=${core}, \
    previous implementation=${prevImpl}, new implementation=${newImpl}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});