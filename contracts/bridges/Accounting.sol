// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "../interfaces/IBonderRegistry.sol";

/**
 * @dev Accounting is an abstract contract that encapsulates the most critical logic in the Hop contracts.
 * The accounting system works by using two balances that can only increase `_credit` and `_debit`.
 * A bonder's available balance is the total credit minus the total debit. The contract exposes
 * two external functions that allows a bonder to stake and unstake and exposes two internal
 * functions to its child contracts that allow the child contract to add to the credit 
 * and debit balance. In addition, child contracts can override `_additionalDebit` to account
 * for any additional debit balance in an alternative way. Lastly, it exposes a modifier,
 * `requirePositiveBalance`, that can be used by child contracts to ensure the bonder does not
 * use more than its available stake.
 */

abstract contract Accounting is ReentrancyGuard {
    using SafeMath for uint256;

    IBonderRegistry registry;

    mapping(address => uint256) private _credit;
    mapping(address => uint256) private _debit;

    event Stake (
        address indexed account,
        uint256 amount
    );

    event Unstake (
        address indexed account,
        uint256 amount
    );

    event BonderAdded (
        address indexed newBonder
    );

    event BonderRemoved (
        address indexed previousBonder
    );

    /* ========== Modifiers ========== */

    modifier onlyBonder {
        require(getIsBonder(msg.sender), "ACT: Caller is not registered bonder");
        _;
    }

    modifier onlyGovernance {
        _requireIsGovernance();
        _;
    }

    /// @dev Used by parent contract to ensure that the Bonder is solvent at the end of the transaction.
    modifier requirePositiveBalance {
        _;
        require(getCredit(msg.sender) >= getDebitAndAdditionalDebit(msg.sender), "ACT: Not enough available credit");
    }

    /// @dev Sets the Bonder addresses
    constructor(IBonderRegistry _registry) public {
        registry = _registry;
    }

    /* ========== Virtual functions ========== */
    /**
     * @dev The following functions are overridden in L1_Bridge and L2_Bridge
     */
    function _transferFromBridge(address recipient, uint256 amount) internal virtual;
    function _transferToBridge(address from, uint256 amount) internal virtual;
    function _requireIsGovernance() internal virtual;

    /**
     * @dev This function can be optionally overridden by a parent contract to track any additional
     * debit balance in an alternative way.
     */
    function _additionalDebit(address /*bonder*/) internal view virtual returns (uint256) {
        this; // Silence state mutability warning without generating any additional byte code
        return 0;
    }

    /* ========== Public/external getters ========== */

    /**
     * @dev Check if address is a Bonder
     * @param maybeBonder The address being checked
     * @return true if address is a Bonder
     */
    function getIsBonder(address maybeBonder) public view returns (bool) {
        return registry.isBonderAllowed(maybeBonder, _credit[maybeBonder]);
    }

    /**
     * @dev Get the Bonder's credit balance
     * @param bonder The owner of the credit balance being checked
     * @return The credit balance for the Bonder
     */
    function getCredit(address bonder) public view returns (uint256) {
        return _credit[bonder];
    }

    /**
     * @dev Gets the debit balance tracked by `_debit` and does not include `_additionalDebit()`
     * @param bonder The owner of the debit balance being checked
     * @return The debit amount for the Bonder
     */
    function getRawDebit(address bonder) external view returns (uint256) {
        return _debit[bonder];
    }

    /**
     * @dev Get the Bonder's total debit
     * @param bonder The owner of the debit balance being checked
     * @return The Bonder's total debit balance
     */
    function getDebitAndAdditionalDebit(address bonder) public view returns (uint256) {
        return _debit[bonder].add(_additionalDebit(bonder));
    }

    /* ========== External Config Management Setters ========== */

    function setRegistry(IBonderRegistry _registry) external onlyGovernance {
        require(_registry != IBonderRegistry(0), "L1_BRG: _registry cannot be address(0)");
        registry = _registry;
    }

    /* ========== Bonder external functions ========== */

    /** 
     * @dev Allows the Bonder to deposit tokens and increase its credit balance
     * @param bonder The address being staked on
     * @param amount The amount being staked
     */
    function stake(address bonder, uint256 amount) external payable nonReentrant {
        _transferToBridge(msg.sender, amount);
        _credit[bonder] = _credit[bonder].add(amount);

        emit Stake(bonder, amount);
    }

    /**
     * @dev Allows the caller to withdraw any available balance and add to their debit balance
     * @param amount The amount being unstaked
     */
    function unstake(uint256 amount) external requirePositiveBalance nonReentrant {
        _credit[msg.sender] = _credit[msg.sender].sub(amount);
        _transferFromBridge(msg.sender, amount);

        emit Unstake(msg.sender, amount);
    }

    /* ========== Internal functions ========== */

    function _addCredit(address bonder, uint256 amount) internal {
        _credit[bonder] = _credit[bonder].add(amount);
    }

    function _addDebit(address bonder, uint256 amount) internal {
        _debit[bonder] = _debit[bonder].add(amount);
    }

    function _subDebit(address bonder, uint256 amount) internal {
        _debit[bonder] = _debit[bonder].sub(amount);
    }
}
