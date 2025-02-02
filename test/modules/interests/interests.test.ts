import { ethers, waffle } from "hardhat";
import chai, { use } from "chai";
import { solidity } from "ethereum-waffle";
import { InterestCalculator } from "../../../typechain/InterestCalculator";
import { SignerWithAddress } from "@nomiclabs/hardhat-ethers/signers";
import { BigNumber } from "@ethersproject/bignumber";


chai.use(solidity);
const { expect } = chai;

const blocksPerYear = 2336000;

const multiplierPerBlock = 0.7 / blocksPerYear;
const baseRatePerBlock = 0.57 / blocksPerYear;
const kinkMultiplierPerBlock = 12.6 / blocksPerYear;
const kinkBaseRatePerBlock = 1.13 / blocksPerYear;
const kink = 0.8;

const fakeAddress = "0x5570fF7334c5B86c10333dec3985197eeB67555F"

function simuUtilizationRate(cash: number, borrows: number, reserves: number){
    return borrows ? borrows / (cash + borrows - reserves) : 0
}

function simuBorrowRate(cash: number, borrows: number, reserves: number){
    let useRate: number = simuUtilizationRate(cash, borrows, reserves)
    if(useRate < kink){
        return (useRate * multiplierPerBlock) + baseRatePerBlock
    }
    else {
        return (useRate - kink) * kinkMultiplierPerBlock + kinkBaseRatePerBlock
    }
}

function simuSupplyRate(cash: number, borrows: number, reserves: number, reserveFactor: number = 0.2){
    let useRate: number = simuUtilizationRate(cash, borrows, reserves)
    let borRate: number = simuBorrowRate(cash, borrows, reserves)
    return useRate * (borRate * (1 - reserveFactor))
}

function closeEnough(a: number, b :number){
    return -1e-10 < (a - b)  && (a - b) < 1e-10;
}


describe('Interest Calculator contract tests', () => {
    let admin: SignerWithAddress

    const values = [
        { // 0%
            'c': 500,
            'b': 0,
            'r': 0
        },
        { // 50%
            'c': 500,
            'b': 500,
            'r': 0
        },
        { // 80%
            'c': 300,
            'b': 800,
            'r': 100
        },
        { // 100%
            'c': 200,
            'b': 1000,
            'r': 200
        }
    ]
    
    let interest: InterestCalculator

    beforeEach( async () => {
        [admin] = await ethers.getSigners();

        const interestFactory = await ethers.getContractFactory(
            "InterestCalculator",
            admin
        );
        interest = (await interestFactory.deploy()) as InterestCalculator;
        await interest.deployed();

    });

    it(' should be deployed', async () => {
        expect(interest.address).to.properAddress
    });

    it(' should calculate correct use rates', async () => {
        
        values.forEach(async v => {
            let res = await interest.utilizationRate(v['c'],v['b'],v['r'])
            let simu :number = simuUtilizationRate(v['c'],v['b'],v['r'])
            let val: number = +(ethers.utils.formatEther(res))
            expect(val).to.be.eq(simu)
            
        });
    });

    it(' should calculate correct borrow rates', async () => {

        values.forEach(async v => {
            let res = await interest.getBorrowRate(fakeAddress,v['c'],v['b'],v['r'])
            let simu :number = simuBorrowRate(v['c'],v['b'],v['r'])
            let val: number = +(ethers.utils.formatEther(res))
            simu = Math.round(simu * 1e18) / 1e18
            expect(closeEnough(val, simu))
            
        });
    });

    it(' should calculate correct supply rates', async () => {
        const reserveFactor = ethers.utils.parseEther('0.2')

        values.forEach(async v => {
            let res = await interest.getSupplyRate(fakeAddress,v['c'],v['b'],v['r'], reserveFactor)
            let simu :number = simuSupplyRate(v['c'],v['b'],v['r'])
            let val: number = +(ethers.utils.formatEther(res))
            simu = Math.round(simu * 1e18) / 1e18
            expect(closeEnough(val, simu))
            
        });
    });

    it(' should handle overflows', async () => {
        const largestUint: BigNumber = ethers.constants.MaxUint256

        await expect(
            interest.utilizationRate(largestUint, largestUint, 0)
        ).to.be.revertedWith("SafeMath: addition overflow")

        await expect(
            interest.getBorrowRate(fakeAddress,0, largestUint, 0)
        ).to.be.revertedWith("SafeMath: multiplication overflow")
    })

});