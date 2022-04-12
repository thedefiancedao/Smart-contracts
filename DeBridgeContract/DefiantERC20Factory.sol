// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/proxy/Clones.sol";
import "./interfaces/IDefiantERC20.sol";

contract DefiantERC20Factory {
    constructor() public {}

    event DefiantERC20Created(address contractAddress);

    /**
     * @notice Deploys a new node
     * @param defiantERC20Address address of the defiantERC20Address contract to initialize with
     * @param name Token name
     * @param symbol Token symbol
     * @param decimals Token name
     * @param owner admin address to be initialized with
     * @return Address of the newest node management contract created
     **/
    function deploy(
        address defiantERC20Address,
        string memory name,
        string memory symbol,
        uint8 decimals,
        address owner
    ) external returns (address) {
        address defERC20Clone = Clones.clone(defiantERC20Address);
        IDefiantERC20(defERC20Clone).initialize(name, symbol, decimals, owner);

        emit DefiantERC20Created(defERC20Clone);

        return defERC20Clone;
    }
}
