// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

interface IFiatTokenV2 {
    function initialize(
        string memory tokenName,
        string memory tokenSymbol,
        string memory tokenCurrency,
        uint8 tokenDecimals,
        address newMasterMinter,
        address newPauser,
        address newBlacklister,
        address newOwner
    ) external;

    function configureMinter(address minter, uint256 minterAllowedAmount) external returns (bool);

    function mint(address _to, uint256 _amount) external returns (bool);
}
