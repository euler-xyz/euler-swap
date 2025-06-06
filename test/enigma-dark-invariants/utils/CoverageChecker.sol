// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract CoverageChecker {
    function _checkCoverage(uint256 coverage, uint256 low, uint256 high) internal pure returns (string memory) {
        // Validate the range
        require(high > low, "High must be greater than Low.");
        require(coverage >= low && coverage <= high, "Coverage must be within the provided range.");

        // Calculate the size of each threshold interval
        uint256 range = high - low;
        uint256 step = range / 20; // Divide the range into 20 thresholds

        // Check which threshold the coverage falls into
        if (coverage <= low + step) {
            return "Threshold 1: Very Low Coverage";
        } else if (coverage <= low + step * 2) {
            return "Threshold 2: Critical Low Coverage";
        } else if (coverage <= low + step * 3) {
            return "Threshold 3: Low Coverage";
        } else if (coverage <= low + step * 4) {
            return "Threshold 4: Below Average Coverage";
        } else if (coverage <= low + step * 5) {
            return "Threshold 5: Near Average Coverage";
        } else if (coverage <= low + step * 6) {
            return "Threshold 6: Average Coverage";
        } else if (coverage <= low + step * 7) {
            return "Threshold 7: Slightly Above Average";
        } else if (coverage <= low + step * 8) {
            return "Threshold 8: Moderate Coverage";
        } else if (coverage <= low + step * 9) {
            return "Threshold 9: Good Coverage";
        } else if (coverage <= low + step * 10) {
            return "Threshold 10: Very Good Coverage";
        } else if (coverage <= low + step * 11) {
            return "Threshold 11: Excellent Coverage";
        } else if (coverage <= low + step * 12) {
            return "Threshold 12: Strong Coverage";
        } else if (coverage <= low + step * 13) {
            return "Threshold 13: High Coverage";
        } else if (coverage <= low + step * 14) {
            return "Threshold 14: Very High Coverage";
        } else if (coverage <= low + step * 15) {
            return "Threshold 15: Outstanding Coverage";
        } else if (coverage <= low + step * 16) {
            return "Threshold 16: Exceptional Coverage";
        } else if (coverage <= low + step * 17) {
            return "Threshold 17: Nearly Perfect Coverage";
        } else if (coverage <= low + step * 18) {
            return "Threshold 18: Almost Full Coverage";
        } else if (coverage <= low + step * 19) {
            return "Threshold 19: Near Maximum Coverage";
        } else {
            return "Threshold 20: Maximum Coverage Achieved!";
        }
    }
}
