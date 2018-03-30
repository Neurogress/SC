pragma solidity ^0.4.15;

import '../lib/SafeMath.sol';
import '../lib/Base.sol';
import '../lib/Owned.sol';
import '../token/TokenTimeLock.sol';


contract Crowdsale is Base, Owned {
    using SafeMath for uint256;

    enum State { INIT, PRESALE, PREICO, PREICO_FINISHED, ICO, REFUND_RUNNING, CLOSED, STOPPED }
    enum SupplyType { BOUNTY, SALE }

    uint public constant DECIMALS = 10**18;
    uint public constant MAX_PRESALE_SUPPLY = 1250000 * DECIMALS;
    uint public constant MAX_PREICO_SUPPLY = 16500000 * DECIMALS;
    uint public constant MAX_ICO_SUPPLY = 32250000 * DECIMALS;
    uint public constant MAX_BOUNTY_SUPPLY = 1500000 * DECIMALS;

    uint public constant TEAM_TOKENS = 8500000 * DECIMALS;
    uint public constant LOCKED_TEAM_TOKENS = 40000000 * DECIMALS;

    uint[] public ICO_BONUSES = [2000, 2000, 1500, 1500, 1000, 1000, 500, 500, 0, 0];

    State public currentState = State.INIT;
    IToken public token;

    uint public totalPresaleSupply = 0;
    uint public totalPreICOSupply = 0;
    uint public totalICOSupply = 0;
    uint public totalBountySupply = 0;

    uint public totalFunds = 0;
    uint public tokenPrice = 1 * (10**18); //wei
    uint public bonus = 5000; //50%
    uint public currentPrice;
    address public beneficiary;
    mapping(address => uint) balances;
    uint public countMembers = 0;

    TokenTimelock public lockedTeamTokens;

    uint private bonusBase = 10000; //100%;

    event Transfer(address indexed _to, uint256 _value, uint256 _amountWithoutBonuses, SupplyType _supplyType);

    modifier inState(State _state){
        require(currentState == _state);
        _;
    }

    modifier salesRunning(){
        require(currentState == State.PREICO || currentState == State.ICO);
        _;
    }

    modifier presaleOrSalesRunning(){
        require(currentState == State.PRESALE || currentState == State.PREICO || currentState == State.ICO);
        _;
    }

    modifier notStopped(){
        require(currentState != State.STOPPED);
        _;
    }

    function Crowdsale(address _beneficiary) public {
        beneficiary = _beneficiary;
    }

    function ()
        public
        payable
        salesRunning
    {
        _receiveFunds();
    }

    function initialize(address _token)
        public
        onlyOwner
        inState(State.INIT)
    {
        require(_token != address(0));

        token = IToken(_token);
        currentPrice = tokenPrice;

        totalBountySupply = totalBountySupply.add(token.totalSupply());
    }

    function setBonus(uint _bonus) public
        onlyOwner
        notStopped
    {
        bonus = _bonus;
    }

    function getBonus()
        public
        constant
        returns(uint)
    {
        return bonus.mul(100).div(bonusBase);
    }

    function setTokenPrice(uint _tokenPrice) public
        onlyOwner
        notStopped
    {
        currentPrice = _tokenPrice;
    }

    function setState(State _newState)
        public
        onlyOwner
    {
        require(
            currentState != State.STOPPED && (_newState == State.STOPPED ||
            (currentState == State.INIT && _newState == State.PRESALE
            || currentState == State.PRESALE && _newState == State.PREICO
            || currentState == State.PREICO && (_newState == State.REFUND_RUNNING || _newState == State.PREICO_FINISHED)
            || currentState == State.PREICO_FINISHED && _newState == State.ICO
            || currentState == State.ICO && (_newState == State.REFUND_RUNNING || _newState == State.CLOSED)
            || currentState == State.REFUND_RUNNING && _newState == State.CLOSED))
        );

        if(_newState == State.CLOSED){
            _finish();
        }

        currentState = _newState;
    }

    function refundBalance(address _owner)
      public
      constant
      returns(uint)
    {
      return balances[_owner];
    }

    function withdraw(uint _amount)
        public
        noAnyReentrancy
        onlyOwner
    {
        require(_amount > 0 && _amount <= this.balance);
        beneficiary.transfer(_amount);
    }

    function refund()
        public
        noAnyReentrancy
        inState(State.REFUND_RUNNING)
    {
        require(balances[msg.sender] != 0);
        uint amountToRefund = balances[msg.sender];
        balances[msg.sender] = 0;

        msg.sender.transfer(amountToRefund);
    }

    function investDirect(address _to, uint _amount)
        public
        onlyOwner
        presaleOrSalesRunning
    {
        uint _amountWithoutBonuses = _amount;

        _countCurrentBonus();
        uint bonusTokens = _amount.mul(bonus).div(bonusBase);
        _amount = _amount.add(bonusTokens);

        _checkMaxSaleSupply(_amount, SupplyType.SALE);

        _mint(_to, _amount, _amountWithoutBonuses, SupplyType.SALE);
    }

    function pureInvestDirect(address _to, uint _amount, SupplyType _supplyType)
        public
        onlyOwner
        presaleOrSalesRunning
    {
        _checkMaxSaleSupply(_amount, _supplyType);
        _mint(_to, _amount, _amount, _supplyType);
    }


    function getCountMembers()
    public
    constant
    returns(uint)
    {
        return countMembers;
    }

    function sendTeamTokens(address _teamAddress, address _lockedTeamAddress, uint64 _releaseTime)
        public
        onlyOwner
        presaleOrSalesRunning
    {
        require(lockedTeamTokens == address(0));
        require(_teamAddress != address(0));
        require(_lockedTeamAddress != address(0));

        IToken(token).mint(_teamAddress, TEAM_TOKENS);
        Transfer(_teamAddress, TEAM_TOKENS, TEAM_TOKENS, SupplyType.SALE);

        lockedTeamTokens = new TokenTimelock(token, _lockedTeamAddress, _releaseTime);

        IToken(token).mint(lockedTeamTokens, LOCKED_TEAM_TOKENS);
        Transfer(lockedTeamTokens, LOCKED_TEAM_TOKENS, LOCKED_TEAM_TOKENS, SupplyType.SALE);
    }

    //==================== Internal Methods =================
    function _mint(address _to, uint _amount, uint _amountWithoutBonuses, SupplyType _supplyType)
        noAnyReentrancy
        internal
    {
        _increaseSupply(_amount, _supplyType);
        IToken(token).mint(_to, _amount);
        Transfer(_to, _amount, _amountWithoutBonuses, _supplyType);
    }

    function _finish()
        noAnyReentrancy
        internal
    {
        IToken(token).start();
    }

    function _receiveFunds()
        internal
    {
        require(msg.value != 0);
        uint weiAmount = msg.value;
        uint transferTokens = weiAmount.mul(DECIMALS).div(currentPrice);
        uint tokensWithoutBonuses = transferTokens;

        _countCurrentBonus();

        uint bonusTokens = transferTokens.mul(bonus).div(bonusBase);
        transferTokens = transferTokens.add(bonusTokens);

        _checkMaxSaleSupply(transferTokens, SupplyType.SALE);

        if(balances[msg.sender] == 0){
            countMembers = countMembers.add(1);
        }

        balances[msg.sender] = balances[msg.sender].add(weiAmount);
        totalFunds = totalFunds.add(weiAmount);
        beneficiary.transfer(msg.value);
        _mint(msg.sender, transferTokens, tokensWithoutBonuses, SupplyType.SALE);
    }

    function _checkMaxSaleSupply(uint transferTokens, SupplyType _supplyType)
        internal
    {
        if(_supplyType == SupplyType.SALE) {
            if(currentState == State.PRESALE) {
                require(totalPresaleSupply.add(transferTokens) <= MAX_PRESALE_SUPPLY);
            } else if(currentState == State.PREICO) {
                require(totalPreICOSupply.add(transferTokens) <= MAX_PREICO_SUPPLY);
            } else if(currentState == State.ICO) {
                require(totalICOSupply.add(transferTokens) <= MAX_ICO_SUPPLY);
            }
        } else if(_supplyType == SupplyType.BOUNTY) {
            require(totalBountySupply.add(transferTokens) <= MAX_BOUNTY_SUPPLY);
        }
    }

    function _increaseSupply(uint _amount, SupplyType _supplyType)
        internal
    {
        if(_supplyType == SupplyType.SALE) {
            if(currentState == State.PRESALE) {
                totalPresaleSupply = totalPresaleSupply.add(_amount);
            } else if(currentState == State.PREICO) {
                totalPreICOSupply = totalPreICOSupply.add(_amount);
            } else if(currentState == State.ICO) {
                totalICOSupply = totalICOSupply.add(_amount);
            }
        } else if(_supplyType == SupplyType.BOUNTY) {
            totalBountySupply = totalBountySupply.add(_amount);
        }
    }

    function _countCurrentBonus()
        internal
    {
        if(currentState != State.ICO) {
            return;
        }
        uint currentPercentage = totalICOSupply.mul(10).div(MAX_ICO_SUPPLY);

        if(currentPercentage >= ICO_BONUSES.length) {
            currentPercentage = ICO_BONUSES.length - 1;
        }
        bonus = ICO_BONUSES[currentPercentage];
    }
}