// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./preToken.sol";
import "./ReentrancyGuard.sol";

library SafeERC20{
    using Address for address;

    function safeTransfer  (
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

interface IDeHolder {
	function _buy (address token, address to, uint256 amount) external payable;
}

contract DeHolder is IDeHolder{

	address fundContract;

	constructor (address _fundContract) {
        fundContract = _fundContract;
    }

	function _buy (address token, address to, uint256 amount) override external payable {
        require(msg.sender == fundContract, "Illegal request");
		IERC20(token).transfer(to, amount);
	}
}


library MerkleProof {
    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For ,this a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == root;
    }
}

contract DeVenture is ReentrancyGuard{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    address private creator;
    
    DeHolder public holder;
    preToken[] public preTokens;

    address public immutable zentoken;
    uint256 public immutable startDate = block.timestamp + 0 days;
    uint256 public exchangeRate = 10;
    uint256 public minAllocation = 1e16;
    uint256 public maxAllocation = 100 * 1e18;  // 18 decimals
    uint256 public immutable maxFundsRaised;
    uint256 public totalRaise;
    uint256 public heldTotal;
    address payable public immutable ETHWallet;
    bool public transferStatus = true;
    bool public isFunding = true;
    
    bytes32 public merkleRoot;

    mapping(address => uint256) public heldTokens;
    mapping(address => uint256) public heldTimeline;

    struct projectInfo {
        address tokenAddress;                   // Project Token Contract Address
        string tokenSymbol;                     // Project Token Symbol
        address payable DefiantWallet;             // Project or DAO wallet where USDC will be sent to
        uint256 tokenAmount;                    // Total amount to be raised
        uint256 totalRaised;                    // Total amount already raised
        uint16 exchangeRate;                    // ExchangeRate USDC to project token
        uint256 softCap;                        // Minimal raise amount to finish funding
        uint256 maxAllocation;                  // Max amount to fund
        uint256 minAllocation;                  // Min amount to fund
        uint256 startDate;                      // Fund Start Date
        uint256 endDate;                        // Fund End Date
        bool isFunding;                         // Funding Flag
        address[] whitelist;                    // Whitelisted addresses
        uint256[] heldAmount;                   // Held Amount of each user
    }

    projectInfo[] public projects;              // Array of Project Information
    address public USDCAddress = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address public CVXAddress = 0x4e3FBD56CD56c3e72c1403e103b45Db9da5B9D2B;
    address public BTRFLYAddress = 0xC0d4Ceb216B3BA9C3701B291766fDCbA977ceC3A;
    address public FXSAddress = 0x3432B6A60D23Ca0dFCa7761B7ab56459D9C964D0;
    address public CRVAddress = 0xD533a949740bb3306d119CC777fa900bA034cd52;

    event Contribution(address from, uint256 amount);
    event ReleaseTokens(address from, uint256 amount);
    event CloseSale(address from);
    event SetMerkleRoot(address from);
    event SetMinAllocation(address from, uint256 minAllocation);
    event SetMaxAllocation(address from, uint256 maxAllocation);
    event UpdateRate(address from, uint256 rate);
    event ChangeCreator(address from);
    event ChangeTransferStats(address from);

    modifier onlyOwner() {
        require(msg.sender == creator, "Ido: caller is not the owner");
        _;
    }

    modifier checkStart(){
        require(block.timestamp >= startDate, "The project has not yet started");
        _;
    }

    constructor(
        // uint256 _startDate
    ) {

        totalRaise = 0;
        maxFundsRaised = _maxFundsRaised;   // 18 decimals
        creator = msg.sender;
       require(address(_wallet) != address(0), "Ido: wallet is 0" );
        ETHWallet = _wallet;
        holder = new DeHolder(address(this));
    }

    function closeSale() external onlyOwner {
        isFunding = false;
    }

    function getHolderAddress() external view returns (address) {
        return address(holder);
    }

    function setMerkleRoot(bytes32 _merkleRoot) external onlyOwner{
        merkleRoot = _merkleRoot;
    }

    function setMinAllocation(uint256 _minAllocation) external onlyOwner {
        minAllocation = _minAllocation;
    }

    function setMaxAllocation(uint256 _maxAllocation) external onlyOwner {
        maxAllocation = _maxAllocation;
    }

    // REGISTER FUNCTION
    // Registers the project to be listed on the upcoming project
    function register(
        string memory tokenSymbol,              // Project Token Symbol
        address tokenAddress,                   // Project Token Contract Address
        address payable DefiantWallet,             // Project or DAO wallet where USDC will be sent to
        uint256 tokenAmount,                    // Total amount to be raised
        uint16 exchangeRate,                    // ExchangeRate USDC to project token
        uint256 softCap,                        // Minimal raise amount to finish funding
        uint256 maxAllocation,                  // Max amount to fund
        uint256 minAllocation,                  // Min amount to fund
        uint256 startDate,                      // Fund Start Date
        uint256 endDate,                        // Fund End Date
        address[] memory whitelist              // Fund End Date
        ) external payable {
        
        uint256[] memory initHeldAmount;

        for(uint256 i = 0; i < whitelist.length; i ++) {
            initHeldAmount[i] = 0;
        }

        projectInfo memory newProject = projectInfo(
            {
                tokenSymbol: tokenSymbol,
                tokenAddress: tokenAddress,
                DefiantWallet: DefiantWallet,
                tokenAmount: tokenAmount,
                totalRaised: 0,
                exchangeRate: exchangeRate,
                softCap: softCap,
                maxAllocation: maxAllocation,
                minAllocation: minAllocation,
                startDate: startDate,
                endDate: endDate,
                isFunding: false,
                whitelist: whitelist,
                heldAmount: initHeldAmount
            }
        );

        projects.push(newProject);
        IERC20(tokenAddress).transferFrom(msg.sender, address(holder), tokenAmount);
    }


    // Lock USDC
    function deposit( uint256 amount, uint256 projectId, uint8 tokenType ) external payable {

        require(amount >= projects[projectId].minAllocation, "The quantity is too low");
        require(amount <= projects[projectId].maxAllocation, "The quantity is too high");
        require(( amount + projects[projectId].totalRaised ) * projects[projectId].exchangeRate >= projects[projectId].tokenAmount, "The total raise is higher than maximum raised funds" );

        if(tokenType == 0) {
            for( uint i = 0; i < projects[projectId].whitelist.length; i ++) {
                if( projects[projectId].whitelist[i] == msg.sender ) {
                    projects[projectId].heldAmount[i] += amount;                
                }
            }

            projects[projectId].totalRaised += amount;
            IERC20(USDCAddress).transferFrom(msg.sender, address(holder), amount);
        }
        else if(tokenType == 1) {
            for( uint i = 0; i < projects[projectId].whitelist.length; i ++) {
                if( projects[projectId].whitelist[i] == msg.sender ) {
                    projects[projectId].heldAmount[i] += amount;                
                }
            }

            projects[projectId].totalRaised += amount * projects[projectId].exchangeRate + amount * projects[projectId].exchangeRate.mul(75).div(1000);
            IERC20(CVXAddress).transferFrom(msg.sender, address(holder), amount);            
        }        
        else if(tokenType == 2) {
            for( uint i = 0; i < projects[projectId].whitelist.length; i ++) {
                if( projects[projectId].whitelist[i] == msg.sender ) {
                    projects[projectId].heldAmount[i] += amount;                
                }
            }

            projects[projectId].totalRaised += amount * projects[projectId].exchangeRate + amount * projects[projectId].exchangeRate.mul(75).div(1000);
            IERC20(BTRFLYAddress).transferFrom(msg.sender, address(holder), amount);            
        }        
        else if(tokenType == 3) {
            for( uint i = 0; i < projects[projectId].whitelist.length; i ++) {
                if( projects[projectId].whitelist[i] == msg.sender ) {
                    projects[projectId].heldAmount[i] += amount;                
                }
            }

            projects[projectId].totalRaised += amount * projects[projectId].exchangeRate + amount * projects[projectId].exchangeRate.mul(75).div(1000);
            IERC20(FXSAddress).transferFrom(msg.sender, address(holder), amount);            
        }        
        else if(tokenType == 4) {
            for( uint i = 0; i < projects[projectId].whitelist.length; i ++) {
                if( projects[projectId].whitelist[i] == msg.sender ) {
                    projects[projectId].heldAmount[i] += amount;                
                }
            }

            projects[projectId].totalRaised += amount * projects[projectId].exchangeRate + amount * projects[projectId].exchangeRate.mul(75).div(1000);
            IERC20(CRVAddress).transferFrom(msg.sender, address(holder), amount);            
        }        
    }

    //Unlock USDC and Mint pretokens
    function unlockUSDC( uint256 projectId ) external payable {
        require(!isFunding, "Haven't reached the claim goal");

        preTokens[projectId] = new preToken({
            NAME: string(abi.encodePacked("pre", projects[projectId].tokenSymbol)),
            SYMBOL: string(abi.encodePacked("x", projects[projectId].tokenSymbol)),
            SUPPLY: projects[projectId].totalRaised,
            IDOAddress: address(holder)
        });

        IERC20(USDCAddress).transferFrom(address(holder), projects[projectId].DefiantWallet, projects[projectId].totalRaised);
    }

    //Claim pretokens
    function claimPreTokens( uint256 projectId ) external payable {
        require(!isFunding, "Haven't reached the claim goal");

        uint256 heldAmount = 0;

        for( uint i = 0; i < projects[projectId].whitelist.length; i ++) {
            if( projects[projectId].whitelist[i] == msg.sender ) {
                heldAmount = projects[projectId].heldAmount[i];
            }
        }

        IERC20(preTokens[projectId]).transferFrom(address(holder), msg.sender, heldAmount);
    }


    //Claim Project Token and burn pretoken
    function claimProjectToken( uint256 projectId ) external payable {
        
        uint256 heldAmount = 0;
        require(!projects[projectId].isFunding, "Haven't reached the claim goal");

        for( uint i = 0; i < projects[projectId].whitelist.length; i ++) {
            if( projects[projectId].whitelist[i] == msg.sender ) {
                heldAmount = projects[projectId].heldAmount[i];
                projects[projectId].heldAmount[i] = 0;
            }
        }

        IERC20(address(preTokens[projectId]))._burn(msg.sender, heldAmount);
        
        heldAmount = heldAmount * exchangeRate;

        IDeHolder(holder)._buy(projects[projectId].tokenAddress, msg.sender, heldAmount);
    }

    // update the ETH/COIN rate
    function updateRate(uint256 rate) external onlyOwner {
        require(isFunding, "ido is closed");
        require(rate <= 100_100*100, "Rate is higher than total supply");
        exchangeRate = rate;
    }

    // change creator address
    function changeCreator(address _creator) external onlyOwner {
        require(address(_creator) != address(0), "Ido: _creator is 0");
        creator = _creator;
    }

    // change transfer status for ERC20 token
    function changeTransferStatus(bool _allowed) external onlyOwner {
        transferStatus = _allowed;
    }

    // public function to get the amount of tokens held for an address
    function getHeldCoin(address _address) external view returns (uint256) {
        return heldTokens[_address];
    }

    // function to create held tokens for developer
    function createHoldToken(address _to, uint256 amount) internal {
        heldTokens[_to] = amount;
        heldTimeline[_to] = block.number;
        heldTotal += amount;
    }
}