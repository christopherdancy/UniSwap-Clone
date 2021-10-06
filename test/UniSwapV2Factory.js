const { expect } = require('chai');
const { solidityKeccak256, keccak256 } = require('ethers/lib/utils');
const { ethers } = require('hardhat');

describe ('UniSwapV2Factory', () => {
    let UniSwapFactoryABI;
    let UniSwapFactory;
    let UniSwapPair;
    let toSetter;
    let wallet;
    let other;
    let updatedSetter;
    let token0;
    let token1;

    beforeEach(async () => {
        UniSwapFactoryABI = await ethers.getContractFactory('UniSwapV2Factory');
        [toSetter, wallet, other, updatedSetter, token0, token1] = await ethers.getSigners();
        UniSwapFactory = await UniSwapFactoryABI.deploy(toSetter.address);

        UniSwapPair = await ethers.getContractFactory('UniSwapV2Factory');
    })

    it('feeTo, feeToSetter, allPairsLength', async () => {
        expect(await UniSwapFactory.feeToSetter()).to.equal(toSetter.address);
        expect(await UniSwapFactory.feeTo()).to.equal(ethers.constants.AddressZero);
        expect(await UniSwapFactory.allPairsLength()).to.equal('0');
    })

    it('Create Pair', async () => {
        expect( await UniSwapFactory.createPair(token0.address, token1.address))
        .to.emit('PairCreated');

        await expect(UniSwapFactory.createPair(token0.address, token1.address))
        .to.be.revertedWith('PairAlreadyCreated()');
        await expect(UniSwapFactory.createPair(token1.address, token0.address))
        .to.be.revertedWith('PairAlreadyCreated()');
        
        // getPair should return the same Pair address
        expect(await UniSwapFactory.getPair(token0.address, token1.address))
        .to.equal(await UniSwapFactory.getPair(token1.address, token0.address));

        // Check created pair address == expected address (salt)
        const actualPairAddress = UniSwapFactory.getPair(token1.address, token0.address);
        const salt = solidityKeccak256(['string', 'string'], [token0.address, token1.address]);
        const initCode = keccak256(UniSwapPair.bytecode);
        const expectedPairAddress = ethers.utils.getCreate2Address(UniSwapFactory.address, salt, initCode);
        expect(expectedPairAddress == actualPairAddress);

        
        // Check address array == created address
        expect(await UniSwapFactory.allPairsLength()).to.equal(1);
        expect(await UniSwapFactory.allPairs[0] == actualPairAddress);
    })

    it('setFeeTo', async () => {
        await expect(UniSwapFactory.connect(other).setFeeTo(other.address))
        .to.be.revertedWith('Only FeeToSetter may call');
        
        await UniSwapFactory.setFeeTo(wallet.address);
        expect(await UniSwapFactory.feeTo()).to.equal(wallet.address);
    })
    
    it('setFeeToSetter', async () => {
        await expect(UniSwapFactory.connect(other).setFeeToSetter(other.address))
        .to.be.revertedWith('Only FeeToSetter may call');
        
        await UniSwapFactory.setFeeToSetter(updatedSetter.address);
        expect(await UniSwapFactory.feeToSetter()).to.equal(updatedSetter.address);
    })
})