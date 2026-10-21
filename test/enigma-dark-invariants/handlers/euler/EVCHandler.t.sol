// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// Libraries
import {EthereumVaultConnector} from "ethereum-vault-connector/EthereumVaultConnector.sol";

// Testing contracts
import {Actor} from "../../utils/Actor.sol";
import {BaseHandler, EnumerableSet} from "../../base/BaseHandler.t.sol";

/// @title EVCHandler
/// @notice Handler test contract for the EVC actions
abstract contract EVCHandler is BaseHandler {
    using EnumerableSet for EnumerableSet.AddressSet;

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                      STATE VARIABLES                                      //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                       GHOST VARAIBLES                                     //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           ACTIONS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////

    function setAccountOperator(uint8 i, uint8 j, bool authorised) external setup {
        bool success;
        bytes memory returnData;

        address account = _getRandomActor(i);

        address operator = _getRandomActor(j);

        _before();
        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.setAccountOperator.selector, account, operator, authorised)
        );

        if (success) {
            _after();
        } else {
            revert("EVCHandler: setAccountOperator failed");
        }
    }

    // COLLATERAL

    function enableCollateral(uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address vaultAddress = _getRandomVault(j);

        _before();
        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.enableCollateral.selector, account, vaultAddress)
        );

        if (success) {
            _after();
        } else {
            revert("EVCHandler: enableCollateral failed");
        }
    }

    function disableCollateral(uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address vaultAddress = _getRandomVault(j);

        _before();
        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.disableCollateral.selector, account, vaultAddress)
        );

        if (success) {
            _after();
        } else {
            revert("EVCHandler: disableCollateral failed");
        }
    }

    function reorderCollaterals(uint8 i, uint8 index1, uint8 index2) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        _before();
        (success, returnData) = actor.proxy(
            address(evc),
            abi.encodeWithSelector(EthereumVaultConnector.reorderCollaterals.selector, account, index1, index2)
        );

        if (success) {
            _after();
        } else {
            revert("EVCHandler: disableCollateral failed");
        }
    }

    // CONTROLLER

    function enableController(uint8 i, uint8 j) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        address vault = _getRandomVault(j);

        _before();
        (success, returnData) = actor.proxy(
            address(evc), abi.encodeWithSelector(EthereumVaultConnector.enableController.selector, account, vault)
        );

        if (success) {
            _after();
        } else {
            revert("EVCHandler: enableController failed");
        }
    }

    function disableControllerEVC(uint8 i) external setup {
        bool success;
        bytes memory returnData;

        // Get one of the three actors randomly
        address account = _getRandomActor(i);

        _before();
        (success, returnData) = actor.proxy(
            address(evc), abi.encodeWithSelector(EthereumVaultConnector.disableController.selector, account)
        );

        if (success) {
            _after();
        } else {
            revert("EVCHandler: disableControllerEVC failed");
        }
    }

    ///////////////////////////////////////////////////////////////////////////////////////////////
    //                                           HELPERS                                         //
    ///////////////////////////////////////////////////////////////////////////////////////////////
}
