import { ethers, network, upgrades } from "hardhat";
import { INVALID_DEPLOYED_ADDRESS, GOERLI_CONTRACTS } from './deployed';

async function main() {
  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 5) {
    console.error(`Chain ID mismatch: expected=5, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }

  const core = GOERLI_CONTRACTS.core;
  if ( core === INVALID_DEPLOYED_ADDRESS) {
    console.error('Core not deployed');
    process.exitCode = 1;
    return;
  }

  const prevImpl = await upgrades.erc1967.getImplementationAddress(core);
  const GoerliV2 = await ethers.getContractFactory("GoerliV2");
  const proxy = await upgrades.upgradeProxy(core, GoerliV2, { 
    kind: 'uups', useDeployedImplementation: true, call: 'initializeV2',
    unsafeAllowRenames: true
   });
  await proxy.deployTransaction.wait();
  const newImpl = await upgrades.erc1967.getImplementationAddress(core);
  console.log(`Goerli upgrade V1 to V2: network=${network.name}, core=${core}, \
    previous implementation=${prevImpl}, new implementation=${newImpl}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});