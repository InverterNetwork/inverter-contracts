// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

import "forge-std/Test.sol";

// Internal Interfaces
import {IAuthorizer} from "src/interfaces/IAuthorizer.sol";

/**
 * @dev Helper contract providing `_assume...` functions to check fuzzer inputs.
 */
abstract contract FuzzInputChecker is Test {
    // Helper Caches.
    mapping(address => bool) modulesCache;

    function _assumeValidProposalId(uint proposalId) internal {}

    function _assumeValidFunders(address[] memory funders) internal {}

    function _assumeValidModulesWithAuthorizer(
        address[] memory modules,
        IAuthorizer authorizer
    ) internal {
        _assumeValidModules(modules);

        address module;
        for (uint i; i < modules.length; i++) {
            module = modules[i];

            // Assume module not authorizer instance.
            vm.assume(module != address(authorizer));
        }
    }

    function _assumeValidModules(address[] memory modules) internal {
        // Note that at least two modules are necessary to replace them with
        // an authorizer and a payer instance.
        vm.assume(modules.length > 2);

        address module;
        for (uint i; i < modules.length; i++) {
            module = modules[i];

            _assumeValidModule(module);

            // Assume unique module.
            vm.assume(!modulesCache[module]);

            // Add module to modules cache.
            modulesCache[module] = true;
        }
    }

    function _assumeValidModule(address module) internal {
        vm.assume(module != address(0));
    }
}
