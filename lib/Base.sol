pragma solidity ^0.4.15;


contract Base {
    
    modifier only(address allowed) {
        require(msg.sender == allowed);
        _;
    }

    // *************************************************
    // *          reentrancy handling                  *
    // *************************************************

    uint private bitlocks = 0;
    modifier noReentrancy(uint m) {
        var _locks = bitlocks;
        require(_locks & m <= 0);
        bitlocks |= m;
        _;
        bitlocks = _locks;
    }

    modifier noAnyReentrancy {
        var _locks = bitlocks;
        require(_locks <= 0);
        bitlocks = uint(-1);
        _;
        bitlocks = _locks;
    }

    modifier reentrant { _; }
}
