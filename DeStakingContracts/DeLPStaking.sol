pragma solidity >=0.8.4;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
contract DeLPStaking is Ownable {
    
    using SafeMath for uint256;
    // Info of each user.

    struct UserInfo {
        uint256 amount;     // How many LP tokens the user has provided.
        uint256 rewardDebt; // Reward debt. See explanation below.
        //
    }

    IERC20 public rsist;
    //The lpToken TOKEN!
    IERC20 public lpToken;
    // RSIST tokens created per block.
    uint256 public rsistPerBlock;
    // Bonus muliplier for early cake makers.
    uint256 public BONUS_MULTIPLIER = 1;
    // Info of each user that stakes LP tokens.
    mapping (address => UserInfo) public userInfo;
    // Total allocation points. Must be the sum of all allocation points in all pools.
    uint256 public totalAllocPoint = 0;
    // The block number when RSIST mining starts.
    uint256 public startBlock;
    // How many allocation points assigned to pool.
    uint256 public allocPoint;
    // Accumulated RSIST per share, times 1e12.
    uint256 public accRSISTPerShare;
    //Last block number that CAKEs distribution occurs.
    uint256 public lastRewardBlock; 

    event Deposit(
        address indexed user, 
        uint256 amount
        );

    event Withdraw(
        address indexed user, 
        uint256 amount
        );

    event EmergencyWithdraw(
        address indexed user, 
        uint256 amount
        );

    constructor(
        IERC20 _RSIST,
        IERC20 _lpToken,
        uint256 _RSISTPerBlock,
        uint256 _startBlock
  
    ) public {
        RSIST = _RSIST;
        lpToken = _lpToken;
        RSISTPerBlock = _RSISTPerBlock;
        startBlock = _startBlock;
        allocPoint = 1000;
        lastRewardBlock = startBlock;
        accRSISTPerShare= 0;
        totalAllocPoint = 1000;
    }

    function updateMultiplier(uint256 multiplierNumber) public onlyOwner {
        BONUS_MULTIPLIER = multiplierNumber;
    }

    // Update the pool's allocation point. Can only be called by the owner.
    function set(uint256 _allocPoint) public onlyOwner {
        uint256 prevAllocPoint = allocPoint;
        allocPoint = _allocPoint;
        if (prevAllocPoint != _allocPoint) {
            totalAllocPoint = totalAllocPoint.sub(prevAllocPoint).add(_allocPoint);
            updatePool();
        }
    }

    // Return reward multiplier over the given _from to _to block.
    function getMultiplier(uint256 _from, uint256 _to) public view returns (uint256) {
        return _to.sub(_from).mul(BONUS_MULTIPLIER);
    }

    // View function to see pending pheonix on frontend.
    function pendingRSIST(address _user) 
        external 
        view 
        returns (uint256,uint256) 
        {
        UserInfo storage user = userInfo[_user];
        uint256 lpSupply = lpToken.balanceOf(address(this));
        uint256 accRSIST = accRSISTPerShare;
        if (block.number > lastRewardBlock && lpSupply != 0) {
            uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
            
            uint256 RSISTReward = multiplier.mul(RSISTPerBlock).mul(allocPoint).div(totalAllocPoint);
            accRSIST = accRSIST.add(RSISTReward.mul(1e12).div(lpSupply));
        }
        return (user.amount.mul(accRSIST).div(1e12).sub(user.rewardDebt),accRSIST);
    }

    // Update reward variables of the given pool to be up-to-date.
    function updatePool() public {
        if (block.number <= lastRewardBlock) {
            return;
        }
        uint256 lpSupply = lpToken.balanceOf(address(this));
        if (lpSupply == 0) {
            lastRewardBlock = block.number;
            return;
        }
        uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
        uint256 RSISTReward = multiplier.mul(RSISTPerBlock).mul(allocPoint).div(totalAllocPoint);
        accRSISTPerShare = accRSISTPerShare.add(RSISTReward.mul(1e12).div(lpSupply));
        lastRewardBlock = block.number;
    }

    // Deposit LP tokens to MasterChef for CAKE allocation.
    function deposit( uint256 _amount) public {
        UserInfo storage user = userInfo[msg.sender];
        updatePool();
        if (user.amount > 0) {
            uint256 pending = user.amount.mul(accRSISTPerShare).div(1e12).sub(user.rewardDebt);
            if(pending > 0) {
                RSIST.transfer(msg.sender, pending);
            }
        }
        if (_amount > 0) {
            lpToken.transferFrom(address(msg.sender), address(this), _amount);
            user.amount = user.amount.add(_amount);
        }
        user.rewardDebt = user.amount.mul(accRSISTPerShare).div(1e12);
        emit Deposit(msg.sender, _amount);
    }
    function lpTokenSupply() public view returns(uint256){
        return lpToken.balanceOf(address(this));
    }
    // function acc() public view returns(uint256){
    //     return accRSISTPerShare;
    // }
    // function userInf() public view returns(uint256,uint256){
    //     return (userInfo[msg.sender].amount,userInfo[msg.sender].rewardDebt);
    // }
    // function utils() public view returns(uint256){
    //     return (block.number);
    // }
    // function getRSIST() public view returns(uint256){
    //     uint256 multiplier = getMultiplier(lastRewardBlock, block.number);
    //     uint256 RSISTReward = multiplier.mul(RSISTPerBlock).mul(allocPoint).div(totalAllocPoint);
    //     return RSISTReward;
    // }
    // Withdraw LP tokens from MasterChef.
    function withdraw(uint256 _amount) public {

        UserInfo storage user = userInfo[msg.sender];
        require(user.amount >= _amount, "withdraw: not good");

        updatePool();
        uint256 pending = user.amount.mul(accRSISTPerShare).div(1e12).sub(user.rewardDebt);
        if(pending > 0) {
           RSIST.transfer(msg.sender, pending);
        }
        if(_amount > 0) {
            user.amount = user.amount.sub(_amount);
            lpToken.transfer(address(msg.sender), _amount);
        }
        user.rewardDebt = user.amount.mul(accRSISTPerShare).div(1e12);
        emit Withdraw(msg.sender, _amount);
    }
     // Withdraw without caring about rewards. EMERGENCY ONLY.
    function emergencyWithdraw() public {
        // hi
        UserInfo storage user = userInfo[msg.sender];
        lpToken.transfer(address(msg.sender), user.amount);
        emit EmergencyWithdraw(msg.sender, user.amount);
        user.amount = 0;
        user.rewardDebt = 0;
    }
}