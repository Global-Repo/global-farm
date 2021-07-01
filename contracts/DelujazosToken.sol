// SPDX-License-Identifier: Unlicensed

import './Ownable.sol';
import './DevPower.sol';
import './IBEP20.sol';
import './BEP20.sol';
import './SafeMath.sol';
import './Address.sol';

pragma solidity 0.6.12;

/* CAMBIAR: Nombre del swap y del token en constructor BEP20 */
contract DelujazosToken is BEP20{
	
	// DS: Burn address podria ser 0x0 però mola més un 0x...dEaD;
	address public constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
	
	// DS: màxim antiwhale que podem posar. Per defecte, ningú podrà enviar més del 15% del supply mai. 
	// DS: no hi ha mínim, perque si hi ha un atac, podria ser-nos útil evitar que hi hagi transfers de tokens.
	uint16 public constant MAX_ANTIWHALE = 1500;
	
	// DS: A aquestes adreces no els hi aplica el mecanisme antiwhale
    mapping(address => bool) private _antiWhaleWhiteList;
	
    // DS: 2% del supply és el màxim que es pot transferir inicialment (es podrà modificar després). En diferent base per evitar decimals.
    uint16 public antiWhalePercent = 200;
	
    // DS: El dev és el únic que pot modificar les variables propies del token.
    address private _mainDevWallet;
	
	// Events
    event MaxTransferAntiWhale(address indexed devPower, uint256 oldAntiWhalePercent, uint256 newAntiWhalePercent);
		
	// DS: Constructor del token. Els paràmetres passen pel constructor del BEP20 + afegim adreces antiwhale whitelisted.
	// DS: OnlyOwner i DevPower = msg.sender.
    constructor() public BEP20('TestingSwap', 'Delujos'){
		
		// DS: el dev/contracte poden transferir entre ells o enviar a BURN_ADDRESS/address(0) sense problemes.
		_antiWhaleWhiteList[msg.sender] = true;
		_antiWhaleWhiteList[address(this)] = true;
		_antiWhaleWhiteList[BURN_ADDRESS] = true;
		_antiWhaleWhiteList[address(0)] = true;
    }
	
	// DS: Getter if excluded from antiwhale
    function GetIfExcludedFromAntiWhale(address addr) public view returns (bool) {
        return _antiWhaleWhiteList[addr];
    }
	
	// DS: Per emergències o coses puntuals, si hem d'activar/desactivar alguna direcció de l'antiwhale
    function setExcludedFromAntiWhale(address addr, bool _excluded) public onlyDevPower {
        _antiWhaleWhiteList[addr] = _excluded;
    }
	
    // DS: Calculem el màxim de tokens que ens permetrà transferir l'antiwhale (depèn del totalSupply(), implementat a BEP20 + IBEP20).
    function maxTokensTransferAmountAntiWhaleMethod() public view returns (uint256) {
        return totalSupply().mul(antiWhalePercent).div(10000);
    }
	
	// DS: setejem un nou antiwhale percent. Lo normal serà anar baixant aquest valor a mesura que puji el marketcap. 
	function updateMaxTransferAntiWhale(uint16 _newAntiWhalePercent) public onlyDevPower {
        require(_newAntiWhalePercent <= MAX_ANTIWHALE, "[!] Antiwhale method triggered. You are trying to set a % which is too high Check MAX_ANTIWHALE in the SC.");
        emit MaxTransferAntiWhale(msg.sender, antiWhalePercent, _newAntiWhalePercent);
        antiWhalePercent = _newAntiWhalePercent;
    }
	
	// DS: Setejem una condició a comprovar a una funció (transfer) abans d'executar-la. 
    modifier antiWhale(address origen, address destinataria, uint256 q) {
        
		// DS: Comprovació simple per saber que no hi ha hagut problemes. El número de tokens mínims permesos en una transfer ha de ser superior a 0.
		if (maxTokensTransferAmountAntiWhaleMethod() > 0) {
			
			// DS: només podem saltar-nos l'antiwhale si tan origen com destí estàn whitelisted. Un dev no se'l pot saltar amb un user.
            if (_antiWhaleWhiteList[origen] == false && _antiWhaleWhiteList[destinataria] == false) 
			{
                require(q <= maxTokensTransferAmountAntiWhaleMethod(), "[!] Antiwhale method triggered. You are trying to transfer too many tokens. Calm down and don't panic sell bro.");
            }
        }
        _;
    }
		
    // DS: fem override del _transfer, que és la funció que fa el _transfer "final" i serveix per poder aplicar característiques pròpies [Veure BEP20.sol].
    function _transfer(address sender, address recipient, uint256 amount) internal virtual override antiWhale(sender, recipient, amount) {
		
		// Fem servir el transfer normal.
		super._transfer(sender, recipient, amount);
    }
	
    /// @notice Creates `_amount` token to `_to`. Must only be called by the owner (MasterChef).
    function mint(address _to, uint256 _amount) public onlyOwner {
        _mint(_to, _amount);
        _moveDelegates(address(0), _delegates[_to], _amount);
    }
    
    function safe32(uint n, string memory errorMessage) internal pure returns (uint32) {
        require(n < 2**32, errorMessage);
        return uint32(n);
    }

    function getChainId() internal pure returns (uint) {
        uint256 chainId;
        assembly { chainId := chainid() }
        return chainId;
    }

    /// @dev A record of each accounts delegate
    mapping (address => address) internal _delegates;

    /// @dev A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint32 fromBlock;
        uint256 votes;
    }

    /// @dev A record of votes checkpoints for each account, by index
    mapping (address => mapping (uint32 => Checkpoint)) public checkpoints;

    /// @dev The number of checkpoints for each account
    mapping (address => uint32) public numCheckpoints;

    /// @dev The EIP-712 typehash for the contract's domain
    bytes32 public constant DOMAIN_TYPEHASH = keccak256("EIP712Domain(string name,uint256 chainId,address verifyingContract)");

    /// @dev The EIP-712 typehash for the delegation struct used by the contract
    bytes32 public constant DELEGATION_TYPEHASH = keccak256("Delegation(address delegatee,uint256 nonce,uint256 expiry)");

    /// @dev of states for signing / validating signatures
    mapping (address => uint) public nonces;

      /// @dev An event thats emitted when an account changes its delegate
    event DelegateChanged(address indexed delegator, address indexed fromDelegate, address indexed toDelegate);

    /// @dev An event thats emitted when a delegate account's vote balance changes
    event DelegateVotesChanged(address indexed delegate, uint previousBalance, uint newBalance);

    /**
     * @dev Delegate votes from `msg.sender` to `delegatee`
     * @param delegator The address to get delegatee for
     */
    function delegates(address delegator) external view returns (address)    
	{
        return _delegates[delegator];
    }


	
   /**
    * @dev votes from `msg.sender` to `delegatee`
    * @param delegatee The address to delegate votes to
    */
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /**
     * @dev Delegates votes from signatory to `delegatee`
     * @param delegatee The address to delegate votes to
     * @param nonce The contract state required to match the signature
     * @param expiry The time at which to expire the signature
     * @param v The recovery byte of the signature
     * @param r Half of the ECDSA signature pair
     * @param s Half of the ECDSA signature pair
     */
    function delegateBySig(
        address delegatee,
        uint nonce,
        uint expiry,
        uint8 v,
        bytes32 r,
        bytes32 s
    )
        external
    {
        bytes32 domainSeparator = keccak256(
            abi.encode(
                DOMAIN_TYPEHASH,
                keccak256(bytes(name())),
                getChainId(),
                address(this)
            )
        );

        bytes32 structHash = keccak256(
            abi.encode(
                DELEGATION_TYPEHASH,
                delegatee,
                nonce,
                expiry
            )
        );

        bytes32 digest = keccak256(
            abi.encodePacked(
                "\x19\x01",
                domainSeparator,
                structHash
            )
        );

        address signatory = ecrecover(digest, v, r, s);
        require(signatory != address(0), "CAKE::delegateBySig: invalid signature");
        require(nonce == nonces[signatory]++, "CAKE::delegateBySig: invalid nonce");
        require(now <= expiry, "CAKE::delegateBySig: signature expired");
        return _delegate(signatory, delegatee);
    }

    /**
     * @notice Gets the current votes balance for `account`
     * @param account The address to get votes balance
     * @return The number of current votes for `account`
     */
    function getCurrentVotes(address account)
        external
        view
        returns (uint256)
    {
        uint32 nCheckpoints = numCheckpoints[account];
        return nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /**
     * @notice Determine the prior number of votes for an account as of a block number
     * @dev Block number must be a finalized block or else this function will revert to prevent misinformation.
     * @param account The address of the account to check
     * @param blockNumber The block number to get the vote balance at
     * @return The number of votes the account had as of the given block
     */
    function getPriorVotes(address account, uint blockNumber)
        external
        view
        returns (uint256)
    {
        require(blockNumber < block.number, "CAKE::getPriorVotes: not yet determined");

        uint32 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint32 lower = 0;
        uint32 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint32 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    function _delegate(address delegator, address delegatee)
        internal
    {
        address currentDelegate = _delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator); // balance of underlying CAKEs (not scaled);
        _delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(address srcRep, address dstRep, uint256 amount) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                // decrease old representative
                uint32 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0 ? checkpoints[srcRep][srcRepNum - 1].votes : 0;
                uint256 srcRepNew = srcRepOld.sub(amount);
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                // increase new representative
                uint32 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0 ? checkpoints[dstRep][dstRepNum - 1].votes : 0;
                uint256 dstRepNew = dstRepOld.add(amount);
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint32 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    )
        internal
    {
        uint32 blockNumber = safe32(block.number, "CAKE::_writeCheckpoint: block number exceeds 32 bits");

        if (nCheckpoints > 0 && checkpoints[delegatee][nCheckpoints - 1].fromBlock == blockNumber) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(blockNumber, newVotes);
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }
}
