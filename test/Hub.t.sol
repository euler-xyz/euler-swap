// SPDX-License-Identifier: GPL-2.0-or-later
pragma solidity ^0.8.24;

import {Test, console} from "forge-std/Test.sol";
import {EVaultTestBase, TestERC20} from "evk-test/unit/evault/EVaultTestBase.t.sol";
import {IEVC} from "ethereum-vault-connector/interfaces/IEthereumVaultConnector.sol";
import {IEVault} from "evk/EVault/IEVault.sol";
import {IEulerSwap, EulerSwap} from "../src/EulerSwap.sol";
import {EulerSwapHub} from "../src/EulerSwapHub.sol";

contract HubTest is EVaultTestBase {
    address public holder = makeAddr("holder");
    EulerSwapHub hub;

    function setUp() public virtual override {
        super.setUp();

        hub = new EulerSwapHub(address(evc), address(factory));

        // Vault config

        eTST.setLTV(address(eTST2), 0.9e4, 0.9e4, 0);
        eTST2.setLTV(address(eTST), 0.9e4, 0.9e4, 0);

        // Pricing

        oracle.setPrice(address(assetTST), unitOfAccount, 1e18);
        oracle.setPrice(address(assetTST2), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST), unitOfAccount, 1e18);
        oracle.setPrice(address(eTST2), unitOfAccount, 1e18);

        oracle.setPrice(address(assetTST), address(assetTST2), 1e18);
        oracle.setPrice(address(assetTST2), address(assetTST), 1e18);

        // Funding

        mintAndDeposit(holder, eTST, 10e18);
        mintAndDeposit(holder, eTST2, 10e18);
    }

    function mintAndDeposit(address who, IEVault vault, uint256 amount) internal {
        TestERC20 tok = TestERC20(vault.asset());
        tok.mint(who, amount);

        vm.prank(who);
        tok.approve(address(vault), type(uint256).max);

        vm.prank(who);
        vault.deposit(amount, who);
    }

    function getEulerSwapParams(uint112 reserve0, uint112 reserve1, uint256 fee)
        internal
        view
        returns (EulerSwap.Params memory)
    {
        return IEulerSwap.Params({
            vault0: address(eTST),
            vault1: address(eTST2),
            eulerAccount: holder,
            equilibriumReserve0: reserve0,
            equilibriumReserve1: reserve1,
            currReserve0: reserve0,
            currReserve1: reserve1,
            fee: fee
        });
    }

    function predictAddress(
        address hubAddr,
        IEulerSwap.Params memory params,
        IEulerSwap.CurveParams memory curveParams,
        bytes32 salt
    ) internal pure returns (address) {
        return address(
            uint160(
                uint256(
                    keccak256(
                        abi.encodePacked(
                            bytes1(0xff),
                            hubAddr,
                            keccak256(abi.encode(address(params.eulerAccount), salt)),
                            keccak256(abi.encodePacked(type(EulerSwap).creationCode, abi.encode(params, curveParams)))
                        )
                    )
                )
            )
        );
    }

    function test_deterministicAddress() public {
        IEulerSwap.Params memory params = getEulerSwapParams(50e18, 50e18, 0.001e18);
        IEulerSwap.CurveParams memory curveParams =
            IEulerSwap.CurveParams({priceX: 1e18, priceY: 1e18, concentrationX: 0.97e18, concentrationY: 0.97e18});
        bytes32 salt = bytes32(uint256(1234));

        address predictedAddress = predictAddress(address(hub), params, curveParams, salt);

        vm.prank(holder);
        evc.setAccountOperator(holder, predictedAddress, true);

        vm.prank(holder);
        address actualAddress = hub.deploy(params, curveParams, salt);

        assertEq(predictedAddress, actualAddress);
    }

    function test_preInstallInBatch() public {
        IEulerSwap.Params memory params = getEulerSwapParams(50e18, 50e18, 0.001e18);
        IEulerSwap.CurveParams memory curveParams =
            IEulerSwap.CurveParams({priceX: 1e18, priceY: 1e18, concentrationX: 0.97e18, concentrationY: 0.97e18});
        bytes32 salt = bytes32(uint256(1234));

        address predictedAddress = predictAddress(address(hub), params, curveParams, salt);

        IEVC.BatchItem[] memory items = new IEVC.BatchItem[](2);

        items[0] = IEVC.BatchItem({
            onBehalfOfAccount: address(0),
            targetContract: address(evc),
            value: 0,
            data: abi.encodeCall(evc.setAccountOperator, (holder, predictedAddress, true))
        });

        items[1] = IEVC.BatchItem({
            onBehalfOfAccount: holder,
            targetContract: address(hub),
            value: 0,
            data: abi.encodeCall(EulerSwapHub.deploy, (params, curveParams, salt))
        });

        vm.prank(holder);
        evc.batch(items);
    }
}
