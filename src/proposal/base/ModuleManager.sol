// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// External Dependencies
import {ContextUpgradeable} from "@oz-up/utils/ContextUpgradeable.sol";
import {Initializable} from "@oz-up/proxy/utils/Initializable.sol";

// Internal Dependencies
import {Types} from "src/common/Types.sol";

// Interfaces
import {IModuleManager} from "src/proposal/base/IModuleManager.sol";

/**
 * @title Module Manager
 *
 * @dev A contract to manage modules that can execute transactions via this
 *      contract and manage own role-based access control mechanisms.
 *
 *      The role-based access control mechanism is based on OpenZeppelin's
 *      AccessControl contract. Each module has it's own access control context
 *      which it is able to freely manage.
 *
 *      The transaction execution and module management is copied from Gnosis
 *      Safe's [ModuleManager](https://github.com/safe-global/safe-contracts/blob/main/contracts/base/ModuleManager.sol).
 *
 * @author Adapted from Gnosis Safe
 * @author byterocket
 */
abstract contract ModuleManager is
    IModuleManager,
    Initializable,
    ContextUpgradeable
{
    //--------------------------------------------------------------------------
    // Modifiers

    modifier __ModuleManager_onlyAuthorized() {
        if (!__ModuleManager_isAuthorized(_msgSender())) {
            revert Proposal__ModuleManager__CallerNotAuthorized();
        }
        _;
    }

    modifier onlyModule() {
        if (!isModule(_msgSender())) {
            revert Proposal__ModuleManager__OnlyCallableByModule();
        }
        _;
    }

    modifier validModule(address module) {
        _ensureValidModule(module);
        _;
    }

    modifier isModule_(address module) {
        if (!isModule(module)) {
            revert Proposal__ModuleManager__IsNotModule();
        }
        _;
    }

    modifier isNotModule(address module) {
        _ensureNotModule(module);
        _;
    }

    modifier onlyConsecutiveModules(address prevModule, address module) {
        if (_modules[prevModule] != module) {
            revert Proposal__ModuleManager__ModulesNotConsecutive();
        }
        _;
    }

    //--------------------------------------------------------------------------
    // Constants

    address private constant _SENTINEL = address(0x1);

    //--------------------------------------------------------------------------
    // Storage

    /// @dev Mapping of modules.
    mapping(address => address) private _modules;

    uint private _moduleCounter;

    /// @dev Mapping of modules and access control roles to accounts and
    ///      whether they holds that role.
    /// @dev module address => role => account address => bool.
    ///
    /// @custom:invariant Modules can only mutate own account roles.
    /// @custom:invariant Only modules can mutate not own account roles.
    /// @custom:invariant Account can always renounce own roles.
    /// @custom:invariant Roles only exist for enabled modules.
    mapping(address => mapping(bytes32 => mapping(address => bool))) private
        _moduleRoles;

    //--------------------------------------------------------------------------
    // Initializer

    function __ModuleManager_init(address[] calldata modules)
        internal
        onlyInitializing
    {
        __Context_init();

        // Set up sentinel to signal empty list of modules.
        _modules[_SENTINEL] = _SENTINEL;

        // @todo mp: Change modules from address to IModules.
        //           This enables easier refactoring in future for "multi-modules".
        //           Or not???

        address module;
        for (uint i; i < modules.length; i++) {
            module = modules[i];

            // Ensure module address is valid and module not already added.
            _ensureValidModule(module);
            _ensureNotModule(module);

            // Commit adding the module.
            _commitAddModule(module);

            // @todo mp: Call into module to "register this proposal" as using
            //           that module instance?
            // This would make it possible to have "multi-modules".
            // One module contract that is an active module for infinite many
            // proposals by saving it's state on a per-proposal basis.
        }
    }

    function __ModuleManager_addModule(address module)
        internal
        isNotModule(module)
        validModule(module)
    {
        _commitAddModule(module);
    }

    //--------------------------------------------------------------------------
    // Internal Functions Implemented in Downstream Contract

    /// @dev Returns whether address `who` is authorized to mutate module
    ///      manager's state.
    /// @dev MUST be overriden in downstream contract.
    function __ModuleManager_isAuthorized(address who)
        internal
        view
        virtual
        returns (bool);

    //--------------------------------------------------------------------------
    // Public View Functions

    /// @inheritdoc IModuleManager
    function hasRole(address module, bytes32 role, address account)
        public
        view
        returns (bool)
    {
        return isModule(module) && _moduleRoles[module][role][account];
    }

    /// @inheritdoc IModuleManager
    function isModule(address module)
        public
        view
        override (IModuleManager)
        returns (bool)
    {
        return module != _SENTINEL && _modules[module] != address(0);
    }

    /// @inheritdoc IModuleManager
    function listModules() external view returns (address[] memory) {
        address[] memory result = new address[](_moduleCounter);

        // Populate result array.
        uint index = 0;
        address elem = _modules[_SENTINEL];
        while (elem != _SENTINEL) {
            result[index] = elem;
            elem = _modules[elem];
            index++;
        }

        return result;
    }

    //--------------------------------------------------------------------------
    // onlyAuthorized Functions

    /// @inheritdoc IModuleManager
    function addModule(address module)
        public
        __ModuleManager_onlyAuthorized
        isNotModule(module)
        validModule(module)
    {
        _commitAddModule(module);
    }

    /// @inheritdoc IModuleManager
    function removeModule(address prevModule, address module)
        public
        __ModuleManager_onlyAuthorized
        isModule_(module)
        onlyConsecutiveModules(prevModule, module)
    {
        _commitRemoveModule(prevModule, module);
    }

    //--------------------------------------------------------------------------
    // onlyModule Functions

    /// @inheritdoc IModuleManager
    function executeTxFromModule(
        address to,
        bytes memory data,
        Types.Operation operation
    )
        public
        override (IModuleManager)
        onlyModule
        returns (bool, bytes memory)
    {
        bool ok;
        bytes memory returnData;

        if (operation == Types.Operation.Call) {
            (ok, returnData) = to.call(data);
        } else {
            (ok, returnData) = to.delegatecall(data);
        }

        return (ok, returnData);
    }

    /// @inheritdoc IModuleManager
    function grantRole(bytes32 role, address account) public onlyModule {
        if (!hasRole(_msgSender(), role, account)) {
            _moduleRoles[_msgSender()][role][account] = true;
            emit ModuleRoleGranted(_msgSender(), role, account);
        }
    }

    /// @inheritdoc IModuleManager
    function revokeRole(bytes32 role, address account) public onlyModule {
        if (hasRole(_msgSender(), role, account)) {
            _moduleRoles[_msgSender()][role][account] = false;
            emit ModuleRoleRevoked(_msgSender(), role, account);
        }
    }

    //--------------------------------------------------------------------------
    // Public Mutating Functions

    /// @inheritdoc IModuleManager
    function renounceRole(address module, bytes32 role) public {
        if (hasRole(module, role, _msgSender())) {
            _moduleRoles[module][role][_msgSender()] = false;
            emit ModuleRoleRevoked(module, role, _msgSender());
        }
    }

    //--------------------------------------------------------------------------
    // Private Functions

    /// @dev Expects `module` to be valid module address.
    /// @dev Expects `module` to not be enabled module.
    function _commitAddModule(address module) private {
        // Add address to _modules mapping.
        _modules[module] = _modules[_SENTINEL];
        _modules[_SENTINEL] = module;
        _moduleCounter++;

        emit ModuleAdded(module);
    }

    /// @dev Expect address arguments to be consecutive in the modules list.
    /// @dev Expects address `module` to be enabled module.
    function _commitRemoveModule(address prevModule, address module) private {
        // Remove module address from list and decrease counter.
        _modules[prevModule] = _modules[module];
        delete _modules[module];
        _moduleCounter--;

        // @todo marvin, mp: See comment.
        //                   Should we maybe allow roles managemant for
        //                   non-modules too?
        //                   Then a disabled module could revoke roles before
        //                   being re-enabled again.
        // Note that we cannot delete the module's roles configuration.
        // This means that in case a module is disabled and then re-enabled,
        // its roles configuration is the same as before.
        // Note that this could potentially lead to security issues!

        emit ModuleRemoved(module);
    }

    function _ensureValidModule(address module) private view {
        // @todo mp: Make gas optimized.
        bool isZero = module == address(0);
        bool isSentinel = module == _SENTINEL;
        bool isThis = module == address(this);

        if (isZero || isSentinel || isThis) {
            revert Proposal__ModuleManager__InvalidModuleAddress();
        }
    }

    function _ensureNotModule(address module) private view {
        if (isModule(module)) {
            revert Proposal__ModuleManager__IsModule();
        }
    }
}
