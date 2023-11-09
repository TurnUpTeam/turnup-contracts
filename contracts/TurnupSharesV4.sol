// SPDX-License-Identifier: MIT

// for security it is better to lock the version
pragma solidity 0.8.19;

import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
// import "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {OwnableUpgradeable} from "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";

contract TurnupSharesV4 is Initializable, OwnableUpgradeable {
    address public protocolFeeDestination;
    uint256 public protocolFeePercent;
    uint256 public subjectFeePercent;

    // SharesSubject => (Holder => Balance)
    mapping(address => mapping(address => uint256)) public sharesBalance;

    // SharesSubject => Supply
    mapping(address => uint256) public sharesSupply;

    mapping (address => address) public authorizedWishes;

    struct WishPass {
        address owner;
        address subject;
        uint256 totalSupply;    
        uint256 subjectReward;
        bool    isClaimReward;
        uint256 reservedQuantity;
        mapping(address => uint256) balanceOf;
    }
    mapping (address => WishPass) public wishPasses;

    enum SubjectType { 
        WISH, 
        BIND, 
        KEY 
    }

	event Trade(address trader, address subject, bool isBuy, uint256 shareAmount, uint256 ethAmount, uint256 protocolEthAmount, uint256 subjectEthAmount, uint256 supply, SubjectType subjectType);

    modifier onlyIfSetup() {
        require(protocolFeeDestination != address(0), "Protocol fee destination not set");
        require(protocolFeePercent > 0, "Protocol fee percent not set");
        require(subjectFeePercent > 0, "Subject fee percent not set");
    _;
    }

    function initialize() public initializer {
        __Ownable_init(); 
    }
 
    function getVer() public pure returns(string memory) {
        return "v4.1.5";
    }

    // @dev Set the destination fee
    // @param _feeDestination The address of the destination
    function setFeeDestination(address _feeDestination) public virtual onlyOwner {
        require(_feeDestination != address(0), "Invalid zero address");
        protocolFeeDestination = _feeDestination;
    }

    // @dev Set the protocol fee percent
    // @param _feePercent The percent of the protocol fee
    function setProtocolFeePercent(uint256 _feePercent) public virtual onlyOwner {
        protocolFeePercent = _feePercent;
    }

    // @dev Set the subject fee percent
    // @param _feePercent The percent of the subject fee
    function setSubjectFeePercent(uint256 _feePercent) public virtual onlyOwner {
        subjectFeePercent = _feePercent;
    }

    // @dev Get the price of a given amount of shares
    // @param supply The current supply of keys
    // @param amount The amount of keys to buy
    // @return The price of the given amount of keys
    function getPrice(uint256 supply, uint256 amount) public pure virtual returns (uint256) {
        uint256 sum1 = supply == 0 ? 0 : (supply - 1 )* (supply) * (2 * (supply - 1) + 1) / 6;
        uint256 sum2 = supply == 0 && amount == 1 ? 0 : (supply + amount - 1) * (supply + amount) * (2 * (supply + amount - 1) + 1) / 6;
        uint256 summation = sum2 - sum1; 
        return (summation * 1 ether) / 2000;
    }

    // @dev Get the current supply of shares
    // @param sharesSubject The subject of the shares
    // @return The current supply of shares
    function getSupply(address sharesSubject) public view virtual returns (uint256) {
        if (wishPasses[sharesSubject].owner != address(0)) {
            return wishPasses[sharesSubject].totalSupply;
        } else if (authorizedWishes[sharesSubject] != address(0)) {
            address wisher = authorizedWishes[sharesSubject];
            return wishPasses[wisher].totalSupply;
        } else {
            return sharesSupply[sharesSubject];
        }
    }

    function getBalance(address sharesSubject, address holderAddress) public view virtual returns (uint256) {
        if (wishPasses[sharesSubject].owner != address(0)) {
            return wishPasses[sharesSubject].balanceOf[holderAddress];
        } else if (authorizedWishes[sharesSubject] != address(0)) {
            address wisher = authorizedWishes[sharesSubject];
            return wishPasses[wisher].balanceOf[holderAddress]; 
        } else {
            return sharesBalance[sharesSubject][holderAddress];
        }
    }


    // @dev Get the buy price of a given amount of shares
    // @param sharesSubject The subject of the shares
    // @param amount The amount of shares to buy
    // @return The buy price of the given amount of shares
    function getBuyPrice(address sharesSubject, uint256 amount) public view virtual returns (uint256) {
        uint256 supply = getSupply(sharesSubject);
        return getPrice(supply, amount);
    }

    // @dev Get the sell price of a given amount of shares
    // @param sharesSubject The subject of the shares
    // @param amount The amount of shares to sell
    // @return The sell price of the given amount of shares
    function getSellPrice(address sharesSubject, uint256 amount) public view virtual returns (uint256) {
        uint256 supply = getSupply(sharesSubject);
        require(supply >= amount, "Invalid amount");
        return getPrice(supply - amount, amount);
    }

    // @dev Get the buy price of a given amount of shares after fees
    // @param sharesSubject The subject of the shares
    // @param amount The amount of shares to buy
    // @return The buy price of the given amount of shares after fees
    function getBuyPriceAfterFee(address sharesSubject, uint256 amount) public view returns (uint256) {
        uint256 price = getBuyPrice(sharesSubject, amount);
        uint256 protocolFee = getProtocolFee(price);
        uint256 subjectFee = getSubjectFee(price);
        return price + protocolFee + subjectFee;
    }

    // @dev Get the sell price of a given amount of shares after fees
    // @param sharesSubject The subject of the shares
    // @param amount The amount of shares to sell
    // @return The sell price of the given amount of shares after fees
    function getSellPriceAfterFee(address sharesSubject, uint256 amount) public view virtual returns (uint256) {
        uint256 price = getSellPrice(sharesSubject, amount);
        uint256 protocolFee = getProtocolFee(price);
        uint256 subjectFee = getSubjectFee(price);
        return price - protocolFee - subjectFee;
    }

    // @dev Get the protocol fee of a given price
    // @param price The price
    function getProtocolFee(uint256 price) public view virtual returns (uint256) {
        return (price * protocolFeePercent) / 1 ether;
    }

    // @dev Get the subject fee of a given price
    // @param price The price
    function getSubjectFee(uint256 price) public view virtual returns (uint256) {
        return (price * subjectFeePercent) / 1 ether;
    }

    // @dev Buy shares for a given subject
    // @param sharesSubject The subject of the shares
    // @param amount The amount of shares to buy
    function buyShares(address sharesSubject, uint256 amount) public payable virtual onlyIfSetup {
        uint256 supply = getSupply(sharesSubject);
        // solhint-disable-next-line reason-string
        require(supply > 0 || sharesSubject == msg.sender, "Only the keys' owner can buy the first key");
        
        uint256 price = getPrice(supply, amount);
        uint256 protocolFee = getProtocolFee(price);
        uint256 subjectFee = getSubjectFee(price);

        // solhint-disable-next-line reason-string
        require(msg.value >= price + protocolFee + subjectFee, "Transaction failed due to price fluctuations");
         
        SubjectType subjectType;

        if (wishPasses[sharesSubject].owner != address(0)) {
            require(wishPasses[sharesSubject].subject == address(0), "bound cant be buy");
            subjectType = SubjectType.WISH;
            wishPasses[sharesSubject].totalSupply += amount;
            wishPasses[sharesSubject].balanceOf[msg.sender] += amount;
            wishPasses[sharesSubject].subjectReward += subjectFee;
            (bool success, ) = protocolFeeDestination.call{value: protocolFee}("");
            require(success, "Unable to send funds");
        } else if (authorizedWishes[sharesSubject] != address(0)) {
            subjectType = SubjectType.BIND;
            address wisher = authorizedWishes[sharesSubject];
            wishPasses[wisher].totalSupply += amount;
            wishPasses[wisher].balanceOf[msg.sender] += amount;
            (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
            (bool success2, ) = sharesSubject.call{value: subjectFee}("");
            require(success1 && success2, "Unable to send funds");
        } else {
            subjectType = SubjectType.KEY;
            sharesBalance[sharesSubject][msg.sender] += amount;
            sharesSupply[sharesSubject] += amount;
            (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
            (bool success2, ) = sharesSubject.call{value: subjectFee}("");
            require(success1 && success2, "Unable to send funds");
        }

        emit Trade(msg.sender, sharesSubject, true, amount, price, protocolFee, subjectFee, supply + amount, subjectType); 
    }

    // @dev Sell shares for a given subject
    // @param sharesSubject The subject of the shares
    // @param amount The amount of shares to sell
    function sellShares(address sharesSubject, uint256 amount) public payable virtual onlyIfSetup {
        uint256 supply = getSupply(sharesSubject);
        require(supply > amount, "Cannot sell the last key");
        
        uint256 price = getPrice(supply - amount, amount);
        uint256 protocolFee = getProtocolFee(price);
        uint256 subjectFee = getSubjectFee(price);
        
        SubjectType subjectType;

        if (wishPasses[sharesSubject].owner != address(0)) {
            require(wishPasses[sharesSubject].subject == address(0), "bound cant be sell");
            uint256 balance = wishPasses[sharesSubject].balanceOf[msg.sender];
            require(balance >= amount, "Insufficient keys");
            require(sharesSubject != msg.sender || balance > amount, "You cannot sell your last key");

            subjectType = SubjectType.WISH;
            wishPasses[sharesSubject].totalSupply -= amount;
            wishPasses[sharesSubject].balanceOf[msg.sender] -= amount;
            wishPasses[sharesSubject].subjectReward += subjectFee;
            
            (bool success1, ) = msg.sender.call{value: price - protocolFee - subjectFee}("");
            (bool success2, ) = protocolFeeDestination.call{value: protocolFee}(""); 
            require(success1 && success2, "Unable to send funds");
        } else if (authorizedWishes[sharesSubject] != address(0)) { 
            address wisher = authorizedWishes[sharesSubject];
            uint256 balance = wishPasses[wisher].balanceOf[msg.sender];
            require(balance >= amount, "Insufficient keys");
            require(sharesSubject != msg.sender || balance > amount, "You cannot sell your last key");

            subjectType = SubjectType.BIND;
            wishPasses[sharesSubject].totalSupply -= amount;
            wishPasses[sharesSubject].balanceOf[msg.sender] -= amount;

            (bool success1, ) = msg.sender.call{value: price - protocolFee - subjectFee}("");
            (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
            (bool success3, ) = sharesSubject.call{value: subjectFee}("");
            require(success1 && success2 && success3, "Unable to send funds");
        } else { 
            uint256 balance = sharesBalance[sharesSubject][msg.sender];
            require(sharesSubject != msg.sender || balance > amount, "You cannot sell your last key");
            require(balance >= amount, "Insufficient keys");

            subjectType = SubjectType.KEY;
            sharesBalance[sharesSubject][msg.sender] -= amount;
            sharesSupply[sharesSubject] -= amount;

            (bool success1, ) = msg.sender.call{value: price - protocolFee - subjectFee}("");
            (bool success2, ) = protocolFeeDestination.call{value: protocolFee}("");
            (bool success3, ) = sharesSubject.call{value: subjectFee}("");
            require(success1 && success2 && success3, "Unable to send funds");
        }   

        emit Trade(msg.sender, sharesSubject, false, amount, price, protocolFee, subjectFee, supply - amount, subjectType); 
    }

    function batchGetBuyPrice(address[] calldata sharesSubjects, uint256[] calldata amounts) public view returns(address[] memory, uint256[] memory) {
        require(sharesSubjects.length == amounts.length, "Wrong amount");
        uint256[] memory prices = new uint256[](amounts.length);
        for (uint256 i = 0; i < sharesSubjects.length; i++) {
            prices[i] = getBuyPrice(sharesSubjects[i], amounts[i]);
        }
        return (sharesSubjects, prices);
    }

    function batchGetBuyPriceAfterFee(address[] calldata sharesSubjects, uint256[] calldata amounts) public view returns(address[] memory, uint256[] memory) {
        require(sharesSubjects.length == amounts.length, "Wrong amount");
        uint256[] memory prices = new uint256[](amounts.length);
        for (uint256 i = 0; i < sharesSubjects.length; i++) {
            prices[i] = getBuyPriceAfterFee(sharesSubjects[i], amounts[i]);
        }
        return (sharesSubjects, prices);
    }

    // @dev This function is used to buy shares for multiple subjects at once
    //   Limit the elements in the array when calling this function to not
    //   risk to run out of gas
    // @param sharesSubjects The array of subjects to buy shares for
    // @param amounts The array of amounts to buy for each subject
    function batchBuyShares(address[] memory sharesSubjects, uint256[] memory amounts) public virtual {
        require(sharesSubjects.length == amounts.length, "Wrong amount");
        for (uint256 i = 0; i < sharesSubjects.length; i++) {
            buyShares(sharesSubjects[i], amounts[i]);
        }
    }

    // @dev This function is used to create a new wish
    //  Only the contract owner can execute it.
    // @param wisher The address of the wisher
    // @param reservedQuantity The amount of shares to reserve for the wisher
    function newWishPass(address wisher, uint256 reservedQuantity) external virtual onlyOwner onlyIfSetup {
        require(reservedQuantity > 0 && reservedQuantity <= 50, "reserve quantity too large");
        require(wisher != address(0), "Invalid zero Wisher");
        require(wishPasses[wisher].owner == address(0), "duplicate wish");

        wishPasses[wisher].owner = wisher;
        wishPasses[wisher].reservedQuantity = reservedQuantity;
        wishPasses[wisher].totalSupply = reservedQuantity;
    }

    // @dev This function is used to bind a wish to a subject
    //   Only the contract owner can execute it.
    // @param sharesSubject The address of the subject
    // @param wisher The address of the wisher
    function bindWishPass(address sharesSubject, address wisher) external virtual onlyOwner {
        require(sharesSubject != address(0) && wisher != address(0), "wrong address");
        require(wishPasses[wisher].owner == wisher, "wish not found");
        
        if (authorizedWishes[sharesSubject] == wisher) {
            // Support reentrancy
            return;
        }

        require(authorizedWishes[sharesSubject] == address(0), "duplicate bind");
        
        wishPasses[wisher].subject = sharesSubject;
        authorizedWishes[sharesSubject] = wisher;

        require(!wishPasses[wisher].isClaimReward, "claim reward should be false");
        wishPasses[wisher].isClaimReward = true;

        if (wishPasses[wisher].subjectReward > 0) {
            (bool success, ) = sharesSubject.call{value: wishPasses[wisher].subjectReward}("");
            require(success, "Unable to claim reward");
        }
    }
  
    // @dev This function is used to claim the reserved wish pass
    //   Only the sharesSubject itself can call this function to make the claim
    function claimReservedWishPass() external payable virtual {
        address sharesSubject = msg.sender;
        require(authorizedWishes[sharesSubject] != address(0), "Invalid Wish address, unable to purchase");

        address wisher = authorizedWishes[sharesSubject];
        require(wishPasses[wisher].owner == wisher, "invalid zero wisher");
        require(wishPasses[wisher].subject == sharesSubject, "not match subject");
        require(wishPasses[wisher].reservedQuantity > 0, "zero reserved quantity");
        
        uint256 amount = wishPasses[wisher].reservedQuantity;
        uint256 price = getPrice(0, amount); 
        uint256 protocolFee = getProtocolFee(price);
        uint256 subjectFee = getSubjectFee(price);

        require(msg.value >= price + protocolFee + subjectFee, "Transaction failed due to price");

        wishPasses[wisher].reservedQuantity = 0; 
        wishPasses[wisher].balanceOf[sharesSubject] += amount;
        
        (bool success1, ) = protocolFeeDestination.call{value: protocolFee}("");
        (bool success2, ) = sharesSubject.call{value: subjectFee}(""); 

        require(success1 && success2, "Unable to send funds");

        uint256 supply = wishPasses[wisher].totalSupply;
        emit Trade(msg.sender, sharesSubject, true, amount, price, protocolFee, subjectFee, supply, SubjectType.BIND); 
    }
}