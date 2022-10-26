import { time, loadFixture } from "@nomicfoundation/hardhat-network-helpers";
import { expect } from "chai";
import { ethers } from "hardhat";

describe("Staking & Lock test suite", () => {
    const { parseUnits, formatUnits } = ethers.utils;
    // We define a fixture to reuse the same setup in every test.
    async function deployStakingFixture() {
        const [owner, admin, user1, user2, user3] = await ethers.getSigners();

        const Token = await ethers.getContractFactory("Token");
        const token = await Token.deploy("Test Token", "TEST");

        const Staking = await ethers.getContractFactory("Staking");
        const staking = await Staking.deploy(token.address);

        const mintAmount = parseUnits("1000", 18);
        await token.mint(user1.address, mintAmount);
        await token.mint(user2.address, mintAmount);
        await token.mint(user3.address, mintAmount);

        return { token, staking, owner, admin, user1, user2, user3 };
    }

    describe("Staking", () => {
        describe("Validations", () => {
            it("Should revert if amount is not greater than 0", async() => {
                const {staking, user1} = await loadFixture(deployStakingFixture);
                await expect(
                    staking.connect(user1).stake(parseUnits("0", 18))
                ).to.be.revertedWith("Amount must be greater than 0");
            });

            it("Should revert if users do not approve their tokens", async() => {
                const {staking, user1} = await loadFixture(deployStakingFixture);
                await expect(
                    staking.connect(user1).stake(parseUnits("100", 18))
                ).to.be.revertedWith("ERC20: insufficient allowance");
            });

            it("Should revert if users unstake more than they staked", async() => {
                const {staking, user1} = await loadFixture(deployStakingFixture);
                await expect(
                    staking.connect(user1).unstake(user1.address, parseUnits("100", 18))
                ).to.be.revertedWith("Insufficient amount");
            });
        });

        describe("Events", () => {
            it("User1 stakes 100 tokens and unstakes 50 tokens", async() => {
                const {token, staking, user1} = await loadFixture(deployStakingFixture);
                const stakeAmount = parseUnits("100", 18);
                await token.connect(user1).approve(staking.address, stakeAmount);
                await expect(
                    staking.connect(user1).stake(stakeAmount)
                ).to.emit(staking, "Staked").withArgs(user1.address, stakeAmount);
    
                const unstakeAmount = parseUnits("50", 18);
                await expect(
                    staking.connect(user1).unstake(user1.address, unstakeAmount)
                ).to.emit(staking, "Unstaked").withArgs(user1.address, user1.address, unstakeAmount);
    
                expect(await staking.balanceOf(user1.address)).to.equal(parseUnits("50", 18)); // 100 - 50
            });
    
            it("User2 stakes 200 tokens and unstakes 100 tokens", async() => {
                const {token, staking, user2} = await loadFixture(deployStakingFixture);
                const stakeAmount2 = parseUnits("200", 18);
    
                await token.connect(user2).approve(staking.address, stakeAmount2);
                await expect(
                    staking.connect(user2).stake(stakeAmount2)
                ).to.emit(staking, "Staked").withArgs(user2.address, stakeAmount2);
    
                const unstakeAmount = parseUnits("100", 18);
                await expect(
                    staking.connect(user2).unstake(user2.address, unstakeAmount)
                ).to.emit(staking, "Unstaked").withArgs(user2.address, user2.address, unstakeAmount);
    
                expect(await staking.balanceOf(user2.address)).to.equal(parseUnits("100", 18)); // 200 - 100
            });
    
            it("User3 stakes 300 tokens and unstakes 100 tokens", async() => {
                const {token, staking, user3} = await loadFixture(deployStakingFixture);
                const stakeAmount3 = parseUnits("300", 18);
                await token.connect(user3).approve(staking.address, stakeAmount3);
                await expect(
                    staking.connect(user3).stake(stakeAmount3)
                ).to.emit(staking, "Staked").withArgs(user3.address, stakeAmount3);

                const unstakeAmount = parseUnits("100", 18);
                await expect(
                    staking.connect(user3).unstake(user3.address, unstakeAmount)
                ).to.emit(staking, "Unstaked").withArgs(user3.address, user3.address, unstakeAmount);
    
                expect(await staking.balanceOf(user3.address)).to.equal(parseUnits("200", 18)); // 300 - 100
            });
        })
    });

    describe("Lock", () => {
        let staking: any, token: any;
        let owner: any, admin: any, user1: any, user2: any, user3: any;
        
        before(async() => {
            const fixture = await loadFixture(deployStakingFixture);
            staking = fixture.staking;
            token = fixture.token;
            owner = fixture.owner;
            admin = fixture.admin;
            user1 = fixture.user1;
            user2 = fixture.user2;
            user3 = fixture.user3;
        });

        it("Only owner can set admin role", async() => {
            const adminRole = await staking.ADMIN_ROLE();
            // Only owner can set admin role
            await expect(
                staking.connect(user1).setupAdminRole(admin.address)
            ).to.be.reverted;

            await expect(
                staking.setupAdminRole(admin.address)
            ).to.emit(staking, "RoleGranted").withArgs(adminRole, admin.address, owner.address);
        });

        it("Only admin can manage blacklist", async() => {
            await expect(
                staking.connect(user2).addBlacklist(user1.address)
            ).to.be.reverted;

            await staking.connect(admin).addBlacklist(user1.address);

            // The blacklisted users cannot use the lock system
            await expect(
                staking.connect(user1).lock(365 * 24 * 3600, parseUnits("100", 18))
            ).to.be.revertedWith("Your wallet is blacklisted");
        });

        it("User2 locks 100 tokens for the first time with 12 months' duration", async() => {
            const duration = 365 * 24 * 3600; // 1 year
            const lockAmount = parseUnits("100", 18);
            const lockId = await staking.nextLockIdForHolder(user2.address);
            
            await token.connect(user2).approve(staking.address, lockAmount);
            await expect(
                staking.connect(user2).lock(duration, lockAmount)
            ).to.emit(staking, "Locked").withArgs(user2.address, lockId);
        });

        it("User2 claims the unlocked tokens 1 month later", async() => {
            const oneMonth = 30 * 24 * 3600;
            const firstLockDuration = 365 * 24 * 3600 // 1 year
            const unlockAmount = (100 * Math.pow(10, 18) / firstLockDuration) * oneMonth;
            
            await time.increase(oneMonth);
            const beforeBalance = parseFloat((await token.balanceOf(user2.address)).toString());
            await expect(
                staking.connect(user2).claim(0)
            ).to.emit(staking, "Claimed");
            const afterBalance = parseFloat((await token.balanceOf(user2.address)).toString());
            
            expect(beforeBalance + unlockAmount).to.greaterThanOrEqual(afterBalance);
        })

        it("User2 locks 200 tokens for the second time with 13 months' duration", async() => {
            const secLockAmount = parseUnits("200", 18);
            const secDuration = (365 + 30) * 24 * 3600; // 13 months
            const secLockId = await staking.nextLockIdForHolder(user2.address);

            await token.connect(user2).approve(staking.address, secLockAmount);
            await expect(
                staking.connect(user2).lock(secDuration, secLockAmount)
            ).to.emit(staking, "Locked").withArgs(user2.address, secLockId);
        });

        it("Only admin can do an emergency panic", async() => {
            await expect(
                staking.connect(user1).emergencyPanic()
            ).to.be.reverted;

            await staking.connect(admin).emergencyPanic();
            
            // Allow user2 to claim all of his second lock
            await expect(
                staking.connect(user2).claim(1)
            ).to.emit(staking, "Claimed").withArgs(user2.address, parseUnits("200", 18));    
        });
    });
})
