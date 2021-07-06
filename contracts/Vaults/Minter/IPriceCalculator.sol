// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

interface IPriceCalculator {
    struct ReferenceData {
        uint lastData;
        uint lastUpdated;
    }

    function pricesInUSD(address[] memory assets) external view returns (uint[] memory);
    function valueOfAsset(address asset, uint amount) external view returns (uint valueInBNB, uint valueInUSD);
    function priceOfBunny() view external returns (uint);
    function priceOfBNB() view external returns (uint);
}