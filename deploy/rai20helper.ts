import { ethers, network } from "hardhat";

async function main() {

  // We get the contract to deploy
  const RAI20FactoryHelper = await ethers.getContractFactory("RAI20FactoryHelper");
  const rai20FactoryHelper = await RAI20FactoryHelper.deploy();

  await rai20FactoryHelper.deployed();

  const initCodeHash = await rai20FactoryHelper.TOKEN_INIT_CODE_HASH();

  console.log(`RAI20 init code hash: ${network.name}/${initCodeHash}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
