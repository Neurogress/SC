pragma solidity ^0.4.15;

contract IToken {
  uint256 public totalSupply;
  function mint(address _to, uint _amount) public returns(bool);
  function start() public;
  function balanceOf(address who) public constant returns (uint256);
  function transfer(address to, uint256 value) public returns (bool);
}

contract TokenTimelock {
  IToken public token;
  address public beneficiary;
  uint64 public releaseTime;

  function TokenTimelock(address _token, address _beneficiary, uint64 _releaseTime) public {
    require(_releaseTime > now);
    token = IToken(_token);
    beneficiary = _beneficiary;
    releaseTime = _releaseTime;
  }

  function release() public {
    require(now >= releaseTime);

    uint256 amount = token.balanceOf(this);
    require(amount > 0);

    token.transfer(beneficiary, amount);
  }
}
