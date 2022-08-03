import { ethers, network } from "hardhat";

async function main() {

  // We get the contract to deploy
  const RAI20Factory = await ethers.getContractFactory("RAI20Factory");
  const rai20Factory = await RAI20Factory.deploy();

  await rai20Factory.deployed();

  const RAI20 = await ethers.getContractFactory("RAI20");

  console.log(`RAI20Factory deployed to: ${network.name}/${rai20Factory.address}, RAI20 init code hash=${ethers.utils.keccak256(RAI20.bytecode)}`);
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
