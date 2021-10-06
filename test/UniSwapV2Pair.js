const { expect, util } = require("chai");
const { utils, constants } = require("ethers");
const { ethers } = require("hardhat");

describe("UniSwapV2Pair", function () {
  let UniSwapv2Pair;
  let UniSwapv2PairDeployed;
  let UniSwapv2PairAddress;
  let UniSwapFactory;
  let UniSwapFactoryDeployed;
  let tokenMock;
  let toSetter;
  let token0;
  let token1;
  let user;

  const MINIMUM_LIQUIDITY = utils.parseUnits('1', '3');

  // `beforeEach` will run before each test, re-deploying the contract every
  // time. It receives a callback, which can be async.
  beforeEach(async function () {
    [toSetter, user, sender] = await ethers.getSigners();

    // Deploy Token Mocks
    tokenMock = await ethers.getContractFactory('Erc20Mock');
    token0 = await tokenMock.deploy('token0', '0');
    token1 = await tokenMock.deploy('token1', '1');

    // Deploy Factory Contract
    UniSwapFactory = await ethers.getContractFactory("UniSwapV2Factory")
    UniSwapFactoryDeployed = await UniSwapFactory.deploy(toSetter.address);

    // Deploy Instance of Pair Contract
    UniSwapv2Pair = await ethers.getContractFactory('UniSwapV2Pair');
    await UniSwapFactoryDeployed.createPair(token0.address, token1.address);
    UniSwapv2PairAddress = await UniSwapFactoryDeployed.getPair(token0.address, token1.address);
    UniSwapv2PairDeployed = await UniSwapv2Pair.attach(UniSwapv2PairAddress);
    expect(await UniSwapv2PairDeployed.factory()).to.equal(UniSwapFactoryDeployed.address);
  });

  // You can nest describe calls to create subsections.
  // Will not run only must switch token0 - token1
  describe("UniSwapV2Pair", function () {
    it("Should mint", async function () {
      const tokenAmount0 = utils.parseEther('1');
      const tokenAmount1 = utils.parseEther('4');
      await token0.transfer(UniSwapv2PairDeployed.address, tokenAmount0);
      await token1.transfer(UniSwapv2PairDeployed.address, tokenAmount1);

      const expectedLiquidity = utils.parseEther('2');
      await expect(UniSwapv2PairDeployed.mint(user.address))
      .to.emit(UniSwapv2PairDeployed, 'Transfer')
      .withArgs(constants.AddressZero, constants.AddressZero, MINIMUM_LIQUIDITY)
      .to.emit(UniSwapv2PairDeployed, 'Transfer')
      .withArgs(constants.AddressZero, user.address, expectedLiquidity.sub(MINIMUM_LIQUIDITY))
      .to.emit(UniSwapv2PairDeployed, 'Sync')
      .withArgs(tokenAmount1, tokenAmount0)
      .to.emit(UniSwapv2PairDeployed, 'Mint')
      .withArgs(toSetter.address, tokenAmount1, tokenAmount0)

      expect(await UniSwapv2PairDeployed.totalSupply()).to.eq(expectedLiquidity)
      expect(await UniSwapv2PairDeployed.balanceOf(user.address)).to.eq(expectedLiquidity.sub(MINIMUM_LIQUIDITY))
      expect(await token0.balanceOf(UniSwapv2PairDeployed.address)).to.eq(tokenAmount0)
      expect(await token1.balanceOf(UniSwapv2PairDeployed.address)).to.eq(tokenAmount1)
      const reserves = await UniSwapv2PairDeployed.getReserves()
      expect(reserves[0]).to.eq(tokenAmount1)
      expect(reserves[1]).to.eq(tokenAmount0)
    });

    async function addLiquidity(tokenAmount0, tokenAmount1) {
      await token0.transfer(UniSwapv2PairDeployed.address, tokenAmount0);
      await token1.transfer(UniSwapv2PairDeployed.address, tokenAmount1); 
      await UniSwapv2PairDeployed.mint(user.address);
    }

    it('Should transfer', async () => {
      const tokenAmount0 = utils.parseEther('5');
      const tokenAmount1 = utils.parseEther('10');
      await addLiquidity(tokenAmount0, tokenAmount1);

      const swapAmount = utils.parseEther('1');
      await token0.transfer(UniSwapv2PairDeployed.address, swapAmount);

      const expectedOutputAmount = '1662497915624478906';
      await expect(UniSwapv2PairDeployed.swap(0, expectedOutputAmount, user.address, '0x'))
            .to.emit(token1, 'Transfer')
            .withArgs(UniSwapv2PairDeployed.address, user.address, expectedOutputAmount)
            .to.emit(UniSwapv2PairDeployed, 'Sync')
            .withArgs(tokenAmount0.add(swapAmount), tokenAmount1.sub(expectedOutputAmount))
            .to.emit(UniSwapv2PairDeployed, 'Swap')
            .withArgs(toSetter.address, swapAmount, 0, 0, expectedOutputAmount)

      const reserves = await UniSwapv2PairDeployed.getReserves()
      expect(reserves[0]).to.eq(tokenAmount0.add(swapAmount))
      expect(reserves[1]).to.eq(tokenAmount1.sub(expectedOutputAmount))
      expect(await token0.balanceOf(UniSwapv2PairDeployed.address)).to.eq(tokenAmount0.add(swapAmount))
      expect(await token1.balanceOf(UniSwapv2PairDeployed.address)).to.eq(tokenAmount1.sub(expectedOutputAmount))
      expect(await token1.balanceOf(user.address)).to.eq(expectedOutputAmount)
      expect(await token0.balanceOf(user.address)).to.eq('0')
    });

    it('Should burn', async () => {
      const tokenAmount0 = utils.parseEther('3');
      const tokenAmount1 = utils.parseEther('3');
      await addLiquidity(tokenAmount0, tokenAmount1);

      const expectedLiquid = utils.parseEther('3');
      await UniSwapv2PairDeployed.connect(user).transfer(UniSwapv2PairDeployed.address, expectedLiquid.sub(MINIMUM_LIQUIDITY));

      await expect(UniSwapv2PairDeployed.connect(user).burn(user.address))
            .to.emit(UniSwapv2PairDeployed, 'Transfer')
            .withArgs(UniSwapv2PairDeployed.address, constants.AddressZero, expectedLiquid.sub(MINIMUM_LIQUIDITY))
            .to.emit(token0, 'Transfer')
            .withArgs(UniSwapv2PairDeployed.address, user.address, tokenAmount0.sub(1000))
            .to.emit(token1, 'Transfer')
            .withArgs(UniSwapv2PairDeployed.address, user.address, tokenAmount1.sub(1000))
            .to.emit(UniSwapv2PairDeployed, 'Sync')
            .withArgs(1000, 1000)
            .to.emit(UniSwapv2PairDeployed, 'Burn')
            .withArgs(user.address, tokenAmount0.sub(1000), tokenAmount1.sub(1000), user.address)   

      expect(await UniSwapv2PairDeployed.balanceOf(user.address)).to.eq(0)
      expect(await UniSwapv2PairDeployed.totalSupply()).to.eq(MINIMUM_LIQUIDITY)
      expect(await token0.balanceOf(UniSwapv2PairDeployed.address)).to.eq(1000)
      expect(await token1.balanceOf(UniSwapv2PairDeployed.address)).to.eq(1000)
    });
  });
  
});