// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity ^0.8.0;

// Internal Interfaces
import {IModule, IOrchestrator_v1} from "src/modules/base/IModule.sol";
import {IInverterBeacon_v1} from "src/proxies/interfaces/IInverterBeacon_v1.sol";

interface IModuleFactory_v1 {
    //--------------------------------------------------------------------------
    // Errors

    /// @notice Given metadata invalid.
    error ModuleFactory_v1__InvalidMetadata();

    /// @notice Given beacon invalid.
    error ModuleFactory_v1__InvalidInverterBeacon();

    /// @notice Given metadata unregistered.
    error ModuleFactory_v1__UnregisteredMetadata();

    /// @notice Given metadata already registered.
    error ModuleFactory_v1__MetadataAlreadyRegistered();

    //--------------------------------------------------------------------------
    // Events

    /// @notice Event emitted when new beacon registered for metadata.
    /// @param metadata The registered Metadata
    /// @param beacon The registered Beacon
    event MetadataRegistered(
        IModule.Metadata indexed metadata, IInverterBeacon_v1 indexed beacon
    );

    /// @notice Event emitted when new module created for a orchestrator_v1.
    /// @param orchestrator The corresponding orchestrator.
    /// @param module The created module instance.
    /// @param identifier The module's identifier.
    event ModuleCreated(
        address indexed orchestrator, address indexed module, bytes32 identifier
    );

    //--------------------------------------------------------------------------
    // Functions

    /// @notice Returns the governor_v1 contract address
    /// @return The address of the governor contract
    function governor() external view returns (address);

    /// @notice Creates a module instance identified by given metadata.
    /// @param metadata The module's metadata.
    /// @param orchestrator The orchestrator's instance of the module.
    /// @param configData The configData of the module
    function createModule(
        IModule.Metadata memory metadata,
        IOrchestrator_v1 orchestrator,
        bytes memory configData
    ) external returns (address);

    /// @notice Returns the {IInverterBeacon_v1} instance registered and the id for given
    ///         metadata.
    /// @param metadata The module's metadata.
    /// @return The module's {IInverterBeacon_v1} instance registered.
    /// @return The metadata's id.
    function getBeaconAndId(IModule.Metadata memory metadata)
        external
        view
        returns (IInverterBeacon_v1, bytes32);

    /// @notice Registers metadata `metadata` with {IInverterBeacon_v1} implementation
    ///         `beacon`.
    /// @dev Only callable by owner.
    /// @param metadata The module's metadata.
    /// @param beacon The module's {IInverterBeacon_v1} instance.
    function registerMetadata(
        IModule.Metadata memory metadata,
        IInverterBeacon_v1 beacon
    ) external;
}
