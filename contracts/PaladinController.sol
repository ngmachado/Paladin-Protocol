//██████╗  █████╗ ██╗      █████╗ ██████╗ ██╗███╗   ██╗
//██╔══██╗██╔══██╗██║     ██╔══██╗██╔══██╗██║████╗  ██║
//██████╔╝███████║██║     ███████║██║  ██║██║██╔██╗ ██║
//██╔═══╝ ██╔══██║██║     ██╔══██║██║  ██║██║██║╚██╗██║
//██║     ██║  ██║███████╗██║  ██║██████╔╝██║██║ ╚████║
//╚═╝     ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝╚═════╝ ╚═╝╚═╝  ╚═══╝
                                                     

pragma solidity ^0.7.6;
//SPDX-License-Identifier: MIT

import "./utils/SafeMath.sol";
import "./IPaladinController.sol";
import "./ControllerProxy.sol";
import "./PalPool.sol";
import "./IPalPool.sol";
import "./IPalToken.sol";
import "./utils/IERC20.sol";
import "./utils/SafeERC20.sol";
import "./utils/Admin.sol";
import "./utils/Errors.sol";

/** @title Paladin Controller contract  */
/// @author Paladin
contract PaladinController is IPaladinController, Admin {
    using SafeMath for uint;
    using SafeERC20 for IERC20;

    /** @notice Layout for the Proxy contract */
    address public currentIplementation;
    address public pendingImplementation;

    /** @notice List of current active palToken Pools */
    address[] public palTokens;
    address[] public palPools;
    mapping(address => address) public palTokenToPalPool;

    bool private initialized = false;

    /** @notice Struct with current SupplyIndex for a Pool, and the block of the last update */
    struct PoolRewardsState {
        uint224 index;
        uint32 blockNumber;
    }

    /** @notice Initial index for Rewards */
    uint224 public constant initialRewardsIndex = 1e36;

    address public rewardTokenAddress; // PAL token address to put here

    /** @notice State of the Rewards for each Pool */
    mapping(address => PoolRewardsState) public supplyRewardState;

    /** @notice Amount of reward tokens to disitribute each block */
    mapping(address => uint) public supplySpeeds;

    /** @notice Last reward index for each Pool for each user */
    /** PalPool => User => Index */
    mapping(address => mapping(address => uint)) public supplierRewardIndex;

    /** @notice Deposited amoutns by user for each palToken (indexed by corresponding PalPool address) */
    /** PalPool => User => Amount */
    mapping(address => mapping(address => uint)) public supplierDeposits;

    /** @notice Total amount of each palToken deposited (indexed by corresponding PalPool address) */
    /** PalPool => Total Amount */
    mapping(address => uint) public totalSupplierDeposits;

    /** @notice Ratio to distribute Borrow Rewards */
    mapping(address => uint) public borrowRatios; // scaled 1e18

    /** @notice Ratio for each PalLoan (set at PalLoan creation) */
    mapping(address => uint) public loansBorrowRatios; // scaled 1e18

    /** @notice Amount of reward Tokens accrued by the user, and claimable */
    mapping(address => uint) public accruedRewards;

    /*
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!!!!!!!!!!!!!!!!! ALWAYS PUT NEW STORAGE AT THE BOTTOM !!!!!!!!!!!!!!!!!!
    !!!!!!!!! WE DON'T WANT COLLISION WHEN SWITCHING IMPLEMENTATIONS !!!!!!!!!
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    */


    constructor(){
        admin = msg.sender;
    }

    /**
    * @notice Check if an address is a valid palPool
    * @return bool : result
    */
    function isPalPool(address _pool) public view override returns(bool){
        //Check if the given address is in the palPools list
        address[] memory _pools = palPools;
        for(uint i = 0; i < _pools.length; i++){
            if(_pools[i] == _pool){
                return true;
            }
        }
        return false;
    }


    /**
    * @notice Get all the PalTokens listed in the controller
    * @return address[] : List of PalToken addresses
    */
    function getPalTokens() external view override returns(address[] memory){
        return palTokens;
    }


    /**
    * @notice Get all the PalPools listed in the controller
    * @return address[] : List of PalPool addresses
    */
    function getPalPools() external view override returns(address[] memory){
        return palPools;
    }

    /**
    * @notice Set the basic PalPools/PalTokens controller list
    * @param _palTokens array of address of PalToken contracts
    * @param _palPools array of address of PalPool contracts
    * @return bool : Success
    */ 
    function setInitialPools(address[] memory _palTokens, address[] memory _palPools) external override adminOnly returns(bool){
        require(!initialized, Errors.POOL_LIST_ALREADY_SET);
        require(_palTokens.length == _palPools.length, Errors.LIST_SIZES_NOT_EQUAL);
        palPools = _palPools;
        palTokens = _palTokens;
        initialized = true;

        for(uint i = 0; i < _palPools.length; i++){
            //Update the Reward State for the new Pool
            PoolRewardsState storage supplyState = supplyRewardState[_palPools[i]];
            if(supplyState.index == 0){
                supplyState.index = initialRewardsIndex;
            }
            supplyState.blockNumber = safe32(block.number);

            //Link PalToken with PalPool
            palTokenToPalPool[_palTokens[i]] = _palPools[i];
        }

        return true;
    }
    
    /**
    * @notice Add a new PalPool/PalToken couple to the controller list
    * @param _palToken address of the PalToken contract
    * @param _palPool address of the PalPool contract
    * @return bool : Success
    */ 
    function addNewPool(address _palToken, address _palPool) external override adminOnly returns(bool){
        //Add a new address to the palToken & palPool list
        require(!isPalPool(_palPool), Errors.POOL_ALREADY_LISTED);

        palTokens.push(_palToken);
        palPools.push(_palPool);
        palTokenToPalPool[_palToken] = _palPool;

        //Update the Reward State for the new Pool
        PoolRewardsState storage supplyState = supplyRewardState[_palPool];
        if(supplyState.index == 0){
            supplyState.index = initialRewardsIndex;
        }
        supplyState.blockNumber = safe32(block.number);

        //The other Reward values should already be set at 0 :
        //BorrowRatio : 0
        //SupplySpeed : 0
        //If not set as 0, we want ot use last values (or change them with the adequate function beforehand)
        
        emit NewPalPool(_palPool, _palToken);

        return true;
    }

    
    /**
    * @notice Remove a PalPool from the list (& the related PalToken)
    * @param _palPool address of the PalPool contract to remove
    * @return bool : Success
    */ 
    function removePool(address _palPool) external override adminOnly returns(bool){
        //Remove a palToken & palPool from the list
        require(isPalPool(_palPool), Errors.POOL_NOT_LISTED);

        address[] memory _pools = palPools;
        
        uint lastIndex = (_pools.length).sub(1);
        for(uint i = 0; i < _pools.length; i++){
            if(_pools[i] == _palPool){
                //get the address of the PalToken for the Event
                address _palToken = palTokens[i];

                delete palTokenToPalPool[_palToken];

                //Replace the address to remove with the last one of the array
                palPools[i] = palPools[lastIndex];
                palTokens[i] = palTokens[lastIndex];

                //And pop the last item of the array
                palPools.pop();
                palTokens.pop();

                emit RemovePalPool(_palPool, _palToken);
             
                return true;
            }
        }
        return false;
    }


    /**
    * @notice Check if the given PalPool has enough cash to make a withdraw
    * @param palPool address of PalPool
    * @param amount amount withdrawn
    * @return bool : true if possible
    */
    function withdrawPossible(address palPool, uint amount) external view override returns(bool){
        //Get the underlying balance of the palPool contract to check if the action is possible
        PalPool _palPool = PalPool(palPool);
        return(_palPool.underlyingBalance() >= amount);
    }
    

    /**
    * @notice Check if the given PalPool has enough cash to borrow
    * @param palPool address of PalPool
    * @param amount amount ot borrow
    * @return bool : true if possible
    */
    function borrowPossible(address palPool, uint amount) external view override returns(bool){
        //Get the underlying balance of the palPool contract to check if the action is possible
        PalPool _palPool = PalPool(palPool);
        return(_palPool.underlyingBalance() >= amount);
    }
    

    /**
    * @notice Check if Deposit was correctly done
    * @param palPool address of PalPool
    * @param dest address to send the minted palTokens
    * @param amount amount of palTokens minted
    * @return bool : Verification Success
    */
    function depositVerify(address palPool, address dest, uint amount) external view override returns(bool){
        require(isPalPool(msg.sender), Errors.CALLER_NOT_POOL);
        
        palPool;
        dest;

        //Check the amount sent isn't null 
        return amount > 0;
    }


    /**
    * @notice Check if Withdraw was correctly done
    * @param palPool address of PalPool
    * @param dest address to send the underlying tokens
    * @param amount amount of underlying token returned
    * @return bool : Verification Success
    */
    function withdrawVerify(address palPool, address dest, uint amount) external view override returns(bool){
        require(isPalPool(msg.sender), Errors.CALLER_NOT_POOL);

        palPool;
        dest;

        //Check the amount sent isn't null
        return amount > 0;
    }
    

    /**
    * @notice Check if Borrow was correctly done
    * @param palPool address of PalPool
    * @param borrower borrower's address 
    * @param amount amount of token borrowed
    * @param feesAmount amount of fees paid by the borrower
    * @param loanAddress address of the new deployed PalLoan
    * @return bool : Verification Success
    */
    function borrowVerify(address palPool, address borrower, address delegatee, uint amount, uint feesAmount, address loanAddress) external override returns(bool){
        require(isPalPool(msg.sender), Errors.CALLER_NOT_POOL);
        
        borrower;
        delegatee;
        amount;
        feesAmount;

        // Set the borrowRatio for this new Loan
        setLoanBorrowRewards(palPool, loanAddress);
        
        //no method yet 
        return true;
    }

    /**
    * @notice Check if Expand Borrow was correctly done
    * @param loanAddress address of the PalLoan contract
    * @param newFeesAmount new amount of fees in the PalLoan
    * @return bool : Verification Success
    */
    function expandBorrowVerify(address palPool, address loanAddress, uint newFeesAmount) external override returns(bool){
        require(isPalPool(msg.sender), Errors.CALLER_NOT_POOL);
        
        newFeesAmount;

        // In case the Loan is expanded, the new ratio is used (in case the ratio changed)
        setLoanBorrowRewards(palPool, loanAddress);
        
        //no method yet 
        return true;
    }


    /**
    * @notice Check if Borrow Closing was correctly done
    * @param palPool address of PalPool
    * @param borrower borrower's address
    * @param loanAddress address of the PalLoan contract to close
    * @return bool : Verification Success
    */
    function closeBorrowVerify(address palPool, address borrower, address loanAddress) external override returns(bool){
        require(isPalPool(msg.sender), Errors.CALLER_NOT_POOL);
        
        borrower;

        //Accrue Rewards to the Loan's owner
        accrueBorrowRewards(palPool, loanAddress);
        
        //no method yet 
        return true;
    }


    /**
    * @notice Check if Borrow Killing was correctly done
    * @param palPool address of PalPool
    * @param killer killer's address
    * @param loanAddress address of the PalLoan contract to kill
    * @return bool : Verification Success
    */
    function killBorrowVerify(address palPool, address killer, address loanAddress) external override returns(bool){
        require(isPalPool(msg.sender), Errors.CALLER_NOT_POOL);
        
        killer;

        //Accrue Rewards to the Loan's owner
        accrueBorrowRewards(palPool, loanAddress);
        
        //no method yet 
        return true;
    }



    // PalToken Deposit/Withdraw functions

    function deposit(address palToken, uint amount) external override returns(bool){
        address palPool = palTokenToPalPool[palToken];
        address user = msg.sender;
        IERC20 token = IERC20(palToken);

        require(amount <= token.balanceOf(user), Errors.INSUFFICIENT_BALANCE);

        updateSupplyIndex(palPool);
        accrueSupplyRewards(palPool, user);

        supplierDeposits[palPool][user] = supplierDeposits[palPool][user].add(amount);
        totalSupplierDeposits[palPool] = totalSupplierDeposits[palPool].add(amount);

        token.safeTransferFrom(user, address(this), amount);

        emit Deposit(user, palToken, amount);

        return true;
    }


    function withdraw(address palToken, uint amount) external override returns(bool){
        address palPool = palTokenToPalPool[palToken];
        address user = msg.sender;

        require(amount <= supplierDeposits[palPool][user], Errors.INSUFFICIENT_DEPOSITED);

        updateSupplyIndex(palPool);
        accrueSupplyRewards(palPool, user);

        IERC20 token = IERC20(palToken);

        supplierDeposits[palPool][user] = supplierDeposits[palPool][user].sub(amount);
        totalSupplierDeposits[palPool] = totalSupplierDeposits[palPool].sub(amount);

        token.safeTransfer(user, amount);

        emit Withdraw(user, palToken, amount);

        return true;
    }


    // Rewards functions
    
    /**
    * @notice Internal - Updates the Supply Index of a Pool for reward distribution
    * @param palPool address of the Pool to update the Supply Index for
    */
    function updateSupplyIndex(address palPool) internal {
        // Get last Pool Supply Rewards state
        PoolRewardsState storage state = supplyRewardState[palPool];
        // Get the current block number, and the Supply Speed for the given Pool
        uint currentBlock = block.number;
        uint supplySpeed = supplySpeeds[palPool];

        // Calculate the number of blocks since last update
        uint ellapsedBlocks = currentBlock.sub(uint(state.blockNumber));

        // If an update is needed : block ellapsed & non-null speed (rewards to distribute)
        if(ellapsedBlocks > 0 && supplySpeed > 0){
            // Get the Total Amount deposited in the Controller of PalToken associated to the Pool
            uint totalDeposited = totalSupplierDeposits[palPool];

            // Calculate the amount of rewards token accrued since last update
            uint accruedAmount = ellapsedBlocks.mul(supplySpeed);

            // And the new ratio for reward distribution to user
            // Based on the amount of rewards accrued, and the change in the TotalSupply
            uint ratio = totalDeposited > 0 ? accruedAmount.mul(1e36).div(totalDeposited) : 0;

            // Write new Supply Rewards values in the storage
            state.index = safe224(uint(state.index).add(ratio));
            state.blockNumber = safe32(currentBlock);
        }
        else if(ellapsedBlocks > 0){
            // If blocks ellapsed, but no rewards to distribute (speed == 0),
            // just write the last update block number
            state.blockNumber = safe32(currentBlock);
        }

    }

    /**
    * @notice Internal - Accrues rewards token to the user claimable balance, depending on the Pool SupplyRewards state
    * @param palPool address of the PalPool the user interracted with
    * @param user address of the user to accrue rewards to
    */
    function accrueSupplyRewards(address palPool, address user) internal {
        // Get the Pool current SupplyRewards state
        PoolRewardsState storage state = supplyRewardState[palPool];

        // Get the current reward index for the Pool
        // And the user last reward index
        uint currentSupplyIndex = state.index;
        uint userSupplyIndex = supplierRewardIndex[palPool][user];

        // Update the Index in the mapping, the local value is used after
        supplierRewardIndex[palPool][user] = currentSupplyIndex;

        if(userSupplyIndex == 0 && currentSupplyIndex >= initialRewardsIndex){
            // Set the initial Index for the user
            userSupplyIndex = initialRewardsIndex;
        }

        // Get the difference of index with the last one for user
        uint indexDiff = currentSupplyIndex.sub(userSupplyIndex);

        if(indexDiff > 0){
            // And using the user PalToken balance deposited in the Controller,
            // we can get how much rewards where accrued
            uint userBalance = supplierDeposits[palPool][user];

            uint userAccruedRewards = userBalance.mul(indexDiff).div(1e36);

            // Add the new amount of rewards to the user total claimable balance
            accruedRewards[user] = accruedRewards[user].add(userAccruedRewards);
        }

    }

    /**
    * @notice Internal - Saves the BorrowRewards Ratio for a PalLoan, depending on the PalPool
    * @param palPool address of the PalPool the Loan comes from
    * @param loanAddress address of the PalLoan contract
    */
    function setLoanBorrowRewards(address palPool, address loanAddress) internal {
        // Saves the current Borrow Reward Ratio to use for that Loan rewards at Closing/Killing
        loansBorrowRatios[loanAddress] = borrowRatios[palPool];
    }

    /**
    * @notice Internal - Accrues reward to the PalLoan owner when the Loan is closed
    * @param palPool address of the PalPool the Loan comes from
    * @param loanAddress address of the PalLoan contract
    */
    function accrueBorrowRewards(address palPool, address loanAddress) internal {
        // Get the PalLoan BorrowRatio for rewards
        uint loanBorrowRatio = loansBorrowRatios[loanAddress];

        // Skip if no rewards set for the PalLoan
        if(loanBorrowRatio > 0){
            IPalPool pool = IPalPool(palPool);

            // Get the Borrower, and the amount of fees used by the Loan
            // And using the borrowRatio, accrue rewards for the borrower
            // The amount ot be accrued is calculated as feesUsed * borrowRatio
            address borrower;
            uint feesUsedAmount;

            (borrower,,,,,,,feesUsedAmount,,,,) = pool.getBorrowData(loanAddress);

            uint userAccruedRewards = feesUsedAmount.mul(loanBorrowRatio).div(1e18);

            // Add the new amount of rewards to the user total claimable balance
            accruedRewards[borrower] = accruedRewards[borrower].add(userAccruedRewards);
        }

    }

    /**
    * @notice Returns the current amount of reward tokens the user can claim
    * @param user address of user
    */
    function claimable(address user) external view override returns(uint) {
        return accruedRewards[user];
    }

    /**
    * @notice Update the claimable rewards for a given user
    * @param user address of user
    */
    function updateUserRewards(address user) external override {
        address[] memory _pools = palPools;
        for(uint i = 0; i < _pools.length; i++){
            // Need to update the Supply Index
            updateSupplyIndex(_pools[i]);
            // To then accrue the user rewards for that Pool
            //set at 0 & true for amount & positive, since no change in user LP position
            accrueSupplyRewards(_pools[i], user);
            // No need to do it for the Borrower rewards
        }
    }

    /**
    * @notice Accrues rewards for the user, then send all rewards tokens claimable
    * @param user address of user
    */
    function claim(address user) external override {
        // Accrue any claimable rewards for all the Pools for the user
        address[] memory _pools = palPools;
        for(uint i = 0; i < _pools.length; i++){
            // Need to update the Supply Index
            updateSupplyIndex(_pools[i]);
            // To then accrue the user rewards for that Pool
            //set at 0 & true for amount & positive, since no change in user LP position
            accrueSupplyRewards(_pools[i], user);
            // No need to do it for the Borrower rewards
        }

        // Get current amount claimable for the user
        uint toClaim = accruedRewards[user];

        // If there is a claimable amount
        if(toClaim > 0){
            IERC20 token = IERC20(rewardToken());
            require(toClaim <= token.balanceOf(address(this)), Errors.REWARDS_CASH_TOO_LOW);

            // All rewards were accrued and sent to the user, reset the counter
            accruedRewards[user] = 0;

            // Transfer the tokens to the user
            token.transfer(user, toClaim);

            emit ClaimRewards(user, toClaim);
        }
    }

    /**
    * @notice Returns the global Supply distribution speed
    * @return uint : Total Speed
    */
    function totalSupplyRewardSpeed() external view override returns(uint) {
        // Sum up the SupplySpeed for all the listed PalPools
        address[] memory _pools = palPools;
        uint totalSpeed = 0;
        for(uint i = 0; i < _pools.length; i++){
            totalSpeed = totalSpeed.add(supplySpeeds[_pools[i]]);
        }
        return totalSpeed;
    }



    /** @notice Address of the reward Token (PAL token) */
    function rewardToken() public view returns(address) {
        return rewardTokenAddress;
    }
        
    
    //Admin function

    function becomeImplementation(ControllerProxy proxy) external override adminOnly {
        // Only to call after the contract was set as Pending Implementation in the Proxy contract
        // To accept the delegatecalls, and update the Implementation address in the Proxy
        require(proxy.acceptImplementation(), Errors.FAIL_BECOME_IMPLEMENTATION);
    }

    function updateRewardToken(address newRewardTokenAddress) external override adminOnly {
        rewardTokenAddress = newRewardTokenAddress;
    }


    function setPoolsNewController(address _newController) external override adminOnly returns(bool){
        address[] memory _pools = palPools;
        for(uint i = 0; i < _pools.length; i++){
            IPalPool _palPool = IPalPool(_pools[i]);
            _palPool.setNewController(_newController);
        }
        return true;
    }


    function withdrawFromPool(address _pool, uint _amount, address _recipient) external override adminOnly returns(bool){
        IPalPool _palPool = IPalPool(_pool);
        _palPool.withdrawFees(_amount, _recipient);
        return true;
    }

    // set a pool rewards values (admin)
    function updatePoolRewards(address palPool, uint newSupplySpeed, uint newBorrowRatio) external override adminOnly {
        require(isPalPool(palPool), Errors.POOL_NOT_LISTED);

        if(newSupplySpeed != supplySpeeds[palPool]){
            //Make sure it's updated before setting the new speed
            updateSupplyIndex(palPool);

            supplySpeeds[palPool] = newSupplySpeed;
        }

        if(newBorrowRatio != borrowRatios[palPool]){
            borrowRatios[palPool] = newBorrowRatio;
        }

        emit PoolRewardsUpdated(palPool, newSupplySpeed, newBorrowRatio);
    }

    // (admin) send all unclaimed/non-accrued rewards to other contract / to multisig / to admin ?



    //Math utils

    function safe224(uint n) internal pure returns (uint224) {
        require(n < 2**224, "Number is over 224 bits");
        return uint224(n);
    }

    function safe32(uint n) internal pure returns (uint32) {
        require(n < 2**32, "Number is over 32 bits");
        return uint32(n);
    }


}