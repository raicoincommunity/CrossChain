import { ethers, network } from "hardhat";

async function main() {
  let genesis_signer: string | undefined;
  let genesis_validator: string | undefined;
  if (network.name === 'bsctest') {
    genesis_signer = process.env.BSC_TEST_GENESIS_SIGNER;
    genesis_validator = process.env.BSC_TEST_GENESIS_VALIDATOR;
  } else if (network.name === 'goerli') {
    genesis_signer = process.env.GOERLI_GENESIS_SIGNER;
    genesis_validator = process.env.GOERLI_GENESIS_VALIDATOR;
  } else {
    console.error(`Unsupported network: ${network.name}`);
    process.exitCode = 1;
    return;
  }

  if (!genesis_signer) {
    console.error('Genesis signer not set');
    process.exitCode = 1;
    return;
  }

  if (!genesis_validator) {
    console.error('Genesis validator not set');
    process.exitCode = 1;
    return;
  }

  // We get the contract to deploy
  const ValidatorManager = await ethers.getContractFactory("ValidatorManager");
  const validatorManager = await ValidatorManager.deploy(genesis_validator, genesis_signer);

  await validatorManager.deployed();

  console.log(`ValidatorManager deployed to: ${network.name}/${validatorManager.address}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
