import { ethers, network, upgrades } from "hardhat";
import { INVALID_DEPLOYED_ADDRESS, GOERLI_CONTRACTS } from './deployed';

async function main() {

  const validatorManager = GOERLI_CONTRACTS.validatorManager;
  if (validatorManager === INVALID_DEPLOYED_ADDRESS) {
    console.error('ValidatorManager not deployed');
    process.exitCode = 1;
    return;
  }

  const rai20Factory = GOERLI_CONTRACTS.rai20Factory;
  if (rai20Factory === INVALID_DEPLOYED_ADDRESS) {
    console.error('ERC20Factory not deployed');
    process.exitCode = 1;
    return;
  }

  const rai721Factory = GOERLI_CONTRACTS.rai721Factory;
  if (rai721Factory === INVALID_DEPLOYED_ADDRESS) {
    console.error('ERC721Factory not deployed');
    process.exitCode = 1;
    return;
  }

  const { chainId } = await ethers.provider.getNetwork();
  if (chainId !== 5) {
    console.error(`Chain ID mismatch: expected=5, actual=${chainId}`);
    process.exitCode = 1;
    return;
  }

  // We get the contract to deploy
  const Goerli = await ethers.getContractFactory("Goerli");
  const goerli = await upgrades.deployProxy(Goerli,
    [validatorManager, rai20Factory, rai721Factory],
    { kind: 'uups' });

  await goerli.deployed();

  console.log(`Goerli core deployed to: ${network.name}/${goerli.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});