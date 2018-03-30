pragma solidity ^0.4.15;

import './ERC20.sol';
import '../lib/Owned.sol';


contract Token is Owned, StandartToken {
    string public name = "Neurogress";
    string public symbol = "NRG";
    uint public decimals = 18;

    address public crowdsaleMinter;

    event Mint(address indexed to, uint256 amount);

    modifier canMint() {
        require(!isStarted);
        _;
    }

    modifier onlyCrowdsaleMinter(){
        require(msg.sender == crowdsaleMinter);
        _;
    }

    function () public {
        revert();
    }

    function setCrowdsaleMinter(address _crowdsaleMinter)
        public
        onlyOwner
        canMint
    {
        crowdsaleMinter = _crowdsaleMinter;
    }

    function mint(address _to, uint256 _amount)
        onlyCrowdsaleMinter
        canMint
        public
        returns (bool)
    {
        totalSupply = totalSupply.add(_amount);
        balances[_to] = balances[_to].add(_amount);
        Mint(_to, _amount);
        return true;
    }

    function start()
        onlyCrowdsaleMinter
        canMint
        public
        returns (bool)
    {
        isStarted = true;
        return true;
    }
}
