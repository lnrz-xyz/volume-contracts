// SPDX-License-Identifier: MIT

import {UD60x18, ud} from "@prb/math/src/UD60x18.sol";

contract CurveCalculator {
    function calculateConstant(
        uint256 threshold,
        uint256 maxSupply
    ) public pure returns (uint256) {
        UD60x18 TWO = ud(2e18);
        UD60x18 T = ud(threshold);
        UD60x18 S = ud(maxSupply);

        // Avoid using pow with fixed-point exponents
        UD60x18 maxSupplySquared = S.mul(S);

        UD60x18 numerator = TWO.mul(T);
        UD60x18 result = numerator.div(maxSupplySquared);

        return result.unwrap();
    }

    function getBuyPrice(
        uint256 amount,
        uint256 currentSupply,
        uint256 K
    ) public pure returns (uint256) {
        if (amount == 0) {
            return 0;
        }
        uint256 newSupply = currentSupply + amount;

        UD60x18 k = ud(K);
        UD60x18 TWO = ud(2e18);

        UD60x18 currentSupplyUD = ud(currentSupply);
        UD60x18 newSupplyUD = ud(newSupply);

        // Use multiplication instead of pow
        UD60x18 priceCurrentSupply = k
            .mul(currentSupplyUD.mul(currentSupplyUD))
            .div(TWO);
        UD60x18 priceNewSupply = k.mul(newSupplyUD.mul(newSupplyUD)).div(TWO);
        UD60x18 totalPrice = priceNewSupply.sub(priceCurrentSupply);

        return totalPrice.unwrap();
    }

    function getSellPrice(
        uint256 amount,
        uint256 currentSupply,
        uint256 K
    ) public pure returns (uint256) {
        require(amount <= currentSupply, "Amount exceeds current supply");
        uint256 newSupply = currentSupply - amount;

        UD60x18 k = ud(K);
        UD60x18 TWO = ud(2e18);

        UD60x18 currentSupplyUD = ud(currentSupply);
        UD60x18 newSupplyUD = ud(newSupply);

        // Use multiplication instead of pow
        UD60x18 priceCurrentSupply = k
            .mul(currentSupplyUD.mul(currentSupplyUD))
            .div(TWO);
        UD60x18 priceNewSupply = k.mul(newSupplyUD.mul(newSupplyUD)).div(TWO);
        UD60x18 totalPrice = priceCurrentSupply.sub(priceNewSupply);

        return totalPrice.unwrap();
    }
}
