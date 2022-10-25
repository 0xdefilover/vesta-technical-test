// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IToken.sol";

contract Staking is AccessControl {

    struct LockInfo {
        uint256 lastUpdatedTime;
        uint256 totalLockedAmount;
        uint256 unlockPerMonth;
    }

    event Staked(address indexed from, uint256 amount);
    event Unstaked(address indexed caller, address indexed to, uint256 amount);
    event Locked(address indexed from, bytes32 lockId);
    event Claimed(address indexed to, uint256 amount);

    bytes32 public constant OWNER_ROLE = keccak256("OWNER_ROLE");
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    uint256 public constant ONE_YEAR = 365 days;
    uint256 public constant ONE_MONTH = 30 days;
    
    IToken public token;
    
    mapping(address => uint256) private balances;
    /// @dev Mapping from lock identifier to lock info
    mapping(bytes32 => LockInfo) private locked;
    /// @dev The users can lock more than once. This is a mapping from address to index
    mapping(address => uint256) private lockCount;
    mapping(address => bool) private blacklist;
    bool private emergPanic;

    constructor(address _stakingToken) {
        token = IToken(_stakingToken);
        _setupRole(OWNER_ROLE, msg.sender);
    }
    
    modifier notBlacklisted() {
        require(!blacklist[msg.sender], "Your wallet is blacklisted");
        _;
    }

    /**
     * @dev Setup admin role fro multisig wallet
     */
    function setupAdminRole(address _admin) public onlyRole(OWNER_ROLE) {
        _grantRole(ADMIN_ROLE, _admin);
    }

    function addBlacklist(address _user) external onlyRole(ADMIN_ROLE) {
        blacklist[_user] = true;
    }

    /**
     * @dev Admins can do an emergency panic to unlock all the locked tokens
     */
    function unlockAllToken() external onlyRole(ADMIN_ROLE) {
        emergPanic = true;
    }

    function stake(uint256 _amount) external {
        require(_amount > 0, "Invalid amount");
        balances[msg.sender] += _amount;
        token.transferFrom(msg.sender, address(this), _amount);
        emit Staked(msg.sender, _amount);
    }

    function unStake(address _to, uint256 _amount) external {
        require(_amount > 0, "Invalid amount");
        require(balances[_to] >= _amount, "Insufficient amount");
        balances[_to] -= _amount;
        token.transfer(_to, _amount);
        emit Unstaked(msg.sender, _to, _amount);
    }

    function lock(uint256 _duration, uint256 _amount) external notBlacklisted {
        require(_amount > 0, "Invalid amount");
        require(_duration >= ONE_YEAR, "Lock duration should be over one year");

        bytes32 lockId = nextLockIdForHolder(msg.sender);

        locked[lockId] = LockInfo(
            block.timestamp,
            _amount,
            _amount * ONE_MONTH / _duration
        );
        token.transferFrom(msg.sender, address(this), _amount);
        uint256 currentLockCount = lockCount[msg.sender];
        lockCount[msg.sender] = currentLockCount + 1;

        emit Locked(msg.sender, lockId);
    }

    /**
     * @dev Claims the unlock tokens for a given lock index. 
     * For only one lock, it is 0, but for more than once, it can be 0, 1...
     */
    function claim(uint256 _index) external {
        bytes32 lockId = lockIdForAddressAndIndex(msg.sender, _index);
        LockInfo storage lockInfo = locked[lockId];
        require(lockInfo.totalLockedAmount > 0, "Lock info does not exist");

        uint256 unlockAmount = 0;
        if (emergPanic) {
            unlockAmount = lockInfo.totalLockedAmount;
            lockInfo.totalLockedAmount = 0;
            lockInfo.lastUpdatedTime = block.timestamp;
        } else {
            uint256 duration = block.timestamp - lockInfo.lastUpdatedTime;
            require(duration >= ONE_MONTH, "No unlock amount");
            uint256 unlockedMonths = duration / ONE_MONTH;
            unlockAmount = lockInfo.unlockPerMonth * unlockedMonths;
            if (lockInfo.totalLockedAmount >= unlockAmount) {
                lockInfo.totalLockedAmount -= unlockAmount;
            } else {
                lockInfo.totalLockedAmount = 0;
                unlockAmount = lockInfo.totalLockedAmount;
            }
            lockInfo.lastUpdatedTime += unlockedMonths * ONE_MONTH;
        }

        token.transfer(msg.sender, unlockAmount);
        emit Claimed(msg.sender, unlockAmount);
    }

    /**
     * @dev Computes the next lock identifier for a given user address.
     */
    function nextLockIdForHolder(address _user) public view returns(bytes32) {
        return lockIdForAddressAndIndex(
            _user,
            lockCount[_user]
        );
    }
    /**
     * @dev Computes the lock identifier for an address and an index.
     */
    function lockIdForAddressAndIndex(
        address _user,
        uint256 _index
    ) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _index));
    }
}
