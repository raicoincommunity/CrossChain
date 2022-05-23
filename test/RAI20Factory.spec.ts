import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { expect } from "chai";
import { ethers } from "hardhat";
import { RAI20Factory, RAI20 } from "../typechain";
import { ADDRESS_ZERO} from './lib/constants';


describe("RAI20Factory", function () {

  let owner: SignerWithAddress;
  let core: SignerWithAddress;
  let addr1: SignerWithAddress;
  let addr2: SignerWithAddress;
  let factoryInstance: RAI20Factory;
  const abiCoder = ethers.utils.defaultAbiCoder;

  const deploy = async function () {
    [owner, core, addr1, addr2] = await ethers.getSigners();
    const factory = await ethers.getContractFactory("RAI20Factory");
    factoryInstance = await factory.deploy();
  }
 
  describe("Deployment", function () {
    before(deploy);

    it("Should set the right deployer", async function () {
      expect(await factoryInstance.deployer()).to.equal(owner.address);
    });

    it("Should init coreContract to 0", async function () {
      expect(await factoryInstance.coreContract()).to.equal(ADDRESS_ZERO);
    });
  });

  describe("Set core contract", function () {
    before(deploy);

    it("Should revert if not set by deployer", async function () {
      await expect(factoryInstance.connect(addr2).setCoreContract(addr1.address)).to.be.revertedWith("Not deployer");
    });

    it("Should set the coreContract", async function () {
      const tx = await factoryInstance.connect(owner).setCoreContract(addr1.address);
      await tx.wait();
      expect(await factoryInstance.coreContract()).to.equal(addr1.address);
    });

    it("Should revert if the coreContract has been set", async function () {
      await expect(factoryInstance.setCoreContract(addr2.address)).to.be.revertedWith("Already set");
    });
  });

  describe("Create", function () {
    before(deploy);

    it("Should revert if coreContract is not set", async function () {
      const tx = factoryInstance.create("Ethereum Token", "rETH_bsc", "Binance Smart Chain", 2, "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", 18);
      await expect(tx).to.be.revertedWith("Not core contract");
    });

    it("Should set the coreContract", async function () {
      const tx = await factoryInstance.connect(owner).setCoreContract(core.address);
      await tx.wait();
      expect(await factoryInstance.coreContract()).to.equal(core.address);
    });

    it("Should revert if not called by coreContract", async function () {
      const tx = factoryInstance.connect(addr1).create("Ethereum Token", "rETH_bsc", "Binance Smart Chain", 2, "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", 18);
      await expect(tx).to.be.revertedWith("Not core contract");
    });

    let token: RAI20;
    it("Should create a new RAI20 token", async function () {
      const tx = await factoryInstance.connect(core).create("Ethereum Token", "rETH_bsc", "Binance Smart Chain", 2, "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", 18);
      const receipt = await tx.wait();
      const tokenAddr = abiCoder.decode(["address"], receipt.logs![0].data!)[0];

      token = await ethers.getContractAt("RAI20", tokenAddr);
      expect(await token.name()).to.equal("Ethereum Token");
      expect(await token.symbol()).to.equal("rETH_bsc");
      expect(await token.originalChain()).to.equal("Binance Smart Chain");
      expect(await token.originalChainId()).to.equal(2);
      expect(await token.originalContract()).to.equal("0x2170Ed0880ac9A755fd29B2688956BD959F933F8");
      expect(await token.decimals()).to.equal(18);
      expect(await token.coreContract()).to.equal(core.address);
    });

    it("Should revert if create with the same chain ID and contract address", async function () {
      const tx = factoryInstance.connect(core).create("Ethereum Token2", "rETH2_bsc", "Binance Smart Chain 2", 2, "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", 8);
      await expect(tx).to.be.reverted;
    });
  });

  describe("Mint & burn", function () {
    before(deploy);

    it("Should set the coreContract", async function () {
      const tx = await factoryInstance.connect(owner).setCoreContract(core.address);
      await tx.wait();
      expect(await factoryInstance.coreContract()).to.equal(core.address);
    });

    let token: RAI20;
    it("Should create a new RAI20 token", async function () {
      const tx = await factoryInstance.connect(core).create("Ethereum Token", "rETH_bsc", "Binance Smart Chain", 2, "0x2170Ed0880ac9A755fd29B2688956BD959F933F8", 18);
      const receipt = await tx.wait();
      const tokenAddr = abiCoder.decode(["address"], receipt.logs![0].data!)[0];
      token = await ethers.getContractAt("RAI20", tokenAddr);
    });

    it("Should revert if not mint by coreContract", async function () {
      const tx = token.connect(owner).mint(owner.address, 1000);
      await expect(tx).to.be.revertedWith("Not from core");
    });

    it("Should mint success", async function () {
      let tx = await token.connect(core).mint(addr1.address, 1000);
      await tx.wait();
      expect(await token.balanceOf(addr1.address)).to.equal(1000);
      expect(await token.totalSupply()).to.equal(1000);
      tx = await token.connect(core).mint(addr2.address, 2000);
      await tx.wait();
      expect(await token.balanceOf(addr2.address)).to.equal(2000);
      expect(await token.totalSupply()).to.equal(3000);
    });

    it("Should revert if not burn by coreContract", async function () {
      const tx = token.connect(addr1).burn(500);
      await expect(tx).to.be.revertedWith("Not from core");
    });

    it("Should burn success", async function () {
      let tx = await token.connect(addr1).transfer(core.address, 500);
      await tx.wait();
      expect(await token.balanceOf(addr1.address)).to.equal(500);
      expect(await token.totalSupply()).to.equal(3000);
      expect(await token.balanceOf(core.address)).to.equal(500);
      tx = await token.connect(core).burn(100);
      await tx.wait();
      expect(await token.balanceOf(core.address)).to.equal(400);
      expect(await token.totalSupply()).to.equal(2900);
    });

    it("Should revert if not enough balance to burn", async function () {
      const tx = token.connect(core).burn(401);
      await expect(tx).to.be.revertedWith("ERC20: burn amount exceeds balance");
    });
  });

});